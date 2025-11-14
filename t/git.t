#!/usr/bin/env perl

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

use Test::More tests => 3;
use Test::Exception;
use FindBin;
use lib "$FindBin::Bin/../lib";

BEGIN {
    use_ok('GitBz::Git');
}

subtest 'run() tests' => sub {

    plan tests => 2;

    lives_ok { GitBz::Git->run( 'status', '--porcelain' ) } 'Git status runs';

    my $result = GitBz::Git->run( 'rev-parse', 'HEAD' );
    like( $result, qr/^[a-f0-9]{40}$/, 'Returns commit hash' );
};

subtest 'get_commits() tests' => sub {

    plan tests => 12;

    my @commits = GitBz::Git->get_commits("HEAD");
    is( scalar(@commits), 1 );

    @commits = GitBz::Git->get_commits("HEAD~1");
    is( scalar(@commits), 1 );

    @commits = GitBz::Git->get_commits("HEAD~1");
    is( scalar(@commits), 1 );

    @commits = GitBz::Git->get_commits("HEAD~3..HEAD");
    is( scalar(@commits), 3 );

    @commits = GitBz::Git->get_commits("HEAD~3..");
    is( scalar(@commits), 3 );

    @commits = GitBz::Git->get_commits("HEAD~3..HEAD~1");
    is( scalar(@commits), 2 );

    throws_ok {
        @commits = GitBz::Git->get_commits("HEAD..HEAD");
    }
    "GitBz::Exception::Git";

    throws_ok {
        @commits = GitBz::Git->get_commits("..HEAD");
        is( scalar(@commits), 0 );
    }
    "GitBz::Exception::Git";

    @commits = GitBz::Git->get_commits("97e231b0c71938f2ff7ca16fec4bb1cec16c0abd");
    is_deeply(
        \@commits,
        [ { subject => q{[#14] Fix inconsistent shebang}, id => q{97e231b0c71938f2ff7ca16fec4bb1cec16c0abd} } ]
    );

    @commits = GitBz::Git->get_commits("97e231b");
    is_deeply(
        \@commits,
        [ { subject => q{[#14] Fix inconsistent shebang}, id => q{97e231b0c71938f2ff7ca16fec4bb1cec16c0abd} } ]
    );

    # reverse order
    @commits = GitBz::Git->get_commits("HEAD~3..");
    my $HEAD = qx{git rev-parse HEAD};
    chomp $HEAD;
    is( $commits[2]->{id}, $HEAD );
    my $HEAD2 = qx{git rev-parse HEAD~2};
    chomp $HEAD2;
    is( $commits[0]->{id}, $HEAD2 );
};
