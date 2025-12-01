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
use Cwd qw(getcwd);

BEGIN {
    use_ok('GitBz::Git');
}

# Change to test git repository
my $original_dir = getcwd();
chdir "$FindBin::Bin/data/git_repo" or die "Cannot chdir to test repo: $!";

END {
    chdir $original_dir if defined $original_dir;
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

    # Test with a known commit from the test repository (using second commit which has a parent)
    @commits = GitBz::Git->get_commits("a232c458fdec49418c9369ba2cf9d305264791f3");
    is_deeply(
        \@commits,
        [ { subject => q{Second test commit}, id => q{a232c458fdec49418c9369ba2cf9d305264791f3} } ],
        'Full hash returns correct commit and subject'
    );

    @commits = GitBz::Git->get_commits("a232c45");
    is_deeply(
        \@commits,
        [ { subject => q{Second test commit}, id => q{a232c458fdec49418c9369ba2cf9d305264791f3} } ],
        'Short hash expands to full hash with correct subject'
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
