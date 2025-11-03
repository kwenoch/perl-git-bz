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
use FindBin;
use lib "$FindBin::RealBin/../lib";
use GitBz::Git;
use GitBz::RestClient;
use JSON;
use Encode;
use MIME::Base64 qw(encode_base64 decode_base64);
use Cwd;

# Black-box UTF-8 handling regression tests

my $original_dir = getcwd();
my $test_repo    = "$FindBin::RealBin/data/git_repo";

subtest 'GitBz::Git format_patch preserves UTF-8' => sub {
    chdir $test_repo or die "Cannot chdir to $test_repo: $!";

    # Test GitBz::Git->format_patch() method directly
    my $patch_output = GitBz::Git->format_patch( '--root', 'HEAD' );

    # Should contain proper UTF-8 characters (will FAIL with buggy code)
    like( $patch_output, qr/ç/,     'Patch contains UTF-8 character ç' );
    like( $patch_output, qr/á/,     'Patch contains UTF-8 character á' );
    like( $patch_output, qr/✔/,     'Patch contains UTF-8 character ✔' );
    like( $patch_output, qr/❤/,     'Patch contains UTF-8 character ❤' );
    like( $patch_output, qr/★/,     'Patch contains UTF-8 character ★' );
    like( $patch_output, qr/Tomás/, 'Patch contains author name with UTF-8' );

    chdir $original_dir;
};

subtest 'RestClient _create_attachment_payload handles UTF-8 comments correctly' => sub {

    # Create RestClient instance
    my $client = GitBz::RestClient->new( https => 1, host => 'https://example.com' );

    # Test comment with UTF-8 characters as would come from GitBz::Git
    my $utf8_comment = "Comment with UTF-8: ç á ✔";

    # Test the internal payload creation method
    my $payload = $client->_create_attachment_payload(
        123, "patch data", "test.patch", "Test patch",
        comment => $utf8_comment
    );

    my $json_payload = encode_json($payload);

    # Should contain proper UTF-8, not double-encoded (will FAIL with buggy code)
    like( $json_payload, qr/"comment":"[^"]*ç[^"]*"/, 'Comment contains proper UTF-8 ç' );
    like( $json_payload, qr/"comment":"[^"]*á[^"]*"/, 'Comment contains proper UTF-8 á' );
    unlike( $json_payload, qr/Ã§/, 'Comment does not contain double-encoded ç' );
    unlike( $json_payload, qr/Ã¡/, 'Comment does not contain double-encoded á' );
};

subtest 'RestClient _create_attachment_payload preserves patch data encoding' => sub {
    # Create RestClient instance  
    my $client = GitBz::RestClient->new( https => 1, host => 'https://example.com' );
    
    # Test patch data with UTF-8 characters as would come from GitBz::Git->format_patch()
    my $patch_data = "From: Author\nSubject: Test\n\nCommit message with ç\n\n+Added line with ç";
    
    # Test the internal payload creation method
    my $payload = $client->_create_attachment_payload(
        123, $patch_data, "test.patch", "Test patch"
    );
    
    # Decode the base64 data to check it wasn't double-encoded
    my $decoded_data = decode_base64($payload->{data});
    
    # Should preserve original UTF-8 encoding (will FAIL if double-encoded)
    is($decoded_data, $patch_data, 'Patch data is preserved without double-encoding');
    like($decoded_data, qr/ç/, 'Patch data contains UTF-8 character ç');
};

done_testing();
