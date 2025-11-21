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

    git bz apply [options] <bug-ref>
    git bz apply --continue
    git bz apply --skip
    git bz apply --abort

=head1 DESCRIPTION

Applies patch attachments from a Bugzilla bug to the current Git branch.
Automatically handles dependency bugs by prompting to apply them first.
Provides interactive patch selection and handles git-am workflow states.

=cut

use Modern::Perl;
use Getopt::Long qw(GetOptionsFromArray);
use Try::Tiny    qw(catch try);
use GitBz::Git;
use GitBz::Bug;
use GitBz::Exception;
use File::Temp;
use File::Path qw(rmtree);
use MIME::Base64;

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
    ) or GitBz::Exception->throw("Invalid options");

    return try {
        if ( $opts{continue} || $opts{skip} || $opts{abort} ) {
            return $self->handle_git_am_state( \%opts );
        }

        GitBz::Exception->throw("Usage: git bz apply [options] <bug-ref>") unless @args == 1;

        my $bug_ref = $args[0];

        # Reset applied bugs tracking for new apply session
        @bugs_applied = ();

        my $patches_applied = $self->apply_bug_with_dependencies( $bug_ref, \%opts );

        if ($patches_applied) {
            print "\n✓ Successfully applied $patches_applied patch(es) from bug $bug_ref\n";
        }
    } catch {
        GitBz::Exception->throw("Apply failed: $_");
    };
}

=head2 apply_bug_with_dependencies

    $apply->apply_bug_with_dependencies($bug_ref, \%opts);

Applies a bug and its dependencies recursively.

=cut

sub apply_bug_with_dependencies {
    my ( $self, $bug_ref, $opts ) = @_;

    # Skip if already applied
    return if grep { $_ eq $bug_ref } @bugs_applied;

    my $client = $self->{commands}->{client};
    my $bug    = GitBz::Bug->get( $client, $bug_ref );

    GitBz::Exception->throw("Bug $bug_ref not found") unless $bug;

    # Handle dependencies first
    my $dependencies = $bug->depends_on;
    if ( $dependencies && @$dependencies ) {
        for my $dep_id (@$dependencies) {
            next if grep { $_ eq $dep_id } @bugs_applied;

            my $dep_bug = GitBz::Bug->get( $client, $dep_id );
            my $status  = $dep_bug->status;

            # Only prompt for dependencies in relevant states
            if (   $status eq 'Needs Signoff'
                || $status eq 'Signed Off'
                || $status eq 'Failed QA'
                || $status eq 'Passed QA'
                || $status eq 'BLOCKED' )
            {

                print "\n📋 Bug $bug_ref depends on bug $dep_id ($status)\n";
                my $choice = $self->prompt_multi( "Follow? [(y)es, (n)o]", [ "y", "n" ] );

                if ( $choice eq "y" ) {
                    try {
                        $self->apply_bug_with_dependencies( $dep_id, $opts );
                    } catch {
                        GitBz::Exception->throw(
                            "Cannot apply cleanly patches from bug $dep_id. " . "Everything will be left dirty. $_" );
                    };
                }
            }
        }
    }

    # Apply the main bug
    my $patches_applied = $self->apply_bug_patches( $bug_ref, $opts );

    # Track as applied only if patches were actually applied
    if ($patches_applied) {
        push @bugs_applied, $bug_ref;
    }

    return $patches_applied;
}

=head2 handle_git_am_state

    $apply->handle_git_am_state(\%opts);

Handles git-am workflow states (continue, skip, abort).
Cleans up temp directory on abort or successful completion.

=cut

sub handle_git_am_state {
    my ( $self, $opts ) = @_;

    # Check if we're in a git-am session
    my $git_dir = try {
        my $dir = GitBz::Git->run('rev-parse', '--git-dir');
        chomp $dir;
        return $dir;
    } catch {
        GitBz::Exception->throw("Not inside a git repository");
    };

    unless (-d "$git_dir/rebase-apply") {
        GitBz::Exception->throw("Not inside a 'git bz apply' operation");
    }

    # Check if this is a git-bz operation and get temp directory
    my ($has_state, $temp_dir) = $self->load_state($git_dir);

    if ( $opts->{abort} ) {
        GitBz::Git->run( 'am', '--abort' );
        # Clean up temp directory if it exists
        if ($temp_dir && -d $temp_dir) {
            rmtree($temp_dir);
            print "\n✗ Aborted patch application and cleaned up temp files\n";
        } else {
            print "\n✗ Aborted patch application\n";
        }
    } elsif ( $opts->{continue} ) {
        GitBz::Git->run( 'am', '--continue' );
        # Clean up temp directory on successful completion
        if ($temp_dir && -d $temp_dir) {
            rmtree($temp_dir);
        }
        print "\n✓ Successfully continued applying patches\n";
    } elsif ( $opts->{skip} ) {
        GitBz::Git->run( 'am', '--skip' );
        # Clean up temp directory on successful completion
        if ($temp_dir && -d $temp_dir) {
            rmtree($temp_dir);
        }
        print "\n⊘ Skipped current patch\n";
    }
}

=head2 apply_bug_patches

    $apply->apply_bug_patches($bug_ref, \%opts);

Retrieves and applies patches from a bug.

=cut

sub apply_bug_patches {
    my ( $self, $bug_ref, $opts ) = @_;

    my $client = $self->{commands}->{client};
    my $bug    = GitBz::Bug->get( $client, $bug_ref );

    GitBz::Exception->throw("Bug $bug_ref not found") unless $bug;

    my $attachments = $bug->attachments;

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

    $self->apply_patches( \@selected_patches, $opts );
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

    $apply->save_state($git_dir, $temp_dir);

Saves git-bz state when git-am fails for proper cleanup on abort.
Stores temp directory location for later cleanup.

=cut

sub save_state {
    my ( $self, $git_dir, $temp_dir ) = @_;

    my $state_file = "$git_dir/rebase-apply/git-bz";

    open my $fh, '>', $state_file or die "Cannot write state file: $!";
    print $fh "# git-bz state file\n";

    # Store temp directory path for cleanup on abort
    if ($temp_dir) {
        print $fh "temp_dir=$temp_dir\n";
    }

    close $fh;
}

=head2 load_state

    my ($has_state, $temp_dir) = $apply->load_state($git_dir);

Loads git-bz state file if it exists. Returns whether state was found
and the temp directory path if stored.

=cut

sub load_state {
    my ( $self, $git_dir ) = @_;

    my $state_file = "$git_dir/rebase-apply/git-bz";
    return (0, undef) unless -f $state_file;

    # Read temp directory from state file
    open my $fh, '<', $state_file or return (1, undef);
    my $temp_dir;
    while (my $line = <$fh>) {
        if ($line =~ /^temp_dir=(.+)$/) {
            $temp_dir = $1;
            chomp $temp_dir;
            last;
        }
    }
    close $fh;

    return (1, $temp_dir);
}

=head2 apply_patches

    $apply->apply_patches(\@attachments, \%opts);

Applies selected patches using git-am.

=cut

sub apply_patches {
    my ( $self, $attachments, $opts ) = @_;

    # Create temp directory - don't auto-cleanup so files are available on failure
    my $temp_dir = File::Temp->newdir( CLEANUP => 0 );
    my @patch_files;

    # Save patches directly from REST API data
    for my $i ( 0 .. $#$attachments ) {
        my $att      = $attachments->[$i];
        my $filename = sprintf( "%s/%04d-%s.patch", $temp_dir, $i + 1, $att->{id} );

        # Decode base64 data from REST API
        my $decoded_patch = decode_base64( $att->{data} );

        open my $fh, '>', $filename or die "Cannot write $filename: $!";
        print $fh $decoded_patch;
        close $fh;

        push @patch_files, $filename;
    }

    # Apply patches with git am
    my @git_am_args = ('am');
    push @git_am_args, '--signoff' if $opts->{signoff};
    push @git_am_args, @patch_files;

    try {
        GitBz::Git->run(@git_am_args);
        # Success - clean up temp directory
        rmtree($temp_dir);
    } catch {
        # If git-am failed and saved its state, save our state too for cleanup
        my $git_dir = GitBz::Git->run('rev-parse', '--git-dir');
        chomp $git_dir;
        if (-d "$git_dir/rebase-apply") {
            $self->save_state($git_dir, $temp_dir);
            print STDERR "\nPatches left in $temp_dir for manual application if needed\n";
            print STDERR "Use 'git bz apply --abort' to abort and clean up temp files\n\n";
        }
        die $_;
    };
}

1;
