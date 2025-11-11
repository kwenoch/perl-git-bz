#!/usr/bin/env perl

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
