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
        chomp $stdout if $stdout;
        return $stdout || '';
    } catch {
        GitBz::Exception::Git->throw($_);
    };
}

sub rev_list {
    my ( $class, @args ) = @_;
    my $output = $class->run( 'rev-list', '--pretty=format:%s', @args );

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

    # Try as single commit first
    my $rev = try { $class->run( 'rev-parse', $range, '--verify' ) } catch { undef };

    if ($rev) {
        return $class->rev_list( $rev, '--max-count=1' );
    } else {
        return $class->rev_list($range);
    }
}

1;
