package GitBz::Commands::Attach;

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

GitBz::Commands::Attach - Attach Git commits as patches to Bugzilla bugs

=head1 SYNOPSIS

    git bz attach [options] [<bug-ref>] <commit-range>
    git bz attach --edit 12345 HEAD~2..HEAD
    git bz attach --yes HEAD  # Skip confirmation prompts
    git bz attach HEAD        # Extracts bug ref from commit message

=head1 DESCRIPTION

Attaches Git commits as patch files to Bugzilla bugs.
Supports interactive editing of bug fields and attachment metadata.

=cut

use Modern::Perl;

use Getopt::Long qw(GetOptionsFromArray);
use Try::Tiny    qw(catch try);
use File::Temp;

use GitBz::Git;
use GitBz::Exception;
use GitBz::StatusWorkflow;
use GitBz::Bug;

=head2 new

    my $attach = GitBz::Commands::Attach->new($commands);

Constructor.

=cut

sub new {
    my ( $class, $commands ) = @_;
    bless {
        commands => $commands,
        client   => $commands->{client}
    }, $class;
}

=head2 execute

    $attach->execute(@args);

Main entry point for the attach command.

=cut

sub execute {
    my ( $self, @args ) = @_;

    my %opts;

    GetOptionsFromArray(
        \@args,
        'edit|e' => \$opts{edit},
        'yes|y'  => \$opts{yes},
    ) or GitBz::Exception->throw("Invalid options");

    return try {
        my ( $bug_ref, $commit_range ) = $self->parse_args(@args);
        my @commits = GitBz::Git->get_commits($commit_range);

        GitBz::Exception->throw("No commits found") unless @commits;

        $self->attach_patches( $bug_ref, \@commits, \%opts );

        print "\n✓ Successfully attached " . scalar(@commits) . " patch(es) to bug $bug_ref\n";
    } catch {
        GitBz::Exception->throw("Attach failed: $_");
    };
}

=head2 parse_args

    my ($bug_ref, $commit_range) = $attach->parse_args(@args);

Parses command line arguments to extract bug reference and commit range.

=cut

sub parse_args {
    my ( $self, @args ) = @_;

    GitBz::Exception->throw("Usage: git bz attach [options] [<bug-ref>] <commit-range>")
        unless @args >= 1 && @args <= 2;

    if ( @args == 1 ) {

        # Try to extract bug reference from commit message
        my @commits = GitBz::Git->get_commits( $args[0] );
        my $bug_ref = $self->extract_bug_ref( $commits[0] );
        GitBz::Exception->throw("No bug reference found in commit message") unless $bug_ref;
        return ( $bug_ref, $args[0] );
    } else {
        return ( $args[0], $args[1] );
    }
}

=head2 extract_bug_ref

    my $bug_ref = $attach->extract_bug_ref($commit);

Extracts bug reference from commit message.

=cut

sub extract_bug_ref {
    my ( $self, $commit ) = @_;

    my $message = GitBz::Git->run( 'log', '--format=%B', '-1', $commit->{id} );

    # Look for Bug NNNN or bug NNNN
    if ( $message =~ /\b[Bb]ug\s+(\d+)\b/ ) {
        return $1;
    }

    return;
}

=head2 preflight_checks

    $attach->preflight_checks($bug_ref, \@commits);

Performs preflight checks before attaching patches.

=cut

sub preflight_checks {
    my ( $self, $bug_ref, $commits ) = @_;

    my @mismatched_bugs;
    
    for my $commit (@$commits) {
        my $commit_bug_ref = $self->extract_bug_ref($commit);
        if ( $commit_bug_ref && $commit_bug_ref ne $bug_ref ) {
            push @mismatched_bugs, {
                commit => substr($commit->{id}, 0, 7),
                subject => $commit->{subject},
                bug_ref => $commit_bug_ref
            };
        }
    }

    if (@mismatched_bugs) {
        print "\n🚨 ALERT: Bug number mismatch detected!\n";
        print "Attaching to bug $bug_ref, but found commits with different bug numbers:\n\n";
        
        for my $mismatch (@mismatched_bugs) {
            print "  $mismatch->{commit}: $mismatch->{subject}\n";
            print "    → References bug $mismatch->{bug_ref} (not $bug_ref)\n\n";
        }
        
        print "Continue anyway? [y/N]: ";
        my $response = <STDIN>;
        chomp $response;
        
        unless ( $response =~ /^[yY]/ ) {
            GitBz::Exception->throw("Aborted due to bug number mismatch\n");
        }
    }
}

=head2 confirm_attachment

    $attach->confirm_attachment($bug_ref, \@commits);

Shows confirmation prompt before attaching patches.

=cut

sub confirm_attachment {
    my ( $self, $bug_ref, $commits ) = @_;

    print "\nReady to attach " . scalar(@$commits) . " patch(es) to bug $bug_ref:\n\n";
    
    for my $commit (@$commits) {
        print "  " . substr($commit->{id}, 0, 7) . ": $commit->{subject}\n";
    }
    
    print "\nProceed with attachment? [Y/n]: ";
    my $response = <STDIN>;
    chomp $response;
    
    if ( $response =~ /^[nN]/ ) {
        GitBz::Exception->throw("Attachment cancelled by user\n");
    }
}

=head2 attach_patches

    $attach->attach_patches($bug_ref, \@commits, \%opts);

Attaches commit patches to the specified bug.

=cut

sub attach_patches {
    my ( $self, $bug_ref, $commits, $opts ) = @_;

    my $client = $self->{client};
    my $bug    = GitBz::Bug->get( $client, $bug_ref );

    # Preflight checks
    $self->preflight_checks( $bug_ref, $commits );

    # Show confirmation prompt
    $self->confirm_attachment( $bug_ref, $commits ) unless $opts->{yes};

    my $is_first = 1;
    my %bug_updates;
    my @obsoletes_list;

    for my $commit (@$commits) {
        my $patch       = GitBz::Git->format_patch( $commit->{id} . '^..' . $commit->{id} );
        my $filename    = sprintf( "%s.patch", substr( $commit->{id}, 0, 7 ) );
        my $description = $commit->{subject};
        my $body        = GitBz::Git->run( 'log', '--format=%b', '-1', $commit->{id} );
        my $comment     = $body || "Patch from commit " . substr( $commit->{id}, 0, 7 );
        my @obsoletes;

        if ( $opts->{edit} && $is_first ) {
            ( $description, $comment, my $obsoletes_ref, my $updates_ref ) =
                $self->edit_attachment_comment( $bug, $commit );
            @obsoletes   = @$obsoletes_ref if $obsoletes_ref;
            %bug_updates = %$updates_ref   if $updates_ref;
            push @obsoletes_list, @obsoletes;
        }

        eval {
            $bug->add_attachment(
                $patch,
                $filename,
                $description,
                comment => $comment,
            );
        };
        
        if ($@) {
            print "✗ Failed to attach: $description\n";
            print "Error: $@\n";
            return; # Skip remaining steps
        }

        # Store attachment info for later display
        push @{ $self->{_attached} }, $description;
        $is_first = 0;
    }

    # Show all updates together
    if ( %bug_updates || @obsoletes_list || $self->{_attached} ) {
        print "\nUpdating bug $bug_ref:\n";

        # Show attachments
        for my $desc ( @{ $self->{_attached} || [] } ) {
            print "  ✓ Attached: $desc\n";
        }

        # Show bug field updates
        if ( $bug_updates{status} && $bug_updates{status} ne $bug->status ) {
            print "  ✓ Status: " . $bug->status . " → $bug_updates{status}\n";
        }
        if (   $bug_updates{cf_patch_complexity}
            && $bug_updates{cf_patch_complexity} ne ( $bug->cf_patch_complexity || '' ) )
        {
            my $old = $bug->cf_patch_complexity || 'none';
            print "  ✓ Patch-complexity: $old → $bug_updates{cf_patch_complexity}\n";
        }
        if ( $bug_updates{comment} ) {
            print "  ✓ Added comment\n";
        }
        if ( $bug_updates{depends_on} ) {
            my $depends_change = $bug_updates{depends_on};
            if ( $depends_change->{add} ) {
                print "  ✓ Depends: added " . join( ' ', @{ $depends_change->{add} } ) . "\n";
            }
            if ( $depends_change->{remove} ) {
                print "  ✓ Depends: removed " . join( ' ', @{ $depends_change->{remove} } ) . "\n";
            }
        }

        # Show obsoleted attachments
        for my $attach_id (@obsoletes_list) {
            my $attachments   = $bug->attachments;
            my %attach_lookup = map { $_->{id} => $_->{summary} } @$attachments;
            my $summary       = $attach_lookup{$attach_id} || "Unknown";
            print "  ✓ Obsoleted attachment $attach_id - $summary\n";
        }

        # Perform updates
        if (%bug_updates) {
            $bug->update(%bug_updates);
        }

        # Perform obsoletes
        for my $attach_id (@obsoletes_list) {
            $bug->obsolete_attachment($attach_id);
        }
    }

    # Obsoletes are now handled in the unified update section above
}

=head2 edit_attachment_comment

    my ($desc, $comment, $obsoletes, $updates) = 
        $attach->edit_attachment_comment($bug, $commit);

Provides interactive editing of attachment details and bug fields.

=cut

sub edit_attachment_comment {
    my ( $self, $bug, $commit ) = @_;

    my $client = $self->{client};

    my $template = "";
    $template .= "# Attachment to Bug " . $bug->id . " - " . $bug->summary . "\n\n";
    $template .= $commit->{subject} . "\n\n";

    # Add commit body as initial comment
    my $body = GitBz::Git->run( 'log', '--format=%b', '-1', $commit->{id} );
    $template .= $body . "\n\n" if $body;

    # Show existing patches for obsoleting
    my $attachments = $bug->attachments;
    if ( $attachments && @$attachments ) {
        for my $patch (@$attachments) {
            next unless $patch->{is_patch} && !$patch->{is_obsolete};
            my $obsoleted = ( $commit->{subject} eq $patch->{summary} ) ? "" : "#";
            $template .= "${obsoleted}Obsoletes: $patch->{id} - $patch->{summary}\n";
        }
        $template .= "\n";
    }

    # Add status options
    my $workflow = GitBz::StatusWorkflow->new($client);
    $template .= "# Current status: " . $bug->status . "\n";
    my $status_values = $workflow->get_next_status_values( $bug->status );
    for my $status (@$status_values) {
        $template .= "# Status: $status\n";
    }
    $template .= "\n";

    # Add patch complexity options
    my $complexity = $bug->cf_patch_complexity || "";
    $template .= "# Current patch-complexity: $complexity\n";
    my $complexity_values = $client->get_field_values('cf_patch_complexity');
    if ($complexity_values) {
        for my $comp (@$complexity_values) {
            $template .= "# Patch-complexity: $comp\n";
        }
    }
    $template .= "\n";

    # Add depends options
    my $depends_list = $bug->depends_on;
    my $depends_str  = @$depends_list ? join( ' ', @$depends_list ) : '';
    $template .= "# Current depends: $depends_str\n";

    # Show current depends uncommented
    for my $dep (@$depends_list) {
        $template .= "Depends: bug $dep\n";
    }

    # Show skeleton commented
    $template .= "# Depends: bug xxxx\n";
    $template .= "# Depends: bug yyyy\n";
    $template .= "\n";

    $template .= "# Please edit the description (first line) and comment (other lines).\n";
    $template .= "# Lines starting with '#' will be ignored. Delete everything to abort.\n";
    $template .= "# To obsolete existing patches, uncomment the appropriate lines.\n";

    my $edited = $self->edit_template($template);
    return $self->parse_edited_content( $edited, $bug );
}

=head2 edit_template

    my $edited_content = $attach->edit_template($template);

Opens an editor for the user to modify the template.

=cut

sub edit_template {
    my ( $self, $template ) = @_;

    my $temp = File::Temp->new( SUFFIX => '.txt' );
    binmode $temp, ':utf8';
    print $temp $template;
    close $temp;

    my $editor = $ENV{EDITOR} || $ENV{GIT_EDITOR} || 'vi';
    system( $editor, $temp->filename );

    open my $fh, '<:utf8', $temp->filename or die "Cannot read temp file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    return $content;
}

=head2 parse_edited_content

    my ($desc, $comment, $obsoletes, $updates) = 
        $attach->parse_edited_content($edited_content, $bug);

Parses the edited template content and extracts changes.

=cut

sub parse_edited_content {
    my ( $self, $content, $bug ) = @_;

    my @lines = split /\n/, $content;
    my @non_comment_lines = grep { !/^#/ && /\S/ } @lines;

    my $description = shift @non_comment_lines || "";
    $description =~ s/^\s+|\s+$//g;

    my @obsoletes;
    my @comment_lines;
    my %bug_updates;

    for my $line (@non_comment_lines) {
        if ( $line =~ /^\s*Obsoletes\s*:\s*(\d+)/ ) {
            push @obsoletes, $1;
        } elsif ( $line =~ /^\s*Status\s*:\s*(.+)/ ) {
            $bug_updates{status} = $1;
        } elsif ( $line =~ /^\s*Patch-complexity\s*:\s*(.+)/ ) {
            $bug_updates{cf_patch_complexity} = $1;
        } elsif ( $line =~ /^\s*Depends\s*:\s*([Bb][Uu][Gg])?\s*(\d+)/ ) {
            push @{ $bug_updates{depends_on} }, $2;
        } else {
            push @comment_lines, $line;
        }
    }

    my $comment = join( "\n", @comment_lines );
    $comment =~ s/^\s+|\s+$//g;

    if ($comment) {
        $bug_updates{comment} = { body => $comment };
    }

    # Convert depends_on to proper API format with add/remove actions
    if ( $bug_updates{depends_on} ) {
        my @new_depends = @{ $bug_updates{depends_on} };
        my @old_depends = @{ $bug->depends_on };

        my @to_add = grep {
            my $new = $_;
            !grep { $_ eq $new } @old_depends
        } @new_depends;
        my @to_remove = grep {
            my $old = $_;
            !grep { $_ eq $old } @new_depends
        } @old_depends;

        if ( @to_add || @to_remove ) {
            my %depends_update;
            $depends_update{add}     = \@to_add    if @to_add;
            $depends_update{remove}  = \@to_remove if @to_remove;
            $bug_updates{depends_on} = \%depends_update;
        } else {
            delete $bug_updates{depends_on};
        }
    }

    GitBz::Exception->throw("Empty description, aborting\n") unless $description;

    return ( $description, $comment, \@obsoletes, \%bug_updates );
}

1;
