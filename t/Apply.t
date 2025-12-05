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
use Test::MockModule;
use FindBin;
use lib "$FindBin::Bin/../lib";

use GitBz::Commands::Apply;

=head1 NAME

t/Apply.t - Test feedback messages in apply command

=cut

subtest 'apply_bug_patches feedback messages' => sub {
    plan tests => 4;

    # Mock GitBz::Bug
    my $bug_mock = Test::MockModule->new('GitBz::Bug');
    $bug_mock->mock(
        'get',
        sub {
            my ( $client, $bug_ref ) = @_;
            return bless {
                _summary     => 'Test bug summary',
                _attachments => [
                    {
                        id          => 123,
                        summary     => 'Test patch 1',
                        is_patch    => 1,
                        is_obsolete => 0,
                        data        => 'bW9ja2VkIHBhdGNoIGNvbnRlbnQ='    # base64 for "mocked patch content"
                    },
                    {
                        id          => 124,
                        summary     => 'Test patch 2',
                        is_patch    => 1,
                        is_obsolete => 0,
                        data        => 'bW9ja2VkIHBhdGNoIGNvbnRlbnQ='    # base64 for "mocked patch content"
                    }
                ]
                },
                'GitBz::Bug';
        }
    );
    $bug_mock->mock( 'summary',     sub { shift->{_summary} } );
    $bug_mock->mock( 'attachments', sub { shift->{_attachments} } );

    my $commands = { client => {} };
    my $apply    = GitBz::Commands::Apply->new($commands);

    subtest 'user chooses no' => sub {
        plan tests => 3;

        # Mock prompt_multi to simulate user choosing "no"
        my $apply_mock = Test::MockModule->new('GitBz::Commands::Apply');
        $apply_mock->mock( 'prompt_multi', sub { return 'n'; } );

        my $result;
        my $output = stdout_from( sub { $result = $apply->apply_bug_patches( "12345", {} ) } );

        like( $output, qr/📋 Bug 12345 - Test bug summary/, "Shows bug header" );
        like(
            $output, qr/No patches applied for bug 12345/,
            "Shows 'no patches applied' message when user chooses no"
        );
        is( $result, 0, "Returns 0 when no patches are applied" );
    };

    subtest 'interactive with no selection' => sub {
        plan tests => 3;

        # Mock prompt_multi to simulate interactive with no selection
        my $apply_mock = Test::MockModule->new('GitBz::Commands::Apply');
        $apply_mock->mock( 'prompt_multi',                 sub { return 'i'; } );
        $apply_mock->mock( 'select_patches_interactively', sub { return (); } );

        my $result;
        my $output = stdout_from( sub { $result = $apply->apply_bug_patches( "12345", {} ) } );

        like( $output, qr/📋 Bug 12345 - Test bug summary/, "Shows bug header" );
        like(
            $output, qr/No patches selected for bug 12345/,
            "Shows 'no patches selected' message when none selected interactively"
        );
        is( $result, 0, "Returns 0 when no patches are selected" );
    };

    subtest 'user chooses yes - applies all patches' => sub {
        plan tests => 5;

        # Mock prompt_multi to simulate user choosing "yes"
        my $apply_mock = Test::MockModule->new('GitBz::Commands::Apply');
        $apply_mock->mock( 'prompt_multi',  sub { return 'y'; } );
        $apply_mock->mock( 'apply_patches', sub { } );               # Mock actual patch application

        my $result;
        my $output = stdout_from( sub { $result = $apply->apply_bug_patches( "12345", {} ) } );

        like( $output, qr/📋 Bug 12345 - Test bug summary/, "Shows bug header" );
        like( $output, qr/• 123 - Test patch 1/,           "Shows first patch in list" );
        like( $output, qr/• 124 - Test patch 2/,           "Shows second patch in list" );
        is( $result, 2, "Returns 2 when 2 patches are applied" );

        # Test with confirm option (auto-yes) - also capture output
        my $output2 = stdout_from( sub { $result = $apply->apply_bug_patches( "12345", { confirm => 1 } ) } );
        is( $result, 2, "Returns 2 when confirm option is used" );
    };

    subtest 'interactive with partial selection' => sub {
        plan tests => 2;

        # Mock prompt_multi to simulate interactive with selection
        my $apply_mock = Test::MockModule->new('GitBz::Commands::Apply');
        $apply_mock->mock( 'prompt_multi', sub { return 'i'; } );
        $apply_mock->mock(
            'select_patches_interactively',
            sub {
                # Return only first patch with data field
                return (
                    {
                        id          => 123,
                        summary     => 'Test patch 1',
                        is_patch    => 1,
                        is_obsolete => 0,
                        data        => 'bW9ja2VkIHBhdGNoIGNvbnRlbnQ='    # base64 for "mocked patch content"
                    }
                );
            }
        );
        $apply_mock->mock( 'apply_patches', sub { } );    # Mock actual patch application

        my $result;
        my $output = stdout_from( sub { $result = $apply->apply_bug_patches( "12345", {} ) } );

        like( $output, qr/📋 Bug 12345 - Test bug summary/, "Shows bug header" );
        is( $result, 1, "Returns 1 when 1 patch is selected interactively" );
    };
};

done_testing();
