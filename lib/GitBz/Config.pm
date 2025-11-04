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

=head1 NAME

GitBz::Config - Configuration management for git-bz

=head1 SYNOPSIS

    use GitBz::Config;
    
    my $tracker = GitBz::Config->get_default_tracker();
    my $path = GitBz::Config->get("bz-tracker.$tracker.path");
    my $https = GitBz::Config->get_bool("bz-tracker.$tracker.https");

=head1 DESCRIPTION

Handles loading and merging configuration from Git config and default settings.
Provides Koha-specific defaults for Bugzilla integration.

=cut

use Modern::Perl;

use GitBz::Git;

use constant DEFAULT_TRACKER => 'bugs.koha-community.org';

sub get {
    my ($class, $name, $default, $type) = @_;

    $default //= '';
    my @args;

    if ($type) {
        push @args, "--type=$type";
    }
    push @args, "--default=$default";
    push @args, "--get", $name;

    return GitBz::Git->run( 'config', @args );
}

sub get_bool {
    my ($class, $name) = @_;

    return $class->get( $name, '', 'bool' ) eq 'true';
}

sub get_default_tracker {
    my ($class) = @_;

    return $class->get( 'bz.default-tracker', DEFAULT_TRACKER );
}

1;
