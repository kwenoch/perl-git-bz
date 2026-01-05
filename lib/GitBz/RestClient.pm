package GitBz::RestClient;

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

GitBz::RestClient - Bugzilla REST API client

=head1 SYNOPSIS

    use GitBz::RestClient;
    
    my $client = GitBz::RestClient->new(
        host     => 'bugs.koha-community.org',
        https    => 1,
        username => $username,
        password => $password,
    );
    
    $client->login();
    my $bug = $client->get_bug(12345);

=head1 DESCRIPTION

Provides a REST API client for interacting with Bugzilla instances.
Handles authentication, bug retrieval, attachment management, and bug updates.

=cut

use Modern::Perl;
use LWP::UserAgent;
use JSON;
use MIME::Base64;
use Encode qw(encode decode);
use GitBz::Exception;

=head2 new

    my $client = GitBz::RestClient->new(%args);

Creates a new REST client instance.

=cut

sub new {
    my ( $class, %args ) = @_;

    my $base_url = sprintf(
        "%s://%s%s/rest",
        $args{https} ? 'https' : 'http',
        $args{host},
        $args{path} || ''
    );

    my $ua = LWP::UserAgent->new();
    $ua->timeout( $args{timeout} || 30 );
    $ua->ssl_opts( verify_hostname => 0 );

    return bless {
        ua       => $ua,
        base_url => $base_url,
        token    => undef,
        username => $args{username},
        password => $args{password},
        %args
    }, $class;
}

=head2 login

    $client->login($username, $password);

Authenticates with Bugzilla and stores the session token.

=cut

sub login {
    my ( $self, $username, $password ) = @_;

    $self->{username} = $username if $username;
    $self->{password} = $password if $password;

    my $response = $self->{ua}->get(
        sprintf(
            "%s/login?login=%s&password=%s",
            $self->{base_url}, $self->{username},
            $self->{password}
        )
    );

    if ( $response->is_success ) {
        my $data = decode_json( $response->content );
        $self->{token} = $data->{token};
        return 1;
    }

    GitBz::Exception::Bugzilla->throw( "Login failed: " . $response->status_line );
}

=head2 get_token

    my $token = $client->get_token();

Returns authentication token, logging in if necessary.

=cut

sub get_token {
    my ($self) = @_;

    return $self->{token} if $self->{token};

    if ( $self->{username} && $self->{password} ) {
        $self->login();
        return $self->{token};
    }

    return undef;
}

=head2 get_bug

    my $bug = $client->get_bug($bug_id);

Retrieves bug data from Bugzilla.

=cut

sub get_bug {
    my ( $self, $bug_id ) = @_;

    my $url = sprintf(
        "%s/bug/%s?include_fields=id,summary,status,resolution,depends_on,cf_patch_complexity,cf_sponsors,cf_sponsorship,qa_contact",
        $self->{base_url}, $bug_id
    );
    my $token = $self->get_token();
    $url .= "&token=$token" if $token;

    my $response = $self->{ua}->get($url);

    if ( !$response->is_success ) {
        GitBz::Exception::Bugzilla->throw( "Failed to get bug: " . $response->status_line );
    }

    my $data = decode_json( $response->content );
    return $data->{bugs}->[0];
}

=head2 get_attachments

    my $attachments = $client->get_attachments($bug_id);

Retrieves all attachments for a bug.

=cut

sub get_attachments {
    my ( $self, $bug_id ) = @_;

    my $url      = sprintf( "%s/bug/%s/attachment", $self->{base_url}, $bug_id );
    my $token = $self->get_token();
    $url .= "?token=$token" if $token;

    my $response = $self->{ua}->get($url);

    if ( !$response->is_success ) {
        GitBz::Exception::Bugzilla->throw( "Failed to get attachments: " . $response->status_line );
    }

    my $data = decode_json( $response->content );
    return $data->{bugs}->{$bug_id} || [];
}

=head2 add_attachment

    $client->add_attachment($bug_id, $data, $filename, $summary, %opts);

Adds a new attachment to a bug.

=cut

sub add_attachment {
    my ( $self, $bug_id, $data, $filename, $summary, %opts ) = @_;

    my $url = sprintf( "%s/bug/%s/attachment", $self->{base_url}, $bug_id );

    my $payload = $self->_create_attachment_payload( $bug_id, $data, $filename, $summary, %opts );

    my $token = $self->get_token();
    warn "DEBUG: Token for add_attachment: " . ( $token || 'NONE' ) . "\n" if $ENV{DEBUG};
    $payload->{token} = $token                                             if $token;

    my $response = $self->{ua}->post(
        $url,
        Content_Type => 'application/json',
        Content      => encode_json($payload)
    );

    if ( !$response->is_success ) {
        GitBz::Exception::Bugzilla->throw( "Failed to add attachment: " . $response->status_line );
    }

    return decode_json( $response->content );
}

=head2 update_bug

    $client->update_bug($bug_id, %params);

Updates bug fields and adds comments.

=cut

sub update_bug {
    my ( $self, $bug_id, %params ) = @_;

    my $url = sprintf( "%s/bug/%s", $self->{base_url}, $bug_id );

    my $payload = {
        ids => [$bug_id],
        %params
    };

    my $token = $self->get_token();
    $payload->{token} = $token if $token;

    my $response = $self->{ua}->put(
        $url,
        Content_Type => 'application/json',
        Content      => encode_json($payload)
    );

    if ( !$response->is_success ) {
        GitBz::Exception::Bugzilla->throw( "Failed to update bug: " . $response->status_line );
    }

    return decode_json( $response->content );
}

=head2 get_field_values

    my $values = $client->get_field_values($field_name);

Retrieves possible values for a bug field.

=cut

sub get_field_values {
    my ( $self, $field_name ) = @_;

    my $url      = sprintf( "%s/field/bug", $self->{base_url} );
    my $response = $self->{ua}->get($url);

    if ( !$response->is_success ) {
        return [];
    }

    my $data = decode_json( $response->content );

    # Find the field in the fields array
    for my $field ( @{ $data->{fields} || [] } ) {
        if ( $field->{name} eq $field_name && $field->{values} ) {
            return [ map { $_->{name} } @{ $field->{values} } ];
        }
    }

    return [];
}

=head2 search_users

    my $users = $client->search_users($search_term);

Searches for users matching the given search term.
Returns arrayref of user hashes with 'email', 'real_name', and 'id' keys.

=cut

sub search_users {
    my ( $self, $search_term ) = @_;

    return [] unless $search_term;

    # Get authentication token
    my $token = $self->get_token();

    # Build URL with token for authentication
    my $url = sprintf( "%s/user?match=%s", $self->{base_url}, $search_term );
    $url .= "&token=$token" if $token;

    my $response = $self->{ua}->get($url);

    if ( !$response->is_success ) {
        return [];
    }

    my $data = decode_json( $response->content );

    # Return users array with relevant fields
    return [ map {
        {
            email     => $_->{email},
            real_name => $_->{real_name} || '',
            id        => $_->{id}
        }
    } @{ $data->{users} || [] } ];
}

=head2 obsolete_attachment

    $client->obsolete_attachment($attachment_id);

Marks an attachment as obsolete.

=cut

sub obsolete_attachment {
    my ( $self, $attachment_id ) = @_;

    my $url = sprintf( "%s/bug/attachment/%s", $self->{base_url}, $attachment_id );

    my $payload = {
        ids         => [$attachment_id],
        is_obsolete => JSON::true,
    };

    my $token = $self->get_token();
    $payload->{token} = $token if $token;

    my $response = $self->{ua}->put(
        $url,
        Content_Type => 'application/json',
        Content      => encode_json($payload)
    );

    if ( !$response->is_success ) {
        GitBz::Exception::Bugzilla->throw( "Failed to obsolete attachment: " . $response->status_line );
    }

    return decode_json( $response->content );
}

# Internal methods

=head2 _create_attachment_payload

    my $payload = $client->_create_attachment_payload($bug_id, $data, $filename, $summary, %opts);

Internal method to create attachment payload for Bugzilla REST API.
Returns hashref suitable for JSON encoding.

=cut

sub _create_attachment_payload {
    my ( $self, $bug_id, $data, $filename, $summary, %opts ) = @_;

    my $payload = {
        ids          => [$bug_id],
        data         => encode_base64($data),
        file_name    => $filename,
        summary      => $summary,
        content_type => 'text/plain',
        is_patch     => JSON::true,
    };

    $payload->{comment} = decode( 'UTF-8', $opts{comment} ) if $opts{comment};
    return $payload;
}

=head2 get_bug_url

    my $url = $client->get_bug_url($bug_id);

Returns the web URL for viewing a bug in the browser.

=cut

sub get_bug_url {
    my ( $self, $bug_id ) = @_;

    # Convert REST URL to web URL
    my $web_url = $self->{base_url};
    $web_url =~ s|/rest$||;    # Remove /rest suffix

    return "$web_url/show_bug.cgi?id=$bug_id";
}

1;
