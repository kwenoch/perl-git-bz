#!/usr/bin/perl

use Modern::Perl;
use Test::More;
use Test::Exception;
use File::Temp;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use GitBz::Git;

# Test plan
plan tests => 8;

# Create a temporary git repository for testing
my $temp_dir = File::Temp->newdir();
my $repo_dir = "$temp_dir/test_repo";
mkdir $repo_dir;

# Initialize git repo
chdir $repo_dir or die "Cannot chdir to $repo_dir: $!";
system("git init -q") == 0 or die "git init failed";
system("git config user.name 'Test User'") == 0 or die "git config failed";
system("git config user.email 'test\@example.com'") == 0 or die "git config failed";

# Create initial commit with sponsor
system("echo 'test' > README") == 0 or die "echo failed";
system("git add README") == 0 or die "git add failed";
system(qq{git commit -q -m "Initial commit\n\nSponsored-by: ACME Corp"}) == 0 or die "git commit failed";

# Test 1: add_trailer_to_commit adds a new trailer
{
    my $commit_id = `git rev-parse HEAD`;
    chomp $commit_id;

    my $new_msg = GitBz::Git->add_trailer_to_commit($commit_id, 'Sponsored-by', 'ByWater Solutions');

    like($new_msg, qr/Sponsored-by: ACME Corp/, 'Original sponsor preserved');
    like($new_msg, qr/Sponsored-by: ByWater Solutions/, 'New sponsor added');
}

# Test 2: add_trailer_to_commit preserves other trailers
{
    system("echo 'test2' > README2") == 0 or die "echo failed";
    system("git add README2") == 0 or die "git add failed";
    system(qq{git commit -q -m "Add feature\n\nSigned-off-by: Test User <test\@example.com>"}) == 0 or die "git commit failed";

    my $commit_id = `git rev-parse HEAD`;
    chomp $commit_id;

    my $new_msg = GitBz::Git->add_trailer_to_commit($commit_id, 'Sponsored-by', 'Catalyst IT');

    like($new_msg, qr/Signed-off-by: Test User/, 'Signed-off-by preserved');
    like($new_msg, qr/Sponsored-by: Catalyst IT/, 'Sponsor added');
}

# Test 3: amend_commit_message only works for HEAD
{
    my $old_commit_id = `git rev-parse HEAD~1`;
    chomp $old_commit_id;

    throws_ok {
        GitBz::Git->amend_commit_message($old_commit_id, "New message");
    } 'GitBz::Exception::Git', 'Cannot amend non-HEAD commit';
}

# Test 4: amend_commit_message works for HEAD
{
    my $head_id = `git rev-parse HEAD`;
    chomp $head_id;

    lives_ok {
        GitBz::Git->amend_commit_message($head_id, "Amended message\n\nSponsored-by: New Sponsor");
    } 'Can amend HEAD commit';

    my $new_msg = GitBz::Git->run('log', '--format=%B', '-1', 'HEAD');
    like($new_msg, qr/Amended message/, 'Commit message changed');
    like($new_msg, qr/Sponsored-by: New Sponsor/, 'Sponsor added via amend');
}

# Cleanup
chdir '/';

done_testing();
