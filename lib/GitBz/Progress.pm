package GitBz::Progress;

use Modern::Perl '2023';
use Term::ANSIColor qw(colored);
use Time::HiRes     qw(usleep);
use POSIX ":sys_wait_h";

our $VERSION = '0.1.0';

# Spinner characters for animation (braille dots pattern)
our @SPINNER_CHARS = qw(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏);

# Global verbosity level (0 = quiet, 1 = default, 2+ = verbose)
our $VERBOSITY = 1;

=head1 NAME

GitBz::Progress - Progress indicators and feedback for GitBz

=head1 SYNOPSIS

    use GitBz::Progress;

    # Show animated spinner during a long operation
    my $spinner = GitBz::Progress::start_spinner("Fetching bug data");
    # ... do work ...
    GitBz::Progress::stop_spinner($spinner, "success");  # or "error"

    # Automatic spinner with code block
    my $result = GitBz::Progress::with_spinner("Fetching bug", sub {
        # ... do work ...
        return $data;
    });

    # Show real-time progress
    GitBz::Progress::print_success("Attached patch successfully");
    GitBz::Progress::print_error("Failed to upload");

=head1 DESCRIPTION

Provides consistent progress indicators with animated spinners and colored
output for GitBz commands. Uses fork-based spinners to animate during
blocking operations.

=cut

=head2 set_verbosity

Set the global verbosity level for progress output.
- 0: Quiet (minimal output)
- 1: Default (spinners and line replacement)
- 2+: Verbose (each step on new line)

    GitBz::Progress::set_verbosity($level);

=cut

sub set_verbosity {
    my ($level) = @_;
    $VERBOSITY = $level // 1;
}

=head2 get_verbosity

Get the current global verbosity level.

    my $level = GitBz::Progress::get_verbosity();

=cut

sub get_verbosity {
    return $VERBOSITY;
}

=head2 start_spinner

Start an animated spinner with a message.

    my $spinner = GitBz::Progress::start_spinner("Loading...");

Returns a spinner object that should be passed to stop_spinner().
The spinner runs in a background process and animates automatically.

=cut

sub start_spinner {
    my ($message) = @_;

    # Check if output is to a terminal
    my $is_tty = -t STDOUT;

    if ( !$is_tty ) {

        # For non-TTY, just print message
        print "$message...";
        return {
            message => $message,
            is_tty  => 0,
        };
    }

    # Fork a process to animate the spinner
    my $pid = fork();

    if ( !defined $pid ) {

        # Fork failed, fall back to simple message
        print colored( ['cyan'], "$message..." );
        STDOUT->flush();
        return {
            message => $message,
            is_tty  => 1,
            pid     => undef,
        };
    }

    if ( $pid == 0 ) {

        # Child process - animate the spinner
        my $frame = 0;
        while (1) {
            my $spinner_char = $SPINNER_CHARS[ $frame % @SPINNER_CHARS ];
            print "\r" . "  " . colored( ['cyan'], $spinner_char ) . " $message...";
            STDOUT->flush();
            usleep(80_000);    # 80ms between frames
            $frame++;
        }

        # Never reaches here, parent will kill us
        exit 0;
    }

    # Parent process - return spinner info
    return {
        message    => $message,
        is_tty     => $is_tty,
        pid        => $pid,
        start_time => time(),
    };
}

=head2 stop_spinner

Stop an animated spinner and show completion status.

    GitBz::Progress::stop_spinner($spinner, "success");
    GitBz::Progress::stop_spinner($spinner, "error", "Connection failed");

First parameter: spinner object from start_spinner()
Second parameter: "success" or "error"
Third parameter (optional): custom message

=cut

sub stop_spinner {
    my ( $spinner_obj, $status, $custom_message ) = @_;

    my $message = $custom_message || $spinner_obj->{message};

    # Kill the spinner process if it exists
    if ( $spinner_obj->{pid} ) {
        kill 'TERM', $spinner_obj->{pid};
        waitpid( $spinner_obj->{pid}, 0 );
    }

    if ( !$spinner_obj->{is_tty} ) {

        # Not a terminal, just print status
        if ( $status eq 'success' ) {
            print " " . colored( ['green'], '✓' ) . "\n";
        } else {
            print " " . colored( ['red'], '✗' ) . "\n";
        }
        return;
    }

    # For terminal: clear the line and print final status
    print "\r\e[K";

    if ( $status eq 'success' ) {
        print colored( ['green'], '  ✓ ' ) . "$message\n";
    } else {
        print colored( ['red'], '  ✗ ' ) . "$message\n";
    }
}

=head2 print_success

Print a success message with a green checkmark.

    GitBz::Progress::print_success("Attached: patch-name.patch");

=cut

sub print_success {
    my ($message) = @_;
    print colored( ['green'], '  ✓ ' ) . "$message\n";
}

=head2 print_error

Print an error message with a red X.

    GitBz::Progress::print_error("Failed to upload attachment");

=cut

sub print_error {
    my ($message) = @_;
    print colored( ['red'], '  ✗ ' ) . "$message\n";
}

=head2 print_info

Print an informational message.

    GitBz::Progress::print_info("Processing 5 patches...");

=cut

sub print_info {
    my ($message) = @_;
    print colored( ['blue'], '  ℹ ' ) . "$message\n";
}

=head2 print_warning

Print a warning message with a yellow warning symbol.

    GitBz::Progress::print_warning("Bug number mismatch detected");

=cut

sub print_warning {
    my ($message) = @_;
    print colored( ['yellow'], '  ⚠ ' ) . "$message\n";
}

=head2 progress_counter

Format a progress counter string.

    my $counter = GitBz::Progress::progress_counter(3, 10);
    # Returns: "[3/10]"

=cut

sub progress_counter {
    my ( $current, $total ) = @_;
    return colored( ['cyan'], sprintf( "[%d/%d]", $current, $total ) );
}

=head2 with_spinner

Execute a code block with an animated spinner.
Uses global verbosity level to determine whether to show the spinner.

    my $result = GitBz::Progress::with_spinner("Fetching bug", sub {
        # ... do work ...
        return $data;
    });

Returns the return value from the code block.
If the code throws an exception, the spinner is stopped with error status
and the exception is re-thrown.

=cut

sub with_spinner {
    my ( $message, $code ) = @_;

    # Level 0: quiet mode, just execute without spinner
    if ( $VERBOSITY == 0 ) {
        return $code->();
    }

    # Levels 1+: show spinner
    my $spinner = start_spinner($message);

    my $result;
    my $success = eval {
        $result = $code->();
        1;
    };

    if ($@) {
        my $error = $@;
        stop_spinner( $spinner, 'error' );
        die $error;
    }

    stop_spinner( $spinner, 'success' );
    return $result;
}

=head2 update_progress_line

Update a progress line based on global verbosity level.
- Level 0: No output
- Level 1: Update line in place (default)
- Level 2+: Print each line

    GitBz::Progress::update_progress_line("[1/10] Processing patch");

=cut

sub update_progress_line {
    my ($message) = @_;

    my $is_tty = -t STDOUT;

    # Level 0: quiet mode, no output
    return if $VERBOSITY == 0;

    # Level 2+: verbose mode or non-TTY: print each line
    if ( $VERBOSITY >= 2 || !$is_tty ) {
        print "  ✓ $message\n";
    } else {
        # Level 1 with TTY: clear line and print new status
        print "\r\e[K";
        print colored( ['green'], '  ✓ ' ) . "$message";
        STDOUT->flush();
    }
}

=head2 finalize_progress_line

Finalize the last progress line (ensure newline is printed at verbosity level 1).
Uses global verbosity level.

    GitBz::Progress::finalize_progress_line();

=cut

sub finalize_progress_line {
    my $is_tty = -t STDOUT;

    # Only print newline if we were updating in place (level 1 with TTY)
    if ( $VERBOSITY == 1 && $is_tty ) {
        print "\n";
    }
}

1;

__END__

=head1 AUTHOR

Martin Renvoize

=head1 LICENSE

This is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
