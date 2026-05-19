package GitBz::Commands::Apply;

# This file is part of git-bz.
#
# git-bz is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# git-bz is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with git-bz; if not, see <https://www.gnu.org/licenses>.

=head1 NAME

GitBz::Commands::Apply - Apply patches from Bugzilla bugs with dependency cascading

=head1 SYNOPSIS

    git bz apply [options] <bug-ref> [bug-ref ...]
    git bz apply --continue
    git bz apply --skip
    git bz apply --abort

=head1 DESCRIPTION

Applies patch attachments from a Bugzilla bug to the current Git branch.
Automatically handles dependency bugs by prompting to apply them first.
Provides interactive patch selection and handles git-am workflow states.

=cut

use Modern::Perl;

use utf8;
use open ':std', ':utf8';

use Getopt::Long qw(GetOptionsFromArray);
use Try::Tiny    qw(catch try);
use GitBz::Git;
use GitBz::Bug;
use GitBz::Config;
use GitBz::Exception;
use GitBz::Progress;
use File::Temp;
use File::Path qw(rmtree);
use MIME::Base64;

binmode( STDOUT, ':utf8' );
binmode( STDERR, ':utf8' );

# Track applied bugs to avoid duplicates during recursive dependency resolution
our @bugs_applied = ();

=head2 new

    my $apply = GitBz::Commands::Apply->new($commands);

Constructor.

=cut

sub new {
    my ( $class, $commands ) = @_;
    bless { commands => $commands }, $class;
}

=head2 execute

    $apply->execute(@args);

Main entry point for the apply command.

=cut

sub execute {
    my ( $self, @args ) = @_;

    my %opts;

    GetOptionsFromArray(
        \@args,
        'continue|resolved' => \$opts{continue},
        'skip'              => \$opts{skip},
        'abort'             => \$opts{abort},
        'confirm'           => \$opts{confirm},
        'signoff|s'         => \$opts{signoff},
        'bugzilla|b=s'      => \$opts{bugzilla},
        'verbose|v+'        => \$opts{verbose},
    ) or GitBz::Exception->throw("Invalid options");

    # Set verbosity level: 0 (quiet), 1 (default), 2 (verbose)
    # Command line flag takes precedence, then config, then default to 1
    unless ( defined $opts{verbose} ) {
        my $config_verbose = GitBz::Config->get( 'bz.verbose', '1' );
        chomp $config_verbose;
        $opts{verbose} = $config_verbose =~ /^\d+$/ ? $config_verbose : 1;
    }

    # Set global verbosity for Progress module
    GitBz::Progress::set_verbosity( $opts{verbose} );

    return try {
        if ( $opts{continue} || $opts{skip} || $opts{abort} ) {
            return $self->handle_git_am_state( \%opts );
        }

        GitBz::Exception->throw("Usage: git bz apply [options] <bug-ref> [bug-ref ...]") unless @args;

        # Reset applied bugs tracking for new apply session
        @bugs_applied = ();

        for my $bug_ref (@args) {
            $self->apply_bug_with_dependencies( $bug_ref, \%opts );
        }
    } catch {
        GitBz::Exception->throw("Apply failed: $_");
    };
}

=head2 apply_bug_with_dependencies

    $apply->apply_bug_with_dependencies($bug_ref, \%opts, $bug);

Applies a bug and its dependencies recursively.
If $bug object is provided, uses it; otherwise fetches the bug.

=cut

sub apply_bug_with_dependencies {
    my ( $self, $bug_ref, $opts, $bug ) = @_;

    # Skip if already applied
    return if grep { $_ eq $bug_ref } @bugs_applied;

    my $client = $self->{commands}->{client};

    # Fetch bug if not already provided
    unless ($bug) {
        $bug = GitBz::Progress::with_spinner(
            "Fetching bug $bug_ref",
            sub {
                return GitBz::Bug->get( $client, $bug_ref );
            },
            1
        );
    }

    GitBz::Exception->throw("Bug $bug_ref not found") unless $bug;

    # Handle dependencies first
    my $dependencies = $bug->depends_on;
    if ( $dependencies && @$dependencies ) {
        for my $dep_id (@$dependencies) {
            next if grep { $_ eq $dep_id } @bugs_applied;

            my $dep_bug = GitBz::Progress::with_spinner(
                "Checking dependency bug $dep_id",
                sub {
                    return GitBz::Bug->get( $client, $dep_id );
                },
                1
            );
            my $status = $dep_bug->status;

            # Only prompt for dependencies in relevant states
            if (   $status eq 'Needs Signoff'
                || $status eq 'Signed Off'
                || $status eq 'Failed QA'
                || $status eq 'Passed QA'
                || $status eq 'BLOCKED'
                || $status eq 'In Discussion' )
            {

                print "\n📋 Bug $bug_ref depends on bug $dep_id ($status)\n";
                my $choice = $self->prompt_multi( "Follow? [(y)es, (n)o]", [ "y", "n" ] );

                if ( $choice eq "y" ) {
                    try {
                        # Pass the already-fetched dependency bug to avoid re-fetching
                        $self->apply_bug_with_dependencies( $dep_id, $opts, $dep_bug );
                    } catch {
                        GitBz::Exception->throw(
                            "Cannot apply cleanly patches from bug $dep_id. " . "Everything will be left dirty. $_" );
                    };
                }
            }
        }
    }

    # Apply the main bug (pass the already-fetched bug object)
    my $patches_applied = $self->apply_bug_patches( $bug_ref, $opts, $bug );

    # Track as applied only if patches were actually applied
    if ($patches_applied) {
        push @bugs_applied, $bug_ref;
        print "\n";  # Add spacing before top-level result
        GitBz::Progress::print_success("Successfully applied $patches_applied patch(es) from bug $bug_ref", 0);
    }

    return $patches_applied;
}

=head2 handle_git_am_state

    $apply->handle_git_am_state(\%opts);

Handles git-am workflow states (continue, skip, abort).
Continues applying remaining patches after --continue or --skip.
Cleans up temp directory on abort or successful completion.

=cut

sub handle_git_am_state {
    my ( $self, $opts ) = @_;

    # Check if we're in a git-am session
    my $git_dir = try {
        my $dir = GitBz::Git->run( 'rev-parse', '--git-dir' );
        chomp $dir;
        return $dir;
    } catch {
        GitBz::Exception->throw("Not inside a git repository");
    };

    unless ( -d "$git_dir/rebase-apply" ) {
        GitBz::Exception->throw("Not inside a 'git bz apply' operation");
    }

    # Check if this is a git-bz operation and get state
    my ( $has_state, $temp_dir, $remaining_patches ) = $self->load_state($git_dir);

    if ( $opts->{abort} ) {
        GitBz::Git->run( 'am', '--abort' );

        # Clean up temp directory if it exists
        if ( $temp_dir && -d $temp_dir ) {
            rmtree($temp_dir);
            print "\n";  # Add spacing before top-level result
            GitBz::Progress::print_error("Aborted patch application and cleaned up temp files", 0);
        } else {
            print "\n";  # Add spacing before top-level result
            GitBz::Progress::print_error("Aborted patch application", 0);
        }
    } elsif ( $opts->{continue} ) {
        GitBz::Git->run( 'am', '--continue' );
        print "\n";  # Add spacing before top-level result
        GitBz::Progress::print_info("Continued with current patch", 0);

        # Continue with remaining patches if any
        if ( $remaining_patches && @$remaining_patches ) {
            GitBz::Progress::print_info("Continuing with " . scalar(@$remaining_patches) . " remaining patch(es)...");
            my $patch_info = $self->load_patch_info_from_temp( $temp_dir, $remaining_patches );
            $self->apply_patches( $patch_info, $temp_dir, $opts );
        } else {

            # No remaining patches - just clean up
            if ( $temp_dir && -d $temp_dir ) {
                rmtree($temp_dir);
            }
        }
    } elsif ( $opts->{skip} ) {
        GitBz::Git->run( 'am', '--skip' );
        print "\n";  # Add spacing before top-level result
        GitBz::Progress::print_warning("Skipped current patch", 0);

        # Continue with remaining patches if any
        if ( $remaining_patches && @$remaining_patches ) {
            GitBz::Progress::print_info("Continuing with " . scalar(@$remaining_patches) . " remaining patch(es)...");
            my $patch_info = $self->load_patch_info_from_temp( $temp_dir, $remaining_patches );
            $self->apply_patches( $patch_info, $temp_dir, $opts );
        } else {

            # No remaining patches - just clean up
            if ( $temp_dir && -d $temp_dir ) {
                rmtree($temp_dir);
            }
        }
    }
}

=head2 load_patch_info_from_temp

    my \@patch_info = $apply->load_patch_info_from_temp($temp_dir, \@patch_ids);

Reconstructs patch_info array from temp directory and patch IDs.
Returns array of hashrefs with {file => path, id => patch_id, summary => ''}.

=cut

sub load_patch_info_from_temp {
    my ( $self, $temp_dir, $patch_ids ) = @_;

    return () unless $patch_ids && @$patch_ids && $temp_dir && -d $temp_dir;

    # Find all patch files in temp directory
    opendir my $dh, $temp_dir or die "Cannot read temp directory: $!";
    my @all_files = grep { /\.patch$/ } readdir($dh);
    closedir $dh;

    # Build patch_info for requested IDs
    my @patch_info;
    for my $patch_id (@$patch_ids) {

        # Find the patch file for this ID
        my ($patch_file) = grep { /-${patch_id}\.patch$/ } @all_files;
        unless ($patch_file) {
            print STDERR "Warning: Could not find patch file for ID $patch_id, skipping\n";
            next;
        }

        push @patch_info, {
            file    => "$temp_dir/$patch_file",
            id      => $patch_id,
            summary => ''                         # Summary not available when loading from temp
        };
    }

    return \@patch_info;
}

=head2 apply_bug_patches

    $apply->apply_bug_patches($bug_ref, \%opts, $bug);

Retrieves and applies patches from a bug.
If $bug object is provided, uses it; otherwise fetches the bug.

=cut

sub apply_bug_patches {
    my ( $self, $bug_ref, $opts, $bug ) = @_;

    # Fetch bug if not already provided
    print "\n" if GitBz::Progress::get_verbosity() >= 2;    # Extra newline in verbose mode for readability
    unless ($bug) {
        my $client = $self->{commands}->{client};
        $bug = GitBz::Progress::with_spinner(
            "Fetching bug $bug_ref",
            sub {
                return GitBz::Bug->get( $client, $bug_ref );
            },
            1
        );
    }

    GitBz::Exception->throw("Bug $bug_ref not found") unless $bug;

    my $attachments = GitBz::Progress::with_spinner(
        "Fetching bug $bug_ref attachments",
        sub {
            return $bug->attachments;
        },
        1
    );

    # Filter for patch attachments
    my @patches;
    for my $att (@$attachments) {
        if ( $att->{is_patch} && !$att->{is_obsolete} ) {
            push @patches, $att;
        }
    }

    GitBz::Exception->throw("No patch attachments found") unless @patches;

    print "\n📋 Bug $bug_ref - " . $bug->summary . "\n\n";

    for my $patch (@patches) {
        print "  • $patch->{id} - $patch->{summary}\n";
    }
    print "\n";

    my @selected_patches;

    if ( $opts->{confirm} ) {
        @selected_patches = @patches;
    } else {
        my $choice = $self->prompt_multi( "Apply? [(y)es, (n)o, (i)nteractive]", [ "y", "n", "i" ] );

        if ( $choice eq "n" ) {
            print "\nNo patches applied for bug $bug_ref\n";
            return 0;
        } elsif ( $choice eq "i" ) {
            @selected_patches = $self->select_patches_interactively( \@patches, $bug );
        } else {
            @selected_patches = @patches;
        }
    }

    unless (@selected_patches) {
        print "\nNo patches selected for bug $bug_ref\n";
        return 0;
    }

    # Convert attachments to patch files
    my ( $temp_dir, $patch_info ) = $self->prepare_patch_files( \@selected_patches, $opts );

    # Apply all patch files
    $self->apply_patches( $patch_info, $temp_dir, $opts );

    return scalar @selected_patches;
}

=head2 prompt_multi

    my $choice = $apply->prompt_multi($prompt, \@choices);

Prompts user for input with multiple choice options.

=cut

sub prompt_multi {
    my ( $self, $prompt, $choices ) = @_;

    while (1) {
        print "$prompt ";
        my $response = <STDIN>;
        chomp $response;
        $response = lc($response);

        for my $choice (@$choices) {
            return $choice if $response eq $choice || $response eq substr( $choice, 0, 1 );
        }

        print "Please enter one of: " . join( ", ", @$choices ) . "\n";
    }
}

=head2 select_patches_interactively

    my @selected = $apply->select_patches_interactively(\@patches, $bug);

Provides interactive patch selection through an editor.

=cut

sub select_patches_interactively {
    my ( $self, $patches, $bug ) = @_;

    # Create template for patch selection
    my $template = "";
    $template .= "# Bug " . $bug->id . " - " . $bug->summary . "\n";
    $template .= "# Select patches to apply by uncommenting the lines below\n";
    $template .= "# Lines starting with # are ignored\n\n";

    for my $patch (@$patches) {
        $template .= sprintf( "# %d %s\n", $patch->{id}, $patch->{summary} );
    }

    # Edit template
    my $temp = File::Temp->new( SUFFIX => '.txt' );
    print $temp $template;
    close $temp;

    my $editor = $ENV{EDITOR} || 'vi';
    system( $editor, $temp->filename );

    # Parse selected patches
    open my $fh, '<', $temp->filename or die "Cannot read temp file: $!";
    my @selected;
    my %patches_by_id = map { $_->{id} => $_ } @$patches;

    while ( my $line = <$fh> ) {
        chomp $line;
        next if $line =~ /^\s*#/ || $line =~ /^\s*$/;

        if ( $line =~ /^\s*(\d+)/ ) {
            my $patch_id = $1;
            if ( $patches_by_id{$patch_id} ) {
                push @selected, $patches_by_id{$patch_id};
            }
        }
    }
    close $fh;

    if (@selected) {
        print "\n✓ Selected " . scalar(@selected) . " patch(es):\n";
        for my $patch (@selected) {
            print "  • $patch->{summary}\n";
        }
    } else {
        print "\n⚠ No patches selected\n";
    }

    return @selected;
}

=head2 save_state

    $apply->save_state($git_dir, $temp_dir, \@remaining_patch_ids);

Saves git-bz state when git-am fails for proper cleanup on abort.
Stores temp directory location and remaining patches.

=cut

sub save_state {
    my ( $self, $git_dir, $temp_dir, $remaining_patch_ids ) = @_;

    my $state_file = "$git_dir/rebase-apply/git-bz";

    open my $fh, '>', $state_file or die "Cannot write state file: $!";
    print $fh "# git-bz state file\n";

    # Store temp directory path for cleanup on abort
    if ($temp_dir) {
        print $fh "temp_dir=$temp_dir\n";
    }

    # Store remaining patch IDs in parseable format
    if ( $remaining_patch_ids && @$remaining_patch_ids ) {
        print $fh "remaining_patches=" . join( ",", @$remaining_patch_ids ) . "\n";
    }

    close $fh;
}

=head2 load_state

    my ($has_state, $temp_dir, $remaining_patches) = $apply->load_state($git_dir);

Loads git-bz state file if it exists. Returns whether state was found,
the temp directory path, and array ref of remaining patch IDs.

=cut

sub load_state {
    my ( $self, $git_dir ) = @_;

    my $state_file = "$git_dir/rebase-apply/git-bz";
    return ( 0, undef, undef ) unless -f $state_file;

    # Read state from file
    open my $fh, '<', $state_file or return ( 1, undef, undef );
    my $temp_dir;
    my @remaining_patches;

    while ( my $line = <$fh> ) {
        if ( $line =~ /^temp_dir=(.+)$/ ) {
            $temp_dir = $1;
            chomp $temp_dir;
        } elsif ( $line =~ /^remaining_patches=(.+)$/ ) {
            my $patches_str = $1;
            chomp $patches_str;
            @remaining_patches = split( /,/, $patches_str );
        }
    }
    close $fh;

    return ( 1, $temp_dir, \@remaining_patches );
}

=head2 prepare_patch_files

    my ($temp_dir, \@patch_info) = $apply->prepare_patch_files(\@attachments, \%opts);

Converts attachments to patch files in a temp directory.
Returns temp directory and array of hashrefs with {file => path, id => att_id, summary => att_summary}.

=cut

sub prepare_patch_files {
    my ( $self, $attachments, $opts ) = @_;

    # Create temp directory - don't auto-cleanup so files are available on failure
    my $temp_dir = File::Temp->newdir( CLEANUP => 0 );
    my @patch_info;

    # Save patches directly from REST API data
    # Level 0 (quiet): skip header, Level 1+: show header
    print "\nPreparing " . scalar(@$attachments) . " patch(es):\n" if GitBz::Progress::get_verbosity() >= 1;

    for my $i ( 0 .. $#$attachments ) {
        my $att      = $attachments->[$i];
        my $filename = sprintf( "%s/%04d-%s.patch", $temp_dir, $i + 1, $att->{id} );

        # Decode base64 data from REST API
        my $decoded_patch = decode_base64( $att->{data} );

        open my $fh, '>:raw', $filename or die "Cannot write $filename: $!";
        print $fh $decoded_patch;
        close $fh;

        # Show progress based on verbosity level
        my $counter = sprintf( "[%d/%d]", $i + 1, scalar(@$attachments) );
        GitBz::Progress::update_progress_line("$counter Preparing $att->{summary}");

        push @patch_info, {
            file    => $filename,
            id      => $att->{id},
            summary => $att->{summary}
        };
    }

    # Overwrite the last progress line with summary
    if ( GitBz::Progress::get_verbosity() >= 1 ) {
        my $is_tty = -t STDOUT;
        if ( GitBz::Progress::get_verbosity() == 1 && $is_tty ) {
            print "\r\e[K";
        }
        GitBz::Progress::print_success("Prepared " . scalar(@$attachments) . " patch(es)");
    }

    return ( $temp_dir, \@patch_info );
}

=head2 apply_patches

    $apply->apply_patches(\@patch_info, $temp_dir, \%opts);

Applies patch files sequentially with 3-way merge support.
patch_info is array of hashrefs with {file => path, id => att_id, summary => att_summary}.

=cut

sub apply_patches {
    my ( $self, $patch_info, $temp_dir, $opts ) = @_;

    my $git_dir = GitBz::Git->run( 'rev-parse', '--git-dir' );
    chomp $git_dir;

    # Level 0 (quiet): skip header, Level 1+: show header
    if ( GitBz::Progress::get_verbosity() >= 1 ) {
        GitBz::Progress::print_section("Applying " . scalar(@$patch_info) . " patch(es)");
    }

    my $failed = 0;
    for my $i ( 0 .. $#$patch_info ) {
        my $info = $patch_info->[$i];

        # Apply this patch with 3-way merge for better conflict resolution
        my @git_am_args = ( 'am', '-3' );
        push @git_am_args, '--signoff' if $opts->{signoff};
        push @git_am_args, $info->{file};

        try {
            GitBz::Git->run(@git_am_args);

            # Show progress after successful application (print each line, don't overwrite)
            my $counter = sprintf( "[%d/%d]", $i + 1, scalar(@$patch_info) );
            my $summary = $info->{summary} || "patch $info->{id}";
            GitBz::Progress::print_success("$counter Applied $summary", 2) if GitBz::Progress::get_verbosity() >= 1;
        } catch {
            $failed = 1;

            # If git-am failed and saved its state, save our state too
            if ( -d "$git_dir/rebase-apply" ) {

                # Clear any progress line before printing error (only at level 1)
                if ( GitBz::Progress::get_verbosity() == 1 && -t STDOUT ) {
                    print "\r\e[K";
                }

                # Save which patches remain to be applied
                my @remaining_patch_ids = map { $patch_info->[$_]->{id} } ( ( $i + 1 ) .. $#$patch_info );
                $self->save_state( $git_dir, $temp_dir, \@remaining_patch_ids );

                print STDERR "\n";
                my $summary_msg = $info->{summary} ? " - $info->{summary}" : "";
                print STDERR "Patch application failed for attachment $info->{id}$summary_msg\n";
                print STDERR "\n";
                print STDERR "Patches left in $temp_dir for manual application if needed\n";
                print STDERR "\n";
                print STDERR "To resolve:\n";
                print STDERR "  1. Fix conflicts (use 'git mergetool' or edit files manually)\n";
                print STDERR "  2. Stage resolved files with 'git add'\n";
                print STDERR "  3. Continue with 'git bz apply --continue' or 'git am --continue'\n";
                print STDERR "  4. Or skip this patch with 'git bz apply --skip'\n";
                print STDERR "  5. Or abort with 'git bz apply --abort'\n";
                print STDERR "\n";
            }
            die $_;
        };
    }

    # Finalize progress output if all succeeded
    unless ($failed) {
        rmtree($temp_dir);
    }
}

1;
