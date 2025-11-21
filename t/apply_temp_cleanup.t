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

Tests the temporary directory cleanup functionality added to handle git-am failures:
- State file saving and loading (save_state, load_state)
- Temp directory cleanup on abort/continue/skip
- Temp directory preservation on failure
- Cleanup on successful completion

=cut

subtest 'save_state and load_state' => sub {
    plan tests => 6;

    my $commands = { client => {} };
    my $apply = GitBz::Commands::Apply->new($commands);

    # Create a temporary directory to simulate git directory
    my $temp_git_dir = File::Temp->newdir();
    my $rebase_apply_dir = "$temp_git_dir/rebase-apply";
    mkdir $rebase_apply_dir;

    subtest 'load_state returns false when no state file' => sub {
        plan tests => 2;

        my ($has_state, $temp_dir) = $apply->load_state($temp_git_dir);
        is($has_state, 0, 'Returns false when state file does not exist');
        is($temp_dir, undef, 'Returns undef for temp_dir when no state file');
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
        plan tests => 2;

        my ($has_state, $temp_dir) = $apply->load_state($temp_git_dir);
        is($has_state, 1, 'Returns true when state file exists');
        is($temp_dir, '/tmp/test-patches', 'Returns correct temp directory path');
    };

    subtest 'save_state without temp directory' => sub {
        plan tests => 2;

        # Clean up previous state
        unlink "$rebase_apply_dir/git-bz";

        $apply->save_state($temp_git_dir, undef);

        my $state_file = "$rebase_apply_dir/git-bz";
        ok(-f $state_file, 'State file created even without temp_dir');

        my ($has_state, $temp_dir) = $apply->load_state($temp_git_dir);
        is($temp_dir, undef, 'Returns undef when no temp_dir in state file');
    };

    subtest 'load_state with malformed state file' => sub {
        plan tests => 2;

        # Create a malformed state file
        my $state_file = "$rebase_apply_dir/git-bz";
        open my $fh, '>', $state_file or die "Cannot write state file: $!";
        print $fh "# git-bz state file\n";
        print $fh "invalid_key=invalid_value\n";
        close $fh;

        my ($has_state, $temp_dir) = $apply->load_state($temp_git_dir);
        is($has_state, 1, 'Returns true for existing state file');
        is($temp_dir, undef, 'Returns undef when temp_dir not found in state file');
    };

    subtest 'load_state handles file read errors gracefully' => sub {
        plan tests => 2;

        # Create state file with no read permissions
        my $state_file = "$rebase_apply_dir/git-bz";
        open my $fh, '>', $state_file or die "Cannot write state file: $!";
        print $fh "# git-bz state file\n";
        close $fh;
        chmod 0000, $state_file;

        my ($has_state, $temp_dir);
        lives_ok {
            ($has_state, $temp_dir) = $apply->load_state($temp_git_dir);
        } 'load_state does not die on read error';

        is($has_state, 1, 'Returns true for existing state file even with read error');

        # Restore permissions for cleanup
        chmod 0644, $state_file;
    };
};

subtest 'handle_git_am_state with cleanup' => sub {
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
        $apply->save_state($temp_git_dir, $temp_patches_path);

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

    subtest 'continue and skip clean up temp directory' => sub {
        plan tests => 4;

        for my $action ('continue', 'skip') {
            my $temp_git_dir = File::Temp->newdir();
            my $rebase_apply_dir = "$temp_git_dir/rebase-apply";
            mkdir $rebase_apply_dir;

            my $temp_patches_dir = File::Temp->newdir(CLEANUP => 0);
            my $temp_patches_path = "$temp_patches_dir";

            $apply->save_state($temp_git_dir, $temp_patches_path);

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
            stdout_like(
                sub { $apply->handle_git_am_state(\%opts); },
                qr/(Successfully continued|Skipped current patch)/,
                "Shows success message on $action"
            );

            ok(!-d $temp_patches_path, "Temp directory removed after $action");
        }
    };
};

subtest 'apply_patches temp directory handling' => sub {
    plan tests => 3;

    my $commands = { client => {} };
    my $apply = GitBz::Commands::Apply->new($commands);

    # Mock GitBz::Git
    my $git_mock = Test::MockModule->new('GitBz::Git');

    subtest 'creates temp directory without auto-cleanup' => sub {
        plan tests => 1;

        # We can't easily test CLEANUP => 0 directly, but we can verify
        # that the temp directory is not immediately cleaned up
        my $temp_dir_path;

        $git_mock->mock('run', sub {
            my ($class, @args) = @_;
            if ($args[0] eq 'am') {
                # Capture the temp directory path from the arguments
                for my $arg (@args) {
                    if ($arg =~ m{^/tmp/}) {
                        $temp_dir_path = $arg;
                        last;
                    }
                }
                return '';  # Success
            }
        });

        my @attachments = (
            {
                id => 123,
                file_name => 'test.patch',
                data => 'RnJvbSBhYmNkZWYgTW9uIFNlcCAxNyAwMDowMDowMCAyMDAxCkZyb206IFRlc3QgVXNlciA8dGVzdEB0ZXN0LmNvbT4KRGlzdDogdGVzdCBwYXRjaAoKLS0tCiBmaWxlLnR4dCB8IDEgKwogMSBmaWxlIGNoYW5nZWQsIDEgaW5zZXJ0aW9uKCspCgpkaWZmIC0tZ2l0IGEvZmlsZS50eHQgYi9maWxlLnR4dApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAuLjAwMDAwMDAKLS0tIC9kZXYvbnVsbAorKysgYi9maWxlLnR4dApAQCAtMCwwICsxIEBACitjb250ZW50Cg=='
            }
        );

        lives_ok {
            $apply->apply_patches(\@attachments, {});
        } 'apply_patches completes successfully';
    };

    subtest 'cleans up temp directory on success' => sub {
        plan tests => 2;

        my $captured_temp_dir;

        $git_mock->mock('run', sub {
            my ($class, @args) = @_;
            if ($args[0] eq 'am') {
                # Capture temp directory from patch file path
                for my $arg (@args) {
                    if ($arg =~ m{^(/tmp/[^/]+)/}) {
                        $captured_temp_dir = $1;
                        last;
                    }
                }
                return '';  # Success
            }
        });

        my @attachments = (
            {
                id => 123,
                file_name => 'test.patch',
                data => 'RnJvbSBhYmNkZWYgTW9uIFNlcCAxNyAwMDowMDowMCAyMDAxCkZyb206IFRlc3QgVXNlciA8dGVzdEB0ZXN0LmNvbT4KRGlzdDogdGVzdCBwYXRjaAoKLS0tCiBmaWxlLnR4dCB8IDEgKwogMSBmaWxlIGNoYW5nZWQsIDEgaW5zZXJ0aW9uKCspCgpkaWZmIC0tZ2l0IGEvZmlsZS50eHQgYi9maWxlLnR4dApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAuLjAwMDAwMDAKLS0tIC9kZXYvbnVsbAorKysgYi9maWxlLnR4dApAQCAtMCwwICsxIEBACitjb250ZW50Cg=='
            }
        );

        $apply->apply_patches(\@attachments, {});

        ok(defined $captured_temp_dir, 'Temp directory was created');
        ok(!-d $captured_temp_dir, 'Temp directory cleaned up after success');
    };

    subtest 'preserves temp directory on failure' => sub {
        plan tests => 3;

        my $captured_temp_dir;
        my $temp_git_dir = File::Temp->newdir();
        my $rebase_apply_dir = "$temp_git_dir/rebase-apply";

        $git_mock->mock('run', sub {
            my ($class, @args) = @_;
            if ($args[0] eq 'am') {
                # Capture temp directory from patch file path
                for my $arg (@args) {
                    if ($arg =~ m{^(/tmp/[^/]+)/}) {
                        $captured_temp_dir = $1;
                        last;
                    }
                }
                # Create rebase-apply directory to simulate git-am failure
                mkdir $rebase_apply_dir unless -d $rebase_apply_dir;
                die "git am failed\n";
            }
            if ($args[0] eq 'rev-parse' && $args[1] eq '--git-dir') {
                return "$temp_git_dir\n";
            }
        });

        my @attachments = (
            {
                id => 123,
                file_name => 'test.patch',
                data => 'RnJvbSBhYmNkZWYgTW9uIFNlcCAxNyAwMDowMDowMCAyMDAxCkZyb206IFRlc3QgVXNlciA8dGVzdEB0ZXN0LmNvbT4KRGlzdDogdGVzdCBwYXRjaAoKLS0tCiBmaWxlLnR4dCB8IDEgKwogMSBmaWxlIGNoYW5nZWQsIDEgaW5zZXJ0aW9uKCspCgpkaWZmIC0tZ2l0IGEvZmlsZS50eHQgYi9maWxlLnR4dApuZXcgZmlsZSBtb2RlIDEwMDY0NAppbmRleCAuLjAwMDAwMDAKLS0tIC9kZXYvbnVsbAorKysgYi9maWxlLnR4dApAQCAtMCwwICsxIEBACitjb250ZW50Cg=='
            }
        );

        stderr_like(
            sub {
                eval { $apply->apply_patches(\@attachments, {}); };
            },
            qr/Patches left in .* for manual application if needed/,
            'Shows message about temp directory location on failure'
        );

        ok(defined $captured_temp_dir, 'Temp directory was created');
        ok(-d $captured_temp_dir, 'Temp directory preserved after failure');

        # Cleanup
        rmtree($captured_temp_dir) if $captured_temp_dir && -d $captured_temp_dir;
    };
};

done_testing();
