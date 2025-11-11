package GitBz::Commands::Open;

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

use GitBz::Exception;

=head1 NAME

GitBz::Commands::Open - Open bug in browser

=head1 SYNOPSIS

    git bz open 12345

=cut

sub new {
    my ( $class, $commands ) = @_;
    bless { commands => $commands }, $class;
}

sub execute {
    my ( $self, @args ) = @_;

    my $bug_ref = $args[0] or GitBz::Exception->throw("Bug number required");
    
    my $client = $self->{commands}->{client};
    my $bug_url = $client->get_bug_url($bug_ref);
    
    $self->open_url($bug_url);
    
    print "Opened bug $bug_ref in browser\n";
}

sub open_url {
    my ( $self, $url ) = @_;
    
    my $cmd;
    if ( $^O eq 'darwin' ) {        # macOS
        $cmd = 'open';
    } elsif ( $^O eq 'MSWin32' ) {  # Windows
        $cmd = 'start';
    } else {                        # Linux/Unix
        $cmd = 'xdg-open';
    }
    
    system( $cmd, $url ) == 0
        or GitBz::Exception->throw("Failed to open URL: $url");
}

1;
