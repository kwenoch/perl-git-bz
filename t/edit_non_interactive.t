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
use FindBin qw($RealBin);
use lib "$RealBin/../lib";

use GitBz::Commands::Edit;

my $edit = GitBz::Commands::Edit->new( {} );

subtest 'build_non_interactive_content - throws with no options' => sub {
    plan tests => 1;
    my $err = do {
        local $@;
        eval { $edit->build_non_interactive_content( {} ) };
        $@;
    };
    like( $err, qr/--non-interactive requires at least one field option/,
        'Throws when no field options provided' );
};

subtest 'build_non_interactive_content - status only' => sub {
    plan tests => 2;
    my $content = $edit->build_non_interactive_content( { status => 'ASSIGNED' } );
    like( $content, qr/^Status: ASSIGNED$/m, 'Includes Status line' );
    unlike( $content, qr/^#/m,              'No comment lines in output' );
};

subtest 'build_non_interactive_content - comment only' => sub {
    plan tests => 1;
    my $content = $edit->build_non_interactive_content( { comment => 'Taking this one.' } );
    like( $content, qr/Taking this one\./, 'Includes comment text' );
};

subtest 'build_non_interactive_content - comment does not appear as field line' => sub {
    plan tests => 1;
    my $content = $edit->build_non_interactive_content( { comment => 'Hello world' } );
    unlike( $content, qr/^Status:/m, 'No stray Status line from comment' );
};

subtest 'build_non_interactive_content - all fields together' => sub {
    plan tests => 8;
    my $content = $edit->build_non_interactive_content(
        {
            status           => 'Needs Signoff',
            comment          => 'Ready for QA.',
            patch_complexity => 'Small patch',
            sponsorship      => 'Sponsored',
            sponsors         => [ 'ACME Corp', 'ByWater Solutions' ],
            depends          => [ '11111', '22222' ],
            assignee         => 'dev@example.com',
            qa_contact       => 'qa@example.com',
            obsoletes        => [42],
        }
    );

    like( $content, qr/^Status: Needs Signoff$/m,        'Status line' );
    like( $content, qr/^Patch-complexity: Small patch$/m, 'Patch-complexity line' );
    like( $content, qr/^Sponsorship: Sponsored$/m,        'Sponsorship line' );
    like( $content, qr/^Sponsors: ACME Corp$/m,           'First sponsor line' );
    like( $content, qr/^Sponsors: ByWater Solutions$/m,   'Second sponsor line' );
    like( $content, qr/^Depends: bug 11111$/m,            'First depends line' );
    like( $content, qr/^Obsoletes: 42$/m,                 'Obsoletes line' );
    like( $content, qr/Ready for QA\./,                   'Comment text' );
};

subtest 'build_non_interactive_content - qa_contact empty string allowed' => sub {
    plan tests => 1;
    my $content = $edit->build_non_interactive_content( { qa_contact => '' } );
    like( $content, qr/^QA-contact:\s*$/m,
        'Empty QA-contact line present (clears field)' );
};

subtest 'build_non_interactive_content - depends formatted as bug N' => sub {
    plan tests => 1;
    my $content = $edit->build_non_interactive_content( { depends => ['99999'] } );
    like( $content, qr/^Depends: bug 99999$/m, 'Depends line has "bug" prefix' );
};

subtest 'build_non_interactive_content - comment follows field lines' => sub {
    plan tests => 2;
    my $content = $edit->build_non_interactive_content(
        { status => 'RESOLVED', comment => 'Fixed in commit abc.' }
    );
    my $status_pos  = index( $content, "Status: RESOLVED" );
    my $comment_pos = index( $content, "Fixed in commit abc." );
    ok( $status_pos >= 0,           'Status line present' );
    ok( $status_pos < $comment_pos, 'Status line precedes comment' );
};

done_testing();
