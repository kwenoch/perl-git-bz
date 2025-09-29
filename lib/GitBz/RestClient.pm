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

use Modern::Perl;
use LWP::UserAgent;
use JSON;
use MIME::Base64;
use GitBz::Exception;

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
        %args
    }, $class;
}

sub login {
    my ( $self, $username, $password ) = @_;

    my $response = $self->{ua}->post(
        $self->{base_url} . '/login',
        Content_Type => 'application/json',
        Content      => encode_json(
            {
                login    => $username,
                password => $password
            }
        )
    );

    if ( $response->is_success ) {
        my $data = decode_json( $response->content );
        $self->{token} = $data->{token};
        return 1;
    }

    GitBz::Exception::Bugzilla->throw( "Login failed: " . $response->status_line );
}

sub get_bug {
    my ( $self, $bug_id ) = @_;

    my $url      = sprintf( "%s/bug/%s", $self->{base_url}, $bug_id );
    my $response = $self->{ua}->get($url);

    if ( !$response->is_success ) {
        GitBz::Exception::Bugzilla->throw( "Failed to get bug: " . $response->status_line );
    }

    my $data = decode_json( $response->content );
    return $data->{bugs}->[0];
}

sub get_attachments {
    my ( $self, $bug_id ) = @_;

    my $url      = sprintf( "%s/bug/%s/attachment", $self->{base_url}, $bug_id );
    my $response = $self->{ua}->get($url);

    if ( !$response->is_success ) {
        GitBz::Exception::Bugzilla->throw( "Failed to get attachments: " . $response->status_line );
    }

    my $data = decode_json( $response->content );
    return $data->{bugs}->{$bug_id} || [];
}

sub add_attachment {
    my ( $self, $bug_id, $data, $filename, $summary, %opts ) = @_;

    my $url = sprintf( "%s/bug/%s/attachment", $self->{base_url}, $bug_id );

    my $payload = {
        ids          => [$bug_id],
        data         => encode_base64($data),
        file_name    => $filename,
        summary      => $summary,
        content_type => 'text/plain',
        is_patch     => JSON::true,
    };

    $payload->{comment} = $opts{comment} if $opts{comment};
    $payload->{token}   = $self->{token} if $self->{token};

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

sub update_bug {
    my ( $self, $bug_id, %params ) = @_;

    my $url = sprintf( "%s/bug/%s", $self->{base_url}, $bug_id );

    my $payload = {
        ids => [$bug_id],
        %params
    };

    $payload->{token} = $self->{token} if $self->{token};

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

1;
