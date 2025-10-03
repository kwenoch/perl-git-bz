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
        'edit|e' => \$opts{edit},
    ) or GitBz::Exception->throw("Invalid options");

    return try {
        my ( $bug_ref, $commit_range ) = $self->parse_args(@args);
        my @commits = GitBz::Git->get_commits($commit_range);

        GitBz::Exception->throw("No commits found") unless @commits;

        $self->attach_patches( $bug_ref, \@commits, \%opts );

        print "Successfully attached " . scalar(@commits) . " patch(es) to bug $bug_ref\n";
    } catch {
        GitBz::Exception->throw("Attach failed: $_");
    };
}

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

sub extract_bug_ref {
    my ( $self, $commit ) = @_;

    my $message = GitBz::Git->run( 'log', '--format=%B', '-1', $commit->{id} );

    # Look for Bug NNNN or bug NNNN
    if ( $message =~ /\b[Bb]ug\s+(\d+)\b/ ) {
        return $1;
    }

    return;
}

sub attach_patches {
    my ( $self, $bug_ref, $commits, $opts ) = @_;

    my $client = $self->{commands}->{client};
    my $bug    = $client->get_bug($bug_ref);

    my $is_first = 1;
    for my $commit (@$commits) {
        my $patch       = GitBz::Git->format_patch( $commit->{id} . '^..' . $commit->{id} );
        my $filename    = sprintf( "%s.patch", substr( $commit->{id}, 0, 7 ) );
        my $description = $commit->{subject};
        my $body        = GitBz::Git->run( 'log', '--format=%b', '-1', $commit->{id} );
        my $comment     = $body || "Patch from commit " . substr( $commit->{id}, 0, 7 );
        my @obsoletes;

        if ( $opts->{edit} && $is_first ) {
            ( $description, $comment, my $obsoletes_ref ) = $self->edit_attachment_comment( $bug, $commit );
            @obsoletes = @$obsoletes_ref if $obsoletes_ref;
        }

        $client->add_attachment(
            $bug_ref,
            $patch,
            $filename,
            $description,
            comment   => $comment,
            obsoletes => \@obsoletes
        );

        print "Attached: $description\n";
        $is_first = 0;
    }
}

sub edit_attachment_comment {
    my ( $self, $bug, $commit ) = @_;

    my $template = "";
    $template .= "# Attachment to Bug $bug->{id} - $bug->{summary}\n\n";
    $template .= $commit->{subject} . "\n\n";

    # Add commit body as initial comment
    my $body = GitBz::Git->run( 'log', '--format=%b', '-1', $commit->{id} );
    $template .= $body . "\n\n" if $body;

    # Show existing patches for obsoleting
    if ( $bug->{attachments} && @{ $bug->{attachments} } ) {
        for my $patch ( @{ $bug->{attachments} } ) {
            next unless $patch->{is_patch};
            my $obsoleted = ( $commit->{subject} eq $patch->{summary} ) ? "" : "#";
            $template .= "${obsoleted}Obsoletes: $patch->{id} - $patch->{summary}\n";
        }
        $template .= "\n";
    }

    # Add status options
    my $client   = $self->{commands}->{client};
    my $workflow = GitBz::StatusWorkflow->new($client);
    $template .= "# Current status: $bug->{status}\n";
    my $status_values = $workflow->get_next_status_values( $bug->{status} );
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
    my $depends     = $bug->{depends_on} || [];
    my $depends_str = ref($depends) eq 'ARRAY' ? join( ' ', @$depends ) : $depends;
    $template .= "# Current depends: $depends_str\n";
    $template .= "# Depends: bug xxxx\n";
    $template .= "# Depends: bug yyyy\n";
    $template .= "\n";

    $template .= "# Please edit the description (first line) and comment (other lines).\n";
    $template .= "# Lines starting with '#' will be ignored. Delete everything to abort.\n";
    $template .= "# To obsolete existing patches, uncomment the appropriate lines.\n";

    my $edited = $self->edit_template($template);
    return $self->parse_edited_content($edited);
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

sub parse_edited_content {
    my ( $self, $content ) = @_;

    my @lines = split /\n/, $content;
    my @non_comment_lines = grep { !/^#/ && /\S/ } @lines;    # Also filter empty lines

    my $description = shift @non_comment_lines || "";
    $description =~ s/^\s+|\s+$//g;

    my @obsoletes;
    my @comment_lines;

    for my $line (@non_comment_lines) {
        if ( $line =~ /^\s*Obsoletes\s*:\s*(\d+)/ ) {
            push @obsoletes, $1;
        } else {
            push @comment_lines, $line;
        }
    }

    my $comment = join( "\n", @comment_lines );
    $comment =~ s/^\s+|\s+$//g;

    GitBz::Exception->throw("Empty description, aborting\n") unless $description;

    return ( $description, $comment, \@obsoletes );
}

1;
