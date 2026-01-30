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

use utf8;
use open ':std', ':utf8';

use GitBz::Exception;

use Text::UnicodeBox::Table;

=head2 get

    my $bug = GitBz::Bug->get($client, $bug_number);

Constructor that fetches bug data from Bugzilla.

=cut

sub get {
    my ( $class, $client, $number ) = @_;

    my $bug_data = $client->get_bug($number);
    GitBz::Exception->throw("Bug $number not found") unless $bug_data;

    return bless {
        client           => $client,
        data             => $bug_data,
        _attachments     => undef,
        _display_rows    => [],
        _pending_updates => {},
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
sub qa_contact          { $_[0]->{data}->{qa_contact} }
sub assigned_to         { $_[0]->{data}->{assigned_to} }

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

=head2 add_display_row

    $bug->add_display_row($field, $old, $arrow, $new);

Adds a row to be displayed when update() is called.

=cut

sub add_display_row {
    my ( $self, @row ) = @_;
    push @{ $self->{_display_rows} }, \@row;
}

=head2 set_field

    $bug->set_field($field, $value);

Queues a field update and adds display row if value differs from current.

=cut

sub set_field {
    my ( $self, $field, $value ) = @_;

    my %field_labels = (
        status              => 'Status',
        resolution          => 'Resolution',
        cf_patch_complexity => 'Patch-complexity',
        cf_sponsors         => 'Sponsors',
        cf_sponsorship      => 'Sponsorship',
        qa_contact          => 'QA-contact',
        assigned_to         => 'Assignee',
    );

    my $current = $self->can($field) ? $self->$field : undef;

    # Only add if different
    if ( !defined $current || $value ne $current ) {
        $self->{_pending_updates}{$field} = $value;

        my $label = $field_labels{$field} || ucfirst($field);
        my $old   = ( defined $current && $current ne '' ) ? $current : '---';
        $self->add_display_row( $label, $old, '→', $value );
    }
}

=head2 add_comment

    $bug->add_comment($text);

Queues a comment to be added.

=cut

sub add_comment {
    my ( $self, $text ) = @_;

    $self->{_pending_updates}{comment} = { body => $text };
    $self->add_display_row( 'Comment', '', '', '(added)' );
}

=head2 set_depends

    $bug->set_depends(add => [123], remove => [456]);

Queues dependency changes.

=cut

sub set_depends {
    my ( $self, %changes ) = @_;

    $self->{_pending_updates}{depends_on} = \%changes;

    if ( $changes{add} ) {
        $self->add_display_row( 'Depends', '', '', '+ ' . join( ', ', @{ $changes{add} } ) );
    }
    if ( $changes{remove} ) {
        $self->add_display_row( 'Depends', '', '', '- ' . join( ', ', @{ $changes{remove} } ) );
    }
}

=head2 set_sponsors

    $bug->set_sponsors(add => ['Sponsor One'], remove => ['Sponsor Two']);

Queues sponsor changes.

=cut

sub set_sponsors {
    my ( $self, %changes ) = @_;

    $self->{_pending_updates}{cf_sponsors} = \%changes;

    if ( $changes{add} ) {
        $self->add_display_row( 'Sponsors', '', '', '+ ' . join( ', ', @{ $changes{add} } ) );
    }
    if ( $changes{remove} ) {
        $self->add_display_row( 'Sponsors', '', '', '- ' . join( ', ', @{ $changes{remove} } ) );
    }
}

=head2 apply_updates

    $bug->apply_updates();

Applies all pending field updates to Bugzilla.

=cut

sub apply_updates {
    my ($self) = @_;

    return unless %{ $self->{_pending_updates} };

    # Display changes before updating
    $self->_display_changes();

    # Convert sponsors add/remove to comma-separated string
    if ( $self->{_pending_updates}{cf_sponsors} && ref $self->{_pending_updates}{cf_sponsors} eq 'HASH' ) {
        my $changes = $self->{_pending_updates}{cf_sponsors};
        my @current = split /,\s*/, ( $self->cf_sponsors || '' );
        @current = grep { $_ } @current;    # Remove empty strings

        my %sponsors = map { $_ => 1 } @current;

        if ( $changes->{add} ) {
            $sponsors{$_} = 1 for @{ $changes->{add} };
        }
        if ( $changes->{remove} ) {
            delete $sponsors{$_} for @{ $changes->{remove} };
        }

        $self->{_pending_updates}{cf_sponsors} = join( ', ', sort keys %sponsors );
    }

    $self->update( %{ $self->{_pending_updates} } );
    $self->{_pending_updates} = {};
}

=head2 _display_changes

Internal method to display accumulated changes.

=cut

sub _display_changes {
    my ($self) = @_;

    return unless @{ $self->{_display_rows} };

    binmode( STDOUT, ':utf8' );

    # Clear the current line (spinner)
    print "\r\033[K";

    my $table = Text::UnicodeBox::Table->new();
    $table->add_row(@$_) for @{ $self->{_display_rows} };

    my $output = $table->render();
    $output =~ s/^/  /gm;
    print $output . "\n";

    # Clear display rows after showing
    $self->{_display_rows} = [];
}

=head2 update

    $bug->update(%params);

Updates bug fields through the REST API.

=cut

sub update {
    my ( $self, %params ) = @_;

    return $self->{client}->update_bug( $self->id, %params );
}

=head2 validate_user_field_with_lookup

    my $validated_email = $bug->validate_user_field_with_lookup($client, $email, $field_label);

Generic method to validate user field email with automatic lookup and user interaction.
Returns validated email on success, dies on error/cancellation.

=cut

sub validate_user_field_with_lookup {
    my ( $self, $client, $email, $field_label ) = @_;

    # Skip validation if setting to our own login (we know we exist)
    return $email if $email eq $client->{username};

    # Validate email exists before attempting update
    my $is_valid = $client->validate_user($email);

    # If valid, return it
    return $email if $is_valid;

    # If not valid, enter search/select flow (handles validation internally)
    print "\n";
    GitBz::Progress::print_error("$field_label '$email' not found");

    my $selected_email = $self->_select_user( $client, $email, $field_label );

    die "Update cancelled by user\n" unless $selected_email;

    return $selected_email;
}

=head2 _select_user

    my $email = $bug->_select_user($client, $invalid_email, $field_label);

Generic internal method to search for users and present selection menu.
Validates manually entered emails and loops until valid or cancelled.
Returns validated email or undef if cancelled.

=cut

sub _select_user {
    my ( $self, $client, $invalid_email, $field_label ) = @_;

    my $search_email = $invalid_email;

    while (1) {
        # Extract the local part (before @) from the email
        my $search_term;
        if ( $search_email =~ /^([^@]+)@/ ) {
            $search_term = $1;
        } else {
            $search_term = $search_email;
        }

        # Search for users whose email begins with the local part
        print "\nSearching for similar users (begins with '$search_term')...\n";
        my $users = GitBz::Progress::with_spinner(
            "Searching users",
            sub {
                return $client->search_users($search_term);
            },
            1
        );

        if ( !@$users ) {
            print "No similar users found.\n";
            print "Would you like to enter a different $field_label? [y/N]: ";
            my $response = <STDIN>;
            chomp $response;

            if ( $response =~ /^[yY]/ ) {
                print "Enter $field_label email: ";
                my $new_email = <STDIN>;
                chomp $new_email;
                $new_email =~ s/^\s+|\s+$//g;

                if ($new_email) {
                    # Validate the manually entered email
                    print "\nValidating $field_label: $new_email\n";
                    my $is_valid = $client->validate_user($new_email);

                    if ($is_valid) {
                        return $new_email;
                    } else {
                        # Invalid - loop back with this email as search term
                        print "\n";
                        GitBz::Progress::print_error("$field_label '$new_email' not found");
                        $search_email = $new_email;
                        next;
                    }
                }
            }

            return;
        }

        # Present users for selection
        print "\nFound " . scalar(@$users) . " similar user(s):\n\n";

        for my $i ( 0 .. $#$users ) {
            my $user         = $users->[$i];
            my $display_name = $user->{real_name} ? "$user->{real_name} <$user->{email}>" : $user->{email};
            print "  [$i] $display_name\n";
        }

        print "\nSelect a user by number, or press Enter to cancel: ";
        my $selection = <STDIN>;
        chomp $selection;

        if ( $selection =~ /^\d+$/ && $selection >= 0 && $selection <= $#$users ) {
            # User selected from search results - already valid, return immediately
            return $users->[$selection]{email};
        }

        # User cancelled
        return;
    }
}

=head2 validate_qa_contact_with_lookup

    my $validated_email = $bug->validate_qa_contact_with_lookup($client, $email);

Validates QA contact email with automatic lookup and user interaction.
Returns validated email on success, dies on error/cancellation.

=cut

sub validate_qa_contact_with_lookup {
    my ( $self, $client, $email ) = @_;
    return $self->validate_user_field_with_lookup( $client, $email, 'QA contact' );
}

=head2 validate_assignee_with_lookup

    my $validated_email = $bug->validate_assignee_with_lookup($client, $email);

Validates assignee email with automatic lookup and user interaction.
Returns validated email on success, dies on error/cancellation.

=cut

sub validate_assignee_with_lookup {
    my ( $self, $client, $email ) = @_;
    return $self->validate_user_field_with_lookup( $client, $email, 'Assignee' );
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
