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

use Modern::Perl;

use Encode qw(decode);
use IPC::Run3;
use Try::Tiny qw(catch try);
use GitBz::Exception;

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
            $stdout = decode( 'UTF-8', $stdout, Encode::FB_CROAK | Encode::LEAVE_SRC );
            chomp $stdout;
        }
        return $stdout || '';
    } catch {
        GitBz::Exception::Git->throw($_);
    };
}

sub rev_list {
    my ( $class, @args ) = @_;

    unshift( @args, '--pretty=format:%s' );
    unshift( @args, '--max-count=1' )
        if $args[1] eq 'HEAD';

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

sub format_patch {
    my ( $class, $range ) = @_;
    return $class->run( 'format-patch', '--stdout', '-M', $range );
}

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
