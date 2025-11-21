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
use Test::Exception;
use Test::MockModule;
use Test::Output;
use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Temp;
use File::Path qw(rmtree);

use GitBz::Commands::Apply;

=head1 NAME

t/apply_temp_cleanup.t - Test temp directory and state file management in apply command

=head1 DESCRIPTION

Tests the temporary directory cleanup functionality:
- State file saving and loading with remaining patches tracking
- Temp directory cleanup on abort/continue/skip
- Temp directory preservation on failure
- Sequential patch application
- Cleanup on successful completion

=cut

subtest 'save_state and load_state with remaining patches' => sub {
    plan tests => 8;

    my $commands = { client => {} };
    my $apply = GitBz::Commands::Apply->new($commands);

    # Create a temporary directory to simulate git directory
    my $temp_git_dir = File::Temp->newdir();
    my $rebase_apply_dir = "$temp_git_dir/rebase-apply";
    mkdir $rebase_apply_dir;

    subtest 'load_state returns false when no state file' => sub {
        plan tests => 3;

        my ($has_state, $temp_dir, $remaining) = $apply->load_state($temp_git_dir);
        is($has_state, 0, 'Returns false when state file does not exist');
        is($temp_dir, undef, 'Returns undef for temp_dir when no state file');
        is($remaining, undef, 'Returns undef for remaining patches when no state file');
    };

    subtest 'save_state creates state file with temp directory' => sub {
        plan tests => 2;

        my $test_temp_dir = '/tmp/test-patches';
        $apply->save_state($temp_git_dir, $test_temp_dir);

        my $state_file = "$rebase_apply_dir/git-bz";
        ok(-f $state_file, 'State file created');

        open my $fh, '<', $state_file or die "Cannot read state file: $!";
        my $content = do { local $/; <$fh> };
        close $fh;

        like($content, qr/temp_dir=\/tmp\/test-patches/, 'State file contains temp directory path');
    };

    subtest 'load_state retrieves temp directory' => sub {
        plan tests => 3;

        my ($has_state, $temp_dir, $remaining) = $apply->load_state($temp_git_dir);
        is($has_state, 1, 'Returns true when state file exists');
        is($temp_dir, '/tmp/test-patches', 'Returns correct temp directory path');
        is_deeply($remaining, [], 'Returns empty array when no remaining patches');
    };

    subtest 'save_state with remaining patch IDs' => sub {
        plan tests => 2;

        # Clean up previous state
        unlink "$rebase_apply_dir/git-bz";

        my $test_temp_dir = '/tmp/test-patches';
        my @remaining_patches = (123, 456, 789);
        $apply->save_state($temp_git_dir, $test_temp_dir, \@remaining_patches);

        my $state_file = "$rebase_apply_dir/git-bz";
        ok(-f $state_file, 'State file created with remaining patches');

        open my $fh, '<', $state_file or die "Cannot read state file: $!";
        my $content = do { local $/; <$fh> };
        close $fh;

        like($content, qr/remaining_patches=123,456,789/, 'State file contains remaining patch IDs');
    };

    subtest 'load_state retrieves remaining patches' => sub {
        plan tests => 3;

        my ($has_state, $temp_dir, $remaining) = $apply->load_state($temp_git_dir);
        is($has_state, 1, 'Returns true when state file exists');
        is($temp_dir, '/tmp/test-patches', 'Returns correct temp directory path');
        is_deeply($remaining, [123, 456, 789], 'Returns array of remaining patch IDs');
    };

    subtest 'save_state without temp directory or patches' => sub {
        plan tests => 3;

        # Clean up previous state
        unlink "$rebase_apply_dir/git-bz";

        $apply->save_state($temp_git_dir, undef, undef);

        my $state_file = "$rebase_apply_dir/git-bz";
        ok(-f $state_file, 'State file created even without temp_dir or patches');

        my ($has_state, $temp_dir, $remaining) = $apply->load_state($temp_git_dir);
        is($temp_dir, undef, 'Returns undef when no temp_dir in state file');
        is_deeply($remaining, [], 'Returns empty array when no remaining patches');
    };

    subtest 'load_state with malformed state file' => sub {
        plan tests => 3;

        # Create a malformed state file
        my $state_file = "$rebase_apply_dir/git-bz";
        open my $fh, '>', $state_file or die "Cannot write state file: $!";
        print $fh "# git-bz state file\n";
        print $fh "invalid_key=invalid_value\n";
        close $fh;

        my ($has_state, $temp_dir, $remaining) = $apply->load_state($temp_git_dir);
        is($has_state, 1, 'Returns true for existing state file');
        is($temp_dir, undef, 'Returns undef when temp_dir not found in state file');
        is_deeply($remaining, [], 'Returns empty array when no remaining patches in state file');
    };

    subtest 'load_state handles file read errors gracefully' => sub {
        plan tests => 2;

        # Create state file with no read permissions
        my $state_file = "$rebase_apply_dir/git-bz";
        open my $fh, '>', $state_file or die "Cannot write state file: $!";
        print $fh "# git-bz state file\n";
        close $fh;
        chmod 0000, $state_file;

        my ($has_state, $temp_dir, $remaining);
        lives_ok {
            ($has_state, $temp_dir, $remaining) = $apply->load_state($temp_git_dir);
        } 'load_state does not die on read error';

        is($has_state, 1, 'Returns true for existing state file even with read error');

        # Restore permissions for cleanup
        chmod 0644, $state_file;
    };
};

subtest 'load_patch_info_from_temp' => sub {
    plan tests => 4;

    my $commands = { client => {} };
    my $apply = GitBz::Commands::Apply->new($commands);

    subtest 'returns empty when no patch IDs provided' => sub {
        plan tests => 1;

        my $temp_dir = File::Temp->newdir();
        my $patch_info = $apply->load_patch_info_from_temp($temp_dir, []);
        ok(!$patch_info, 'Returns nothing when no patch IDs');
    };

    subtest 'returns empty when temp directory does not exist' => sub {
        plan tests => 1;

        my $patch_info = $apply->load_patch_info_from_temp('/nonexistent', [123]);
        ok(!$patch_info, 'Returns nothing when temp dir does not exist');
    };

    subtest 'loads patch info from temp directory' => sub {
        plan tests => 4;

        # Create temp directory with patch files
        my $temp_dir = File::Temp->newdir(CLEANUP => 1);

        # Create mock patch files
        open my $fh1, '>', "$temp_dir/0001-123.patch" or die $!;
        print $fh1 "patch content 1\n";
        close $fh1;

        open my $fh2, '>', "$temp_dir/0002-456.patch" or die $!;
        print $fh2 "patch content 2\n";
        close $fh2;

        # Load info for specific patches
        my $patch_info = $apply->load_patch_info_from_temp($temp_dir, [123, 456]);

        is(scalar @$patch_info, 2, 'Returns info for 2 patches');
        is($patch_info->[0]{id}, 123, 'First patch has correct ID');
        is($patch_info->[1]{id}, 456, 'Second patch has correct ID');
        like($patch_info->[0]{file}, qr/0001-123\.patch$/, 'First patch has correct file path');
    };

    subtest 'handles missing patch files' => sub {
        plan tests => 1;

        my $temp_dir = File::Temp->newdir(CLEANUP => 1);

        # Create only one patch file
        open my $fh, '>', "$temp_dir/0001-123.patch" or die $!;
        print $fh "patch content\n";
        close $fh;

        # Try to load info for missing patch
        stderr_like(
            sub {
                my $patch_info = $apply->load_patch_info_from_temp($temp_dir, [123, 999]);
            },
            qr/Warning: Could not find patch file for ID 999/,
            'Shows warning for missing patch file'
        );
    };
};

subtest 'handle_git_am_state with cleanup and continuation' => sub {
    plan tests => 4;

    my $commands = { client => {} };
    my $apply = GitBz::Commands::Apply->new($commands);

    # Mock GitBz::Git
    my $git_mock = Test::MockModule->new('GitBz::Git');

    subtest 'throws exception when not in git repository' => sub {
        plan tests => 1;

        $git_mock->mock('run', sub {
            my ($class, @args) = @_;
            if ($args[0] eq 'rev-parse' && $args[1] eq '--git-dir') {
                die "Not a git repository\n";
            }
        });

        throws_ok {
            $apply->handle_git_am_state({ abort => 1 });
        } 'GitBz::Exception', 'Throws exception when not in git repository';
    };

    subtest 'throws exception when not in git-am session' => sub {
        plan tests => 1;

        my $temp_git_dir = File::Temp->newdir();

        $git_mock->mock('run', sub {
            my ($class, @args) = @_;
            if ($args[0] eq 'rev-parse' && $args[1] eq '--git-dir') {
                return "$temp_git_dir\n";
            }
        });

        throws_ok {
            $apply->handle_git_am_state({ abort => 1 });
        } 'GitBz::Exception', 'Throws exception when not in git-am session';
    };

    subtest 'abort cleans up temp directory' => sub {
        plan tests => 2;

        # Create mock git directory structure
        my $temp_git_dir = File::Temp->newdir();
        my $rebase_apply_dir = "$temp_git_dir/rebase-apply";
        mkdir $rebase_apply_dir;

        # Create mock temp directory
        my $temp_patches_dir = File::Temp->newdir(CLEANUP => 0);
        my $temp_patches_path = "$temp_patches_dir";

        # Save state with temp directory
        $apply->save_state($temp_git_dir, $temp_patches_path, []);

        $git_mock->mock('run', sub {
            my ($class, @args) = @_;
            if ($args[0] eq 'rev-parse' && $args[1] eq '--git-dir') {
                return "$temp_git_dir\n";
            }
            if ($args[0] eq 'am' && $args[1] eq '--abort') {
                return '';  # Success
            }
        });

        stdout_like(
            sub { $apply->handle_git_am_state({ abort => 1 }); },
            qr/Aborted patch application and cleaned up temp files/,
            'Shows cleanup message on abort'
        );

        ok(!-d $temp_patches_path, 'Temp directory removed after abort');
    };

    subtest 'continue and skip clean up when no remaining patches' => sub {
        plan tests => 4;

        for my $action ('continue', 'skip') {
            my $temp_git_dir = File::Temp->newdir();
            my $rebase_apply_dir = "$temp_git_dir/rebase-apply";
            mkdir $rebase_apply_dir;

            my $temp_patches_dir = File::Temp->newdir(CLEANUP => 0);
            my $temp_patches_path = "$temp_patches_dir";

            # Save state with no remaining patches
            $apply->save_state($temp_git_dir, $temp_patches_path, []);

            $git_mock->mock('run', sub {
                my ($class, @args) = @_;
                if ($args[0] eq 'rev-parse' && $args[1] eq '--git-dir') {
                    return "$temp_git_dir\n";
                }
                if ($args[0] eq 'am' && ($args[1] eq '--continue' || $args[1] eq '--skip')) {
                    return '';  # Success
                }
            });

            my %opts = ( $action => 1 );
            my $expected = $action eq 'continue' ? 'Continued with current patch' : 'Skipped current patch';
            stdout_like(
                sub { $apply->handle_git_am_state(\%opts); },
                qr/$expected/,
                "Shows success message on $action"
            );

            ok(!-d $temp_patches_path, "Temp directory removed after $action with no remaining patches");
        }
    };
};

subtest 'prepare_patch_files' => sub {
    plan tests => 3;

    my $commands = { client => {} };
    my $apply = GitBz::Commands::Apply->new($commands);

    subtest 'creates temp directory and patch files' => sub {
        plan tests => 5;

        my @attachments = (
            {
                id => 123,
                summary => 'Test patch 1',
                data => 'RnJvbSBhYmNkZWYgTW9uIFNlcCAxNyAwMDowMDowMCAyMDAxCkZyb206IFRlc3QgVXNlciA8dGVzdEB0ZXN0LmNvbT4KRGlzdDogdGVzdCBwYXRjaAoKLS0tCiBmaWxlLnR4dCB8IDEgKwogMSBmaWxlIGNoYW5nZWQsIDEgaW5zZXJ0aW9uKCspCgpkaWZmIC0tZ2l0IGEvZmlsZS50eHQgYi9maWxlLnR4dApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAuLjAwMDAwMDAKLS0tIC9kZXYvbnVsbAorKysgYi9maWxlLnR4dApAQCAtMCwwICsxIEBACitjb250ZW50Cg=='
            },
            {
                id => 456,
                summary => 'Test patch 2',
                data => 'RnJvbSBhYmNkZWYgTW9uIFNlcCAxNyAwMDowMDowMCAyMDAxCkZyb206IFRlc3QgVXNlciA8dGVzdEB0ZXN0LmNvbT4KRGlzdDogdGVzdCBwYXRjaAo='
            }
        );

        my ($temp_dir, $patch_info) = $apply->prepare_patch_files(\@attachments);

        ok(-d $temp_dir, 'Temp directory created');
        is(scalar @$patch_info, 2, 'Returns info for 2 patches');
        ok(-f $patch_info->[0]{file}, 'First patch file exists');
        ok(-f $patch_info->[1]{file}, 'Second patch file exists');
        is($patch_info->[0]{id}, 123, 'First patch has correct ID');

        # Cleanup
        rmtree($temp_dir) if -d $temp_dir;
    };

    subtest 'patch info contains correct structure' => sub {
        plan tests => 4;

        my @attachments = (
            {
                id => 789,
                summary => 'Test patch',
                data => 'RnJvbSBhYmNkZWYgTW9uIFNlcCAxNyAwMDowMDowMCAyMDAxCg=='
            }
        );

        my ($temp_dir, $patch_info) = $apply->prepare_patch_files(\@attachments);

        is($patch_info->[0]{id}, 789, 'Patch info includes ID');
        is($patch_info->[0]{summary}, 'Test patch', 'Patch info includes summary');
        like($patch_info->[0]{file}, qr/\.patch$/, 'Patch info includes file path with .patch extension');
        like($patch_info->[0]{file}, qr/-789\.patch$/, 'Patch file name includes ID');

        # Cleanup
        rmtree($temp_dir) if -d $temp_dir;
    };

    subtest 'temp directory not auto-cleaned' => sub {
        plan tests => 1;

        my @attachments = (
            {
                id => 999,
                summary => 'Test',
                data => 'cGF0Y2ggZGF0YQ=='
            }
        );

        my ($temp_dir, $patch_info) = $apply->prepare_patch_files(\@attachments);
        my $temp_dir_path = "$temp_dir";

        # Even after scope ends, directory should exist (CLEANUP => 0)
        undef $temp_dir;
        ok(-d $temp_dir_path, 'Temp directory persists after object goes out of scope');

        # Cleanup
        rmtree($temp_dir_path);
    };
};

subtest 'apply_patches sequential application' => sub {
    plan tests => 3;

    my $commands = { client => {} };
    my $apply = GitBz::Commands::Apply->new($commands);

    # Mock GitBz::Git
    my $git_mock = Test::MockModule->new('GitBz::Git');

    subtest 'applies patches successfully and cleans up' => sub {
        plan tests => 2;

        my $temp_dir = File::Temp->newdir(CLEANUP => 0);
        my $temp_dir_path = "$temp_dir";

        my @patch_info = (
            { file => "$temp_dir/0001-123.patch", id => 123, summary => 'Test patch 1' },
            { file => "$temp_dir/0002-456.patch", id => 456, summary => 'Test patch 2' }
        );

        # Create actual patch files
        for my $info (@patch_info) {
            open my $fh, '>', $info->{file} or die $!;
            print $fh "patch content\n";
            close $fh;
        }

        $git_mock->mock('run', sub {
            my ($class, @args) = @_;
            if ($args[0] eq 'rev-parse' && $args[1] eq '--git-dir') {
                return "/tmp/git\n";
            }
            if ($args[0] eq 'am') {
                return '';  # Success
            }
        });

        stdout_like(
            sub { $apply->apply_patches(\@patch_info, $temp_dir, {}); },
            qr/Successfully applied all patches/,
            'Shows success message after applying all patches'
        );

        ok(!-d $temp_dir_path, 'Temp directory cleaned up after success');
    };

    subtest 'preserves temp directory on failure' => sub {
        plan tests => 3;

        my $temp_dir = File::Temp->newdir(CLEANUP => 0);
        my $temp_dir_path = "$temp_dir";
        my $temp_git_dir = File::Temp->newdir();
        my $rebase_apply_dir = "$temp_git_dir/rebase-apply";

        my @patch_info = (
            { file => "$temp_dir/0001-123.patch", id => 123, summary => 'Test patch 1' },
            { file => "$temp_dir/0002-456.patch", id => 456, summary => 'Test patch 2' }
        );

        # Create actual patch files
        for my $info (@patch_info) {
            open my $fh, '>', $info->{file} or die $!;
            print $fh "patch content\n";
            close $fh;
        }

        $git_mock->mock('run', sub {
            my ($class, @args) = @_;
            if ($args[0] eq 'rev-parse' && $args[1] eq '--git-dir') {
                return "$temp_git_dir\n";
            }
            if ($args[0] eq 'am') {
                # Simulate git-am failure on first patch
                mkdir $rebase_apply_dir unless -d $rebase_apply_dir;
                die "git am failed\n";
            }
        });

        stderr_like(
            sub {
                eval { $apply->apply_patches(\@patch_info, $temp_dir, {}); };
            },
            qr/Patches left in .* for manual application if needed/,
            'Shows message about temp directory location on failure'
        );

        ok(-d $temp_dir_path, 'Temp directory preserved after failure');
        ok(-f "$rebase_apply_dir/git-bz", 'State file created on failure');

        # Cleanup
        rmtree($temp_dir_path);
    };

    subtest 'saves remaining patches on partial failure' => sub {
        plan tests => 2;

        my $temp_dir = File::Temp->newdir(CLEANUP => 0);
        my $temp_dir_path = "$temp_dir";
        my $temp_git_dir = File::Temp->newdir();
        my $rebase_apply_dir = "$temp_git_dir/rebase-apply";

        my @patch_info = (
            { file => "$temp_dir/0001-111.patch", id => 111, summary => 'Patch 1' },
            { file => "$temp_dir/0002-222.patch", id => 222, summary => 'Patch 2' },
            { file => "$temp_dir/0003-333.patch", id => 333, summary => 'Patch 3' }
        );

        # Create actual patch files
        for my $info (@patch_info) {
            open my $fh, '>', $info->{file} or die $!;
            print $fh "patch content\n";
            close $fh;
        }

        my $apply_count = 0;
        $git_mock->mock('run', sub {
            my ($class, @args) = @_;
            if ($args[0] eq 'rev-parse' && $args[1] eq '--git-dir') {
                return "$temp_git_dir\n";
            }
            if ($args[0] eq 'am') {
                $apply_count++;
                if ($apply_count == 2) {
                    # Fail on second patch
                    mkdir $rebase_apply_dir unless -d $rebase_apply_dir;
                    die "git am failed\n";
                }
                return '';  # Success for first patch
            }
        });

        eval { $apply->apply_patches(\@patch_info, $temp_dir, {}); };

        # Load state to check remaining patches
        my ($has_state, $saved_temp_dir, $remaining) = $apply->load_state($temp_git_dir);
        is_deeply($remaining, [333], 'State file contains remaining patch ID (333)');
        is($apply_count, 2, 'Applied patches until failure (patch 1 succeeded, patch 2 failed)');

        # Cleanup
        rmtree($temp_dir_path);
    };
};

done_testing();
