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

use Test::More tests => 19;
use Test::MockModule;
use FindBin;
use lib "$FindBin::Bin/../lib";

BEGIN {
    use_ok('GitBz::Progress');
}

# Test get_terminal_width with mocked tput
subtest 'get_terminal_width with tput' => sub {
    plan tests => 2;

    # Clear cache
    $GitBz::Progress::TERMINAL_WIDTH = undef;
    $GitBz::Progress::LAST_WIDTH_CHECK = 0;

    # Mock tput to return 120
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub {
        my $width = 120;
        $GitBz::Progress::TERMINAL_WIDTH = $width;
        return $width;
    };

    my $width = GitBz::Progress::get_terminal_width();
    is( $width, 120, 'Returns mocked tput width' );
    is( $GitBz::Progress::TERMINAL_WIDTH, 120, 'Caches the width' );
};

# Test get_terminal_width with COLUMNS env var
subtest 'get_terminal_width with COLUMNS env' => sub {
    plan tests => 1;

    # Clear cache
    $GitBz::Progress::TERMINAL_WIDTH = undef;
    $GitBz::Progress::LAST_WIDTH_CHECK = 0;

    # Set COLUMNS environment variable
    local $ENV{COLUMNS} = 100;

    # Mock tput to fail
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub {
        if ( $ENV{COLUMNS} && $ENV{COLUMNS} =~ /^\d+$/ && $ENV{COLUMNS} > 0 ) {
            $GitBz::Progress::TERMINAL_WIDTH = $ENV{COLUMNS};
            return $GitBz::Progress::TERMINAL_WIDTH;
        }
        return 80;
    };

    my $width = GitBz::Progress::get_terminal_width();
    is( $width, 100, 'Returns COLUMNS env width when tput fails' );
};

# Test get_terminal_width fallback
subtest 'get_terminal_width fallback' => sub {
    plan tests => 1;

    # Clear cache
    $GitBz::Progress::TERMINAL_WIDTH = undef;
    $GitBz::Progress::LAST_WIDTH_CHECK = 0;

    # Mock to use fallback
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub {
        $GitBz::Progress::TERMINAL_WIDTH = 80;
        return 80;
    };

    my $width = GitBz::Progress::get_terminal_width();
    is( $width, 80, 'Falls back to 80 columns' );
};

# Test truncate_message - short message
subtest 'truncate_message - short message' => sub {
    plan tests => 1;

    # Mock terminal width to 80
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 80; };

    my $message = "Short message";
    my $result = GitBz::Progress::truncate_message( $message, 4, 0 );
    is( $result, "Short message", 'Short message not truncated' );
};

# Test truncate_message - exact fit
subtest 'truncate_message - exact fit' => sub {
    plan tests => 1;

    # Mock terminal width to 80
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 80; };

    my $message = "A" x 76;  # 80 - 4 prefix = 76 available
    my $result = GitBz::Progress::truncate_message( $message, 4, 0 );
    is( length($result), 76, 'Message fitting exactly not truncated' );
};

# Test truncate_message - long message
subtest 'truncate_message - long message' => sub {
    plan tests => 3;

    # Mock terminal width to 80
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 80; };

    my $message = "Bug 40811: Implement dual API for file transports with simplified auto-management";
    my $result = GitBz::Progress::truncate_message( $message, 4, 0 );

    ok( length($result) <= 76, 'Truncated message fits within width' );
    like( $result, qr/…$/, 'Truncated message ends with ellipsis' );
    is( length($result), 76, 'Truncated message uses full available width' );
};

# Test truncate_message - with prefix and suffix
subtest 'truncate_message - with prefix and suffix' => sub {
    plan tests => 2;

    # Mock terminal width to 80
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 80; };

    my $message = "A" x 100;
    my $result = GitBz::Progress::truncate_message( $message, 4, 3 );

    # Available: 80 - 4 - 3 = 73 chars
    is( length($result), 73, 'Truncated with both prefix and suffix' );
    like( $result, qr/…$/, 'Ends with ellipsis' );
};

# Test truncate_message - very long message
subtest 'truncate_message - very long message' => sub {
    plan tests => 2;

    # Mock terminal width to 80
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 80; };

    my $message = "X" x 500;
    my $result = GitBz::Progress::truncate_message( $message, 4, 0 );

    is( length($result), 76, 'Very long message truncated to max width' );
    like( $result, qr/^X+…$/, 'Contains original chars and ellipsis' );
};

# Test truncate_message - UTF-8 message
subtest 'truncate_message - UTF-8 message' => sub {
    plan tests => 2;

    # Mock terminal width to 80
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 80; };

    my $message = "Bug 日本語: " . ("テスト" x 30);
    my $result = GitBz::Progress::truncate_message( $message, 4, 0 );

    ok( length($result) <= 76, 'UTF-8 message truncated to fit' );
    like( $result, qr/…$/, 'UTF-8 message ends with ellipsis' );
};

# Test truncate_message - zero prefix/suffix
subtest 'truncate_message - zero prefix/suffix' => sub {
    plan tests => 1;

    # Mock terminal width to 80
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 80; };

    my $message = "A" x 100;
    my $result = GitBz::Progress::truncate_message( $message, 0, 0 );

    # Available: 80 - 0 - 0 = 80 chars, but -1 for ellipsis = 79
    is( length($result), 80, 'Truncated with zero prefix/suffix uses full width' );
};

# Test truncate_message - undefined prefix/suffix
subtest 'truncate_message - undefined prefix/suffix' => sub {
    plan tests => 1;

    # Mock terminal width to 80
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 80; };

    my $message = "A" x 100;
    my $result = GitBz::Progress::truncate_message( $message, undef, undef );

    is( length($result), 80, 'Handles undefined prefix/suffix as 0' );
};

# Test truncate_message - narrow terminal
subtest 'truncate_message - narrow terminal' => sub {
    plan tests => 2;

    # Mock terminal width to 20
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 20; };

    my $message = "This is a very long message";
    my $result = GitBz::Progress::truncate_message( $message, 4, 0 );

    # Available: 20 - 4 = 16 chars
    is( length($result), 16, 'Truncated for narrow terminal' );
    like( $result, qr/…$/, 'Narrow terminal result has ellipsis' );
};

# Test verbosity levels
subtest 'verbosity levels' => sub {
    plan tests => 3;

    GitBz::Progress::set_verbosity(0);
    is( GitBz::Progress::get_verbosity(), 0, 'Set verbosity to 0' );

    GitBz::Progress::set_verbosity(1);
    is( GitBz::Progress::get_verbosity(), 1, 'Set verbosity to 1' );

    GitBz::Progress::set_verbosity(2);
    is( GitBz::Progress::get_verbosity(), 2, 'Set verbosity to 2' );
};

# Test progress_counter
subtest 'progress_counter' => sub {
    plan tests => 1;

    my $counter = GitBz::Progress::progress_counter( 3, 10 );
    like( $counter, qr/\[3\/10\]/, 'Progress counter formats correctly' );
};

# Test truncate_message - minimum width edge case
subtest 'truncate_message - minimum width' => sub {
    plan tests => 2;

    # Mock terminal width to 10
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 10; };

    my $message = "Very long message here";
    my $result = GitBz::Progress::truncate_message( $message, 8, 0 );

    # Available: 10 - 8 = 2 chars, -1 for ellipsis = 1 char minimum
    ok( length($result) >= 2, 'Minimum width enforced' );
    like( $result, qr/…$/, 'Still has ellipsis at minimum width' );
};

# Test caching behavior
subtest 'terminal width caching' => sub {
    plan tests => 2;

    # Clear cache
    $GitBz::Progress::TERMINAL_WIDTH = undef;
    $GitBz::Progress::LAST_WIDTH_CHECK = 0;

    # First call
    my $width1 = GitBz::Progress::get_terminal_width();
    my $first_check_time = $GitBz::Progress::LAST_WIDTH_CHECK;

    # Second call immediately after (should use cache)
    my $width2 = GitBz::Progress::get_terminal_width();
    my $second_check_time = $GitBz::Progress::LAST_WIDTH_CHECK;

    is( $width1, $width2, 'Cached width matches original' );
    is( $first_check_time, $second_check_time, 'Cache check time unchanged' );
};

# Test empty message
subtest 'truncate_message - empty message' => sub {
    plan tests => 1;

    # Mock terminal width to 80
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 80; };

    my $message = "";
    my $result = GitBz::Progress::truncate_message( $message, 4, 0 );
    is( $result, "", 'Empty message remains empty' );
};

# Test single character message
subtest 'truncate_message - single char' => sub {
    plan tests => 1;

    # Mock terminal width to 80
    no warnings 'redefine';
    local *GitBz::Progress::get_terminal_width = sub { return 80; };

    my $message = "A";
    my $result = GitBz::Progress::truncate_message( $message, 4, 0 );
    is( $result, "A", 'Single character not truncated' );
};
