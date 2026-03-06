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
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use GitBz::Commands::Attach;
use GitBz::Bug;

plan tests => 7;

# Mock bug helper
sub create_mock_bug {
    my %data = @_;
    return bless {
        data => {
            id              => $data{id} || 12345,
            summary         => $data{summary} || 'Test bug',
            status          => $data{status} || 'NEW',
            cf_sponsors     => $data{cf_sponsors} || '',
            cf_sponsorship  => $data{cf_sponsorship} || '',
            cf_patch_complexity => $data{cf_patch_complexity} || '',
            depends_on      => $data{depends_on} || [],
        },
        _attachments => [],
    }, 'GitBz::Bug';
}

# Mock REST client
my $mock_client = Test::MockModule->new('GitBz::RestClient');
$mock_client->mock('get_field_values', sub {
    return ['Small patch', 'Medium patch', 'Large patch'];
});

my $mock_workflow = Test::MockModule->new('GitBz::StatusWorkflow');
$mock_workflow->mock('get_next_status_values', sub {
    return ['ASSIGNED', 'Needs Signoff'];
});

my $mock_commands = {
    client => bless({}, 'GitBz::RestClient'),
};
my $attach = GitBz::Commands::Attach->new($mock_commands);

# Mock edit_template to return the template without opening editor
my $mock_attach = Test::MockModule->new('GitBz::Commands::Attach');
my $captured_template;
$mock_attach->mock('edit_template', sub {
    my ($self, $template) = @_;
    $captured_template = $template;
    return $template;  # Return template unchanged
});

subtest 'Sponsor section with no sponsors - shows example' => sub {
    plan tests => 2;

    my $mock_git = Test::MockModule->new('GitBz::Git');
    $mock_git->mock('get_sponsors', sub { return (); });

    my $bug = create_mock_bug(cf_sponsors => '');
    my @commits = ({ id => 'abc123', subject => 'Test commit' });

    $attach->edit_bug_updates($bug, \@commits);
    my $template = $captured_template;

    like($template, qr/# Current sponsors:\s*$/m,
         'Shows empty current sponsors');
    like($template, qr/# Sponsors: Sponsor Name/,
         'Shows example sponsor format when no sponsors');
};

subtest 'Sponsor section with existing bug sponsors only' => sub {
    plan tests => 2;

    my $mock_git = Test::MockModule->new('GitBz::Git');
    $mock_git->mock('get_sponsors', sub { return (); });

    my $bug = create_mock_bug(cf_sponsors => 'ACME Corp');
    my @commits = ({ id => 'abc123', subject => 'Test commit' });

    $attach->edit_bug_updates($bug, \@commits);
    my $template = $captured_template;

    like($template, qr/# Current sponsors: ACME Corp/,
         'Shows current bug sponsors');
    like($template, qr/^Sponsors: ACME Corp$/m,
         'Proposes existing sponsors unchanged');
};

subtest 'Sponsor section with commit sponsors only' => sub {
    plan tests => 3;

    my $mock_git = Test::MockModule->new('GitBz::Git');
    $mock_git->mock('get_sponsors', sub {
        return ('ByWater Solutions');
    });

    my $bug = create_mock_bug(cf_sponsors => '');
    my @commits = ({ id => 'abc123', subject => 'Test commit' });

    $attach->edit_bug_updates($bug, \@commits);
    my $template = $captured_template;

    like($template, qr/#\s+abc123: Test commit/,
         'Shows commit in reference section');
    like($template, qr/#\s+Sponsored-by: ByWater Solutions/,
         'Shows sponsor trailer in commit reference');
    like($template, qr/^Sponsors: ByWater Solutions$/m,
         'Proposes commit sponsor');
};

subtest 'Sponsor section merges bug and commit sponsors' => sub {
    plan tests => 2;

    my $mock_git = Test::MockModule->new('GitBz::Git');
    $mock_git->mock('get_sponsors', sub {
        return ('ByWater Solutions', 'Catalyst IT');
    });

    my $bug = create_mock_bug(cf_sponsors => 'ACME Corp, ByWater Solutions');
    my @commits = ({ id => 'abc123', subject => 'Test commit' });

    $attach->edit_bug_updates($bug, \@commits);
    my $template = $captured_template;

    like($template, qr/# Current sponsors: ACME Corp, ByWater Solutions/,
         'Shows current bug sponsors');
    like($template, qr/Sponsors: ACME Corp.*Sponsors: ByWater Solutions.*Sponsors: Catalyst IT/s,
         'Merges and sorts all unique sponsors on separate lines');
};

subtest 'Multiple commits with different sponsors' => sub {
    plan tests => 3;

    my $mock_git = Test::MockModule->new('GitBz::Git');
    my $call_count = 0;
    $mock_git->mock('get_sponsors', sub {
        my ($class, $commit_id) = @_;
        $call_count++;
        return ('Sponsor One') if $commit_id eq 'abc123';
        return ('Sponsor Two') if $commit_id eq 'def456';
        return ();
    });

    my $bug = create_mock_bug(cf_sponsors => '');
    my @commits = (
        { id => 'abc123', subject => 'First commit' },
        { id => 'def456', subject => 'Second commit' }
    );

    $attach->edit_bug_updates($bug, \@commits);
    my $template = $captured_template;

    like($template, qr/#\s+Sponsored-by: Sponsor One/,
         'Shows first sponsor in commit reference');
    like($template, qr/#\s+Sponsored-by: Sponsor Two/,
         'Shows second sponsor in commit reference');
    like($template, qr/Sponsors: Sponsor One.*Sponsors: Sponsor Two/s,
         'Proposes merged sponsors from all commits on separate lines');
};

subtest 'Sponsor names with whitespace are trimmed' => sub {
    plan tests => 1;

    my $mock_git = Test::MockModule->new('GitBz::Git');
    $mock_git->mock('get_sponsors', sub {
        return ('New Sponsor');
    });

    my $bug = create_mock_bug(cf_sponsors => '  Old Sponsor  ,  Whitespace Sponsor  ');
    my @commits = ({ id => 'abc123', subject => 'Test commit' });

    $attach->edit_bug_updates($bug, \@commits);
    my $template = $captured_template;

    like($template, qr/Sponsors: New Sponsor.*Sponsors: Old Sponsor.*Sponsors: Whitespace Sponsor/s,
         'Trims whitespace and sorts sponsors on separate lines');
};

subtest 'Clearing the edit file cancels the operation' => sub {
    plan tests => 1;

    my $mock_git = Test::MockModule->new('GitBz::Git');
    $mock_git->mock('get_sponsors', sub { return (); });

    # Override edit_template to simulate user clearing the file
    $mock_attach->mock('edit_template', sub { return ''; });

    my $bug = create_mock_bug();
    my @commits = ({ id => 'abc123', subject => 'Test commit' });

    throws_ok(
        sub { $attach->edit_bug_updates($bug, \@commits) },
        qr/cancelled by user/i,
        'Throws cancellation error when file is cleared'
    );

    # Restore the original mock
    $mock_attach->mock('edit_template', sub {
        my ($self, $template) = @_;
        $captured_template = $template;
        return $template;
    });
};

done_testing();
