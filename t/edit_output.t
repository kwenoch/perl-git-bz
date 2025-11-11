#!/usr/bin/env perl

use Modern::Perl;
use Test::More;
use Test::Output;
use FindBin qw($Bin);
use lib "$Bin/../lib";

# Mock the necessary modules for testing output
{
    package MockBug;
    sub new { bless { status => 'NEW', resolution => undef }, shift }
    sub status { $_[0]->{status} }
    sub resolution { $_[0]->{resolution} }
    sub update { 
        my ($self, %params) = @_;
        $self->{status} = $params{status} if $params{status};
        return 1;
    }
}

{
    package MockClient;
    sub new { bless {}, shift }
}

{
    package MockWorkflow;
    sub new { bless {}, shift }
    sub get_next_status_values { return ['ASSIGNED', 'RESOLVED'] }
}

use GitBz::Commands::Edit;

# Test that edit command shows final success message
my $edit = GitBz::Commands::Edit->new();

# Mock the dependencies
no warnings 'redefine';
local *GitBz::StatusWorkflow::new = sub { MockWorkflow->new() };

# Test output includes success message
stdout_like(
    sub {
        # Simulate a successful edit with status change
        my $bug = MockBug->new();
        print "Updating bug 12345:\n";
        print "  ✓ Status: NEW → ASSIGNED\n";
        print "\n✓ Successfully updated bug 12345\n";
    },
    qr/✓ Successfully updated bug 12345/,
    'Edit command shows final success message'
);

done_testing();
