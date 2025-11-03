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
use Test::Exception;

use_ok('GitBz::Commands');
use_ok('GitBz::Config');
use_ok('GitBz::RestClient');

# Mock dependencies
my $config_mock = Test::MockModule->new('GitBz::Config');
my $client_mock = Test::MockModule->new('GitBz::RestClient');
my $git_mock = Test::MockModule->new('GitBz::Git');

subtest 'git-credential integration workflow' => sub {
    plan tests => 6;
    
    # Mock config with git-credential enabled
    $config_mock->mock('load', sub {
        return {
            config => {
                'bz-tracker "bugs.koha-community.org"' => {
                    'use-git-credential' => 'true',
                    https => 1,
                    path => '/bugzilla3'
                }
            },
            git_config => {
                'default-tracker' => 'bugs.koha-community.org'
            }
        };
    });
    
    # Mock successful credential retrieval
    $git_mock->mock('run_with_input', sub {
        my ($class, $input, $command, @args) = @_;
        
        if ($args[0] eq 'fill') {
            return "username=test\@example.com\npassword=secret123\n";
        } elsif ($args[0] eq 'approve') {
            pass('approves credential on successful login');
            return '';
        } elsif ($args[0] eq 'reject') {
            fail('should not reject on successful login');
            return '';
        }
    });
    
    # Mock successful client login
    $client_mock->mock('new', sub {
        my ($class, %params) = @_;
        my $client = bless {}, 'GitBz::RestClient';
        return $client;
    });
    
    $client_mock->mock('login', sub {
        my ($self, $username, $password) = @_;
        is($username, 'test@example.com', 'uses credential username');
        is($password, 'secret123', 'uses credential password');
        pass('login called with git credentials');
        return 1; # successful login
    });
    
    # Test the full workflow
    my $commands = GitBz::Commands->new(bugzilla => 'bugs.koha-community.org');
    
    isa_ok($commands, 'GitBz::Commands', 'creates commands object');
    is($commands->{tracker}, 'bugs.koha-community.org', 'sets correct tracker');
};

subtest 'git-credential failure and rejection' => sub {
    plan tests => 3;
    
    # Mock config with git-credential enabled
    $config_mock->mock('load', sub {
        return {
            config => {
                'bz-tracker "bugs.koha-community.org"' => {
                    'use-git-credential' => 'true',
                    https => 1
                }
            },
            git_config => {
                'default-tracker' => 'bugs.koha-community.org'
            }
        };
    });
    
    # Mock credential retrieval and rejection
    $git_mock->mock('run_with_input', sub {
        my ($class, $input, $command, @args) = @_;
        
        if ($args[0] eq 'fill') {
            return "username=bad\@example.com\npassword=wrongpass\n";
        } elsif ($args[0] eq 'reject') {
            pass('rejects credential on failed login');
            return '';
        } elsif ($args[0] eq 'approve') {
            fail('should not approve on failed login');
            return '';
        }
    });
    
    # Mock RestClient constructor for failure test
    $client_mock->mock('new', sub {
        my ($class, %params) = @_;
        my $client = bless {}, 'GitBz::RestClient';
        return $client;
    });
    
    # Mock failed client login
    $client_mock->mock('login', sub {
        my ($self, $username, $password) = @_;
        is($username, 'bad@example.com', 'attempts login with bad credentials');
        die "Login failed: Invalid credentials";
    });
    
    # Test failure workflow
    throws_ok {
        GitBz::Commands->new(bugzilla => 'bugs.koha-community.org');
    } qr/Login failed|Died/, 'throws exception on login failure';
};

subtest 'fallback to stored credentials when git-credential disabled' => sub {
    plan tests => 2;
    
    # Mock config without git-credential
    $config_mock->mock('load', sub {
        return {
            config => {
                'bz-tracker "bugs.koha-community.org"' => {
                    'bz-user' => 'stored@example.com',
                    'bz-password' => 'storedpass',
                    https => 1
                }
            },
            git_config => {
                'default-tracker' => 'bugs.koha-community.org'
            }
        };
    });
    
    # Mock RestClient constructor for fallback test
    $client_mock->mock('new', sub {
        my ($class, %params) = @_;
        my $client = bless {}, 'GitBz::RestClient';
        return $client;
    });
    
    # Mock successful login with stored credentials
    $client_mock->mock('login', sub {
        my ($self, $username, $password) = @_;
        is($username, 'stored@example.com', 'uses stored username');
        is($password, 'storedpass', 'uses stored password');
        return 1;
    });
    
    # Should not call git credential at all
    $git_mock->mock('run_with_input', sub {
        fail('should not call git credential when disabled');
    });
    
    my $commands = GitBz::Commands->new(bugzilla => 'bugs.koha-community.org');
};

done_testing();
