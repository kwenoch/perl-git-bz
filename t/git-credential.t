#!/usr/bin/perl

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
use Test::Exception;
use Test::Warn;

use_ok('GitBz::Commands');
use_ok('GitBz::Git');

# Mock GitBz::Git to avoid actual git calls
my $git_mock = Test::MockModule->new('GitBz::Git');

subtest 'git credential retrieval' => sub {
    plan tests => 4;
    
    # Mock successful credential retrieval
    $git_mock->mock('run_with_input', sub {
        my ($class, $input, $command, @args) = @_;
        
        is($command, 'credential', 'calls git credential');
        is($args[0], 'fill', 'uses fill command');
        like($input, qr/protocol=https/, 'includes protocol');
        
        return "username=test\@example.com\npassword=secret123\n";
    });
    
    my ($username, $password) = GitBz::Commands->_get_git_credentials(
        'bugs.koha-community.org',
        { https => 1, path => '/bugzilla3' }
    );
    
    is($username, 'test@example.com', 'extracts username correctly');
};

subtest 'git credential approval' => sub {
    plan tests => 3;
    
    $git_mock->mock('run_with_input', sub {
        my ($class, $input, $command, @args) = @_;
        
        is($command, 'credential', 'calls git credential');
        is($args[0], 'approve', 'uses approve command');
        like($input, qr/username=test\@example\.com/, 'includes username in approval');
        
        return '';
    });
    
    GitBz::Commands->_approve_git_credential({
        tracker => 'bugs.koha-community.org',
        tracker_config => { https => 1, path => '/bugzilla3' },
        username => 'test@example.com',
        password => 'secret123'
    });
};

subtest 'git credential rejection' => sub {
    plan tests => 3;
    
    $git_mock->mock('run_with_input', sub {
        my ($class, $input, $command, @args) = @_;
        
        is($command, 'credential', 'calls git credential');
        is($args[0], 'reject', 'uses reject command');
        like($input, qr/username=test\@example\.com/, 'includes username in rejection');
        
        return '';
    });
    
    GitBz::Commands->_reject_git_credential({
        tracker => 'bugs.koha-community.org',
        tracker_config => { https => 1, path => '/bugzilla3' },
        username => 'test@example.com',
        password => 'secret123'
    });
};

subtest 'credential input formatting' => sub {
    plan tests => 1;
    
    $git_mock->mock('run_with_input', sub {
        my ($class, $input, $command, @args) = @_;
        
        # The input should be: protocol=https\nhost=bugs.koha-community.org\npath=bugzilla3\n\n
        # When split on \n, this gives us the lines plus one empty string at the end
        my @lines = split /\n/, $input, -1; # -1 to preserve trailing empty strings
        is_deeply(\@lines, [
            'protocol=https',
            'host=bugs.koha-community.org',
            'path=bugzilla3',
            '',
            ''
        ], 'formats credential input correctly');
        
        return "username=test\npassword=pass\n";
    });
    
    GitBz::Commands->_get_git_credentials(
        'bugs.koha-community.org',
        { https => 1, path => '/bugzilla3' }
    );
};

subtest 'credential error handling' => sub {
    plan tests => 3;
    
    # Mock git credential failure
    $git_mock->mock('run_with_input', sub {
        die "git credential failed";
    });
    
    my ($username, $password);
    warning_is {
        ($username, $password) = GitBz::Commands->_get_git_credentials(
            'bugs.koha-community.org',
            { https => 1 }
        );
    } "Failed to get git credentials: git credential failed", 'warns on git credential failure';
    
    is($username, undef, 'returns undef username on error');
    is($password, undef, 'returns undef password on error');
};

subtest 'http vs https protocol handling' => sub {
    plan tests => 2;
    
    $git_mock->mock('run_with_input', sub {
        my ($class, $input, $command, @args) = @_;
        
        if ($input =~ /protocol=http\n/) {
            pass('uses http protocol when https=0');
        } elsif ($input =~ /protocol=https\n/) {
            pass('uses https protocol when https=1');
        }
        
        return "username=test\npassword=pass\n";
    });
    
    # Test HTTP
    GitBz::Commands->_get_git_credentials(
        'bugs.example.org',
        { https => 0 }
    );
    
    # Test HTTPS  
    GitBz::Commands->_get_git_credentials(
        'bugs.example.org',
        { https => 1 }
    );
};

done_testing();
