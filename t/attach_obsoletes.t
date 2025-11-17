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

use Test::More tests => 7;
use Test::Exception;
use Test::MockModule;
use IO::String;

use FindBin;
use lib "$FindBin::RealBin/../lib";

use GitBz::Commands::Attach;

# Mock GitBz::Git
my $mock_git = Test::MockModule->new('GitBz::Git');
$mock_git->mock(
    'get_commits',
    sub {
        return (
            { id => 'abc123', subject => 'Bug 12345: Fix something important' },
            { id => 'def456', subject => 'Bug 12345: Add new feature' }
        );
    }
);
$mock_git->mock( 'format_patch', sub { return "patch content"; } );
$mock_git->mock( 'run',          sub { return "commit body"; } );

my $mock_commands = { client => undef };
my $attach        = GitBz::Commands::Attach->new($mock_commands);

subtest 'find_trivial_obsoletes - no attachments' => sub {

    plan tests => 1;

    my $mock_bug = Test::MockModule->new( 'GitBz::Bug', no_auto => 1 );
    my $bug      = bless {}, 'GitBz::Bug';
    $mock_bug->mock( 'attachments', sub { return []; } );

    my @commits   = ( { subject => 'Bug 12345: Fix something' } );
    my @obsoletes = $attach->find_trivial_obsoletes( $bug, \@commits );

    is_deeply( \@obsoletes, [], 'Returns empty list when no attachments' );
};

subtest 'find_trivial_obsoletes - no matching patches' => sub {

    plan tests => 1;

    # Mock STDIN for this test - user will skip
    my $input = IO::String->new("s\n");
    local *STDIN = $input;

    my $mock_bug = Test::MockModule->new( 'GitBz::Bug', no_auto => 1 );
    my $bug      = bless {}, 'GitBz::Bug';
    $mock_bug->mock(
        'attachments',
        sub {
            return [
                { id => 1001, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Different patch' },
                { id => 1002, is_patch => 1, is_obsolete => 1, summary => 'Bug 12345: Fix something' },
                { id => 1003, is_patch => 0, is_obsolete => 0, summary => 'Bug 12345: Fix something' },
            ];
        }
    );

    my @commits   = ( { subject => 'Bug 12345: Fix something' } );
    my @obsoletes = $attach->find_trivial_obsoletes( $bug, \@commits );

    is_deeply( \@obsoletes, [], 'Returns empty list when no matching non-obsolete patches' );
};

subtest 'find_trivial_obsoletes - exact matches' => sub {

    plan tests => 1;

    # Mock STDIN for this test - user will skip the non-matching patch
    my $input = IO::String->new("s\n");
    local *STDIN = $input;

    my $mock_bug = Test::MockModule->new( 'GitBz::Bug', no_auto => 1 );
    my $bug      = bless {}, 'GitBz::Bug';
    $mock_bug->mock(
        'attachments',
        sub {
            return [
                { id => 1001, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Fix something important' },
                { id => 1002, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Add new feature' },
                { id => 1003, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Different patch' },
            ];
        }
    );

    my @commits = (
        { subject => 'Bug 12345: Fix something important' },
        { subject => 'Bug 12345: Add new feature' }
    );
    my @obsoletes = $attach->find_trivial_obsoletes( $bug, \@commits );

    is_deeply( [ sort @obsoletes ], [ 1001, 1002 ], 'Returns IDs of matching patches' );
};

subtest 'find_trivial_obsoletes - mixed scenarios' => sub {

    plan tests => 1;

    # Mock STDIN for this test - user will skip the non-matching patch
    my $input = IO::String->new("s\n");
    local *STDIN = $input;

    my $mock_bug = Test::MockModule->new( 'GitBz::Bug', no_auto => 1 );
    my $bug      = bless {}, 'GitBz::Bug';
    $mock_bug->mock(
        'attachments',
        sub {
            return [
                { id => 1001, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Fix something important' },
                { id => 1002, is_patch => 1, is_obsolete => 1, summary => 'Bug 12345: Add new feature' },
                { id => 1003, is_patch => 0, is_obsolete => 0, summary => 'Bug 12345: Fix something important' },
                { id => 1004, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Different patch' },
            ];
        }
    );

    my @commits = (
        { subject => 'Bug 12345: Fix something important' },
        { subject => 'Bug 12345: Add new feature' }
    );
    my @obsoletes = $attach->find_trivial_obsoletes( $bug, \@commits );

    is_deeply( \@obsoletes, [1001], 'Only returns non-obsolete patches that match' );
};

subtest 'user input - obsolete choice' => sub {

    plan tests => 1;

    # Mock STDIN - user chooses to obsolete
    my $input = IO::String->new("o\n");
    local *STDIN = $input;

    my $mock_bug = Test::MockModule->new( 'GitBz::Bug', no_auto => 1 );
    my $bug      = bless {}, 'GitBz::Bug';
    $mock_bug->mock(
        'attachments',
        sub {
            return [
                { id => 1001, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Different patch' },
            ];
        }
    );

    my @commits   = ( { subject => 'Bug 12345: Fix something' } );
    my @obsoletes = $attach->find_trivial_obsoletes( $bug, \@commits );

    is_deeply( \@obsoletes, [1001], 'User chose to obsolete patch' );
};

subtest 'user input - skip choice' => sub {

    plan tests => 1;

    # Mock STDIN - user chooses to skip
    my $input = IO::String->new("s\n");
    local *STDIN = $input;

    my $mock_bug = Test::MockModule->new( 'GitBz::Bug', no_auto => 1 );
    my $bug      = bless {}, 'GitBz::Bug';
    $mock_bug->mock(
        'attachments',
        sub {
            return [
                { id => 1001, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Different patch' },
            ];
        }
    );

    my @commits   = ( { subject => 'Bug 12345: Fix something' } );
    my @obsoletes = $attach->find_trivial_obsoletes( $bug, \@commits );

    is_deeply( \@obsoletes, [], 'User chose to skip patch' );
};

subtest 'user input - cancel choice' => sub {

    plan tests => 2;

    # Mock STDIN - user chooses to cancel
    my $input = IO::String->new("c\n");
    local *STDIN = $input;

    my $mock_bug = Test::MockModule->new( 'GitBz::Bug', no_auto => 1 );
    my $bug      = bless {}, 'GitBz::Bug';
    $mock_bug->mock(
        'attachments',
        sub {
            return [
                { id => 1001, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Different patch' },
            ];
        }
    );

    my @commits = ( { subject => 'Bug 12345: Fix something' } );

    # Should throw an exception when user cancels
    throws_ok {
        my @obsoletes = $attach->find_trivial_obsoletes( $bug, \@commits );
    }
    'GitBz::Exception', 'Throws exception when cancelled';

    like( "$@", qr/Operation cancelled by user/, 'User chose to cancel operation (throws exception)' );
};
