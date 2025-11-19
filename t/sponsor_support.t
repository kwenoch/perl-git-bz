#!/usr/bin/perl

use Modern::Perl;
use Test::More;
use Test::Exception;
use File::Temp;
use File::Path qw(remove_tree);
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use GitBz::Git;

# Test plan
plan tests => 11;

# Create a temporary git repository for testing
my $temp_dir = File::Temp->newdir();
my $repo_dir = "$temp_dir/test_repo";
mkdir $repo_dir;

# Initialize git repo
chdir $repo_dir or die "Cannot chdir to $repo_dir: $!";
system("git init -q") == 0 or die "git init failed";
system("git config user.name 'Test User'") == 0 or die "git config failed";
system("git config user.email 'test\@example.com'") == 0 or die "git config failed";

# Create initial commit
system("echo 'test' > README") == 0 or die "echo failed";
system("git add README") == 0 or die "git add failed";
system("git commit -q -m 'Initial commit'") == 0 or die "git commit failed";

# Test 1: get_trailer with no trailers
{
    my $commit_id = `git rev-parse HEAD`;
    chomp $commit_id;

    my $trailer = GitBz::Git->get_trailer($commit_id, 'Sponsored-by');
    is($trailer, undef, 'get_trailer returns undef when no trailer exists');
}

# Test 2: get_sponsors with no sponsors
{
    my $commit_id = `git rev-parse HEAD`;
    chomp $commit_id;

    my @sponsors = GitBz::Git->get_sponsors($commit_id);
    is(scalar @sponsors, 0, 'get_sponsors returns empty array when no sponsors');
}

# Test 3: Create commit with single sponsor
{
    system("echo 'test2' > README2") == 0 or die "echo failed";
    system("git add README2") == 0 or die "git add failed";
    system(qq{git commit -q -m "Add feature\n\nSponsored-by: ACME Corp"}) == 0 or die "git commit failed";

    my $commit_id = `git rev-parse HEAD`;
    chomp $commit_id;

    my $sponsor = GitBz::Git->get_trailer($commit_id, 'Sponsored-by');
    is($sponsor, 'ACME Corp', 'get_trailer extracts single sponsor');
}

# Test 4: get_sponsors with single sponsor
{
    my $commit_id = `git rev-parse HEAD`;
    chomp $commit_id;

    my @sponsors = GitBz::Git->get_sponsors($commit_id);
    is(scalar @sponsors, 1, 'get_sponsors returns correct count');
    is($sponsors[0], 'ACME Corp', 'get_sponsors extracts correct sponsor name');
}

# Test 5: Create commit with multiple sponsors
{
    system("echo 'test3' > README3") == 0 or die "echo failed";
    system("git add README3") == 0 or die "git add failed";
    system(qq{git commit -q -m "Add another feature\n\nSponsored-by: ByWater Solutions\nSponsored-by: Catalyst IT"}) == 0 or die "git commit failed";

    my $commit_id = `git rev-parse HEAD`;
    chomp $commit_id;

    my @sponsors = GitBz::Git->get_sponsors($commit_id);
    is(scalar @sponsors, 2, 'get_sponsors handles multiple sponsors');
    is($sponsors[0], 'ByWater Solutions', 'First sponsor extracted correctly');
    is($sponsors[1], 'Catalyst IT', 'Second sponsor extracted correctly');
}

# Test 6: Create commit with sponsor and other trailers
{
    system("echo 'test4' > README4") == 0 or die "echo failed";
    system("git add README4") == 0 or die "git add failed";
    system(qq{git commit -q -m "Fix bug\n\nSponsored-by: University of the Arts London\nSigned-off-by: Test User <test\@example.com>"}) == 0 or die "git commit failed";

    my $commit_id = `git rev-parse HEAD`;
    chomp $commit_id;

    my $sponsor = GitBz::Git->get_trailer($commit_id, 'Sponsored-by');
    is($sponsor, 'University of the Arts London', 'get_trailer works with mixed trailers');

    my $signoff = GitBz::Git->get_trailer($commit_id, 'Signed-off-by');
    is($signoff, 'Test User <test@example.com>', 'get_trailer can extract different trailer types');
}

# Test 7: Test list context for get_trailer with multiple values
{
    my $commit_id = `git rev-parse HEAD~1`;
    chomp $commit_id;

    my @sponsors = GitBz::Git->get_trailer($commit_id, 'Sponsored-by');
    is(scalar @sponsors, 2, 'get_trailer in list context returns all values');
}

# Cleanup
chdir '/';

done_testing();
