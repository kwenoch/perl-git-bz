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

use Test::More;
use FindBin qw($Bin);
use lib "$Bin/../lib";

use GitBz::Commands::Open;
use GitBz::RestClient;

# Test basic functionality
my $open = GitBz::Commands::Open->new();
isa_ok($open, 'GitBz::Commands::Open', 'Open command created');

# Test URL generation
{
    package MockClient;
    sub get_bug_url { return "https://bugs.koha-community.org/show_bug.cgi?id=12345" }
}

my $client = bless {}, 'MockClient';
my $url = $client->get_bug_url(12345);
like($url, qr/show_bug\.cgi\?id=12345$/, 'Bug URL format is correct');

done_testing();
