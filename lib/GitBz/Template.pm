package GitBz::Template;

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

GitBz::Template - Bug update template generation and parsing

=head1 SYNOPSIS

    use GitBz::Template;
    
    my $template = GitBz::Template::generate_bug_fields($bug, $client);
    my $updates = GitBz::Template::parse_bug_fields($content, $bug);

=head1 DESCRIPTION

Provides template generation and parsing for bug field updates.
Used by both attach and edit commands to create consistent templates.

=cut

use Modern::Perl;

use utf8;
use open ':std', ':utf8';

use GitBz::StatusWorkflow;
use GitBz::Progress;

=head2 generate_bug_fields

    my $template = GitBz::Template::generate_bug_fields($bug, $client, %options);

Generates template sections for bug fields (status, patch-complexity, depends, sponsorship, sponsors).

Options:
  - all_sponsors: hashref of sponsors from commits (for attach command)
  - attachments: arrayref of bug attachments (for obsoletes section)
  - commits: arrayref of commits being attached (for auto-uncomment obsoletes)

=cut

sub generate_bug_fields {
    my ( $bug, $client, %opts ) = @_;
    
    my $template = "";
    
    # Add obsoletes section if attachments provided (attach command)
    if ( $opts{attachments} && @{ $opts{attachments} } ) {
        # Build list of commit subjects for matching
        my %commit_subjects;
        if ( $opts{commits} ) {
            %commit_subjects = map { $_->{subject} => 1 } @{ $opts{commits} };
        }

        for my $patch ( @{ $opts{attachments} } ) {
            next unless $patch->{is_patch} && !$patch->{is_obsolete};

            # Uncomment if any commit subject matches this patch summary
            my $obsoleted = $commit_subjects{ $patch->{summary} } ? "" : "#";
            $template .= "${obsoleted}Obsoletes: $patch->{id} - $patch->{summary}\n";
        }
        $template .= "\n";
    }
    
    # Add status options
    my $workflow = GitBz::StatusWorkflow->new($client);
    $template .= "# Current status: " . $bug->status . "\n";
    my $status_values = $workflow->get_next_status_values( $bug->status );
    for my $status (@$status_values) {
        $template .= "# Status: $status\n";
    }
    $template .= "\n";

    # Add QA Contact field
    my $qa_contact = $bug->qa_contact || "";
    my $current_user = $client->{username} || 'user@example.com';
    $template .= "# Current QA-contact: $qa_contact\n";
    $template .= "# QA-contact: $current_user\n";
    $template .= "\n";

    # Add patch complexity options
    my $complexity = $bug->cf_patch_complexity || "";
    $template .= "# Current patch-complexity: $complexity\n";
    my $complexity_values = GitBz::Progress::with_spinner(
        "Fetching field values",
        sub {
            return $client->get_field_values('cf_patch_complexity');
        },
        1
    );
    if ($complexity_values) {
        for my $comp (@$complexity_values) {
            $template .= "# Patch-complexity: $comp\n";
        }
    }
    $template .= "\n";

    # Add depends options
    my $depends_list = $bug->depends_on;
    my $depends_str  = @$depends_list ? join( ' ', @$depends_list ) : '';
    $template .= "# Current depends: $depends_str\n";

    # Show current depends uncommented
    for my $dep (@$depends_list) {
        $template .= "Depends: bug $dep\n";
    }

    # Show skeleton commented
    $template .= "# Depends: bug xxxx\n";
    $template .= "# Depends: bug yyyy\n";
    $template .= "\n";

    # Add sponsorship status options
    my $sponsorship = $bug->cf_sponsorship || "";
    $template .= "# Current sponsorship: $sponsorship\n";
    my $sponsorship_values = GitBz::Progress::with_spinner(
        "Fetching field values",
        sub {
            return $client->get_field_values('cf_sponsorship');
        },
        1
    );
    if ($sponsorship_values) {
        for my $status (@$sponsorship_values) {
            $template .= "# Sponsorship: $status\n";
        }
    }
    $template .= "\n";

    # Add sponsors section (one sponsor per line)
    my $current_sponsors = $bug->cf_sponsors || "";
    my @current_sponsor_list;
    if ($current_sponsors) {
        # Split existing sponsors by comma and trim whitespace
        for my $sponsor ( split /,/, $current_sponsors ) {
            $sponsor =~ s/^\s+|\s+$//g;
            push @current_sponsor_list, $sponsor if $sponsor;
        }
    }
    
    my $sponsors_str = @current_sponsor_list ? join( ', ', @current_sponsor_list ) : '';
    $template .= "# Current sponsors: $sponsors_str\n";
    $template .= "# Add one sponsor per line:\n";

    # Build proposed sponsors list from current + commits (if provided)
    my %proposed_sponsors;
    for my $sponsor (@current_sponsor_list) {
        $proposed_sponsors{$sponsor} = 1;
    }

    # Add sponsors from commits (attach command provides this)
    if ( $opts{all_sponsors} ) {
        for my $sponsor ( sort keys %{ $opts{all_sponsors} } ) {
            $proposed_sponsors{$sponsor} = 1;
        }
    }

    # Show current/proposed sponsors uncommented
    if (%proposed_sponsors) {
        for my $sponsor ( sort keys %proposed_sponsors ) {
            $template .= "Sponsors: $sponsor\n";
        }
    }
    
    # Show skeleton commented
    $template .= "# Sponsors: Sponsor Name\n";
    $template .= "\n";

    return $template;
}

=head2 parse_bug_fields

    my $updates = GitBz::Template::parse_bug_fields($content, $bug);

Parses edited template content and returns hashref of bug field updates.

=cut

sub parse_bug_fields {
    my ( $content, $bug ) = @_;

    my @lines = split /\n/, $content;
    my %bug_updates;

    for my $line (@lines) {
        # Skip comments and empty lines
        next if $line =~ /^\s*#/ || $line =~ /^\s*$/;

        if ( $line =~ /^\s*Status\s*:\s*(.+)/ ) {
            $bug_updates{status} = $1;
        } elsif ( $line =~ /^\s*QA-contact\s*:\s*(.*)/ ) {
            my $value = $1;
            $value =~ s/^\s+|\s+$//g;  # Trim whitespace
            $bug_updates{qa_contact} = $value;  # Empty string allowed (clears field)
        } elsif ( $line =~ /^\s*Patch-complexity\s*:\s*(.+)/ ) {
            $bug_updates{cf_patch_complexity} = $1;
        } elsif ( $line =~ /^\s*Sponsors\s*:\s*(.+)/ ) {
            push @{ $bug_updates{cf_sponsors} }, $1;
        } elsif ( $line =~ /^\s*Sponsorship\s*:\s*(.+)/ ) {
            $bug_updates{cf_sponsorship} = $1;
        } elsif ( $line =~ /^\s*Depends\s*:\s*([Bb][Uu][Gg])?\s*(\d+)/ ) {
            push @{ $bug_updates{depends_on} }, $2;
        }
    }

    # Convert depends_on to proper API format with add/remove actions
    if ( $bug_updates{depends_on} ) {
        my @new_depends = @{ $bug_updates{depends_on} };
        my @old_depends = @{ $bug->depends_on };

        my @to_add = grep {
            my $new = $_;
            !grep { $_ eq $new } @old_depends
        } @new_depends;
        my @to_remove = grep {
            my $old = $_;
            !grep { $_ eq $old } @new_depends
        } @old_depends;

        if ( @to_add || @to_remove ) {
            my %depends_update;
            $depends_update{add}     = \@to_add    if @to_add;
            $depends_update{remove}  = \@to_remove if @to_remove;
            $bug_updates{depends_on} = \%depends_update;
        } else {
            delete $bug_updates{depends_on};
        }
    }

    # Convert cf_sponsors to proper API format with add/remove actions
    if ( $bug_updates{cf_sponsors} ) {
        my @new_sponsors = @{ $bug_updates{cf_sponsors} };
        my @old_sponsors = split /,\s*/, ( $bug->cf_sponsors || '' );
        @old_sponsors = grep { $_ } @old_sponsors;  # Remove empty strings

        my @to_add = grep {
            my $new = $_;
            !grep { $_ eq $new } @old_sponsors
        } @new_sponsors;
        my @to_remove = grep {
            my $old = $_;
            !grep { $_ eq $old } @new_sponsors
        } @old_sponsors;

        if ( @to_add || @to_remove ) {
            my %sponsors_update;
            $sponsors_update{add}    = \@to_add    if @to_add;
            $sponsors_update{remove} = \@to_remove if @to_remove;
            $bug_updates{cf_sponsors} = \%sponsors_update;
        } else {
            delete $bug_updates{cf_sponsors};
        }
    }

    # Auto-update cf_sponsorship to 'Sponsored' if sponsors are being added
    if ( $bug_updates{cf_sponsors} && ref $bug_updates{cf_sponsors} eq 'HASH' ) {
        if ( $bug_updates{cf_sponsors}{add} ) {
            my $current_sponsorship = $bug->cf_sponsorship || '';
            my @unsponsored_values  = ( '---', 'Unsponsored', 'Seeking sponsor' );

            # Check if current sponsorship indicates no sponsorship
            if ( grep { $_ eq $current_sponsorship } @unsponsored_values ) {
                $bug_updates{cf_sponsorship} = 'Sponsored';
            }
        }
    }

    return \%bug_updates;
}

1;
