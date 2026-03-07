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
use JSON;
use FindBin;
use lib "$FindBin::RealBin/../../lib";

use GitBz::Commands::Create;

# Build a minimal mock commands object
sub _mock_commands {
    my ($client) = @_;
    return { client => $client };
}

# Build a mock client
{
    package MockClient;
    sub new { bless {}, shift }
    sub search_bugs  { [] }
    sub create_bug   { { id => 99999 } }
    sub get_bug_url  { "https://bugs.example.org/show_bug.cgi?id=$_[1]" }
}

my $mock_client = MockClient->new();

subtest 'constructor' => sub {
    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );
    isa_ok( $create, 'GitBz::Commands::Create', 'Create command constructed' );
    is( $create->{client}, $mock_client, 'client stored' );
};

subtest 'dry-run: no duplicates, all fields provided' => sub {
    my $mock_git = Test::MockModule->new('GitBz::Git');
    $mock_git->mock( 'run', sub { return "main\n" } );

    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock( 'search_bugs', sub { return [] } );

    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    my $output = '';
    open my $fh, '>', \$output;
    local *STDOUT = $fh;

    $create->execute(
        '--summary', 'Test bug title',
        '--desc',    'Some description',
        '--product', 'Koha',
        '--comp',    'OPAC',
        '--version', 'master',
        '--dry-run',

    );
    close $fh;

    like( $output, qr/Potential duplicates:\s*\(none\)/s, 'reports no duplicates' );
    like( $output, qr/Missing fields:\s*\(none\)/s,       'reports no missing fields' );
};

subtest 'dry-run: duplicates found' => sub {
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock(
        'search_bugs',
        sub {
            return [
                { id => 12345, summary => 'Similar bug', status => 'NEW' },
            ];
        }
    );

    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    my $output = '';
    open my $fh, '>', \$output;
    local *STDOUT = $fh;

    $create->execute(
        '--summary', 'Similar bug title',
        '--desc',    'Description',
        '--product', 'Koha',
        '--comp',    'OPAC',
        '--version', 'master',
        '--dry-run',

    );
    close $fh;

    like( $output, qr/Bug 12345 - Similar bug \[NEW\]/, 'shows duplicate bug' );
};

subtest 'dry-run: missing fields reported' => sub {
    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    my $output = '';
    open my $fh, '>', \$output;
    local *STDOUT = $fh;

    $create->execute(
        '--summary', 'Some title',
        '--dry-run',

    );
    close $fh;

    like( $output, qr/Missing fields:.*desc/,    'reports missing desc' );
    like( $output, qr/Missing fields:.*product/i, 'reports missing product' );
    like( $output, qr/Missing fields:.*comp/i,    'reports missing comp' );
    like( $output, qr/Missing fields:.*version/i, 'reports missing version' );
};

subtest 'dry-run JSON output' => sub {
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock(
        'search_bugs',
        sub {
            return [
                { id => 42, summary => 'Duplicate', status => 'ASSIGNED' },
            ];
        }
    );

    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    my $output = '';
    open my $fh, '>', \$output;
    local *STDOUT = $fh;

    $create->execute(
        '--summary', 'Duplicate',
        '--dry-run',
        '--json',

    );
    close $fh;

    my $data = eval { decode_json($output) };
    ok( !$@,                                   'output is valid JSON' );
    ok( exists $data->{duplicates},            'JSON has duplicates key' );
    ok( exists $data->{missing_fields},        'JSON has missing_fields key' );
    is( $data->{duplicates}[0]{id}, 42,        'duplicate id correct' );
    is( $data->{duplicates}[0]{status}, 'ASSIGNED', 'duplicate status correct' );
};

subtest 'non-interactive mode throws on missing fields' => sub {
    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    dies_ok(
        sub {
            $create->execute(
                '--summary',         'Title',
                '--non-interactive',
        
            );
        },
        'throws on missing required fields'
    );

    like( $@, qr/Missing required fields/, 'error message mentions missing fields' );
};

subtest 'non-interactive JSON mode: missing fields outputs JSON before throwing' => sub {
    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    my $output = '';
    open my $fh, '>', \$output;
    local *STDOUT = $fh;

    eval {
        $create->execute(
            '--summary',         'Title',
            '--non-interactive',
    
            '--json',
        );
    };
    close $fh;

    my $data = eval { decode_json($output) };
    ok( !$@,                     'output is valid JSON' );
    is( $data->{status}, 'error', 'status is error' );
    like( $data->{message}, qr/Missing required fields/, 'error message in JSON' );
};

subtest '_edit_description: opens editor and returns stripped content' => sub {
    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    my $mock_create = Test::MockModule->new('GitBz::Commands::Create');
    $mock_create->mock(
        '_run_editor',
        sub {
            my ( $self, $filename ) = @_;
            open my $fh, '>', $filename or die $!;
            print $fh "# This line is a comment and should be removed\n";
            print $fh "\n";
            print $fh "First line of the description.\n";
            print $fh "Second line of the description.\n";
            close $fh;
        }
    );

    my $desc = $create->_edit_description('My bug summary');

    is( $desc, "First line of the description.\nSecond line of the description.", 'multiline description returned, comments stripped' );
};

subtest '_edit_description: template includes summary as a comment' => sub {
    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    my $template_content;
    my $mock_create = Test::MockModule->new('GitBz::Commands::Create');
    $mock_create->mock(
        '_run_editor',
        sub {
            my ( $self, $filename ) = @_;
            open my $fh, '<', $filename or die $!;
            $template_content = do { local $/; <$fh> };
            # Write something so the description is not empty
            open my $out, '>', $filename or die $!;
            print $out "Some description.\n";
        }
    );

    $create->_edit_description('The bug summary');

    like( $template_content, qr/The bug summary/, 'summary shown in editor template' );
    like( $template_content, qr/^#/m,             'template lines are commented out' );
};

subtest '_edit_description: throws when user saves empty file' => sub {
    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    my $mock_create = Test::MockModule->new('GitBz::Commands::Create');
    $mock_create->mock(
        '_run_editor',
        sub {
            my ( $self, $filename ) = @_;
            open my $fh, '>', $filename or die $!;
            print $fh "# Only a comment — effectively empty\n";
        }
    );

    dies_ok( sub { $create->_edit_description('My bug') }, 'throws on empty description' );
    like( $@, qr/Description is required/, 'error mentions description is required' );
};

subtest 'interactive: numbered pick-lists for product/component/version' => sub {
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock(
        'get_products',
        sub {
            return [
                {
                    name       => 'Koha',
                    components => [ 'OPAC', 'Staff interface', 'Acquisitions' ],
                    versions   => [ 'master', '23.11', '23.05' ],
                },
                { name => 'Koha Plugin', components => ['General'], versions => ['master'] },
            ];
        }
    );
    $mock_client_module->mock( 'create_bug', sub { { id => 1 } } );
    $mock_client_module->mock( 'get_bug_url', sub { "https://bugs.example.org/show_bug.cgi?id=1" } );

    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock( 'with_spinner', sub { my ( $msg, $code, $level ) = @_; return $code->() } );
    $mock_progress->mock( 'print_success', sub { } );

    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    # Simulate user input: product 1 (Koha), component 2 (Staff interface), version 1 (master),
    # skip severity (Enter), skip depends (Enter), skip blocks (Enter)
    my $stdin_input = "1\n2\n1\n\n\n\n";
    open my $fake_stdin, '<', \$stdin_input;
    local *STDIN = $fake_stdin;

    my %captured_params;
    $mock_client_module->mock(
        'create_bug',
        sub {
            my ( $self, %params ) = @_;
            %captured_params = %params;
            return { id => 1 };
        }
    );

    my $output = '';
    open my $fh, '>', \$output;
    local *STDOUT = $fh;

    $create->execute(
        '--summary', 'A bug',
        '--desc',    'Some description',
        '--yes',
    );
    close $fh;

    is( $captured_params{product},   'Koha',            'product selected by number' );
    is( $captured_params{component}, 'Staff interface',  'component selected by number' );
    is( $captured_params{version},   'master',           'version selected by number' );

    like( $output, qr/Select product:/,   'shows product selection prompt' );
    like( $output, qr/Select component:/, 'shows component selection prompt' );
    like( $output, qr/Select version:/,   'shows version selection prompt' );
    like( $output, qr/Koha\b/,            'lists Koha as a product option' );
    like( $output, qr/Staff interface/,   'lists Staff interface as a component option' );
};

subtest 'interactive: falls back to plain text when no product data' => sub {
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock( 'get_products', sub { [] } );
    $mock_client_module->mock( 'get_bug_url',  sub { "https://bugs.example.org/show_bug.cgi?id=1" } );

    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock( 'with_spinner', sub { my ( $msg, $code, $level ) = @_; return $code->() } );
    $mock_progress->mock( 'print_success', sub { } );

    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    # Plain text input for product, component, version; skip severity/depends/blocks
    my $stdin_input = "MyProduct\nMyComponent\n1.0\n\n\n\n";
    open my $fake_stdin, '<', \$stdin_input;
    local *STDIN = $fake_stdin;

    my %captured_params;
    $mock_client_module->mock(
        'create_bug',
        sub {
            my ( $self, %params ) = @_;
            %captured_params = %params;
            return { id => 1 };
        }
    );

    my $output = '';
    open my $fh, '>', \$output;
    local *STDOUT = $fh;

    $create->execute(
        '--summary', 'A bug',
        '--desc',    'Some description',
        '--yes',
    );
    close $fh;

    is( $captured_params{product},   'MyProduct',   'product accepted as free text' );
    is( $captured_params{component}, 'MyComponent', 'component accepted as free text' );
    is( $captured_params{version},   '1.0',         'version accepted as free text' );

    like( $output, qr/Enter product:/,   'shows plain product prompt' );
    like( $output, qr/Enter component:/, 'shows plain component prompt' );
    like( $output, qr/Enter version:/,   'shows plain version prompt' );
};

subtest 'interactive: severity pick-list by number' => sub {
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock( 'get_products', sub { [] } );
    $mock_client_module->mock( 'get_bug_url',  sub { "https://bugs.example.org/show_bug.cgi?id=1" } );

    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock( 'with_spinner', sub { my ( $msg, $code, $level ) = @_; return $code->() } );
    $mock_progress->mock( 'print_success', sub { } );

    my %captured;
    $mock_client_module->mock( 'create_bug', sub { my ( $self, %p ) = @_; %captured = %p; { id => 1 } } );

    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    # product, component, version as text; pick severity 4 (normal); skip depends/blocks
    my $stdin_input = "Koha\nOPAC\nmaster\n4\n\n\n";
    open my $fake_stdin, '<', \$stdin_input;
    local *STDIN = $fake_stdin;

    my $mock_create = Test::MockModule->new('GitBz::Commands::Create');
    $mock_create->mock( '_run_editor', sub { my ( $self, $f ) = @_; open my $fh, '>', $f or die; print $fh "Desc.\n" } );

    open my $fh, '>', \my $out;
    local *STDOUT = $fh;
    $create->execute( '--summary', 'A bug', '--yes' );
    close $fh;

    is( $captured{severity}, 'normal', 'severity "normal" selected by number 4' );
    like( $out, qr/Select severity:/, 'severity pick-list shown' );
};

subtest 'interactive: severity by name' => sub {
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock( 'get_products', sub { [] } );
    $mock_client_module->mock( 'get_bug_url',  sub { "https://bugs.example.org/show_bug.cgi?id=1" } );

    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock( 'with_spinner', sub { my ( $msg, $code, $level ) = @_; return $code->() } );
    $mock_progress->mock( 'print_success', sub { } );

    my %captured;
    $mock_client_module->mock( 'create_bug', sub { my ( $self, %p ) = @_; %captured = %p; { id => 1 } } );

    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    # Enter severity as text "critical"
    my $stdin_input = "Koha\nOPAC\nmaster\ncritical\n\n\n";
    open my $fake_stdin, '<', \$stdin_input;
    local *STDIN = $fake_stdin;

    my $mock_create = Test::MockModule->new('GitBz::Commands::Create');
    $mock_create->mock( '_run_editor', sub { my ( $self, $f ) = @_; open my $fh, '>', $f or die; print $fh "Desc.\n" } );

    open my $fh, '>', \my $out;
    local *STDOUT = $fh;
    $create->execute( '--summary', 'A bug', '--yes' );
    close $fh;

    is( $captured{severity}, 'critical', 'severity accepted as free text' );
};

subtest 'interactive: skip severity leaves it unset' => sub {
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock( 'get_products', sub { [] } );
    $mock_client_module->mock( 'get_bug_url',  sub { "https://bugs.example.org/show_bug.cgi?id=1" } );

    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock( 'with_spinner', sub { my ( $msg, $code, $level ) = @_; return $code->() } );
    $mock_progress->mock( 'print_success', sub { } );

    my %captured;
    $mock_client_module->mock( 'create_bug', sub { my ( $self, %p ) = @_; %captured = %p; { id => 1 } } );

    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    my $stdin_input = "Koha\nOPAC\nmaster\n\n\n\n";  # Enter skips severity
    open my $fake_stdin, '<', \$stdin_input;
    local *STDIN = $fake_stdin;

    my $mock_create = Test::MockModule->new('GitBz::Commands::Create');
    $mock_create->mock( '_run_editor', sub { my ( $self, $f ) = @_; open my $fh, '>', $f or die; print $fh "Desc.\n" } );

    open my $fh, '>', \my $out;
    local *STDOUT = $fh;
    $create->execute( '--summary', 'A bug', '--yes' );
    close $fh;

    ok( !exists $captured{severity}, 'severity not passed to create_bug when skipped' );
};

subtest '--severity / --depends / --blocks flags passed to create_bug' => sub {
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock( 'get_bug_url', sub { "https://bugs.example.org/show_bug.cgi?id=1" } );

    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock( 'with_spinner', sub { my ( $msg, $code, $level ) = @_; return $code->() } );
    $mock_progress->mock( 'print_success', sub { } );

    my %captured;
    $mock_client_module->mock( 'create_bug', sub { my ( $self, %p ) = @_; %captured = %p; { id => 1 } } );

    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    open my $fh, '>', \my $out;
    local *STDOUT = $fh;
    $create->execute(
        '--summary',  'A bug',
        '--desc',     'Description',
        '--product',  'Koha',
        '--comp',     'OPAC',
        '--version',  'master',
        '--severity', 'major',
        '--depends',  '100, 200',
        '--blocks',   '300',
        '--yes',
    );
    close $fh;

    is( $captured{severity},          'major',         'severity passed correctly' );
    is_deeply( $captured{depends_on}, [ '100', '200' ], 'depends_on parsed as array' );
    is_deeply( $captured{blocks},     ['300'],           'blocks parsed as array' );
};

subtest 'interactive: depends and blocks prompted and passed' => sub {
    my $mock_client_module = Test::MockModule->new( 'MockClient', no_auto => 1 );
    $mock_client_module->mock( 'get_products', sub { [] } );
    $mock_client_module->mock( 'get_bug_url',  sub { "https://bugs.example.org/show_bug.cgi?id=1" } );

    my $mock_progress = Test::MockModule->new('GitBz::Progress');
    $mock_progress->mock( 'with_spinner', sub { my ( $msg, $code, $level ) = @_; return $code->() } );
    $mock_progress->mock( 'print_success', sub { } );

    my %captured;
    $mock_client_module->mock( 'create_bug', sub { my ( $self, %p ) = @_; %captured = %p; { id => 1 } } );

    my $create = GitBz::Commands::Create->new( _mock_commands($mock_client) );

    # product, component, version as text; skip severity; depends = "111,222"; blocks = "333"
    my $stdin_input = "Koha\nOPAC\nmaster\n\n111,222\n333\n";
    open my $fake_stdin, '<', \$stdin_input;
    local *STDIN = $fake_stdin;

    my $mock_create = Test::MockModule->new('GitBz::Commands::Create');
    $mock_create->mock( '_run_editor', sub { my ( $self, $f ) = @_; open my $fh, '>', $f or die; print $fh "Desc.\n" } );

    open my $fh, '>', \my $out;
    local *STDOUT = $fh;
    $create->execute( '--summary', 'A bug', '--yes' );
    close $fh;

    is_deeply( $captured{depends_on}, [ '111', '222' ], 'depends_on from interactive prompt' );
    is_deeply( $captured{blocks},     ['333'],           'blocks from interactive prompt' );
    like( $out, qr/depends on/i, 'depends-on prompt shown' );
    like( $out, qr/blocks/i,     'blocks prompt shown' );
};

done_testing();
