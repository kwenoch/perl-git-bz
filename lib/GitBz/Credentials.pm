package GitBz::Credentials;

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

GitBz::Credentials - Credential management for git-bz

=head1 SYNOPSIS

    use GitBz::Credentials;
    
    my $creds = GitBz::Credentials->new(
        tracker => 'bugs.koha-community.org',
        tracker_config => $config
    );
    my ($username, $password) = $creds->get_credentials();

=head1 DESCRIPTION

Handles credential retrieval from multiple sources including environment variables,
git configuration, and git credential system.

=cut

use Modern::Perl;
use GitBz::Config;
use GitBz::Git;

sub new {
    my ($class, %opts) = @_;
    
    return bless {
        tracker        => $opts{tracker},
        tracker_config => $opts{tracker_config},
    }, $class;
}

=head2 get_credentials

    my ($username, $password) = $creds->get_credentials();

Retrieves credentials using the following priority order:
1. Environment variables (BUGZILLA_USER, BUGZILLA_PASSWORD)
2. Git credential system (if use-git-credential is enabled)
3. Git configuration (bz-user, bz-password)

Returns credential info for git credential approval/rejection.

=cut

sub get_credentials {
    my ($self) = @_;
    
    my $tracker = $self->{tracker};
    my $tracker_config = $self->{tracker_config};
    
    # Try environment variables first
    my $username = $ENV{BUGZILLA_USER};
    my $password = $ENV{BUGZILLA_PASSWORD};
    
    return ($username, $password, undef) if $username && $password;
    
    # Check if git-credential should be used
    my $use_git_credential = GitBz::Config->get_bool("bz-tracker.$tracker.use-git-credential");
    
    if ($use_git_credential) {
        my ($git_username, $git_password) = $self->_get_git_credentials();
        
        if ($git_username && $git_password) {
            my $git_credential_info = {
                tracker        => $tracker,
                tracker_config => $tracker_config,
                username       => $git_username,
                password       => $git_password,
            };
            return ($git_username, $git_password, $git_credential_info);
        }
    }
    
    # Fall back to git config
    $username = $tracker_config->{'bz-user'};
    $password = $tracker_config->{'bz-password'};
    
    return ($username, $password, undef);
}

sub _get_git_credentials {
    my ($self) = @_;
    
    my $tracker = $self->{tracker};
    my $tracker_config = $self->{tracker_config};
    
    my $protocol = $tracker_config->{https} ? 'https' : 'http';
    my $path = $tracker_config->{path} || '';
    $path =~ s|^/||; # Remove leading slash for git credential
    
    my $input = "protocol=$protocol\nhost=$tracker\n";
    $input .= "path=$path\n" if $path;
    $input .= "\n";
    
    my $output = GitBz::Git->run_with_input($input, 'credential', 'fill');
    
    my ($username, $password);
    for my $line (split /\n/, $output) {
        if ($line =~ /^username=(.*)$/) {
            $username = $1;
        } elsif ($line =~ /^password=(.*)$/) {
            $password = $1;
        }
    }
    
    return ($username, $password);
}

=head2 approve_git_credential

    $creds->approve_git_credential($git_credential_info);

Approves git credential after successful authentication.

=cut

sub approve_git_credential {
    my ($self, $git_credential_info) = @_;
    
    return unless $git_credential_info;
    
    my $tracker_config = $git_credential_info->{tracker_config};
    my $protocol = $tracker_config->{https} ? 'https' : 'http';
    my $path = $tracker_config->{path} || '';
    $path =~ s|^/||;
    
    my $input = "protocol=$protocol\nhost=$git_credential_info->{tracker}\n";
    $input .= "path=$path\n" if $path;
    $input .= "username=$git_credential_info->{username}\n";
    $input .= "password=$git_credential_info->{password}\n\n";
    
    GitBz::Git->run_with_input($input, 'credential', 'approve');
}

=head2 reject_git_credential

    $creds->reject_git_credential($git_credential_info);

Rejects git credential after failed authentication.

=cut

sub reject_git_credential {
    my ($self, $git_credential_info) = @_;
    
    return unless $git_credential_info;
    
    my $tracker_config = $git_credential_info->{tracker_config};
    my $protocol = $tracker_config->{https} ? 'https' : 'http';
    my $path = $tracker_config->{path} || '';
    $path =~ s|^/||;
    
    my $input = "protocol=$protocol\nhost=$git_credential_info->{tracker}\n";
    $input .= "path=$path\n" if $path;
    $input .= "username=$git_credential_info->{username}\n";
    $input .= "password=$git_credential_info->{password}\n\n";
    
    GitBz::Git->run_with_input($input, 'credential', 'reject');
}

1;
