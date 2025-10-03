package GitBz::Bug;

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

sub get {
    my ( $class, $client, $number ) = @_;

    my $bug_data = $client->get_bug($number);
    GitBz::Exception->throw("Bug $number not found") unless $bug_data;

    return bless {
        client       => $client,
        data         => $bug_data,
        _attachments => undef,
    }, $class;
}

sub id                  { $_[0]->{data}->{id} }
sub summary             { $_[0]->{data}->{summary} }
sub status              { $_[0]->{data}->{status} }
sub resolution          { $_[0]->{data}->{resolution} }
sub depends_on          { $_[0]->{data}->{depends_on} || [] }
sub cf_patch_complexity { $_[0]->{data}->{cf_patch_complexity} }

sub attachments {
    my ($self) = @_;

    unless ( $self->{_attachments} ) {
        $self->{_attachments} = $self->{client}->get_attachments( $self->id );
    }

    return $self->{_attachments};
}

sub update {
    my ( $self, %params ) = @_;

    return $self->{client}->update_bug( $self->id, %params );
}

sub add_attachment {
    my ( $self, $data, $filename, $summary, %opts ) = @_;

    return $self->{client}->add_attachment( $self->id, $data, $filename, $summary, %opts );
}

sub obsolete_attachment {
    my ( $self, $attachment_id ) = @_;

    return $self->{client}->obsolete_attachment($attachment_id);
}

1;