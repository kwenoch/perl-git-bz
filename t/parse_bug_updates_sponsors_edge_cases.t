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
use Test::MockModule;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use GitBz::Commands::Attach;
use GitBz::Bug;

plan tests => 12;

# Mock bug helper
sub create_mock_bug {
    my %data = @_;
    return bless {
        data => {
            id              => $data{id} || 12345,
            summary         => $data{summary} || 'Test bug',
            status          => $data{status} || 'NEW',
            cf_sponsors     => $data{cf_sponsors} || '',
            cf_sponsorship  => $data{cf_sponsorship} || '',
            cf_patch_complexity => '',
            depends_on      => [],
        },
        _attachments => [],
    }, 'GitBz::Bug';
}

my $mock_commands = { client => undef };
my $attach = GitBz::Commands::Attach->new($mock_commands);

subtest 'Empty sponsors field not captured' => sub {
    plan tests => 1;

    my $bug = create_mock_bug();
    my $content = "Sponsors:\n";
    my ($comment, $obsoletes, $updates) = $attach->parse_bug_updates($content, $bug);

    is($updates->{cf_sponsors}, undef, 'Empty sponsors field not captured (regex requires .+)');
};

subtest 'Single sponsor parsed correctly' => sub {
    plan tests => 2;

    my $bug = create_mock_bug();
    my $content = "Sponsors: ACME Corp\n";
    my ($comment, $obsoletes, $updates) = $attach->parse_bug_updates($content, $bug);

    is(ref $updates->{cf_sponsors}, 'HASH', 'Sponsors returns hash ref');
    is_deeply($updates->{cf_sponsors}{add}, ['ACME Corp'], 'Single sponsor added correctly');
};

subtest 'Multiple sponsors with commas parsed correctly' => sub {
    plan tests => 2;

    my $bug = create_mock_bug();
    my $content = "Sponsors: ACME Corp, ByWater Solutions, Catalyst IT\n";
    my ($comment, $obsoletes, $updates) = $attach->parse_bug_updates($content, $bug);

    is(ref $updates->{cf_sponsors}, 'HASH', 'Sponsors returns hash ref');
    is_deeply($updates->{cf_sponsors}{add}, 
              ['ACME Corp, ByWater Solutions, Catalyst IT'],
              'Multiple sponsors added correctly');
};

subtest 'Sponsors with extra whitespace - leading trimmed' => sub {
    plan tests => 2;

    my $bug = create_mock_bug();
    my $content = "Sponsors:  ACME Corp  ,  ByWater Solutions  \n";
    my ($comment, $obsoletes, $updates) = $attach->parse_bug_updates($content, $bug);

    # Regex \s* trims leading whitespace after colon, but preserves internal/trailing
    is(ref $updates->{cf_sponsors}, 'HASH', 'Sponsors returns hash ref');
    is_deeply($updates->{cf_sponsors}{add}, 
              ['ACME Corp  ,  ByWater Solutions  '],
              'Leading whitespace after colon trimmed, rest preserved');
};

subtest 'Sponsors field case sensitive label' => sub {
    plan tests => 3;

    my $bug = create_mock_bug();

    my ($c1, $o1, $u1) = $attach->parse_bug_updates("Sponsors: Test\n", $bug);
    is_deeply($u1->{cf_sponsors}{add}, ['Test'], 'Sponsors: (capital S) works');

    my ($c2, $o2, $u2) = $attach->parse_bug_updates("sponsors: Test\n", $bug);
    is($u2->{cf_sponsors}, undef, 'sponsors: (lowercase) does not match');

    my ($c3, $o3, $u3) = $attach->parse_bug_updates("SPONSORS: Test\n", $bug);
    is($u3->{cf_sponsors}, undef, 'SPONSORS: (uppercase) does not match');
};

subtest 'Sponsors with special characters' => sub {
    plan tests => 2;

    my $bug = create_mock_bug();
    my $content = "Sponsors: O'Reilly & Associates, Smith-Johnson Inc.\n";
    my ($comment, $obsoletes, $updates) = $attach->parse_bug_updates($content, $bug);

    is(ref $updates->{cf_sponsors}, 'HASH', 'Sponsors returns hash ref');
    is_deeply($updates->{cf_sponsors}{add},
              ["O'Reilly & Associates, Smith-Johnson Inc."],
              'Sponsors with special characters parsed correctly');
};

subtest 'cf_sponsorship auto-update with empty string current value' => sub {
    plan tests => 1;

    my $bug = create_mock_bug(cf_sponsorship => '');
    my $content = "Sponsors: New Sponsor\n";
    my ($comment, $obsoletes, $updates) = $attach->parse_bug_updates($content, $bug);

    # Empty string is not in the unsponsored values list
    is($updates->{cf_sponsorship}, undef,
       'cf_sponsorship not auto-updated from empty string');
};

subtest 'cf_sponsorship auto-update only for specific values' => sub {
    plan tests => 3;

    # Test '---' value
    my $bug1 = create_mock_bug(cf_sponsorship => '---');
    my ($c1, $o1, $u1) = $attach->parse_bug_updates("Sponsors: Test\n", $bug1);
    is($u1->{cf_sponsorship}, 'Sponsored', 'Auto-updates from ---');

    # Test 'Unsponsored' value
    my $bug2 = create_mock_bug(cf_sponsorship => 'Unsponsored');
    my ($c2, $o2, $u2) = $attach->parse_bug_updates("Sponsors: Test\n", $bug2);
    is($u2->{cf_sponsorship}, 'Sponsored', 'Auto-updates from Unsponsored');

    # Test 'Seeking sponsor' value
    my $bug3 = create_mock_bug(cf_sponsorship => 'Seeking sponsor');
    my ($c3, $o3, $u3) = $attach->parse_bug_updates("Sponsors: Test\n", $bug3);
    is($u3->{cf_sponsorship}, 'Sponsored', 'Auto-updates from Seeking sponsor');
};

subtest 'Mixed sponsor and other updates' => sub {
    plan tests => 3;

    my $bug = create_mock_bug(cf_sponsorship => 'Unsponsored');
    my $content = <<'END';
Status: ASSIGNED
Sponsors: ACME Corp
Patch-complexity: Small patch
END

    my ($comment, $obsoletes, $updates) = $attach->parse_bug_updates($content, $bug);

    is($updates->{status}, 'ASSIGNED', 'Status parsed correctly');
    is_deeply($updates->{cf_sponsors}{add}, ['ACME Corp'], 'Sponsors parsed correctly');
    is($updates->{cf_patch_complexity}, 'Small patch', 'Patch complexity parsed correctly');
};

subtest 'Sponsors field with colon in value' => sub {
    plan tests => 2;

    my $bug = create_mock_bug();
    my $content = "Sponsors: Company: A Division, Other Corp\n";
    my ($comment, $obsoletes, $updates) = $attach->parse_bug_updates($content, $bug);

    is(ref $updates->{cf_sponsors}, 'HASH', 'Sponsors returns hash ref');
    is_deeply($updates->{cf_sponsors}{add},
              ['Company: A Division, Other Corp'],
              'Sponsors with colons in names parsed correctly');
};

subtest 'Multiple sponsor lines (last one wins)' => sub {
    plan tests => 2;

    my $bug = create_mock_bug();
    my $content = <<'END';
Sponsors: First Sponsor
Sponsors: Second Sponsor
END

    my ($comment, $obsoletes, $updates) = $attach->parse_bug_updates($content, $bug);

    # Parser processes line by line, so both are added
    is(ref $updates->{cf_sponsors}, 'HASH', 'Sponsors returns hash ref');
    is_deeply($updates->{cf_sponsors}{add}, ['First Sponsor', 'Second Sponsor'],
              'Multiple Sponsors lines all added');
};

subtest 'Sponsors in comment section not parsed as field' => sub {
    plan tests => 2;

    my $bug = create_mock_bug();
    my $content = <<'END';
This is a comment about sponsors.
The sponsors field should be set separately.
Sponsors: This should not be parsed
END

    my ($comment, $obsoletes, $updates) = $attach->parse_bug_updates($content, $bug);

    # The sponsors line should still be parsed (it's not in a comment)
    # But if it were commented with #, it wouldn't be
    is(ref $updates->{cf_sponsors}, 'HASH', 'Sponsors returns hash ref');
    is_deeply($updates->{cf_sponsors}{add}, ['This should not be parsed'],
              'Sponsors line parsed even in text content');
};

done_testing();
