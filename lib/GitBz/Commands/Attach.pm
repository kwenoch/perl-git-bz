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
use Getopt::Long qw(GetOptionsFromArray);
use Try::Tiny    qw(catch try);
use GitBz::Git;
use GitBz::Exception;

sub new {
    my ( $class, $commands ) = @_;
    bless { commands => $commands }, $class;
}

sub execute {
    my ( $self, @args ) = @_;

    my %opts = (
        'add-url' => undef,
    );

    GetOptionsFromArray(
        \@args,
        'edit|e'       => \$opts{edit},
        'mail|m'       => \$opts{mail},
        'add-url|u'    => \$opts{'add-url'},
        'no-add-url|n' => sub { $opts{'add-url'} = 0 },
        'bugzilla|b=s' => \$opts{bugzilla},
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

    for my $commit (@$commits) {
        my $patch    = GitBz::Git->format_patch( $commit->{id} . '^..' . $commit->{id} );
        my $filename = sprintf( "%s.patch", substr( $commit->{id}, 0, 7 ) );

        $client->add_attachment(
            $bug_ref,
            $patch,
            $filename,
            $commit->{subject},
            comment => "Patch from commit " . substr( $commit->{id}, 0, 7 )
        );

        print "Attached: $commit->{subject}\n";
    }
}

1;
