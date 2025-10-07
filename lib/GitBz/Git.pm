package GitBz::Git;

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

GitBz::Git - Git command wrapper and utilities

=head1 SYNOPSIS

    use GitBz::Git;
    
    my $output = GitBz::Git->run('log', '--oneline', '-5');
    my @commits = GitBz::Git->get_commits('HEAD~3..HEAD');
    my $patch = GitBz::Git->format_patch('abc123^..abc123');

=head1 DESCRIPTION

Provides a wrapper around Git commands with proper error handling and UTF-8 support.
Includes utilities for commit parsing and patch generation.

=cut

use Modern::Perl;

use Encode qw(decode);
use IPC::Run3;
use Try::Tiny qw(catch try);
use GitBz::Exception;

=head2 run

    my $output = GitBz::Git->run($command, @args);

Executes a Git command and returns the output.
Throws GitBz::Exception::Git on failure.

=cut

sub run {
    my ( $class, $command, @args ) = @_;

    my @cmd = ( 'git', $command, @args );
    my ( $stdout, $stderr );

    return try {
        run3 \@cmd, \undef, \$stdout, \$stderr;
        if ( $? != 0 ) {
            GitBz::Exception::Git->throw("Git command failed: $stderr");
        }
        if ($stdout) {
            chomp $stdout;
        }
        return $stdout || '';
    } catch {
        GitBz::Exception::Git->throw($_);
    };
}

=head2 rev_list

    my @commits = GitBz::Git->rev_list(@args);

Runs git rev-list and returns an array of commit hashrefs with 'id' and 'subject' keys.

=cut

sub rev_list {
    my ( $class, @args ) = @_;

    unshift( @args, '--pretty=format:%s' );
    unshift( @args, '--reverse' );  # Add --reverse to get chronological order (oldest first)
    unshift( @args, '--max-count=1' )
        if $args[2] eq 'HEAD';  # Adjust index due to --reverse insertion

    my $output = $class->run( 'rev-list', @args );

    my @commits;
    my @lines = split /\n/, $output;

    for ( my $i = 0 ; $i < @lines ; $i += 2 ) {
        next unless $lines[$i] =~ /^commit\s+([a-f0-9]+)/;
        my $id      = $1;
        my $subject = $lines[ $i + 1 ] || '';
        push @commits, { id => $id, subject => $subject };
    }

    return @commits;
}

=head2 format_patch

    my $patch = GitBz::Git->format_patch($range);

Generates a patch for the given commit range.

=cut

sub format_patch {
    my ( $class, $range ) = @_;
    return $class->run( 'format-patch', '--stdout', '-M', $range );
}

=head2 get_commits

    my @commits = GitBz::Git->get_commits($range);

Parses a commit range and returns commit information.
Handles both single commits and ranges correctly.

=cut

sub get_commits {
    my ( $class, $range ) = @_;

    # Try as single commit first - exactly like original git-bz
    my $rev = try {
        $class->run( 'rev-parse', $range, '--verify' );
    } catch {
        undef
    };

    if ($rev) {

        # Single commit - return just that one commit
        return $class->rev_list( '--max-count=1', $rev );
    } else {

        # Not a single commit, treat as range
        return $class->rev_list($range);
    }
}

1;
