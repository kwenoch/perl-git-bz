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

use Modern::Perl;
use Try::Tiny qw(catch try);
use GitBz::Exception;
use GitBz::Config;
use GitBz::RestClient;

my %COMMANDS = (
    apply  => 'GitBz::Commands::Apply',
    attach => 'GitBz::Commands::Attach',
    edit   => 'GitBz::Commands::Edit',
);

sub new {
    my ( $class, %opts ) = @_;

    my $config         = GitBz::Config->load();
    my $tracker        = $opts{bugzilla}               || $config->{git_config}->{'default-tracker'};
    my $tracker_config = $config->{config}->{$tracker} || {};

    my $client = GitBz::RestClient->new(
        host  => $tracker,
        https => $tracker_config->{https},
        path  => $tracker_config->{path} || '',
    );

    # Auto-login if credentials available
    my $username = $ENV{BUGZILLA_USER};
    my $password = $ENV{BUGZILLA_PASSWORD};

    # Try git config if env vars not set
    if ( !$username || !$password ) {
        my $tracker_section = qq{bz-tracker "$tracker"};
        my $tracker_config  = $config->{config}->{$tracker_section};

        $username ||= $tracker_config->{'bz-user'}     if $tracker_config;
        $password ||= $tracker_config->{'bz-password'} if $tracker_config;
    }

    if ( $username && $password ) {
        $client->login( $username, $password );
    }

    return bless {
        config  => $config,
        client  => $client,
        tracker => $tracker,
    }, $class;
}

sub dispatch {
    my ( $class, @args ) = @_;

    my $command = shift @args || '';

    if ( !$command || !$COMMANDS{$command} ) {
        print STDERR "Usage: git bz [apply|attach|edit] [options]\n";
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
