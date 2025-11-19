package GitBz::Git;

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

GitBz::Git - Git command wrapper and utilities

=head1 SYNOPSIS

    use GitBz::Git;
    
    my $output = GitBz::Git->run('log', '--oneline', '-5');
    my @commits = GitBz::Git->get_commits('HEAD~3..HEAD');
    my $patch = GitBz::Git->format_patch('abc123^..abc123');

=head1 DESCRIPTION

Provides a wrapper around Git commands with proper error handling and UTF-8 support.
Includes utilities for commit parsing and patch generation.

=cut

use Modern::Perl;

use Encode qw(decode);
use IPC::Run3;
use Try::Tiny qw(catch try);
use GitBz::Exception;

=head2 run

    my $output = GitBz::Git->run($command, @args);

Executes a Git command and returns the output.
Throws GitBz::Exception::Git on failure.

=cut

sub run {
    my ( $class, $command, @args ) = @_;

    my @cmd = ( 'git', $command, @args );
    my ( $stdout, $stderr );

    return try {
        run3 \@cmd, \undef, \$stdout, \$stderr;
        if ( $? != 0 ) {
            GitBz::Exception::Git->throw("Git command (@cmd) failed: $stderr");
        }
        if ($stdout) {

            # Don't chomp format-patch output to preserve exact formatting
            chomp $stdout unless $command eq 'format-patch';
        }
        return $stdout || '';
    } catch {
        GitBz::Exception::Git->throw($_);
    };
}

=head2 run_with_input

    my $output = GitBz::Git->run_with_input($input, $command, @args);

Executes a Git command with input piped to stdin and returns the output.

=cut

sub run_with_input {
    my ( $class, $input, $command, @args ) = @_;

    my @cmd = ( 'git', $command, @args );
    my ( $stdout, $stderr );

    return try {
        run3 \@cmd, \$input, \$stdout, \$stderr;
        if ( $? != 0 ) {
            GitBz::Exception::Git->throw("Git command (@cmd) failed: $stderr");
        }
        if ($stdout) {
            chomp $stdout;

            # Decode UTF-8 from Git output
            $stdout = decode( 'UTF-8', $stdout, Encode::FB_CROAK );
        }
        return $stdout || '';
    } catch {
        GitBz::Exception::Git->throw($_);
    };
}

=head2 get_commits

    my @commits = GitBz::Git->get_commits($range);

Parses a commit range and returns commit information.
Handles both single commits and ranges correctly.

Runs git rev-list and returns an array of commit hashrefs with 'id' and 'subject' keys.

=cut

sub get_commits {
    my ( $class, $range ) = @_;

    $range =~ s/^\s+|\s+$//g;

    my ( $from, $to );

    if ( $range !~ /\.\./ ) {
        $from = "$range~";
        $to   = $range;
    } else {

        # Parse FROM..TO
        ( $from, $to ) = split /\.\./, $range, 2;
    }

    # Default "FROM.." to FROM..HEAD
    $to = 'HEAD' if $to eq '';

    $from = undef if $from eq '';

    GitBz::Exception::Git->throw("Cannot find a starting commit for range ($range)")
        unless $from;

    $range = $from ? "$from..$to" : $to;

    my $output = $class->run(
        'rev-list',
        $range,
        '--pretty=format:%s',
        '--reverse',    # Add --reverse to get chronological order (oldest first)
    );

    my @commits;
    my @lines = split /\n/, $output;

    for ( my $i = 0 ; $i < @lines ; $i += 2 ) {
        next unless $lines[$i] =~ /^commit\s+([a-f0-9]+)/;
        my $id      = $1;
        my $subject = $lines[ $i + 1 ] || '';
        push @commits, { id => $id, subject => $subject };
    }

    GitBz::Exception::Git->throw("No commit found for this range ($range)")
        unless @commits;

    return @commits;

}

=head2 format_patch

    my $patch = GitBz::Git->format_patch($range);

Generates a patch for the given commit range.

=cut

sub format_patch {
    my ( $class, $range ) = @_;
    return $class->run( 'format-patch', '--stdout', '-M', $range );
}

=head2 get_trailer

    my $value = GitBz::Git->get_trailer($commit_id, $key);
    my @values = GitBz::Git->get_trailer($commit_id, $key);

Extracts trailer value(s) from a commit. Returns the trailer value in scalar context,
or all values in list context (for trailers that appear multiple times).

=cut

sub get_trailer {
    my ( $class, $commit_id, $key ) = @_;

    my $output = try {
        $class->run( 'log', "--format=%(trailers:key=$key,valueonly)", '-1', $commit_id );
    } catch {
        return;
    };

    return unless $output;

    my @values = split /\n/, $output;
    @values = grep { $_ ne '' } @values;

    return wantarray ? @values : $values[0];
}

=head2 get_sponsors

    my @sponsors = GitBz::Git->get_sponsors($commit_id);

Extracts all "Sponsored-by:" trailer values from a commit.

=cut

sub get_sponsors {
    my ( $class, $commit_id ) = @_;

    my @sponsors = $class->get_trailer( $commit_id, 'Sponsored-by' );
    return @sponsors;
}

1;
