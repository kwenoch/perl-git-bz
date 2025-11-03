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
use FindBin;
use lib "$FindBin::RealBin/../lib";
use GitBz::Git;
use IPC::Run3;
use Cwd;

# Regression test for UTF-8 corruption in GitBz::Git->run()
# Uses controlled test repository with known UTF-8 content

my $original_dir = getcwd();
my $test_repo = "$FindBin::RealBin/data/git_repo";

subtest 'UTF-8 handling in test repository' => sub {
    chdir $test_repo or die "Cannot chdir to $test_repo: $!";
    
    # Get raw git format-patch output for the single commit
    my @cmd = ('git', 'format-patch', '--stdout', '--root', 'HEAD');
    my $raw_output;
    run3 \@cmd, \undef, \$raw_output;
    
    # Get GitBz::Git output
    my $gitbz_output = GitBz::Git->run('format-patch', '--stdout', '--root', 'HEAD');
    
    # Test 1: Outputs should be identical (will FAIL with buggy code)
    is($gitbz_output, $raw_output, 'GitBz::Git output matches raw git format-patch');
    
    # Test 2: Check specific UTF-8 characters are preserved
    like($gitbz_output, qr/ç/, 'UTF-8 character ç is preserved');
    like($gitbz_output, qr/á/, 'UTF-8 character á is preserved');
    like($gitbz_output, qr/✔/, 'UTF-8 character ✔ is preserved');
    like($gitbz_output, qr/❤/, 'UTF-8 character ❤ is preserved');
    like($gitbz_output, qr/★/, 'UTF-8 character ★ is preserved');
    
    # Test 3: Check author name UTF-8 (will FAIL with buggy code)
    like($gitbz_output, qr/Tomás/, 'Author name UTF-8 character á is preserved');
    
    chdir $original_dir;
};

done_testing();
