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
use File::Temp;

use GitBz::Commands::Apply;
use GitBz::Bug;

=head1 NAME

t/apply_dependency_resume.t - Regression test for resuming the parent bug
after a dependency's patches needed manual conflict resolution.

=head1 DESCRIPTION

`git bz apply <bug>` where <bug> depends on another bug whose patches fail
partway through (git-am conflict). After the user resolves the conflict and
runs `git bz apply --continue`, the tool must not just finish the
dependency - it must go on to apply the original bug's own patches too.

=cut

subtest 'continuing after a dependency conflict resumes the parent bug' => sub {
    plan tests => 4;

    @GitBz::Commands::Apply::bugs_applied = ();

    my $temp_git_dir     = File::Temp->newdir();
    my $rebase_apply_dir = "$temp_git_dir/rebase-apply";

    my $bug_mock = Test::MockModule->new('GitBz::Bug');
    $bug_mock->mock(
        'get',
        sub {
            my ( $class, $client, $bug_id ) = @_;

            if ( $bug_id eq '1000' ) {
                return bless {
                    data => {
                        id         => 1000,
                        summary    => 'Parent bug',
                        status     => 'Needs Signoff',
                        depends_on => [2000],
                    },
                    _attachments => [
                        { id => 1001, is_patch => 1, is_obsolete => 0, summary => 'Parent patch', data => 'cGFyZW50' }
                    ]
                }, 'GitBz::Bug';
            } elsif ( $bug_id eq '2000' ) {
                return bless {
                    data => {
                        id         => 2000,
                        summary    => 'Dependency bug',
                        status     => 'Needs Signoff',
                        depends_on => [],
                    },
                    _attachments => [
                        { id => 2001, is_patch => 1, is_obsolete => 0, summary => 'Dep patch 1', data => 'ZGVwMQ==' },
                        { id => 2002, is_patch => 1, is_obsolete => 0, summary => 'Dep patch 2', data => 'ZGVwMg==' },
                    ]
                }, 'GitBz::Bug';
            }
            return undef;
        }
    );
    $bug_mock->mock( 'summary',     sub { shift->{data}{summary} } );
    $bug_mock->mock( 'attachments', sub { shift->{_attachments} } );
    $bug_mock->mock( 'depends_on',  sub { shift->{data}{depends_on} } );
    $bug_mock->mock( 'status',      sub { shift->{data}{status} } );

    my @am_calls;
    my $git_mock = Test::MockModule->new('GitBz::Git');
    $git_mock->mock(
        'run',
        sub {
            my ( $class, @args ) = @_;

            if ( $args[0] eq 'rev-parse' && $args[1] eq '--git-dir' ) {
                return "$temp_git_dir\n";
            }

            if ( $args[0] eq 'am' ) {
                if ( $args[1] eq '--continue' || $args[1] eq '--skip' || $args[1] eq '--abort' ) {
                    push @am_calls, $args[1];
                    return '';
                }

                # Applying a patch file: record which one, and fail on 2002.
                my ($file) = grep { $_ !~ /^-/ } @args[ 1 .. $#args ];
                push @am_calls, $file;

                if ( $file =~ /-2002\.patch$/ ) {
                    mkdir $rebase_apply_dir unless -d $rebase_apply_dir;
                    die "git am failed - conflict\n";
                }
                return '';
            }
        }
    );

    my $commands = { client => {} };
    my $apply    = GitBz::Commands::Apply->new($commands);

    my %opts = ( confirm => 1, non_interactive => 1 );

    eval { $apply->apply_bug_with_dependencies( '1000', \%opts ); };
    my $err = $@;
    like( $err, qr/conflict/, 'Applying the parent bug dies on the dependency conflict' );

    ok( -f "$rebase_apply_dir/git-bz", 'git-bz state file was saved on failure' );

    # Simulate the user resolving the conflict and continuing.
    $apply->handle_git_am_state( { continue => 1 } );

    ok( ( grep { /-1001\.patch$/ } @am_calls ), 'Parent bug patch (1001) was applied after --continue' )
        or diag( explain \@am_calls );

    ok( ( grep { $_ eq '1000' } @GitBz::Commands::Apply::bugs_applied ),
        'Parent bug 1000 is tracked as applied after resuming' );
};

done_testing();
