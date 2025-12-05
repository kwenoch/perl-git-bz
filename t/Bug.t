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
use utf8;
use open ':std', ':utf8';
use Test::More;
use Test::Output;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use GitBz::Bug;

# Mock bug helper
sub create_bug {
    my %data = @_;
    return bless {
        client => undef,
        data   => {
            id                  => $data{id}      || 12345,
            summary             => $data{summary} || 'Test bug',
            status              => $data{status}  || 'NEW',
            resolution          => $data{resolution},
            cf_patch_complexity => $data{cf_patch_complexity},
            cf_sponsors         => $data{cf_sponsors},
            cf_sponsorship      => $data{cf_sponsorship},
        },
        _attachments     => [],
        _display_rows    => [],
        _pending_updates => {},
        },
        'GitBz::Bug';
}

subtest 'set_field() tests' => sub {
    plan tests => 5;

    # Test 1: set_field adds to pending updates
    {
        my $bug = create_bug( status => 'NEW' );
        $bug->set_field( 'status', 'ASSIGNED' );
        is(
            $bug->{_pending_updates}{status}, 'ASSIGNED',
            'set_field adds to pending updates'
        );
    }

    # Test 2: set_field adds display row
    {
        my $bug = create_bug( status => 'NEW' );
        $bug->set_field( 'status', 'ASSIGNED' );
        is(
            scalar @{ $bug->{_display_rows} }, 1,
            'set_field adds display row'
        );
        is_deeply(
            $bug->{_display_rows}[0], [ 'Status', 'NEW', '→', 'ASSIGNED' ],
            'display row has correct format'
        );
    }

    # Test 3: set_field with undefined current value
    {
        my $bug = create_bug();
        $bug->set_field( 'cf_patch_complexity', 'Small patch' );
        is(
            $bug->{_pending_updates}{cf_patch_complexity}, 'Small patch',
            'set_field works with undefined current value'
        );
        is_deeply(
            $bug->{_display_rows}[0], [ 'Patch-complexity', '---', '→', 'Small patch' ],
            'display row shows --- for undefined value'
        );
    }
};

subtest 'add_comment() tests' => sub {
    plan tests => 3;

    # Test 1: add_comment adds to pending updates
    {
        my $bug = create_bug();
        $bug->add_comment('Test comment');
        is_deeply(
            $bug->{_pending_updates}{comment}, { body => 'Test comment' },
            'add_comment adds to pending updates'
        );
    }

    # Test 2: add_comment adds display row
    {
        my $bug = create_bug();
        $bug->add_comment('Test comment');
        is(
            scalar @{ $bug->{_display_rows} }, 1,
            'add_comment adds display row'
        );
        is_deeply(
            $bug->{_display_rows}[0], [ 'Comment', '', '', '(added)' ],
            'display row has correct format'
        );
    }
};

subtest 'set_depends() tests' => sub {
    plan tests => 4;

    # Test 1: set_depends with add
    {
        my $bug = create_bug();
        $bug->set_depends( add => [ 123, 456 ] );
        is_deeply(
            $bug->{_pending_updates}{depends_on}, { add => [ 123, 456 ] },
            'set_depends adds to pending updates'
        );
        is_deeply(
            $bug->{_display_rows}[0], [ 'Depends', '', '', '+ 123, 456' ],
            'display row shows added dependencies'
        );
    }

    # Test 2: set_depends with remove
    {
        my $bug = create_bug();
        $bug->set_depends( remove => [789] );
        is_deeply(
            $bug->{_display_rows}[0], [ 'Depends', '', '', '- 789' ],
            'display row shows removed dependencies'
        );
    }

    # Test 3: set_depends with both add and remove
    {
        my $bug = create_bug();
        $bug->set_depends( add => [123], remove => [456] );
        is(
            scalar @{ $bug->{_display_rows} }, 2,
            'set_depends with add and remove creates two display rows'
        );
    }
};

subtest 'set_sponsors() tests' => sub {
    plan tests => 4;
    
    # Test 1: set_sponsors with add
    {
        my $bug = create_bug();
        $bug->set_sponsors( add => [ 'Sponsor One', 'Sponsor Two' ] );
        is_deeply(
            $bug->{_pending_updates}{cf_sponsors}, { add => [ 'Sponsor One', 'Sponsor Two' ] },
            'set_sponsors adds to pending updates'
        );
        is_deeply(
            $bug->{_display_rows}[0], [ 'Sponsors', '', '', '+ Sponsor One, Sponsor Two' ],
            'display row shows added sponsors'
        );
    }
    
    # Test 2: set_sponsors with remove
    {
        my $bug = create_bug();
        $bug->set_sponsors( remove => ['Old Sponsor'] );
        is_deeply(
            $bug->{_display_rows}[0], [ 'Sponsors', '', '', '- Old Sponsor' ],
            'display row shows removed sponsors'
        );
    }
    
    # Test 3: set_sponsors with both add and remove
    {
        my $bug = create_bug();
        $bug->set_sponsors( add => ['New Sponsor'], remove => ['Old Sponsor'] );
        is(
            scalar @{ $bug->{_display_rows} }, 2,
            'set_sponsors with add and remove creates two display rows'
        );
    }
};

subtest 'add_display_row() tests' => sub {
    plan tests => 2;

    # Test 1: add_display_row adds row
    {
        my $bug = create_bug();
        $bug->add_display_row( 'Field', 'old', '→', 'new' );
        is(
            scalar @{ $bug->{_display_rows} }, 1,
            'add_display_row adds row'
        );
        is_deeply(
            $bug->{_display_rows}[0], [ 'Field', 'old', '→', 'new' ],
            'row has correct format'
        );
    }
};

subtest '_display_changes() tests' => sub {
    plan tests => 2;

    # Test 1: _display_changes outputs table
    {
        my $bug = create_bug();
        $bug->add_display_row( 'Status', 'NEW', '→', 'ASSIGNED' );

        stdout_like(
            sub { $bug->_display_changes() },
            qr/Status.*NEW.*→.*ASSIGNED/s,
            '_display_changes outputs table with arrow'
        );
    }

    # Test 2: _display_changes clears rows
    {
        my $bug = create_bug();
        $bug->add_display_row( 'Status', 'NEW', '→', 'ASSIGNED' );

        stdout_from( sub { $bug->_display_changes() } );

        is(
            scalar @{ $bug->{_display_rows} }, 0,
            '_display_changes clears display rows after output'
        );
    }
};

subtest 'apply_updates() tests' => sub {
    plan tests => 3;

    # Test 1: apply_updates with no pending updates
    {
        my $bug    = create_bug();
        my $result = $bug->apply_updates();
        is( $result, undef, 'apply_updates returns undef when no pending updates' );
    }

    # Test 2: apply_updates displays changes
    {
        my $bug = create_bug( status => 'NEW' );
        $bug->set_field( 'status', 'ASSIGNED' );

        # Mock update method
        no warnings 'redefine';
        local *GitBz::Bug::update = sub { return 1; };

        stdout_like(
            sub { $bug->apply_updates() },
            qr/Status.*NEW.*→.*ASSIGNED/s,
            'apply_updates displays changes before updating'
        );
    }

    # Test 3: apply_updates clears pending updates
    {
        my $bug = create_bug( status => 'NEW' );
        $bug->set_field( 'status', 'ASSIGNED' );

        # Mock update method
        no warnings 'redefine';
        local *GitBz::Bug::update = sub { return 1; };

        stdout_from( sub { $bug->apply_updates() } );

        is(
            scalar keys %{ $bug->{_pending_updates} }, 0,
            'apply_updates clears pending updates after calling update'
        );
    }
};

done_testing();
