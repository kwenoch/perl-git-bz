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
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use GitBz::Bug;

plan tests => 8;

# Mock bug data helper
sub create_bug {
    my %data = @_;
    return bless {
        data => {
            id              => $data{id} || 12345,
            summary         => $data{summary} || 'Test bug',
            status          => $data{status} || 'NEW',
            cf_sponsors     => $data{cf_sponsors},
            cf_sponsorship  => $data{cf_sponsorship},
        },
        _attachments => [],
    }, 'GitBz::Bug';
}

# Test 1: cf_sponsors accessor returns value when set
{
    my $bug = create_bug(
        cf_sponsors => 'ACME Corp'
    );
    is($bug->cf_sponsors, 'ACME Corp', 'cf_sponsors returns value when set');
}

# Test 2: cf_sponsors accessor returns undef when not set
{
    my $bug = create_bug();
    is($bug->cf_sponsors, undef, 'cf_sponsors returns undef when not set');
}

# Test 3: cf_sponsors with multiple sponsors (comma-separated)
{
    my $bug = create_bug(
        cf_sponsors => 'ByWater Solutions, Catalyst IT'
    );
    is($bug->cf_sponsors, 'ByWater Solutions, Catalyst IT',
       'cf_sponsors returns comma-separated list');
}

# Test 4: cf_sponsors with empty string
{
    my $bug = create_bug(
        cf_sponsors => ''
    );
    is($bug->cf_sponsors, '', 'cf_sponsors returns empty string when empty');
}

# Test 5: cf_sponsorship accessor returns value when set
{
    my $bug = create_bug(
        cf_sponsorship => 'Sponsored'
    );
    is($bug->cf_sponsorship, 'Sponsored', 'cf_sponsorship returns value when set');
}

# Test 6: cf_sponsorship accessor returns undef when not set
{
    my $bug = create_bug();
    is($bug->cf_sponsorship, undef, 'cf_sponsorship returns undef when not set');
}

# Test 7: cf_sponsorship with different values
{
    my $bug = create_bug(
        cf_sponsorship => 'Seeking sponsor'
    );
    is($bug->cf_sponsorship, 'Seeking sponsor',
       'cf_sponsorship returns correct value');
}

# Test 8: Both sponsor fields set together
{
    my $bug = create_bug(
        cf_sponsors => 'University of the Arts London',
        cf_sponsorship => 'Sponsored'
    );
    is($bug->cf_sponsors, 'University of the Arts London',
       'Both sponsor fields work together');
}

done_testing();
