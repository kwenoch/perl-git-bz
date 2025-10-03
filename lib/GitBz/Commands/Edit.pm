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

use Modern::Perl;

use utf8;

use Getopt::Long qw(GetOptionsFromArray);
use Try::Tiny    qw(catch try);
use File::Temp;
use GitBz::Git;
use GitBz::Exception;
use GitBz::StatusWorkflow;

sub new {
    my ( $class, $commands ) = @_;
    bless { commands => $commands }, $class;
}

sub execute {
    my ( $self, @args ) = @_;

    my %opts;

    GetOptionsFromArray(
        \@args,
        'pushed'       => \$opts{pushed},
        'add-url|u'    => \$opts{'add-url'},
        'no-add-url|n' => sub { $opts{'add-url'} = 0 },
        'fix=s'        => \$opts{fix},
        'bugzilla|b=s' => \$opts{bugzilla},
    ) or GitBz::Exception->throw("Invalid options");

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

sub edit_bug {
    my ( $self, $bug_ref, $opts ) = @_;

    my $client = $self->{commands}->{client};
    my $bug    = $client->get_bug($bug_ref);
    GitBz::Exception->throw("Bug $bug_ref not found") unless $bug;

    my $template = $self->create_bug_template( $bug, $opts );
    my $edited   = $self->edit_template($template);

    return $self->update_bug( $client, $bug_ref, $edited, $opts );
}

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

sub edit_bug_with_commits {
    my ( $self, $bug_ref, $commits, $opts ) = @_;

    my $client = $self->{commands}->{client};
    my $bug    = $client->get_bug($bug_ref);
    GitBz::Exception->throw("Bug $bug_ref not found") unless $bug;

    my $template = $self->create_bug_template_with_commits( $bug, $commits, $opts );
    my $edited   = $self->edit_template($template);

    return $self->update_bug( $client, $bug_ref, $edited, $opts );
}

sub create_bug_template {
    my ( $self, $bug, $opts ) = @_;
    my $client = $self->{commands}->{client};

    my $template = "";
    $template .= "# Bug $bug->{id} - $bug->{summary}\n\n";
    
    # Show existing patches for obsoleting
    my $attachments = $client->get_attachments($bug->{id});
    if ( $attachments && @$attachments ) {
        for my $patch ( @$attachments ) {
            next unless $patch->{is_patch} && !$patch->{is_obsolete};
            $template .= "#Obsoletes: $patch->{id} - $patch->{summary}\n";
        }
        $template .= "\n";
    }
    
    # Add status options
    my $workflow = GitBz::StatusWorkflow->new($client);
    $template .= "# Current status: $bug->{status}\n";
    my $status_values = $workflow->get_next_status_values($bug->{status});
    for my $status (@$status_values) {
        $template .= "# Status: $status\n";
    }
    $template .= "\n";
    
    # Add patch complexity options
    my $complexity = $bug->{cf_patch_complexity} || "";
    $template .= "# Current patch-complexity: $complexity\n";
    my $complexity_values = $client->get_field_values('cf_patch_complexity');
    if ($complexity_values) {
        for my $comp (@$complexity_values) {
            $template .= "# Patch-complexity: $comp\n";
        }
    }
    $template .= "\n";
    
    # Add depends options
    my $depends = $bug->{depends_on} || [];
    my $depends_str = ref($depends) eq 'ARRAY' ? join(' ', @$depends) : $depends;
    $template .= "# Current depends: $depends_str\n";
    $template .= "# Depends: bug xxxx\n";
    $template .= "# Depends: bug yyyy\n";
    $template .= "\n";
    
    $template .= "# Enter comment below. Lines starting with '#' will be ignored.\n";
    $template .= "# To obsolete patches, uncomment the appropriate Obsoletes lines.\n";

    return $template;
}

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
    my $bug = $client->get_bug($bug_ref);
    my $changed = 0;
    
    # Check if there are actual changes before making API call
    my %actual_changes;
    if ($update_params{status} && $update_params{status} ne $bug->{status}) {
        $actual_changes{status} = $update_params{status};
    }
    if ($update_params{resolution} && $update_params{resolution} ne ($bug->{resolution} || '')) {
        $actual_changes{resolution} = $update_params{resolution};
    }
    if ($update_params{cf_patch_complexity} && $update_params{cf_patch_complexity} ne ($bug->{cf_patch_complexity} || '')) {
        $actual_changes{cf_patch_complexity} = $update_params{cf_patch_complexity};
    }
    if ($update_params{depends_on}) {
        $actual_changes{depends_on} = $update_params{depends_on};
    }
    if ($comment) {
        $actual_changes{comment} = { body => $comment };
    }
    
    if (%actual_changes) {
        print "Updating bug $bug_ref\n";
        
        # Show field changes
        if ($actual_changes{status}) {
            print "Status changed: $bug->{status} → $actual_changes{status}\n";
        }
        if ($actual_changes{resolution}) {
            my $old = $bug->{resolution} || 'none';
            print "Resolution changed: $old → $actual_changes{resolution}\n";
        }
        if ($actual_changes{cf_patch_complexity}) {
            my $old = $bug->{cf_patch_complexity} || 'none';
            print "Patch-complexity changed: $old → $actual_changes{cf_patch_complexity}\n";
        }
        if ($actual_changes{comment}) {
            print "Added comment\n";
        }
        
        $client->update_bug( $bug_ref, %actual_changes );
        $changed = 1;
    }
    
    # Handle obsoleting attachments
    if (@obsoletes) {
        my $attachments = $client->get_attachments($bug_ref);
        my %attach_lookup = map { $_->{id} => $_->{summary} } @$attachments;
        
        for my $attach_id (@obsoletes) {
            $client->obsolete_attachment($attach_id);
            my $summary = $attach_lookup{$attach_id} || "Unknown";
            print "Obsoleted attachment $attach_id - $summary\n";
            $changed = 1;
        }
    }
    
    return $changed;
}

sub extract_bug_ref {
    my ( $self, $commit ) = @_;

    my $message = GitBz::Git->run( 'log', '--format=%B', '-1', $commit->{id} );

    if ( $message =~ /\b[Bb]ug\s+(\d+)\b/ ) {
        return $1;
    }

    return;
}

1;
