
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
use Test::More;
use Test::Exception;
use FindBin;
use lib "$FindBin::Bin/../lib";

BEGIN {
    use_ok('GitBz::Git');
}

subtest 'run() tests' => sub {
    lives_ok { GitBz::Git->run( 'status', '--porcelain' ) } 'Git status runs';

    my $result = GitBz::Git->run( 'rev-parse', 'HEAD' );
    like( $result, qr/^[a-f0-9]{40}$/, 'Returns commit hash' );
};

done_testing;
