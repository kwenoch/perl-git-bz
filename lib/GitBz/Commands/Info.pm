package GitBz::Commands::Info;

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

GitBz::Commands::Info - Discover valid Bugzilla field values

=head1 SYNOPSIS

    git bz info --fields
    git bz info --fields --refresh

=head1 DESCRIPTION

Returns valid field values (products, components, versions) as JSON so that
AI agents and scripts can populate C<git bz create> flags without guessing
invalid inputs. Results are cached locally for one week; use C<--refresh> to
force an immediate update.

=cut

use Modern::Perl;

use Getopt::Long qw(GetOptionsFromArray);
use JSON;

use GitBz::Exception;
use GitBz::Progress;

=head2 new

    my $info = GitBz::Commands::Info->new($commands);

Constructor.

=cut

sub new {
    my ( $class, $commands ) = @_;
    bless {
        commands => $commands,
        client   => $commands->{client},
    }, $class;
}

=head2 execute

    $info->execute(@args);

Main entry point for the info command.

=cut

sub execute {
    my ( $self, @args ) = @_;

    my %opts;
    GetOptionsFromArray(
        \@args,
        'fields'   => \$opts{fields},
        'refresh'  => \$opts{refresh},
    ) or GitBz::Exception->throw("Invalid options");

    unless ( $opts{fields} ) {
        print "Usage: git bz info --fields [--refresh]\n";
        print "\nOptions:\n";
        print "  --fields   List valid products, components, and versions as JSON\n";
        print "  --refresh  Bypass the local cache and fetch fresh data from Bugzilla\n";
        return;
    }

    my $client  = $self->{client};
    my $spinner_msg = $opts{refresh} ? "Refreshing products cache" : "Fetching products";
    my $products = GitBz::Progress::with_spinner(
        $spinner_msg,
        sub { $client->get_products( force_refresh => $opts{refresh} ) },
        1
    );

    print encode_json( { products => $products } ) . "\n";
}

1;
