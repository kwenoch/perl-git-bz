package GitBz::Cache;

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

=head1 NAME

GitBz::Cache - Simple file-based JSON cache with TTL

=head1 SYNOPSIS

    use GitBz::Cache;

    # Store data
    GitBz::Cache->set('products_bugs.example.org', $data);

    # Retrieve if still fresh (returns undef if missing or expired)
    my $data = GitBz::Cache->get('products_bugs.example.org');

    # Remove a cached entry
    GitBz::Cache->invalidate('products_bugs.example.org');

=head1 DESCRIPTION

Stores arbitrary data structures as JSON files under C<~/.cache/git-bz/>.
Each entry is wrapped with a C<timestamp> field. Entries older than C<$TTL>
seconds are treated as expired and return C<undef> from C<get()>.

=cut

use Modern::Perl;

use File::Path qw(make_path);
use File::Spec;
use JSON;

=head1 CONSTANTS

=head2 TTL

Cache entries are considered fresh for one week (604800 seconds).

=cut

our $TTL = 7 * 24 * 60 * 60;

=head2 _cache_dir

Returns the path to the cache directory, respecting C<$XDG_CACHE_HOME>.

=cut

sub _cache_dir {
    my $base = $ENV{XDG_CACHE_HOME} || File::Spec->catdir( $ENV{HOME}, '.cache' );
    return File::Spec->catdir( $base, 'git-bz' );
}

=head2 _cache_file

    my $path = GitBz::Cache->_cache_file($key);

Returns the full path for a cache key. The key is sanitised to be safe as a
filename.

=cut

sub _cache_file {
    my ( $class, $key ) = @_;
    ( my $safe_key = $key ) =~ s/[^\w.-]/_/g;
    return File::Spec->catfile( _cache_dir(), "$safe_key.json" );
}

=head2 get

    my $data = GitBz::Cache->get($key);

Returns the cached data for C<$key> if it exists and is younger than C<$TTL>
seconds. Returns C<undef> if the entry is missing, unreadable, corrupt, or
expired.

=cut

sub get {
    my ( $class, $key ) = @_;

    my $file = $class->_cache_file($key);
    return undef unless -f $file;

    my $content = eval {
        open my $fh, '<', $file or die $!;
        local $/;
        <$fh>;
    };
    return undef unless $content;

    my $cached = eval { decode_json($content) };
    return undef unless $cached && ref $cached eq 'HASH';

    my $age = time() - ( $cached->{timestamp} || 0 );
    return undef if $age > $TTL;

    return $cached->{data};
}

=head2 set

    GitBz::Cache->set($key, $data);

Writes C<$data> to the cache file for C<$key>, tagged with the current
timestamp. Silently ignores write errors (cache is best-effort).

=cut

sub set {
    my ( $class, $key, $data ) = @_;

    my $dir = _cache_dir();
    eval { make_path($dir) };
    return if $@;

    my $file    = $class->_cache_file($key);
    my $content = encode_json( { timestamp => time(), data => $data } );

    eval {
        open my $fh, '>', $file or die $!;
        print $fh $content;
    };
    # Silently ignore write errors — cache is best-effort
}

=head2 invalidate

    GitBz::Cache->invalidate($key);

Removes the cache file for C<$key> if it exists.

=cut

sub invalidate {
    my ( $class, $key ) = @_;
    my $file = $class->_cache_file($key);
    unlink $file if -f $file;
}

1;
