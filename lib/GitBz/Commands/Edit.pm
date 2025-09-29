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
use Getopt::Long qw(GetOptionsFromArray);
use Try::Tiny    qw(catch try);
use File::Temp;
use GitBz::Git;
use GitBz::Exception;

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
            $self->edit_bug( $arg, \%opts );
        } else {

            # Commit or revision range
            my @commits = GitBz::Git->get_commits($arg);
            GitBz::Exception->throw("No commits found") unless @commits;

            $self->edit_commits( \@commits, \%opts );
        }

        print "Edit completed successfully\n";
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

    $self->update_bug( $client, $bug_ref, $edited, $opts );
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
    for my $bug_ref ( keys %bugs ) {
        print "Editing bug $bug_ref...\n";
        $self->edit_bug_with_commits( $bug_ref, $bugs{$bug_ref}, $opts );
    }
}

sub edit_bug_with_commits {
    my ( $self, $bug_ref, $commits, $opts ) = @_;

    my $client = $self->{commands}->{client};
    my $bug    = $client->get_bug($bug_ref);
    GitBz::Exception->throw("Bug $bug_ref not found") unless $bug;

    my $template = $self->create_bug_template_with_commits( $bug, $commits, $opts );
    my $edited   = $self->edit_template($template);

    $self->update_bug( $client, $bug_ref, $edited, $opts );
}

sub create_bug_template {
    my ( $self, $bug, $opts ) = @_;

    my $template = "";

    if ( $opts->{fix} ) {
        $template .= "# Closing bug as FIXED\n";
        $template .= "Status: RESOLVED\n";
        $template .= "Resolution: FIXED\n\n";
    }

    $template .= "# Bug $bug->{id}: $bug->{summary}\n";
    $template .= "# Product: $bug->{product}\n";
    $template .= "# Component: $bug->{component}\n";
    $template .= "# Status: $bug->{status}\n\n";

    $template .= "Comment:\n";
    $template .= "# Enter your comment above. Lines starting with # are ignored.\n";

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
    print $temp $template;
    close $temp;

    my $editor = $ENV{EDITOR} || 'vi';
    system( $editor, $temp->filename );

    open my $fh, '<', $temp->filename or die "Cannot read temp file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    # Remove comment lines
    my @lines = grep { !/^#/ } split /\n/, $content;
    return join( "\n", @lines );
}

sub update_bug {
    my ( $self, $client, $bug_ref, $edited, $opts ) = @_;

    my %update_params;

    # Parse edited content
    my @lines      = split /\n/, $edited;
    my $comment    = '';
    my $in_comment = 0;

    for my $line (@lines) {
        if ( $line =~ /^Status:\s*(.+)/ ) {
            $update_params{status} = $1;
        } elsif ( $line =~ /^Resolution:\s*(.+)/ ) {
            $update_params{resolution} = $1;
        } elsif ( $line =~ /^Comment:/ ) {
            $in_comment = 1;
        } elsif ( $in_comment && $line =~ /\S/ ) {
            $comment .= $line . "\n";
        }
    }

    if ($comment) {
        $update_params{comment} = { body => $comment };
    }

    if (%update_params) {
        $client->update_bug( $bug_ref, %update_params );
        print "Updated bug $bug_ref\n";
    }
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
