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
use Test::MockModule;
use Test::MockObject;
use Test::Output;
use Test::Exception;
use IO::String;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use GitBz::Bug;

# Mock modules once at the top
my $progress_mock = Test::MockModule->new('GitBz::Progress');
$progress_mock->mock( 'print_error',  sub { } );
$progress_mock->mock( 'with_spinner', sub { my ( $msg, $code ) = @_; return $code->(); } );

my $bug_mock = Test::MockModule->new('GitBz::Bug');

# Mock bug helper using Test::MockObject
sub create_bug {
    my %data = @_;

    my $bug = Test::MockObject->new();
    $bug->set_isa('GitBz::Bug');
    $bug->set_always( 'id',         $data{id}      || 12345 );
    $bug->set_always( 'summary',    $data{summary} || 'Test bug' );
    $bug->set_always( 'status',     $data{status}  || 'NEW' );
    $bug->set_always( 'qa_contact', $data{qa_contact} );

    # Add the actual methods we're testing
    $bug->mock( 'validate_qa_contact_with_lookup', \&GitBz::Bug::validate_qa_contact_with_lookup );
    $bug->mock( '_select_qa_contact',              \&GitBz::Bug::_select_qa_contact );

    return $bug;
}

# Mock client
sub create_mock_client {
    my ($search_result, $validate_result, $username) = @_;

    my $client = Test::MockObject->new();
    $client->mock( 'search_users',  sub { return $search_result || []; } );
    $client->mock( 'validate_user', sub { return $validate_result // 1; } );
    $client->{username} = $username || 'test@example.com';

    return $client;
}

subtest 'validate_qa_contact_with_lookup - success with valid email' => sub {
    plan tests => 1;

    my $bug         = create_bug();
    my $mock_client = create_mock_client( undef, 1 );    # validate_user returns true

    my $result = $bug->validate_qa_contact_with_lookup( $mock_client, 'valid@example.com' );

    is( $result, 'valid@example.com', 'Returns validated email' );
};

subtest 'validate_qa_contact_with_lookup - skip validation for own login' => sub {
    plan tests => 2;

    my $bug         = create_bug();
    my $mock_client = create_mock_client( undef, undef, 'myuser@example.com' );

    my $validate_called = 0;
    $mock_client->mock( 'validate_user', sub { $validate_called++; return 1; } );

    my $result = $bug->validate_qa_contact_with_lookup( $mock_client, 'myuser@example.com' );

    is( $result,          'myuser@example.com', 'Returns own email' );
    is( $validate_called, 0,                    'validate_user not called for own login' );
};

subtest 'validate_qa_contact_with_lookup - user cancels selection' => sub {
    plan tests => 1;

    my $bug = create_bug();
    my $mock_client
        = create_mock_client( [ { email => 'john@example.com', real_name => 'John Doe' } ], 0 );    # validate_user returns false

    # Mock STDIN for user cancellation (empty input)
    my $input = "\n";
    local *STDIN;
    open STDIN, '<', \$input;

    throws_ok {
        $bug->validate_qa_contact_with_lookup( $mock_client, 'invalid@example.com' );
    }
    qr/Update cancelled by user/, 'Dies when user cancels';
};

subtest 'validate_qa_contact_with_lookup - iterative validation with eventual success' => sub {
    plan tests => 1;

    my $bug         = create_bug();
    my $mock_client = create_mock_client(
        [ { email => 'john@example.com', real_name => 'John Doe' } ],
        undef    # Will be mocked dynamically below
    );

    # Mock validate_user to fail first time, succeed second time
    my $validate_count = 0;
    $mock_client->mock(
        'validate_user',
        sub {
            my ( $self, $email ) = @_;
            $validate_count++;
            return $validate_count > 1 ? 1 : 0;    # Fail first, succeed second
        }
    );

    # Mock STDIN for selecting user (index 0), then selecting again
    my $input = "0\n0\n";
    local *STDIN;
    open STDIN, '<', \$input;

    my $result = $bug->validate_qa_contact_with_lookup( $mock_client, 'invalid@example.com' );

    is( $result, 'john@example.com', 'Returns validated email after iteration' );
};

subtest '_select_qa_contact - no users found, user enters new email' => sub {
    plan tests => 1;

    my $bug         = create_bug();
    my $mock_client = create_mock_client( [] );

    # Mock STDIN for user input
    my $input = "y\nnew\@example.com\n";
    local *STDIN;
    open STDIN, '<', \$input;

    my $result = $bug->_select_qa_contact( $mock_client, 'invalid@example.com' );

    is( $result, 'new@example.com', 'Returns manually entered email' );
};

subtest '_select_qa_contact - no users found, user declines' => sub {
    plan tests => 1;

    my $bug         = create_bug();
    my $mock_client = create_mock_client( [] );

    # Mock STDIN for user declining
    my $input = "n\n";
    local *STDIN;
    open STDIN, '<', \$input;

    my $result = $bug->_select_qa_contact( $mock_client, 'invalid@example.com' );

    is( $result, undef, 'Returns undef when user declines' );
};

subtest '_select_qa_contact - users found, valid selection' => sub {
    plan tests => 1;

    my $bug         = create_bug();
    my $mock_client = create_mock_client(
        [
            { email => 'john@example.com', real_name => 'John Doe' },
            { email => 'jane@example.com', real_name => 'Jane Smith' }
        ]
    );

    # Mock STDIN for user selection
    my $input = "1\n";    # Select second user
    local *STDIN;
    open STDIN, '<', \$input;

    my $result = $bug->_select_qa_contact( $mock_client, 'invalid@example.com' );

    is( $result, 'jane@example.com', 'Returns selected user email' );
};

subtest '_select_qa_contact - users found, invalid selection' => sub {
    plan tests => 1;

    my $bug         = create_bug();
    my $mock_client = create_mock_client( [ { email => 'john@example.com', real_name => 'John Doe' } ] );

    # Mock STDIN for invalid selection
    my $input = "99\n";    # Invalid index
    local *STDIN;
    open STDIN, '<', \$input;

    my $result = $bug->_select_qa_contact( $mock_client, 'invalid@example.com' );

    is( $result, undef, 'Returns undef for invalid selection' );
};

done_testing();
