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

# Mock classes for testing
{
    package MockBug;
    sub new { 
        my ($class, $attachments) = @_;
        bless { attachments => $attachments || [] }, $class;
    }
    sub attachments { $_[0]->{attachments} }
}

use GitBz::Commands::Attach;

my $attach = GitBz::Commands::Attach->new();

# Test auto-obsolete with exact matches
my @commits = (
    { subject => 'Bug 12345: Fix something' },
    { subject => 'Bug 12345: Add feature' }
);

my $attachments = [
    { id => 1, summary => 'Bug 12345: Fix something', is_patch => 1, is_obsolete => 0 },
    { id => 2, summary => 'Bug 12345: Different patch', is_patch => 1, is_obsolete => 0 },
    { id => 3, summary => 'Bug 12345: Add feature', is_patch => 1, is_obsolete => 0 }
];

my $bug = MockBug->new($attachments);

# Test that exact matches are auto-obsoleted
# Note: This test would need input mocking for the interactive part
# For now, we'll test the logic structure

# Test with no attachments
my $empty_bug = MockBug->new([]);
my @result = $attach->find_trivial_obsoletes($empty_bug, \@commits);
is_deeply(\@result, [], 'No obsoletes when no attachments');

# Test with non-patch attachments
my $non_patch_attachments = [
    { id => 1, summary => 'Bug 12345: Fix something', is_patch => 0, is_obsolete => 0 }
];
my $non_patch_bug = MockBug->new($non_patch_attachments);
@result = $attach->find_trivial_obsoletes($non_patch_bug, \@commits);
is_deeply(\@result, [], 'No obsoletes for non-patch attachments');

done_testing();
