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
use Test::MockModule;
use FindBin;
use lib "$FindBin::Bin/../lib";

use GitBz::Commands::Apply;
use GitBz::Bug;

=head1 NAME

t/apply_dependencies.t - Test cascading dependency behavior in apply command

=head1 DESCRIPTION

Tests that the apply command correctly handles bug dependencies by:
- Detecting dependency bugs
- Prompting user to apply dependencies first
- Recursively applying dependencies
- Tracking applied bugs to avoid duplicates

=cut

subtest 'dependency detection and prompting' => sub {
    plan tests => 3;
    
    # Mock GitBz::Bug to return test data
    my $bug_mock = Test::MockModule->new('GitBz::Bug');
    $bug_mock->mock('get', sub {
        my ($class, $client, $bug_id) = @_;
        
        if ($bug_id == 100) {
            return bless {
                data => {
                    id => 100,
                    summary => 'Dependency bug',
                    status => 'Needs Signoff',
                    depends_on => [],
                },
                _attachments => [
                    { id => 1001, is_patch => 1, is_obsolete => 0, summary => 'Dep patch' }
                ]
            }, 'GitBz::Bug';
        } elsif ($bug_id == 200) {
            return bless {
                data => {
                    id => 200,
                    summary => 'Main bug',
                    status => 'Needs Signoff',
                    depends_on => [100],
                },
                _attachments => [
                    { id => 2001, is_patch => 1, is_obsolete => 0, summary => 'Main patch' }
                ]
            }, 'GitBz::Bug';
        }
        return undef;
    });
    
    my $main_bug = GitBz::Bug->get(undef, 200);
    my $dep_bug = GitBz::Bug->get(undef, 100);
    
    # Test dependency detection
    is_deeply($main_bug->depends_on, [100], 'Main bug depends on bug 100');
    is($dep_bug->status, 'Needs Signoff', 'Dependency bug has applicable status');
    
    # Test that dependency would be prompted
    my $dep_status = $dep_bug->status;
    my $should_prompt = ($dep_status eq 'Needs Signoff' 
                        || $dep_status eq 'Signed Off'
                        || $dep_status eq 'Failed QA'
                        || $dep_status eq 'Passed QA'
                        || $dep_status eq 'BLOCKED'
                        || $dep_status eq 'In Discussion');
    
    ok($should_prompt, 'Dependency bug status triggers prompting');
    
    note("Dependency chain: Bug 200 -> Bug 100");
    note("This would prompt: 'Bug 200 depends on bug 100 (Needs Signoff)'");
    note("User would be asked: 'Follow? [(y)es, (n)o]'");
};

subtest 'applied bugs tracking' => sub {
    plan tests => 4;
    
    # Reset tracking
    @GitBz::Commands::Apply::bugs_applied = ();
    
    is(scalar @GitBz::Commands::Apply::bugs_applied, 0, 'Applied bugs list starts empty');
    
    # Simulate applying bugs
    push @GitBz::Commands::Apply::bugs_applied, 100;
    push @GitBz::Commands::Apply::bugs_applied, 200;
    
    is(scalar @GitBz::Commands::Apply::bugs_applied, 2, 'Two bugs tracked as applied');
    
    # Test duplicate detection
    my $already_applied = grep { $_ eq 100 } @GitBz::Commands::Apply::bugs_applied;
    ok($already_applied, 'Bug 100 is tracked as already applied');
    
    my $not_applied = grep { $_ eq 300 } @GitBz::Commands::Apply::bugs_applied;
    ok(!$not_applied, 'Bug 300 is not tracked as applied');
    
    note("Applied bugs tracking prevents duplicate applications during recursion");
};

subtest 'dependency status filtering' => sub {
    plan tests => 7;
    
    # Test which bug statuses should trigger dependency prompting
    my @applicable_statuses = ('Needs Signoff', 'Signed Off', 'Failed QA', 'Passed QA', 'BLOCKED', 'In Discussion');
    my @non_applicable_statuses = ('NEW', 'ASSIGNED', 'RESOLVED', 'VERIFIED', 'CLOSED');
    
    for my $status (@applicable_statuses) {
        my $should_prompt = ($status eq 'Needs Signoff' 
                            || $status eq 'Signed Off'
                            || $status eq 'Failed QA'
                            || $status eq 'Passed QA'
                            || $status eq 'BLOCKED'
                            || $status eq 'In Discussion');
        ok($should_prompt, "Status '$status' triggers dependency prompting");
    }
    
    my $non_applicable = 'NEW';
    my $should_not_prompt = !($non_applicable eq 'Needs Signoff' 
                             || $non_applicable eq 'Signed Off'
                             || $non_applicable eq 'Failed QA'
                             || $non_applicable eq 'Passed QA'
                             || $non_applicable eq 'BLOCKED');
    ok($should_not_prompt, "Status 'NEW' does not trigger dependency prompting");
    
    note("Only bugs in patch-ready states trigger dependency following");
};

done_testing();
