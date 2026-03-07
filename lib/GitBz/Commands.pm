package GitBz::Commands;

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

GitBz::Commands - Command dispatcher for git-bz

=head1 SYNOPSIS

    use GitBz::Commands;
    
    GitBz::Commands->dispatch(@ARGV);

=head1 DESCRIPTION

Handles command-line argument parsing and dispatches to appropriate command handlers.
Manages configuration loading and Bugzilla client initialization.

=cut

use Modern::Perl;

use Try::Tiny qw(catch try);

use GitBz::Exception;
use GitBz::Config;
use GitBz::Credentials;
use GitBz::RestClient;

my %COMMANDS = (
    apply  => 'GitBz::Commands::Apply',
    attach => 'GitBz::Commands::Attach',
    create => 'GitBz::Commands::Create',
    edit   => 'GitBz::Commands::Edit',
    info   => 'GitBz::Commands::Info',
    open   => 'GitBz::Commands::Open',
);

=head2 new

    my $commands = GitBz::Commands->new(%opts);

Creates a new command dispatcher with configuration and REST client.

=cut

sub new {
    my ( $class, %opts ) = @_;

    my $default_tracker = GitBz::Config->get_default_tracker();
    my $tracker         = $opts{bugzilla} || $default_tracker;
    my $tracker_config  = {
        path          => GitBz::Config->get("bz-tracker.$tracker.path"),
        https         => GitBz::Config->get_bool("bz-tracker.$tracker.https"),
        'bz-user'     => GitBz::Config->get("bz-tracker.$tracker.bz-user"),
        'bz-password' => GitBz::Config->get("bz-tracker.$tracker.bz-password"),
    };

    my $client = GitBz::RestClient->new(
        host  => $tracker,
        https => $tracker_config->{https},
        path  => $tracker_config->{path} || '',
    );

    # Get credentials using new Credentials class
    my $credentials = GitBz::Credentials->new(
        tracker        => $tracker,
        tracker_config => $tracker_config
    );
    my ($username, $password, $git_credential_info) = $credentials->get_credentials();

    my $self = bless {
        client      => $client,
        tracker     => $tracker,
        credentials => $credentials,
    }, $class;

    if ( $username && $password ) {
        eval {
            $client->login( $username, $password );

            # Approve git credential on successful login
            if ($git_credential_info) {
                $credentials->approve_git_credential($git_credential_info);
            }
        };
        if ($@) {

            # Reject git credential on failed login
            if ($git_credential_info) {
                $credentials->reject_git_credential($git_credential_info);
            }
            die $@;
        }
    }

    return $self;
}

=head2 _get_git_credentials

    my ($username, $password) = $commands->_get_git_credentials($tracker, $tracker_config);

Uses git credential helper to retrieve credentials for the tracker.

=cut

sub _get_git_credentials {
    my ( $class, $tracker, $tracker_config ) = @_;

    my $protocol = $tracker_config->{https} ? 'https' : 'http';
    my $path     = $tracker_config->{path} || '';
    $path =~ s|^/||;    # Remove leading slash for git credential

    my $input = "protocol=$protocol\n";
    $input .= "host=$tracker\n";
    $input .= "path=$path\n" if $path;
    $input .= "\n";

    my $output;
    eval { $output = GitBz::Git->run_with_input( $input, 'credential', 'fill' ); };

    if ($@) {
        warn "Failed to get git credentials: $@";
        return ( undef, undef );
    }

    my ( $username, $password );
    for my $line ( split /\n/, $output ) {
        if ( $line =~ /^username=(.*)$/ ) {
            $username = $1;
        } elsif ( $line =~ /^password=(.*)$/ ) {
            $password = $1;
        }
    }

    return ( $username, $password );
}

=head2 _approve_git_credential

    GitBz::Commands->_approve_git_credential($credential_info);

Approves the git credential after successful login.

=cut

sub _approve_git_credential {
    my ( $class, $info ) = @_;

    my $protocol = $info->{tracker_config}->{https} ? 'https' : 'http';
    my $path     = $info->{tracker_config}->{path} || '';
    $path =~ s|^/||;

    my $input = "protocol=$protocol\n";
    $input .= "host=$info->{tracker}\n";
    $input .= "path=$path\n" if $path;
    $input .= "username=$info->{username}\n";
    $input .= "password=$info->{password}\n";
    $input .= "\n";

    eval { GitBz::Git->run_with_input( $input, 'credential', 'approve' ); };

    # Ignore errors - credential approval is best effort
}

=head2 _reject_git_credential

    GitBz::Commands->_reject_git_credential($credential_info);

Rejects the git credential after failed login.

=cut

sub _reject_git_credential {
    my ( $class, $info ) = @_;

    my $protocol = $info->{tracker_config}->{https} ? 'https' : 'http';
    my $path     = $info->{tracker_config}->{path} || '';
    $path =~ s|^/||;

    my $input = "protocol=$protocol\n";
    $input .= "host=$info->{tracker}\n";
    $input .= "path=$path\n" if $path;
    $input .= "username=$info->{username}\n";
    $input .= "password=$info->{password}\n";
    $input .= "\n";

    eval { GitBz::Git->run_with_input( $input, 'credential', 'reject' ); };

    # Ignore errors - credential rejection is best effort
}

=head2 dispatch

    GitBz::Commands->dispatch(@args);

Parses command-line arguments and executes the appropriate command.

=cut

sub dispatch {
    my ( $class, @args ) = @_;

    my $command = shift @args || '';

    if ( !$command || !$COMMANDS{$command} ) {
        print STDERR "Usage: git bz [apply|attach|create|edit|info|open] [options]\n";
        exit 1;
    }

    my $handler_class = $COMMANDS{$command};

    return try {
        eval "require $handler_class" or die $@;

        my $commands = $class->new();
        return $handler_class->new($commands)->execute(@args);
    } catch {
        print STDERR "Error: $_";
        exit 1;
    };
}

1;
