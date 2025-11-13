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

        $self->apply_bug_with_dependencies( $bug_ref, \%opts );

        print "\n✓ Successfully applied patches from bug $bug_ref\n";
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
    $self->apply_bug_patches( $bug_ref, $opts );

    # Track as applied
    push @bugs_applied, $bug_ref;
}

=head2 handle_git_am_state

    $apply->handle_git_am_state(\%opts);

Handles git-am workflow states (continue, skip, abort).

=cut

sub handle_git_am_state {
    my ( $self, $opts ) = @_;

    if ( $opts->{continue} ) {
        GitBz::Git->run( 'am', '--continue' );
    } elsif ( $opts->{skip} ) {
        GitBz::Git->run( 'am', '--skip' );
    } elsif ( $opts->{abort} ) {
        GitBz::Git->run( 'am', '--abort' );
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
            return;
        } elsif ( $choice eq "i" ) {
            @selected_patches = $self->select_patches_interactively( \@patches, $bug );
        } else {
            @selected_patches = @patches;
        }
    }

    return unless @selected_patches;

    $self->apply_patches( \@selected_patches, $opts );
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

=head2 apply_patches

    $apply->apply_patches(\@attachments, \%opts);

Applies selected patches using git-am.

=cut

sub apply_patches {
    my ( $self, $attachments, $opts ) = @_;

    my $temp_dir = File::Temp->newdir();
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

    GitBz::Git->run(@git_am_args);
}

1;
