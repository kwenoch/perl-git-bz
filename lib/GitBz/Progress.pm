package GitBz::Progress;

use Modern::Perl '2023';
use Term::ANSIColor qw(colored);

our $VERSION = '0.1.0';

=head1 NAME

GitBz::Progress - Progress indicators and feedback for GitBz

=head1 SYNOPSIS

    use GitBz::Progress;

    # Show progress during a long operation
    my $spinner = GitBz::Progress::start_spinner("Fetching bug data");
    # ... do work ...
    GitBz::Progress::stop_spinner($spinner, "success");  # or "error"

    # Show real-time progress
    GitBz::Progress::print_success("Attached patch successfully");
    GitBz::Progress::print_error("Failed to upload");
    GitBz::Progress::print_info("Processing...");

=head1 DESCRIPTION

Provides consistent progress indicators and colored output for GitBz commands.
Works with both terminal and non-terminal output.

=cut

=head2 start_spinner

Start a progress indicator with a message.

    my $spinner = GitBz::Progress::start_spinner("Loading...");

Returns a spinner object that should be passed to stop_spinner().

=cut

sub start_spinner {
    my ($message) = @_;

    # Check if output is to a terminal
    my $is_tty = -t STDOUT;

    if ($is_tty) {
        # Print message without newline for terminal
        print colored(['cyan'], "$message...");
        STDOUT->flush();
    } else {
        # For non-TTY, print with ellipsis
        print "$message...";
    }

    return {
        message => $message,
        is_tty => $is_tty,
        start_time => time(),
    };
}

=head2 stop_spinner

Stop a progress indicator and show completion status.

    GitBz::Progress::stop_spinner($spinner, "success");
    GitBz::Progress::stop_spinner($spinner, "error", "Connection failed");

First parameter: spinner object from start_spinner()
Second parameter: "success" or "error"
Third parameter (optional): custom message

=cut

sub stop_spinner {
    my ($spinner_obj, $status, $custom_message) = @_;

    my $message = $custom_message || $spinner_obj->{message};

    if ( !$spinner_obj->{is_tty} ) {
        # Not a terminal, just print status
        if ( $status eq 'success' ) {
            print " " . colored(['green'], '✓') . "\n";
        } else {
            print " " . colored(['red'], '✗') . "\n";
        }
        return;
    }

    # For terminal: clear the line and print final status
    # Move to beginning of line, clear to end, then print result
    print "\r\e[K";

    if ( $status eq 'success' ) {
        print colored(['green'], '  ✓ ') . "$message\n";
    } else {
        print colored(['red'], '  ✗ ') . "$message\n";
    }
}

=head2 print_success

Print a success message with a green checkmark.

    GitBz::Progress::print_success("Attached: patch-name.patch");

=cut

sub print_success {
    my ($message) = @_;
    print colored(['green'], '  ✓ ') . "$message\n";
}

=head2 print_error

Print an error message with a red X.

    GitBz::Progress::print_error("Failed to upload attachment");

=cut

sub print_error {
    my ($message) = @_;
    print colored(['red'], '  ✗ ') . "$message\n";
}

=head2 print_info

Print an informational message.

    GitBz::Progress::print_info("Processing 5 patches...");

=cut

sub print_info {
    my ($message) = @_;
    print colored(['blue'], '  ℹ ') . "$message\n";
}

=head2 print_warning

Print a warning message with a yellow warning symbol.

    GitBz::Progress::print_warning("Bug number mismatch detected");

=cut

sub print_warning {
    my ($message) = @_;
    print colored(['yellow'], '  ⚠ ') . "$message\n";
}

=head2 progress_counter

Format a progress counter string.

    my $counter = GitBz::Progress::progress_counter(3, 10);
    # Returns: "[3/10]"

=cut

sub progress_counter {
    my ($current, $total) = @_;
    return colored(['cyan'], sprintf("[%d/%d]", $current, $total));
}

=head2 with_spinner

Execute a code block with a progress indicator.

    GitBz::Progress::with_spinner("Fetching bug", sub {
        # ... do work ...
        return 1;  # success
    });

Returns the return value from the code block.
If the code throws an exception, the spinner is stopped with error status
and the exception is re-thrown.

=cut

sub with_spinner {
    my ($message, $code) = @_;

    my $spinner = start_spinner($message);

    my $result;
    my $success = eval {
        $result = $code->();
        1;
    };

    if ($@) {
        my $error = $@;
        stop_spinner($spinner, 'error');
        die $error;
    }

    stop_spinner($spinner, 'success');
    return $result;
}

1;

__END__

=head1 AUTHOR

GitBz Contributors

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
