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

=head1 NAME

GitBz::Bug - Bugzilla bug object wrapper

=head1 SYNOPSIS

    use GitBz::Bug;
    
    my $bug = GitBz::Bug->get($client, 12345);
    print $bug->summary;
    $bug->update(status => 'Needs Signoff');
    $bug->add_attachment($patch_data, 'fix.patch', 'Bug fix');

=head1 DESCRIPTION

Provides an object-oriented interface to Bugzilla bugs.
Handles bug data access and operations through the REST client.

=cut

use Modern::Perl;

use GitBz::Exception;

=head2 get

    my $bug = GitBz::Bug->get($client, $bug_number);

Constructor that fetches bug data from Bugzilla.

=cut

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

=head2 Accessor Methods

Bug field accessors:

=cut

sub id                  { $_[0]->{data}->{id} }
sub summary             { $_[0]->{data}->{summary} }
sub status              { $_[0]->{data}->{status} }
sub resolution          { $_[0]->{data}->{resolution} }
sub depends_on          { $_[0]->{data}->{depends_on} || [] }
sub cf_patch_complexity { $_[0]->{data}->{cf_patch_complexity} }
sub cf_sponsors         { $_[0]->{data}->{cf_sponsors} }
sub cf_sponsorship      { $_[0]->{data}->{cf_sponsorship} }

=head2 attachments

    my $attachments = $bug->attachments();

Returns arrayref of bug attachments (cached after first call).

=cut

sub attachments {
    my ($self) = @_;

    unless ( $self->{_attachments} ) {
        $self->{_attachments} = $self->{client}->get_attachments( $self->id );
    }

    return $self->{_attachments};
}

=head2 update

    $bug->update(%params);

Updates bug fields through the REST API.

=cut

sub update {
    my ( $self, %params ) = @_;

    return $self->{client}->update_bug( $self->id, %params );
}

=head2 add_attachment

    $bug->add_attachment($data, $filename, $summary, %opts);

Adds a new attachment to the bug.

=cut

sub add_attachment {
    my ( $self, $data, $filename, $summary, %opts ) = @_;

    return $self->{client}->add_attachment( $self->id, $data, $filename, $summary, %opts );
}

=head2 obsolete_attachment

    $bug->obsolete_attachment($attachment_id);

Marks an attachment as obsolete.

=cut

sub obsolete_attachment {
    my ( $self, $attachment_id ) = @_;

    return $self->{client}->obsolete_attachment($attachment_id);
}

1;