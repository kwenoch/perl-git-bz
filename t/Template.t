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
use Test::MockModule;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use GitBz::Template;

# Mock bug helper
sub create_bug {
    my %data = @_;
    my $bug = bless {
        data => {
            id                  => $data{id} || 12345,
            summary             => $data{summary} || 'Test bug',
            status              => $data{status} || 'NEW',
            resolution          => $data{resolution},
            depends_on          => $data{depends_on} || [],
            cf_patch_complexity => $data{cf_patch_complexity},
            cf_sponsors         => $data{cf_sponsors},
            cf_sponsorship      => $data{cf_sponsorship},
        },
        _attachments => [],
    }, 'GitBz::Bug';
    
    # Add accessor methods
    no strict 'refs';
    *{'GitBz::Bug::id'}                  = sub { $_[0]->{data}->{id} };
    *{'GitBz::Bug::summary'}             = sub { $_[0]->{data}->{summary} };
    *{'GitBz::Bug::status'}              = sub { $_[0]->{data}->{status} };
    *{'GitBz::Bug::resolution'}          = sub { $_[0]->{data}->{resolution} };
    *{'GitBz::Bug::depends_on'}          = sub { $_[0]->{data}->{depends_on} };
    *{'GitBz::Bug::cf_patch_complexity'} = sub { $_[0]->{data}->{cf_patch_complexity} };
    *{'GitBz::Bug::cf_sponsors'}         = sub { $_[0]->{data}->{cf_sponsors} };
    *{'GitBz::Bug::cf_sponsorship'}      = sub { $_[0]->{data}->{cf_sponsorship} };
    
    return $bug;
}

# Mock client
sub create_client {
    return bless {}, 'MockClient';
}

subtest 'generate_bug_fields() - basic fields' => sub {
    plan tests => 5;
    
    my $bug = create_bug();
    my $client = create_client();
    
    # Mock the external calls
    my $mock_workflow = Test::MockModule->new('GitBz::StatusWorkflow');
    $mock_workflow->mock('new', sub { bless {}, 'GitBz::StatusWorkflow' });
    $mock_workflow->mock('get_next_status_values', sub { return ['ASSIGNED', 'Needs Signoff'] });
    
    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock('with_spinner', sub { 
        my ($msg, $code) = @_;
        return ['Small patch', 'Medium patch'];
    });
    
    my $template = GitBz::Template::generate_bug_fields($bug, $client);
    
    like($template, qr/# Current status: NEW/, 'Shows current status');
    like($template, qr/# Status: ASSIGNED/, 'Shows status options');
    like($template, qr/# Current patch-complexity:/, 'Shows patch complexity section');
    like($template, qr/# Current depends:/, 'Shows depends section');
    like($template, qr/# Current sponsorship:/, 'Shows sponsorship section');
};

subtest 'generate_bug_fields() - with sponsors' => sub {
    plan tests => 3;
    
    my $bug = create_bug(cf_sponsors => 'Sponsor One, Sponsor Two');
    my $client = create_client();
    
    my $mock_workflow = Test::MockModule->new('GitBz::StatusWorkflow');
    $mock_workflow->mock('new', sub { bless {}, 'GitBz::StatusWorkflow' });
    $mock_workflow->mock('get_next_status_values', sub { return [] });
    
    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock('with_spinner', sub { return [] });
    
    my $template = GitBz::Template::generate_bug_fields($bug, $client);
    
    like($template, qr/# Current sponsors: Sponsor One, Sponsor Two/, 'Shows current sponsors');
    like($template, qr/Sponsors: Sponsor One/, 'Shows first sponsor uncommented');
    like($template, qr/Sponsors: Sponsor Two/, 'Shows second sponsor uncommented');
};

subtest 'generate_bug_fields() - with commit sponsors' => sub {
    plan tests => 2;
    
    my $bug = create_bug(cf_sponsors => 'Existing Sponsor');
    my $client = create_client();
    
    my $mock_workflow = Test::MockModule->new('GitBz::StatusWorkflow');
    $mock_workflow->mock('new', sub { bless {}, 'GitBz::StatusWorkflow' });
    $mock_workflow->mock('get_next_status_values', sub { return [] });
    
    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock('with_spinner', sub { return [] });
    
    my %all_sponsors = ('New Sponsor' => 1);
    my $template = GitBz::Template::generate_bug_fields($bug, $client, all_sponsors => \%all_sponsors);
    
    like($template, qr/Sponsors: Existing Sponsor/, 'Shows existing sponsor');
    like($template, qr/Sponsors: New Sponsor/, 'Shows new sponsor from commits');
};

subtest 'generate_bug_fields() - with obsoletes (attach mode)' => sub {
    plan tests => 3;
    
    my $bug = create_bug();
    my $client = create_client();
    
    my $mock_workflow = Test::MockModule->new('GitBz::StatusWorkflow');
    $mock_workflow->mock('new', sub { bless {}, 'GitBz::StatusWorkflow' });
    $mock_workflow->mock('get_next_status_values', sub { return [] });
    
    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock('with_spinner', sub { return [] });
    
    my $attachments = [
        { id => 123, summary => 'Old patch', is_patch => 1, is_obsolete => 0 },
        { id => 124, summary => 'Matching patch', is_patch => 1, is_obsolete => 0 },
    ];
    my $commits = [
        { subject => 'Matching patch' },
    ];
    
    my $template = GitBz::Template::generate_bug_fields(
        $bug, $client,
        attachments => $attachments,
        commits => $commits
    );
    
    like($template, qr/#Obsoletes: 123 - Old patch/, 'Commented obsolete for non-matching patch');
    like($template, qr/^Obsoletes: 124 - Matching patch/m, 'Uncommented obsolete for matching patch');
    unlike($template, qr/#Obsoletes: 124/, 'Matching patch not commented');
};

subtest 'generate_bug_fields() - with obsoletes (edit mode)' => sub {
    plan tests => 2;
    
    my $bug = create_bug();
    my $client = create_client();
    
    my $mock_workflow = Test::MockModule->new('GitBz::StatusWorkflow');
    $mock_workflow->mock('new', sub { bless {}, 'GitBz::StatusWorkflow' });
    $mock_workflow->mock('get_next_status_values', sub { return [] });
    
    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock('with_spinner', sub { return [] });
    
    my $attachments = [
        { id => 123, summary => 'Patch one', is_patch => 1, is_obsolete => 0 },
        { id => 124, summary => 'Patch two', is_patch => 1, is_obsolete => 0 },
    ];
    
    my $template = GitBz::Template::generate_bug_fields(
        $bug, $client,
        attachments => $attachments
    );
    
    like($template, qr/#Obsoletes: 123 - Patch one/, 'All obsoletes commented without commits');
    like($template, qr/#Obsoletes: 124 - Patch two/, 'All obsoletes commented without commits');
};

subtest 'parse_bug_fields() - basic parsing' => sub {
    plan tests => 4;
    
    my $bug = create_bug();
    my $content = <<'END';
# Comment line
Status: ASSIGNED
Patch-complexity: Small patch
Sponsorship: Sponsored
END
    
    my $updates = GitBz::Template::parse_bug_fields($content, $bug);
    
    is($updates->{status}, 'ASSIGNED', 'Parses status');
    is($updates->{cf_patch_complexity}, 'Small patch', 'Parses patch complexity');
    is($updates->{cf_sponsorship}, 'Sponsored', 'Parses sponsorship');
    ok(!$updates->{depends_on}, 'No depends when not specified');
};

subtest 'parse_bug_fields() - sponsors with add/remove' => sub {
    plan tests => 3;
    
    my $bug = create_bug(cf_sponsors => 'Old Sponsor');
    my $content = <<'END';
Sponsors: New Sponsor
END
    
    my $updates = GitBz::Template::parse_bug_fields($content, $bug);
    
    is(ref $updates->{cf_sponsors}, 'HASH', 'Sponsors returns hash ref');
    is_deeply($updates->{cf_sponsors}{add}, ['New Sponsor'], 'New sponsor added');
    is_deeply($updates->{cf_sponsors}{remove}, ['Old Sponsor'], 'Old sponsor removed');
};

subtest 'parse_bug_fields() - depends with add/remove' => sub {
    plan tests => 3;
    
    my $bug = create_bug(depends_on => [123]);
    my $content = <<'END';
Depends: bug 456
END
    
    my $updates = GitBz::Template::parse_bug_fields($content, $bug);
    
    is(ref $updates->{depends_on}, 'HASH', 'Depends returns hash ref');
    is_deeply($updates->{depends_on}{add}, [456], 'New dependency added');
    is_deeply($updates->{depends_on}{remove}, [123], 'Old dependency removed');
};

subtest 'parse_bug_fields() - auto-update sponsorship' => sub {
    plan tests => 2;
    
    my $bug = create_bug(cf_sponsorship => 'Seeking sponsor');
    my $content = <<'END';
Sponsors: New Sponsor
END
    
    my $updates = GitBz::Template::parse_bug_fields($content, $bug);
    
    ok($updates->{cf_sponsors}{add}, 'Sponsor being added');
    is($updates->{cf_sponsorship}, 'Sponsored', 'Auto-updates sponsorship to Sponsored');
};

subtest 'parse_bug_fields() - no auto-update when already sponsored' => sub {
    plan tests => 1;
    
    my $bug = create_bug(cf_sponsorship => 'Sponsored');
    my $content = <<'END';
Sponsors: Another Sponsor
END
    
    my $updates = GitBz::Template::parse_bug_fields($content, $bug);
    
    ok(!$updates->{cf_sponsorship}, 'Does not auto-update when already Sponsored');
};

done_testing();
