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

use Modern::Perl;

sub new {
    my ( $class, $client ) = @_;
    bless { client => $client }, $class;
}

sub get_next_status_values {
    my ( $self, $current_status ) = @_;
    
    # Koha Bugzilla workflow transitions
    my %transitions = (
        'NEW'           => ['ASSIGNED', 'Needs Signoff', 'RESOLVED'],
        'ASSIGNED'      => ['Needs Signoff', 'RESOLVED'],
        'Needs Signoff' => ['Signed Off', 'Failed QA', 'RESOLVED'],
        'Signed Off'    => ['Passed QA', 'Failed QA', 'RESOLVED'],
        'Failed QA'     => ['Needs Signoff', 'RESOLVED'],
        'Passed QA'     => ['Pushed to Master', 'Pushed to Stable', 'RESOLVED'],
        'Pushed to Master' => ['RESOLVED'],
        'Pushed to Stable' => ['RESOLVED'],
        'RESOLVED'      => ['REOPENED'],
        'REOPENED'      => ['ASSIGNED', 'Needs Signoff', 'RESOLVED'],
    );
    
    return $transitions{$current_status} || [];
}

sub get_all_status_values {
    my ( $self ) = @_;
    return $self->{client}->get_field_values('bug_status');
}

1;