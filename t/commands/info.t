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
use File::Temp qw(tempdir);
use JSON;
use FindBin;
use lib "$FindBin::RealBin/../../lib";

use GitBz::Commands::Info;
use GitBz::Cache;

# Use a temporary directory for all cache operations in these tests
my $tmpdir = tempdir( CLEANUP => 1 );
local $ENV{XDG_CACHE_HOME} = $tmpdir;

{
    package MockClient;
    sub new { bless {}, shift }
    sub get_products {
        return [
            {
                name       => 'Koha',
                components => [ 'OPAC', 'Staff interface', 'Architecture, internals' ],
                versions   => [ 'master', '22.11', '22.05' ],
            },
        ];
    }
}

my $mock_client = MockClient->new();

sub _mock_commands {
    return { client => $mock_client };
}

subtest 'constructor' => sub {
    my $info = GitBz::Commands::Info->new( _mock_commands() );
    isa_ok( $info, 'GitBz::Commands::Info', 'Info command constructed' );
    is( $info->{client}, $mock_client, 'client stored' );
};

subtest '--fields outputs valid JSON with products' => sub {
    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock( 'with_spinner', sub { my ( $msg, $code, $level ) = @_; return $code->() } );

    my $info = GitBz::Commands::Info->new( _mock_commands() );

    my $output = '';
    open my $fh, '>', \$output;
    local *STDOUT = $fh;

    $info->execute('--fields');
    close $fh;

    my $data = eval { decode_json($output) };
    ok( !$@,                         'output is valid JSON' );
    ok( exists $data->{products},    'JSON has products key' );
    is( scalar @{ $data->{products} }, 1, 'one product returned' );

    my $product = $data->{products}[0];
    is( $product->{name}, 'Koha', 'product name correct' );
    is_deeply(
        $product->{components},
        [ 'OPAC', 'Staff interface', 'Architecture, internals' ],
        'components correct'
    );
    is_deeply(
        $product->{versions},
        [ 'master', '22.11', '22.05' ],
        'versions correct'
    );
};

subtest 'no flags prints usage including --refresh' => sub {
    my $info = GitBz::Commands::Info->new( _mock_commands() );

    my $output = '';
    open my $fh, '>', \$output;
    local *STDOUT = $fh;

    $info->execute();
    close $fh;

    like( $output, qr/--fields/,  'usage mentions --fields' );
    like( $output, qr/--refresh/, 'usage mentions --refresh' );
};

subtest '--fields calls get_products without force_refresh' => sub {
    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock( 'with_spinner', sub { my ( $msg, $code, $level ) = @_; return $code->() } );

    my $captured_opts;
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock(
        'get_products',
        sub {
            my ( $self, %opts ) = @_;
            $captured_opts = \%opts;
            return [ { name => 'Koha', components => ['OPAC'], versions => ['master'] } ];
        }
    );

    my $info = GitBz::Commands::Info->new( _mock_commands() );
    open my $fh, '>', \my $out;
    local *STDOUT = $fh;
    $info->execute('--fields');
    close $fh;

    ok( !$captured_opts->{force_refresh}, 'force_refresh not set for normal --fields' );
};

subtest '--refresh passes force_refresh => 1 to get_products' => sub {
    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock( 'with_spinner', sub { my ( $msg, $code, $level ) = @_; return $code->() } );

    my $captured_opts;
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock(
        'get_products',
        sub {
            my ( $self, %opts ) = @_;
            $captured_opts = \%opts;
            return [ { name => 'Koha', components => ['OPAC'], versions => ['master'] } ];
        }
    );

    my $info = GitBz::Commands::Info->new( _mock_commands() );
    open my $fh, '>', \my $out;
    local *STDOUT = $fh;
    $info->execute('--fields', '--refresh');
    close $fh;

    ok( $captured_opts->{force_refresh}, '--refresh passes force_refresh => 1' );
    my $data = decode_json($out);
    is( $data->{products}[0]{name}, 'Koha', 'data still returned correctly with --refresh' );
};

done_testing();
