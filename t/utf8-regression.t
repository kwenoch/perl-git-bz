#!/usr/bin/env perl

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
