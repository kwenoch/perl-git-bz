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

# Regression test for a bug reported by a user: when a network error occurs
# while tagging/obsoleting comments or attachments (e.g. "Can't connect to
# bugs.koha-community.org:443"), the spinner for that step was never stopped
# on the error path. Since start_spinner() forks a child process that loops
# forever printing spinner frames until explicitly killed by stop_spinner(),
# an uncaught die left that child orphaned - it kept animating on the
# terminal indefinitely (looking like git-bz "hung"), even though the parent
# process had already exited with an error.
#
# These tests verify that GitBz::Progress::stop_spinner() is always invoked
# (with an 'error' status) before the exception propagates, for every step
# that can fail between start_spinner() and stop_spinner().

use Modern::Perl;

use Test::More tests => 4;
use Test::Exception;
use Test::MockModule;

use FindBin;
use lib "$FindBin::RealBin/../lib";

use GitBz::Commands::Attach;

sub _mock_commands { return { client => undef } }

sub _stub_progress {
    my ($mock_progress) = @_;
    my @events;
    $mock_progress->mock( 'with_spinner', sub {
        my ( $msg, $code, $level ) = @_;
        return $code->();
    } );
    $mock_progress->mock( 'start_spinner', sub {
        push @events, { type => 'start', message => $_[0] };
        return { message => $_[0], is_tty => 0 };
    } );
    $mock_progress->mock( 'stop_spinner', sub {
        my ( $spinner, $status, $message ) = @_;
        push @events, { type => 'stop', status => $status, message => $message };
    } );
    $mock_progress->mock( 'print_success', sub { } );
    $mock_progress->mock( 'print_error',   sub { } );
    $mock_progress->mock( 'print_section', sub { } );
    return \@events;
}

my $mock_git = Test::MockModule->new('GitBz::Git');
$mock_git->mock( 'format_patch', sub { return "patch content"; } );
$mock_git->mock( 'run',          sub { return "commit body"; } );

subtest 'spinner stopped with error status when obsolete_attachments fails' => sub {
    plan tests => 2;

    my $mock_bug_class = Test::MockModule->new('GitBz::Bug');
    $mock_bug_class->mock( 'get', sub {
        my ( $class, $client, $number ) = @_;
        return bless { data => { id => $number } }, $class;
    } );
    $mock_bug_class->mock( 'attachments', sub {
        return [ { id => 1001, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Fix something important' } ];
    } );
    $mock_bug_class->mock( 'obsolete_attachments', sub {
        die "Failed to obsolete attachments: 500 Can't connect to bugs.koha-community.org:443\n";
    } );

    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    my $events = _stub_progress($mock_progress);

    my $attach = GitBz::Commands::Attach->new( _mock_commands() );
    my @commits = ( { id => 'abc123', subject => 'Bug 12345: Fix something important' } );

    throws_ok {
        $attach->attach_patches( '12345', \@commits, { yes => 1 } );
    } qr/Can't connect/, 'exception propagates to caller';

    ok( ( grep { ( $_->{type} // '' ) eq 'stop' && ( $_->{status} // '' ) eq 'error' } @$events ),
        'stop_spinner was called with error status (spinner not leaked)' );
};

subtest 'spinner stopped with error status when obsolete_comments_for_attachments fails' => sub {
    plan tests => 2;

    my $mock_bug_class = Test::MockModule->new('GitBz::Bug');
    $mock_bug_class->mock( 'get', sub {
        my ( $class, $client, $number ) = @_;
        return bless { data => { id => $number } }, $class;
    } );
    $mock_bug_class->mock( 'attachments', sub {
        return [ { id => 1001, is_patch => 1, is_obsolete => 0, summary => 'Bug 12345: Fix something important' } ];
    } );
    $mock_bug_class->mock( 'obsolete_attachments',                sub { return {}; } );
    $mock_bug_class->mock( 'obsolete_comments_for_attachments', sub {
        die "Failed to add comment tag: 500 Can't connect to bugs.koha-community.org:443\n";
    } );

    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    my $events = _stub_progress($mock_progress);

    my $attach = GitBz::Commands::Attach->new( _mock_commands() );
    my @commits = ( { id => 'abc123', subject => 'Bug 12345: Fix something important' } );

    throws_ok {
        $attach->attach_patches( '12345', \@commits, { yes => 1 } );
    } qr/Can't connect/, 'exception propagates to caller';

    my @tagging_events = grep { ( $_->{message} // '' ) =~ /[Tt]agging/ } @$events;
    ok( ( grep { $_->{type} eq 'stop' && $_->{status} eq 'error' } @$events ),
        'stop_spinner was called with error status for the tagging step (spinner not leaked)' );
};

subtest 'spinner stopped with error status when patch generation fails' => sub {
    plan tests => 2;

    my $mock_bug_class = Test::MockModule->new('GitBz::Bug');
    $mock_bug_class->mock( 'get', sub {
        my ( $class, $client, $number ) = @_;
        return bless { data => { id => $number } }, $class;
    } );
    $mock_bug_class->mock( 'attachments', sub { return []; } );

    my $mock_git_local = Test::MockModule->new('GitBz::Git');
    $mock_git_local->mock( 'format_patch', sub { die "fatal: bad revision\n"; } );
    $mock_git_local->mock( 'run',          sub { return "commit body"; } );

    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    my $events = _stub_progress($mock_progress);

    my $attach = GitBz::Commands::Attach->new( _mock_commands() );
    my @commits = ( { id => 'abc123', subject => 'Bug 12345: Fix something important' } );

    throws_ok {
        $attach->attach_patches( '12345', \@commits, { yes => 1 } );
    } qr/bad revision/, 'exception propagates to caller';

    ok( ( grep { $_->{type} eq 'stop' && $_->{status} eq 'error' } @$events ),
        'stop_spinner was called with error status for the generate-patch step (spinner not leaked)' );
};

subtest 'orphaned spinner process is reaped even if a step forgets to stop it' => sub {
    plan tests => 3;

    no warnings 'once';
    local $GitBz::Progress::FORCE_TTY = 1;

    my $captured = '';
    open my $fh, '>', \$captured or die $!;
    local *STDOUT = $fh;

    my $spinner = GitBz::Progress::start_spinner("Simulated leaked step");
    ok( $spinner->{pid}, 'spinner forked a child process' );
    ok( kill( 0, $spinner->{pid} ), 'child process is alive right after fork' );

    # Simulate the process exiting without ever calling stop_spinner() for
    # this spinner (i.e. the exact bug being fixed) - the safety-net cleanup
    # (normally run from an END block) must still reap it.
    GitBz::Progress::_cleanup_spinners();

    ok( !kill( 0, $spinner->{pid} ), 'orphaned child process was reaped by the safety net' );
};
