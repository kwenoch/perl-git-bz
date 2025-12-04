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

    # Koha Bugzilla workflow transitions (from REST API)
    my %transitions = (
        'UNCONFIRMED' => [ 'NEW', 'RESOLVED' ],
        'REOPENED'    =>
            [ 'NEW', 'ASSIGNED', 'In Discussion', 'Needs Signoff', 'Needs documenting', 'RESOLVED', 'BLOCKED' ],
        'NEW' => [
            'CONFIRMED', 'ASSIGNED', 'In Discussion', 'Needs Signoff', 'Needs documenting', 'RESOLVED', 'CLOSED',
            'BLOCKED'
        ],
        'CONFIRMED' => [ 'ASSIGNED', 'In Discussion', 'Needs Signoff', 'RESOLVED' ],
        'ASSIGNED'  => [
            'CONFIRMED',            'In Discussion', 'Needs Signoff', 'Signed Off', 'Passed QA', 'Failed QA',
            'Patch doesn\'t apply', 'RESOLVED',      'BLOCKED'
        ],
        'In Discussion' => [
            'CONFIRMED', 'ASSIGNED', 'Needs Signoff', 'Signed Off', 'Passed QA', 'Failed QA', 'Patch doesn\'t apply',
            'Needs documenting', 'RESOLVED', 'BLOCKED'
        ],
        'Needs Signoff' =>
            [ 'ASSIGNED', 'In Discussion', 'Signed Off', 'Failed QA', 'Patch doesn\'t apply', 'RESOLVED', 'BLOCKED' ],
        'Signed Off' => [
            'ASSIGNED', 'In Discussion', 'Needs Signoff', 'Passed QA', 'Failed QA', 'Patch doesn\'t apply', 'RESOLVED',
            'BLOCKED'
        ],
        'Passed QA' => [
            'ASSIGNED',       'In Discussion',    'Needs Signoff', 'Signed Off', 'Failed QA', 'Patch doesn\'t apply',
            'Pushed to main', 'Pushed to stable', 'Pushed to oldstable', 'Pushed to oldoldstable', 'RESOLVED', 'BLOCKED'
        ],
        'Failed QA' => [
            'ASSIGNED', 'In Discussion', 'Needs Signoff', 'Signed Off', 'Passed QA', 'Patch doesn\'t apply',
            'RESOLVED', 'BLOCKED'
        ],
        'Patch doesn\'t apply' => [
            'ASSIGNED', 'In Discussion', 'Needs Signoff', 'Signed Off', 'Passed QA', 'Failed QA', 'RESOLVED', 'BLOCKED'
        ],
        'Pushed to main' => [
            'ASSIGNED', 'Passed QA', 'Failed QA', 'Pushed to stable', 'Needs documenting', 'RESOLVED', 'CLOSED',
            'BLOCKED'
        ],
        'Pushed to stable' =>
            [ 'ASSIGNED', 'Pushed to oldstable', 'Needs documenting', 'RESOLVED', 'CLOSED', 'BLOCKED' ],
        'Pushed to oldstable' =>
            [ 'ASSIGNED', 'Pushed to oldoldstable', 'Needs documenting', 'RESOLVED', 'CLOSED', 'BLOCKED' ],
        'Pushed to oldoldstable' =>
            [ 'ASSIGNED', 'Pushed to oldoldoldstable', 'Needs documenting', 'RESOLVED', 'CLOSED', 'BLOCKED' ],
        'Pushed to oldoldoldstable' => [ 'ASSIGNED', 'Needs documenting', 'RESOLVED', 'CLOSED', 'BLOCKED' ],
        'Needs documenting'         => [
            'Pushed to main',            'Pushed to stable', 'Pushed to oldstable', 'Pushed to oldoldstable',
            'Pushed to oldoldoldstable', 'RESOLVED',         'CLOSED'
        ],
        'RESOLVED' => [ 'UNCONFIRMED', 'REOPENED', 'Needs documenting', 'CLOSED',    'BLOCKED' ],
        'VERIFIED' => [ 'UNCONFIRMED', 'REOPENED', 'Failed QA', 'Needs documenting', 'RESOLVED', 'CLOSED', 'BLOCKED' ],
        'CLOSED'   => [ 'UNCONFIRMED', 'REOPENED', 'Needs documenting', 'RESOLVED',  'BLOCKED' ],
        'BLOCKED'  => [
            'UNCONFIRMED', 'REOPENED',  'NEW', 'CONFIRMED', 'ASSIGNED', 'In Discussion', 'Needs Signoff', 'Signed Off',
            'Passed QA',   'Failed QA', 'Patch doesn\'t apply', 'Pushed to main', 'Pushed to stable',
            'Pushed to oldstable', 'Pushed to oldoldstable', 'Pushed to oldoldoldstable', 'Needs documenting',
            'RESOLVED',            'CLOSED'
        ],
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