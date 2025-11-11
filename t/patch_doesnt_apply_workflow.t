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

use GitBz::StatusWorkflow;

# Mock client for testing
my $mock_client = bless {}, 'MockClient';

my $workflow = GitBz::StatusWorkflow->new($mock_client);

# Test that 'Patch doesn't apply' can transition to required statuses
my $transitions = $workflow->get_next_status_values("Patch doesn't apply");

my @expected = ('ASSIGNED', 'RESOLVED', 'BLOCKED', 'In Discussion', 'Needs Signoff', 'Signed Off', 'Passed QA', 'Failed QA');

is_deeply(
    [sort @$transitions],
    [sort @expected],
    "'Patch doesn't apply' can transition to all required statuses"
);

# Test that the transition list contains all expected statuses
for my $status (@expected) {
    ok(
        (grep { $_ eq $status } @$transitions),
        "'Patch doesn't apply' can transition to '$status'"
    );
}

done_testing();
