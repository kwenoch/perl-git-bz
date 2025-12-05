package GitBz::Commands::Edit;

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

GitBz::Commands::Edit - Edit Bugzilla bug details and add comments

=head1 SYNOPSIS

    git bz edit <bug-ref>
    git bz edit <commit>
    git bz edit <revision-range>
    git bz edit --pushed HEAD~3..HEAD

=head1 DESCRIPTION

Provides interactive editing of Bugzilla bug fields and comments.
Can operate on individual bugs or extract bug references from Git commits.

=cut

use Modern::Perl;

use utf8;
use open ':std', ':utf8';

use Getopt::Long qw(GetOptionsFromArray);
use Try::Tiny    qw(catch try);
use File::Temp;

use GitBz::Git;
use GitBz::Exception;
use GitBz::StatusWorkflow;
use GitBz::Bug;
use GitBz::Progress;

=head2 new

    my $edit = GitBz::Commands::Edit->new($commands);

Constructor.

=cut

sub new {
    my ( $class, $commands ) = @_;
    bless { commands => $commands }, $class;
}

=head2 execute

    $edit->execute(@args);

Main entry point for the edit command.

=cut

sub execute {
    my ( $self, @args ) = @_;

    # Ensure UTF-8 output for this command
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    my %opts;

    GetOptionsFromArray(
        \@args,
        'pushed'       => \$opts{pushed},
        'fix=s'        => \$opts{fix},
        'bugzilla|b=s' => \$opts{bugzilla},
        'verbose=i'    => \$opts{verbose},
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
        GitBz::Exception->throw("Usage: git bz edit [options] (<bug-ref> | <commit> | <revision-range>)")
            unless @args == 1;

        my $arg = $args[0];

        if ( $arg =~ /^\d+$/ ) {

            # Bug reference
            my $changed = $self->edit_bug( $arg, \%opts );
            print "No changes made\n" unless $changed;
        } else {

            # Commit or revision range
            my @commits = GitBz::Git->get_commits($arg);
            GitBz::Exception->throw("No commits found") unless @commits;

            my $changed = $self->edit_commits( \@commits, \%opts );
            print "No changes made\n" unless $changed;
        }

        # Success message is handled in individual methods
    } catch {
        GitBz::Exception->throw("Edit failed: $_");
    };
}

=head2 edit_bug

    my $changed = $edit->edit_bug($bug_ref, \%opts);

Edits a single bug through interactive template.

=cut

sub edit_bug {
    my ( $self, $bug_ref, $opts ) = @_;

    my $client = $self->{commands}->{client};
    my $bug    = GitBz::Progress::with_spinner(
        "Fetching bug $bug_ref",
        sub {
            return GitBz::Bug->get( $client, $bug_ref );
        },
        1
    );

    my $template = $self->create_bug_template( $bug, $opts );
    my $edited   = $self->edit_template($template);

    return $self->update_bug( $client, $bug_ref, $edited, $opts );
}

=head2 edit_commits

    my $changed = $edit->edit_commits(\@commits, \%opts);

Extracts bug references from commits and edits associated bugs.

=cut

sub edit_commits {
    my ( $self, $commits, $opts ) = @_;

    # Extract bug references from commits
    my %bugs;
    for my $commit (@$commits) {
        my $bug_ref = $self->extract_bug_ref($commit);
        if ($bug_ref) {
            push @{ $bugs{$bug_ref} }, $commit;
        }
    }

    GitBz::Exception->throw("No bug references found in commits") unless %bugs;

    # Edit each bug
    my $any_changed = 0;
    for my $bug_ref ( keys %bugs ) {
        print "Editing bug $bug_ref...\n";
        my $changed = $self->edit_bug_with_commits( $bug_ref, $bugs{$bug_ref}, $opts );
        $any_changed ||= $changed;
    }

    return $any_changed;
}

=head2 edit_bug_with_commits

    my $changed = $edit->edit_bug_with_commits($bug_ref, \@commits, \%opts);

Edits a bug with commit context information.

=cut

sub edit_bug_with_commits {
    my ( $self, $bug_ref, $commits, $opts ) = @_;

    my $client = $self->{commands}->{client};
    my $bug    = GitBz::Progress::with_spinner(
        "Fetching bug $bug_ref",
        sub {
            return GitBz::Bug->get( $client, $bug_ref );
        },
        1
    );

    my $template = $self->create_bug_template_with_commits( $bug, $commits, $opts );
    my $edited   = $self->edit_template($template);

    return $self->update_bug( $client, $bug_ref, $edited, $opts );
}

=head2 create_bug_template

    my $template = $edit->create_bug_template($bug, \%opts);

Generates an editor template with current bug state and available options.

=cut

sub create_bug_template {
    my ( $self, $bug, $opts ) = @_;
    my $client = $self->{commands}->{client};

    my $template = "";
    $template .= "# Bug " . $bug->id . " - " . $bug->summary . "\n\n";

    # Show existing patches for obsoleting
    my $attachments = GitBz::Progress::with_spinner(
        "Fetching attachments",
        sub {
            return $bug->attachments;
        },
        1
    );
    if ( $attachments && @$attachments ) {
        for my $patch (@$attachments) {
            next unless $patch->{is_patch} && !$patch->{is_obsolete};
            $template .= "#Obsoletes: $patch->{id} - $patch->{summary}\n";
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
    my $complexity_values = GitBz::Progress::with_spinner(
        "Fetching field values",
        sub {
            return $client->get_field_values('cf_patch_complexity');
        },
        1
    );
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

    # Add sponsorship status options
    my $sponsorship = $bug->cf_sponsorship || "";
    $template .= "# Current sponsorship: $sponsorship\n";
    my $sponsorship_values = GitBz::Progress::with_spinner(
        "Fetching field values",
        sub {
            return $client->get_field_values('cf_sponsorship');
        },
        1
    );
    if ($sponsorship_values) {
        for my $status (@$sponsorship_values) {
            $template .= "# Sponsorship: $status\n";
        }
    }
    $template .= "\n";

    # Add sponsors section (one sponsor per line)
    my $current_sponsors = $bug->cf_sponsors || "";
    my @current_sponsor_list;
    if ($current_sponsors) {

        # Split existing sponsors by comma and trim whitespace
        for my $sponsor ( split /,/, $current_sponsors ) {
            $sponsor =~ s/^\s+|\s+$//g;
            push @current_sponsor_list, $sponsor if $sponsor;
        }
    }

    my $sponsors_str = @current_sponsor_list ? join( ', ', @current_sponsor_list ) : '';
    $template .= "# Current sponsors: $sponsors_str\n";
    $template .= "# Add one sponsor per line:\n";

    # Show current sponsors uncommented
    for my $sponsor (@current_sponsor_list) {
        $template .= "Sponsors: $sponsor\n";
    }

    # Show skeleton commented
    $template .= "# Sponsors: Sponsor Name\n";
    $template .= "\n";

    $template .= "# Enter comment below. Lines starting with '#' will be ignored.\n";
    $template .= "# To obsolete patches, uncomment the appropriate Obsoletes lines.\n";

    return $template;
}

=head2 create_bug_template_with_commits

    my $template = $edit->create_bug_template_with_commits($bug, \@commits, \%opts);

Generates an editor template including commit information.

=cut

sub create_bug_template_with_commits {
    my ( $self, $bug, $commits, $opts ) = @_;

    my $template = $self->create_bug_template( $bug, $opts );

    $template .= "\n# Commits:\n";
    for my $commit (@$commits) {
        $template .= "#   " . substr( $commit->{id}, 0, 7 ) . " " . $commit->{subject} . "\n";
    }

    if ( $opts->{pushed} ) {
        $template .= "\nPushed to master:\n";
        for my $commit (@$commits) {
            $template .= substr( $commit->{id}, 0, 7 ) . " " . $commit->{subject} . "\n";
        }
    }

    return $template;
}

=head2 edit_template

    my $edited_content = $edit->edit_template($template);

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

=head2 update_bug

    my $changed = $edit->update_bug($client, $bug_ref, $edited_content, \%opts);

Parses edited content and updates bug fields through the API.

=cut

sub update_bug {
    my ( $self, $client, $bug_ref, $edited, $opts ) = @_;

    my @lines = split /\n/, $edited;
    my @non_comment_lines = grep { !/^#/ && /\S/ } @lines;

    # Early return if no non-comment lines - no API calls needed
    return 0 unless @non_comment_lines;

    my @obsoletes;
    my @comment_lines;
    my %update_params;

    for my $line (@non_comment_lines) {
        if ( $line =~ /^\s*Status\s*:\s*(.+)/ ) {
            $update_params{status} = $1;
        } elsif ( $line =~ /^\s*Resolution\s*:\s*(.+)/ ) {
            $update_params{resolution} = $1;
        } elsif ( $line =~ /^\s*Patch-complexity\s*:\s*(.+)/ ) {
            $update_params{cf_patch_complexity} = $1;
        } elsif ( $line =~ /^\s*Sponsors\s*:\s*(.+)/ ) {
            push @{ $update_params{cf_sponsors} }, $1;
        } elsif ( $line =~ /^\s*Sponsorship\s*:\s*(.+)/ ) {
            $update_params{cf_sponsorship} = $1;
        } elsif ( $line =~ /^\s*Depends\s*:\s*([Bb][Uu][Gg])?\s*(\d+)/ ) {
            push @{ $update_params{depends_on} }, $2;
        } elsif ( $line =~ /^\s*Obsoletes\s*:\s*(\d+)/ ) {
            push @obsoletes, $1;
        } else {
            push @comment_lines, $line;
        }
    }

    my $comment = join( "\n", @comment_lines );
    $comment =~ s/^\s+|\s+$//g;

    # Early return if no changes
    return 0 unless %update_params || $comment || @obsoletes;

    # Only fetch bug data if we have changes to process
    my $bug = GitBz::Progress::with_spinner(
        "Fetching bug $bug_ref",
        sub {
            return GitBz::Bug->get( $client, $bug_ref );
        },
        1
    );
    my $changed = 0;

    # Check if there are actual changes before making API call
    my %actual_changes;
    if ( $update_params{status} && $update_params{status} ne $bug->status ) {
        $actual_changes{status} = $update_params{status};
    }
    if ( $update_params{resolution} && $update_params{resolution} ne ( $bug->resolution || '' ) ) {
        $actual_changes{resolution} = $update_params{resolution};
    }
    if (   $update_params{cf_patch_complexity}
        && $update_params{cf_patch_complexity} ne ( $bug->cf_patch_complexity || '' ) )
    {
        $actual_changes{cf_patch_complexity} = $update_params{cf_patch_complexity};
    }
    if (   $update_params{cf_sponsorship}
        && $update_params{cf_sponsorship} ne ( $bug->cf_sponsorship || '' ) )
    {
        $actual_changes{cf_sponsorship} = $update_params{cf_sponsorship};
    }
    if ( $update_params{cf_sponsors} ) {
        my @new_sponsors = @{ $update_params{cf_sponsors} };
        my @old_sponsors = split /,\s*/, ( $bug->cf_sponsors || '' );
        @old_sponsors = grep { $_ } @old_sponsors;    # Remove empty strings

        my @to_add = grep {
            my $new = $_;
            !grep { $_ eq $new } @old_sponsors
        } @new_sponsors;
        my @to_remove = grep {
            my $old = $_;
            !grep { $_ eq $old } @new_sponsors
        } @old_sponsors;

        if ( @to_add || @to_remove ) {
            my %sponsors_update;
            $sponsors_update{add}        = \@to_add    if @to_add;
            $sponsors_update{remove}     = \@to_remove if @to_remove;
            $actual_changes{cf_sponsors} = \%sponsors_update;
        }
    }
    if ( $update_params{depends_on} ) {
        my @new_depends = @{ $update_params{depends_on} };
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
            $depends_update{add}        = \@to_add    if @to_add;
            $depends_update{remove}     = \@to_remove if @to_remove;
            $actual_changes{depends_on} = \%depends_update;
        }
    }
    if ($comment) {
        $actual_changes{comment} = { body => $comment };
    }

    if (%actual_changes) {
        print "Updating bug $bug_ref:\n";

        # Queue field updates
        $bug->set_field( 'status',     $actual_changes{status} )     if $actual_changes{status};
        $bug->set_field( 'resolution', $actual_changes{resolution} ) if $actual_changes{resolution};
        $bug->set_field( 'cf_patch_complexity', $actual_changes{cf_patch_complexity} )
            if $actual_changes{cf_patch_complexity};
        $bug->set_sponsors( %{ $actual_changes{cf_sponsors} } ) if $actual_changes{cf_sponsors};
        $bug->set_field( 'cf_sponsorship', $actual_changes{cf_sponsorship} )
            if $actual_changes{cf_sponsorship};
        $bug->add_comment( $actual_changes{comment}{body} )   if $actual_changes{comment};
        $bug->set_depends( %{ $actual_changes{depends_on} } ) if $actual_changes{depends_on};

        $bug->_display_changes();
        my $spinner = GitBz::Progress::start_spinner("Updating bug fields");
        $bug->apply_updates();
        GitBz::Progress::stop_spinner( $spinner, 'success', "Bug fields updated" );
        $changed = 1;
    }

    # Handle obsoleting attachments
    if (@obsoletes) {
        my $attachments = GitBz::Progress::with_spinner(
            "Fetching attachments",
            sub {
                return $bug->attachments;
            },
            1
        );
        my %attach_lookup = map { $_->{id} => $_->{summary} } @$attachments;

        for my $attach_id (@obsoletes) {
            my $summary = $attach_lookup{$attach_id} || "Unknown";
            my $spinner = GitBz::Progress::start_spinner("Obsoleting attachment $attach_id");
            $bug->obsolete_attachment($attach_id);
            GitBz::Progress::stop_spinner( $spinner, 'success', "Obsoleted: $summary" );
            $changed = 1;
        }
    }

    if ($changed) {
        print "\n✓ Successfully updated bug $bug_ref\n";
    }

    return $changed;
}

=head2 extract_bug_ref

    my $bug_ref = $edit->extract_bug_ref($commit);

Extracts bug reference from commit message.

=cut

sub extract_bug_ref {
    my ( $self, $commit ) = @_;

    my $message = GitBz::Git->run( 'log', '--format=%B', '-1', $commit->{id} );

    if ( $message =~ /\b[Bb]ug\s+(\d+)\b/ ) {
        return $1;
    }

    return;
}

1;
