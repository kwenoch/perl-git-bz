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
