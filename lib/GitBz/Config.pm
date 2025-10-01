package GitBz::Config;

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
use Config::Tiny;
use File::HomeDir;
use GitBz::Git;

my $DEFAULT_CONFIG = {
    'bugs.koha-community.org' => {
        https              => 1,
        'default-priority' => 'Normal',
        'default-product'  => 'Koha',
        path               => '/bugzilla3',
    },
};

my $GIT_CONFIG = {
    'default-tracker' => 'bugs.koha-community.org',
    'add-url'         => 'true',
    'browser'         => 'firefox',
};

sub load {
    my ($class) = @_;

    my $config_file = File::HomeDir->my_home . '/.gitconfig';
    my $config      = -f $config_file ? Config::Tiny->read($config_file) : {};

    # Load git config
    my $git_config = {};
    eval {
        my $git_output = GitBz::Git->run( 'config', '--get-regexp', '^bz\.' );
        for my $line ( split /\n/, $git_output ) {
            if ( $line =~ /^bz\.(\S+)\s+(.*)/ ) {
                $git_config->{$1} = $2;
            }
        }
    };

    # Merge configs
    my $merged = { %$GIT_CONFIG, %$git_config };

    # Merge tracker defaults
    for my $tracker ( keys %$DEFAULT_CONFIG ) {
        $config->{$tracker} //= {};
        %{ $config->{$tracker} } = ( %{ $DEFAULT_CONFIG->{$tracker} }, %{ $config->{$tracker} } );
    }

    return { config => $config, git_config => $merged };
}

1;
