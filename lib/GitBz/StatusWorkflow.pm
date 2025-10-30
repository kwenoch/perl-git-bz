package GitBz::StatusWorkflow;

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

GitBz::StatusWorkflow - Koha Bugzilla status workflow management

=head1 SYNOPSIS

    use GitBz::StatusWorkflow;
    
    my $workflow = GitBz::StatusWorkflow->new($client);
    my $next_statuses = $workflow->get_next_status_values('NEW');
    my $all_statuses = $workflow->get_all_status_values();

=head1 DESCRIPTION

Manages Koha-specific Bugzilla status workflow transitions.
Provides valid next status options based on current bug status.

=cut

use Modern::Perl;

=head2 new

    my $workflow = GitBz::StatusWorkflow->new($client);

Creates a new workflow manager with a REST client.

=cut

sub new {
    my ( $class, $client ) = @_;
    bless { client => $client }, $class;
}

=head2 get_next_status_values

    my $statuses = $workflow->get_next_status_values($current_status);

Returns arrayref of valid next status values for the current status.
Based on Koha Bugzilla workflow rules.

=cut

sub get_next_status_values {
    my ( $self, $current_status ) = @_;

    # Koha Bugzilla workflow transitions
    my %transitions = (
        'NEW'              => [ 'ASSIGNED',         'Needs Signoff', 'RESOLVED' ],
        'ASSIGNED'         => [ 'Needs Signoff',    'RESOLVED' ],
        'Needs Signoff'    => [ 'Signed Off',       'Failed QA', 'RESOLVED' ],
        'Signed Off'       => [ 'Passed QA',        'Failed QA', 'RESOLVED' ],
        'Failed QA'        => [ 'Needs Signoff',    'RESOLVED' ],
        'Passed QA'        => [ 'Pushed to Master', 'Pushed to Stable', 'RESOLVED' ],
        'Pushed to Master' => ['RESOLVED'],
        'Pushed to Stable' => ['RESOLVED'],
        'RESOLVED'         => ['REOPENED'],
        'REOPENED'         => [ 'ASSIGNED', 'Needs Signoff', 'RESOLVED' ],
    );

    return $transitions{$current_status} || [];
}

=head2 get_all_status_values

    my $statuses = $workflow->get_all_status_values();

Returns arrayref of all possible bug status values from Bugzilla.

=cut

sub get_all_status_values {
    my ($self) = @_;
    return $self->{client}->get_field_values('bug_status');
}

1;