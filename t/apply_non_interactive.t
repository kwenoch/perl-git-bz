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
use Test::Exception;
use Try::Tiny;
use FindBin;
use lib "$FindBin::Bin/../lib";

use GitBz::Commands::Apply;
use GitBz::Exception;

=head1 NAME

t/apply_non_interactive.t - Test non-interactive mode of should_follow_dependency

=head1 DESCRIPTION

Tests the should_follow_dependency method in non-interactive mode:
- With a policy restricting which statuses to follow
- Without a policy (follow all statuses)
- Exception handling when dependency status is not allowed

=cut

my $apply = GitBz::Commands::Apply->new(undef);

subtest 'non-interactive with follow_status_set policy' => sub {
    plan tests => 5;

    my $opts = {
        non_interactive  => 1,
        follow_status_set => { 'Passed QA' => 1 }
    };

    # Test: Passed QA is in the allowed set, should return 1
    my $result;
    lives_ok {
        $result = $apply->should_follow_dependency(100, 'Passed QA', $opts);
    } 'no exception when following allowed status';
    ok($result, 'should_follow_dependency returns true for status in follow_status_set');

    # Test: Needs Signoff is not in the allowed set, should throw
    throws_ok {
        $apply->should_follow_dependency(100, 'Needs Signoff', $opts);
    } 'GitBz::Exception::DependencyNotReady', 'throws DependencyNotReady when status not in follow_status_set';

    # Verify the exception has correct fields
    my $exc;
    try {
        $apply->should_follow_dependency(100, 'Needs Signoff', $opts);
    } catch {
        $exc = $_;
    };

    is($exc->dep_id, 100, 'exception dep_id field is correct');
    is($exc->status, 'Needs Signoff', 'exception status field is correct');
};

subtest 'non-interactive without follow_status_set (follow all)' => sub {
    plan tests => 10;

    my $opts = {
        non_interactive => 1
        # no follow_status_set defined
    };

    # Test: Any status should return 1
    my @statuses = ('Needs Signoff', 'Passed QA', 'Signed Off', 'NEW', 'CLOSED');

    for my $status (@statuses) {
        my $result;
        lives_ok {
            $result = $apply->should_follow_dependency(200, $status, $opts);
        } "no exception for status '$status' when follow_status_set undefined";
        ok($result, "should_follow_dependency returns true for status '$status' when no policy set");
    }
};

done_testing();
