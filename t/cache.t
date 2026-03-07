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
use File::Temp qw(tempdir);
use File::Spec;
use JSON;
use FindBin;
use lib "$FindBin::RealBin/../lib";

use GitBz::Cache;

# Redirect the cache to a temporary directory for all tests
my $tmpdir = tempdir( CLEANUP => 1 );
local $ENV{XDG_CACHE_HOME} = $tmpdir;

subtest 'set and get a fresh entry' => sub {
    my $data = [ { name => 'Koha', components => ['OPAC'], versions => ['master'] } ];

    GitBz::Cache->set( 'test_key', $data );
    my $result = GitBz::Cache->get('test_key');

    ok( defined $result,             'get returns data for fresh entry' );
    is_deeply( $result, $data,       'returned data matches stored data' );
};

subtest 'get returns undef for missing key' => sub {
    my $result = GitBz::Cache->get('nonexistent_key');
    ok( !defined $result, 'returns undef for missing key' );
};

subtest 'get returns undef for expired entry' => sub {
    my $data = [ { name => 'Expired' } ];

    # Write a cache file with a timestamp in the past (2 weeks ago)
    my $cache_file = GitBz::Cache->_cache_file('expired_key');
    my $old_ts     = time() - ( 14 * 24 * 60 * 60 );
    open my $fh, '>', $cache_file or die "Cannot write: $!";
    print $fh encode_json( { timestamp => $old_ts, data => $data } );
    close $fh;

    my $result = GitBz::Cache->get('expired_key');
    ok( !defined $result, 'returns undef for expired entry' );
};

subtest 'get returns undef for corrupt cache file' => sub {
    my $cache_file = GitBz::Cache->_cache_file('corrupt_key');
    open my $fh, '>', $cache_file or die "Cannot write: $!";
    print $fh "this is not valid JSON {{{";
    close $fh;

    my $result = GitBz::Cache->get('corrupt_key');
    ok( !defined $result, 'returns undef for corrupt JSON' );
};

subtest 'invalidate removes the cache entry' => sub {
    my $data = [ { name => 'ToDelete' } ];

    GitBz::Cache->set( 'delete_me', $data );
    ok( defined GitBz::Cache->get('delete_me'), 'entry exists before invalidate' );

    GitBz::Cache->invalidate('delete_me');
    ok( !defined GitBz::Cache->get('delete_me'), 'entry gone after invalidate' );
};

subtest 'cache key is sanitised for use as filename' => sub {
    my $data = [ { name => 'Test' } ];

    # Key with special characters (like a hostname)
    GitBz::Cache->set( 'products_bugs.example.org', $data );
    my $result = GitBz::Cache->get('products_bugs.example.org');

    ok( defined $result,       'roundtrip works with hostname-like key' );
    is_deeply( $result, $data, 'data intact after roundtrip' );

    # Verify the actual file exists and has a safe name
    my $cache_file = GitBz::Cache->_cache_file('products_bugs.example.org');
    ok( -f $cache_file, 'cache file exists on disk' );
    unlike( $cache_file, qr{[^/\w.-]}, 'cache filename contains only safe characters' );
};

subtest 'set is silent on write errors' => sub {
    # Point cache at a path that cannot be created
    local $ENV{XDG_CACHE_HOME} = '/proc/nonexistent_guaranteed_to_fail';

    lives_ok( sub { GitBz::Cache->set( 'any_key', [1] ) }, 'set does not die on write failure' );
};

done_testing();
