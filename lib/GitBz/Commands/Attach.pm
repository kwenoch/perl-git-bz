package GitBz::Commands::Attach;

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

GitBz::Commands::Attach - Attach Git commits as patches to Bugzilla bugs

=head1 SYNOPSIS

    git bz attach [options] [<bug-ref>] <commit-range>
    git bz attach --edit 12345 HEAD~2..HEAD
    git bz attach --yes HEAD                     # Skip confirmation prompts
    git bz attach HEAD                           # Extracts bug ref from commit message
    git bz attach --no-comment HEAD              # Attach without adding a comment
    git bz attach --obsolete-comments HEAD       # Hide comments for obsoleted patches

=head1 DESCRIPTION

Attaches Git commits as patch files to Bugzilla bugs.
Supports interactive editing of bug fields and attachment metadata.

=cut

use Modern::Perl;

use utf8;
no warnings 'utf8';
use open ':std', ':utf8';

use Getopt::Long qw(GetOptionsFromArray);
use Try::Tiny    qw(catch try);
use File::Temp;

use GitBz::Git;
use GitBz::Exception;
use GitBz::StatusWorkflow;
use GitBz::Bug;
use GitBz::Progress;
use GitBz::Template;

=head2 new

    my $attach = GitBz::Commands::Attach->new($commands);

Constructor.

=cut

sub new {
    my ( $class, $commands ) = @_;
    bless {
        commands => $commands,
        client   => $commands->{client}
    }, $class;
}

=head2 execute

    $attach->execute(@args);

Main entry point for the attach command.

=cut

sub execute {
    my ( $self, @args ) = @_;

    # Ensure UTF-8 output for this command
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    my %opts;

    GetOptionsFromArray(
        \@args,
        'edit|e'           => \$opts{edit},
        'yes|y'            => \$opts{yes},
        'verbose=i'        => \$opts{verbose},
        'no-comment'       => \$opts{no_comment},
        'obsolete-comments' => \$opts{obsolete_comments},
    ) or GitBz::Exception->throw("Invalid options");

    # Set verbosity level: 0 (quiet), 1 (default), 2 (verbose)
    # Command line flag takes precedence, then config, then default to 1
    unless ( defined $opts{verbose} ) {
        my $config_verbose = GitBz::Config->get( 'bz.verbose', '1' );
        chomp $config_verbose;
        $opts{verbose} = $config_verbose =~ /^\d+$/ ? $config_verbose : 1;
    }

    # Set global verbosity for Progress module
    GitBz::Progress::set_verbosity( $opts{verbose} );

    return try {
        my ( $bug_ref, $commit_range ) = $self->parse_args(@args);
        my @commits = GitBz::Git->get_commits($commit_range);

        GitBz::Exception->throw("No commits found") unless @commits;

        $self->attach_patches( $bug_ref, \@commits, \%opts );

        my $patch_word = @commits == 1 ? "patch" : "patches";
        print "\n";  # Add spacing before top-level result
        GitBz::Progress::print_success("Successfully attached " . scalar(@commits) . " $patch_word to bug $bug_ref", 0);
    } catch {
        GitBz::Exception->throw("Attach failed: $_");
    };
}

=head2 parse_args

    my ($bug_ref, $commit_range) = $attach->parse_args(@args);

Parses command line arguments to extract bug reference and commit range.

=cut

sub parse_args {
    my ( $self, @args ) = @_;

    GitBz::Exception->throw("Usage: git bz attach [options] [<bug-ref>] <commit-range>")
        unless @args >= 1 && @args <= 2;

    if ( @args == 1 ) {

        # Try to extract bug reference from commit message
        my @commits = GitBz::Git->get_commits( $args[0] );
        my $bug_ref = $self->extract_bug_ref( $commits[0] );
        GitBz::Exception->throw("No bug reference found in commit message") unless $bug_ref;
        return ( $bug_ref, $args[0] );
    } else {
        return ( $args[0], $args[1] );
    }
}

=head2 extract_bug_ref

    my $bug_ref = $attach->extract_bug_ref($commit);

Extracts bug reference from commit message.

=cut

sub extract_bug_ref {
    my ( $self, $commit ) = @_;

    my $message = GitBz::Git->run( 'log', '--format=%B', '-1', $commit->{id} );

    # Look for Bug NNNN or bug NNNN
    if ( $message =~ /\b[Bb]ug\s+(\d+)\b/ ) {
        return $1;
    }

    return;
}

=head2 preflight_checks

    $attach->preflight_checks($bug_ref, \@commits);

Performs preflight checks before attaching patches.

=cut

sub preflight_checks {
    my ( $self, $bug_ref, $commits ) = @_;

    my @mismatched_bugs;

    for my $commit (@$commits) {
        my $commit_bug_ref = $self->extract_bug_ref($commit);
        if ( $commit_bug_ref && $commit_bug_ref ne $bug_ref ) {
            push @mismatched_bugs, {
                commit  => substr( $commit->{id}, 0, 7 ),
                subject => $commit->{subject},
                bug_ref => $commit_bug_ref
            };
        }
    }

    if (@mismatched_bugs) {
        print "\n🚨 ALERT: Bug number mismatch detected!\n";
        print "Attaching to bug $bug_ref, but found commits with different bug numbers:\n\n";

        for my $mismatch (@mismatched_bugs) {
            print "  $mismatch->{commit}: $mismatch->{subject}\n";
            print "    → References bug $mismatch->{bug_ref} (not $bug_ref)\n\n";
        }

        print "Continue anyway? [y/N]: ";
        my $response = <STDIN>;
        chomp $response;

        unless ( $response =~ /^[yY]/ ) {
            GitBz::Exception->throw("Aborted due to bug number mismatch\n");
        }
    }
}

=head2 confirm_attachment

    $attach->confirm_attachment($bug_ref, \@commits);

Shows confirmation prompt before attaching patches.

=cut

sub confirm_attachment {
    my ( $self, $bug_ref, $commits ) = @_;

    print "\nReady to attach " . scalar(@$commits) . " patch(es) to bug $bug_ref:\n\n";

    for my $commit (@$commits) {
        print "  " . substr( $commit->{id}, 0, 7 ) . ": $commit->{subject}\n";
    }

    print "\nProceed with attachment? [Y/n]: ";
    my $response = <STDIN>;
    chomp $response;

    if ( $response =~ /^[nN]/ ) {
        GitBz::Exception->throw("Attachment cancelled by user\n");
    }
}

=head2 check_missing_sponsors

    $attach->check_missing_sponsors($bug, \@commits);

Checks if bug has sponsors that aren't in any commit trailers.
Offers to add missing sponsors to commits.

=cut

sub check_missing_sponsors {
    my ( $self, $bug, $commits ) = @_;

    # Get sponsors from bug
    my $bug_sponsors_str = $bug->cf_sponsors || '';
    return unless $bug_sponsors_str;

    # Parse bug sponsors into a set
    my %bug_sponsors;
    for my $sponsor ( split /,/, $bug_sponsors_str ) {
        $sponsor =~ s/^\s+|\s+$//g;
        $bug_sponsors{$sponsor} = 1 if $sponsor;
    }

    return unless %bug_sponsors;

    # Get all sponsors from commits
    my %commit_sponsors;
    for my $commit (@$commits) {
        my @sponsors = GitBz::Git->get_sponsors( $commit->{id} );
        for my $sponsor (@sponsors) {
            $commit_sponsors{$sponsor} = 1;
        }
    }

    # Find sponsors in bug but not in any commit
    my @missing_sponsors;
    for my $sponsor ( sort keys %bug_sponsors ) {
        unless ( $commit_sponsors{$sponsor} ) {
            push @missing_sponsors, $sponsor;
        }
    }

    return unless @missing_sponsors;

    # Alert user about missing sponsors
    print "\n⚠️  Bug " . $bug->id . " has sponsors not in commit trailers:\n";
    for my $sponsor (@missing_sponsors) {
        print "  • $sponsor\n";
    }
    print "\nWould you like to add these sponsors to commit trailers? [y/N]: ";
    my $response = <STDIN>;
    chomp $response;

    return unless $response =~ /^[yY]/;

    # Show picklist of commits
    print "\nSelect commits to add sponsors to:\n";
    my @selected_commits;

    for my $i ( 0 .. $#$commits ) {
        my $commit = $commits->[$i];
        print "\n[$i] " . substr( $commit->{id}, 0, 7 ) . ": $commit->{subject}\n";

        # Show existing sponsors for this commit
        my @existing = GitBz::Git->get_sponsors( $commit->{id} );
        if (@existing) {
            print "    Current sponsors: " . join( ', ', @existing ) . "\n";
        }

        print "    Add missing sponsors to this commit? [y/N]: ";
        my $commit_response = <STDIN>;
        chomp $commit_response;

        if ( $commit_response =~ /^[yY]/ ) {
            push @selected_commits, $commit;
        }
    }

    return unless @selected_commits;

    # Add trailers to selected commits
    print "\n";
    my $commits_modified = 0;

    for my $commit (@selected_commits) {
        my $commit_msg = GitBz::Git->run( 'log', '--format=%B', '-1', $commit->{id} );

        # Add each missing sponsor as a trailer
        for my $sponsor (@missing_sponsors) {
            $commit_msg = GitBz::Git->add_trailer_to_commit( $commit->{id}, 'Sponsored-by', $sponsor );
        }

        # Check if this is HEAD and can be amended
        my $head_id = GitBz::Git->run( 'rev-parse', 'HEAD' );
        chomp $head_id;

        if ( $commit->{id} eq $head_id || $head_id =~ /^$commit->{id}/ ) {
            GitBz::Git->amend_commit_message( $commit->{id}, $commit_msg );
            print "✓ Added sponsors to commit " . substr( $commit->{id}, 0, 7 ) . "\n";
            $commits_modified++;
        } else {
            print "⚠️  Cannot modify commit " . substr( $commit->{id}, 0, 7 ) . " (not HEAD)\n";
            print "   Use 'git rebase -i' to modify older commits manually\n";
        }
    }

    if ($commits_modified) {
        print "\n✓ Modified $commits_modified commit(s)\n";
        print "Note: If attaching a range, you may need to update the commit references\n\n";
    }
}

=head2 attach_patches

    $attach->attach_patches($bug_ref, \@commits, \%opts);

Attaches commit patches to the specified bug.

=cut

sub attach_patches {
    my ( $self, $bug_ref, $commits, $opts ) = @_;

    my $client = $self->{client};

    # Fetch bug with spinner
    my $bug = GitBz::Progress::with_spinner(
        "Fetching bug $bug_ref",
        sub {
            return GitBz::Bug->get( $client, $bug_ref );
        },
        1
    );

    # Preflight checks
    $self->preflight_checks( $bug_ref, $commits );

    # Check for missing sponsors and offer to add them
    $self->check_missing_sponsors( $bug, $commits ) unless $opts->{yes};

    # Show confirmation prompt
    $self->confirm_attachment( $bug_ref, $commits ) unless $opts->{yes};

    # Handle edit mode - bug-level updates only, not per-commit
    my %bug_updates;
    my @obsoletes_list;

    if ( $opts->{edit} ) {
        ( my $bug_comment, my $obsoletes_ref, my $updates_ref ) = $self->edit_bug_updates( $bug, $commits );
        @obsoletes_list = @$obsoletes_ref if $obsoletes_ref;
        %bug_updates    = %$updates_ref   if $updates_ref;
    } else {

        # Non-interactive mode - auto-obsolete matching patches
        @obsoletes_list = $self->find_trivial_obsoletes( $bug, $commits, $opts->{yes} );
    }

    # Apply bug updates BEFORE uploading patches
    if ( %bug_updates || @obsoletes_list ) {
        print "\nUpdating bug:\n";

        # Queue field updates
        $bug->set_field( 'status',              $bug_updates{status} ) if $bug_updates{status};
        $bug->set_field( 'qa_contact',          $bug_updates{qa_contact} ) if exists $bug_updates{qa_contact};
        $bug->set_field( 'assigned_to',         $bug_updates{assigned_to} ) if exists $bug_updates{assigned_to};
        $bug->set_field( 'cf_patch_complexity', $bug_updates{cf_patch_complexity} )
            if $bug_updates{cf_patch_complexity};
        $bug->set_sponsors( %{ $bug_updates{cf_sponsors} } )              if $bug_updates{cf_sponsors};
        $bug->set_field( 'cf_sponsorship', $bug_updates{cf_sponsorship} ) if $bug_updates{cf_sponsorship};
        $bug->add_comment( $bug_updates{comment}{body} )                  if $bug_updates{comment};
        $bug->set_depends( %{ $bug_updates{depends_on} } )                if $bug_updates{depends_on};

        # Validate QA contact BEFORE starting spinner or making any API calls
        if ( exists $bug_updates{qa_contact} ) {
            my $validated_email = $bug->validate_qa_contact_with_lookup( $client, $bug_updates{qa_contact} );

            # Update the queued value with validated email
            $bug->{_pending_updates}{qa_contact} = $validated_email;
        }

        # Validate assignee BEFORE starting spinner or making any API calls
        if ( exists $bug_updates{assigned_to} ) {
            my $validated_email = $bug->validate_assignee_with_lookup( $client, $bug_updates{assigned_to} );

            # Update the queued value with validated email
            $bug->{_pending_updates}{assigned_to} = $validated_email;
        }

        # Apply updates with spinner
        if (%bug_updates) {
            # Display changes before spinner (apply_updates will skip display since rows are already cleared)
            $bug->_display_changes();
            my $spinner = GitBz::Progress::start_spinner("Updating bug fields");

            my $update_success = eval {
                $bug->apply_updates();
                1;
            };

            if ($@) {
                my $error = $@;
                GitBz::Progress::stop_spinner( $spinner, 'error' );
                die $error;
            } else {
                GitBz::Progress::stop_spinner( $spinner, 'success', "Bug fields updated" );
            }
        }

        # Perform obsoletes in a single batch API call
        if (@obsoletes_list) {
            my $attachments   = $bug->attachments;
            my %attach_lookup = map { $_->{id} => $_->{summary} } @$attachments;

            my $label = @obsoletes_list == 1
                ? "Obsoleting attachment $obsoletes_list[0]"
                : "Obsoleting " . scalar(@obsoletes_list) . " attachments";
            my $spinner = GitBz::Progress::start_spinner($label);
            $bug->obsolete_attachments(@obsoletes_list);
            my $summary = join( ", ", map { $attach_lookup{$_} || $_ } @obsoletes_list );
            GitBz::Progress::stop_spinner( $spinner, 'success', "Obsoleted: $summary" );

            if ( $opts->{obsolete_comments} ) {
                my $spinner2 = GitBz::Progress::start_spinner("Tagging comments for obsoleted patches");
                my @tagged   = $bug->obsolete_comments_for_attachments(@obsoletes_list);
                if (@tagged) {
                    GitBz::Progress::stop_spinner( $spinner2, 'success',
                        "Tagged " . scalar(@tagged) . " comment(s) as obsolete" );
                } else {
                    GitBz::Progress::stop_spinner( $spinner2, 'success', "No matching comments found" );
                }
            }
        }
    }

    # Show progress header
    my $patch_word = @$commits == 1 ? "patch" : "patches";
    GitBz::Progress::print_section("Uploading " . scalar(@$commits) . " $patch_word");

    my $patch_num     = 0;
    my $total_patches = scalar(@$commits);

    for my $commit (@$commits) {
        $patch_num++;
        my $filename    = sprintf( "%s.patch", substr( $commit->{id}, 0, 7 ) );
        my $description = $commit->{subject};

        # Show progress counter
        my $counter = GitBz::Progress::progress_counter( $patch_num, $total_patches );

        # Generate patch with spinner
        my $spinner = GitBz::Progress::start_spinner("$counter Generating $filename");
        my $patch   = GitBz::Git->format_patch( $commit->{id} . '^..' . $commit->{id} );
        my $body    = GitBz::Git->run( 'log', '--format=%b', '-1', $commit->{id} );
        GitBz::Progress::stop_spinner( $spinner, 'success', undef, 1 );

        my $comment = $opts->{no_comment} ? undef : $body;

        # Upload patch with spinner
        $spinner = GitBz::Progress::start_spinner("$counter Uploading: $description");

        eval {
            $bug->add_attachment(
                $patch,
                $filename,
                $description,
                comment => $comment,
            );
        };

        if ($@) {
            GitBz::Progress::stop_spinner( $spinner, 'error' );
            GitBz::Progress::print_error("Failed to attach: $description", 2);
            GitBz::Progress::print_info("Error: $@", 3);
            return;    # Skip remaining steps
        }

        GitBz::Progress::stop_spinner( $spinner, 'success', "Attached: $description" );
    }
}

=head2 find_trivial_obsoletes

    my @obsoletes = $attach->find_trivial_obsoletes($bug, \@commits, $auto_yes);

Finds patches that should be automatically obsoleted based on matching commit subjects.
Auto-obsoletes exact matches, prompts for confirmation on non-matching patches unless --yes is used.
Options at the prompt: (o)bsolete, (s)kip, skip (a)ll remaining, (c)ancel.

=cut

sub find_trivial_obsoletes {
    my ( $self, $bug, $commits, $auto_yes ) = @_;

    my $attachments = $bug->attachments;
    return () unless $attachments && @$attachments;

    # Build list of commit subjects for matching
    my %commit_subjects = map { $_->{subject} => 1 } @$commits;

    my @auto_obsoletes;
    my @manual_obsoletes;

    for my $patch (@$attachments) {
        next unless $patch->{is_patch} && !$patch->{is_obsolete};

        # Auto-obsolete if commit subject matches patch summary exactly
        if ( $commit_subjects{ $patch->{summary} } ) {
            push @auto_obsoletes, $patch->{id};
        } else {

            # Potential candidate for manual obsoleting
            push @manual_obsoletes, $patch;
        }
    }

    # Handle manual obsoletes with confirmation (unless --yes flag is used)
    my @confirmed_obsoletes;
    if ( @manual_obsoletes && !$auto_yes ) {
        my $skip_all = 0;
        for my $patch (@manual_obsoletes) {
            next if $skip_all;

            print "Patch attachment found: $patch->{id} - $patch->{summary}\n";
            print "This doesn't match any new commit. What would you like to do?\n";
            print "(o)bsolete, (s)kip, skip (a)ll remaining, (c)ancel: ";

            my $choice = <STDIN>;
            chomp $choice;
            $choice = lc($choice);

            if ( $choice eq 'o' || $choice eq 'obsolete' ) {
                push @confirmed_obsoletes, $patch->{id};
            } elsif ( $choice eq 'a' || $choice eq 'all' ) {
                $skip_all = 1;
            } elsif ( $choice eq 'c' || $choice eq 'cancel' ) {
                GitBz::Exception->throw("Operation cancelled by user\n");
            }

            # 's' or 'skip' - do nothing, continue to next patch
        }
    }

    return ( @auto_obsoletes, @confirmed_obsoletes );
}

=head2 edit_bug_updates

    my ($bug_comment, $obsoletes, $updates) = 
        $attach->edit_bug_updates($bug, \@commits);

Provides interactive editing of bug fields and optional comment.

=cut

sub edit_bug_updates {
    my ( $self, $bug, $commits ) = @_;

    my $client = $self->{client};

    my $template = "";
    $template .= "# Bug Update for Bug " . $bug->id . " - " . $bug->summary . "\n\n";

    # Show commits being attached as reference
    $template .= "# Commits being attached:\n";
    my %all_sponsors;
    for my $commit (@$commits) {
        $template .= "# " . substr( $commit->{id}, 0, 7 ) . ": $commit->{subject}\n";

        # Extract and show sponsors for this commit
        my @sponsors = GitBz::Git->get_sponsors( $commit->{id} );
        if (@sponsors) {
            for my $sponsor (@sponsors) {
                $template .= "#   Sponsored-by: $sponsor\n";
                $all_sponsors{$sponsor} = 1;
            }
        }
    }
    $template .= "\n";

    # Add optional bug comment section
    $template .= "# Add optional bug comment below (leave empty for no comment):\n\n\n";

    # Show existing patches for obsoleting
    my $attachments = GitBz::Progress::with_spinner(
        "Fetching attachments",
        sub {
            return $bug->attachments;
        },
        1
    );

    # Add bug field sections (including obsoletes)
    $template .= GitBz::Template::generate_bug_fields(
        $bug, $client,
        all_sponsors => \%all_sponsors,
        attachments  => $attachments,
        commits      => $commits
    );

    $template .= "# Please edit the description (first line) and comment (other lines).\n";
    $template .= "# Lines starting with '#' will be ignored. Delete everything to abort.\n";
    $template .= "# To obsolete existing patches, uncomment the appropriate lines.\n";

    my $edited = $self->edit_template($template);

    # If user cleared the file (empty or only whitespace), treat as cancel
    GitBz::Exception->throw("Attachment cancelled by user\n")
        unless $edited =~ /\S/;

    return $self->parse_bug_updates( $edited, $bug );
}

=head2 edit_template

    my $edited_content = $attach->edit_template($template);

Opens an editor for the user to modify the template.

=cut

sub edit_template {
    my ( $self, $template ) = @_;

    my $temp = File::Temp->new( SUFFIX => '.txt' );
    binmode $temp, ':utf8';
    print $temp $template;
    close $temp;

    my $editor = $ENV{EDITOR} || $ENV{GIT_EDITOR} || 'vi';
    system( $editor, $temp->filename );

    open my $fh, '<:utf8', $temp->filename or die "Cannot read temp file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    return $content;
}

=head2 parse_bug_updates

    my ($bug_comment, $obsoletes, $updates) = 
        $attach->parse_bug_updates($edited_content, $bug);

Parses the edited template content and extracts bug-level changes.

=cut

sub parse_bug_updates {
    my ( $self, $content, $bug ) = @_;

    my @lines = split /\n/, $content;
    my @non_comment_lines = grep { !/^#/ } @lines;

    my @obsoletes;
    my @bug_comment_lines;

    # Parse obsoletes and collect comment lines
    for my $line (@non_comment_lines) {
        if ( $line =~ /^\s*Obsoletes\s*:\s*(\d+)/ ) {
            push @obsoletes, $1;
        } elsif ( $line !~ /^\s*(Status|Patch-complexity|Sponsors|Sponsorship|Depends|QA-contact|Assignee)\s*:/ ) {
            # Everything else is bug-level comment
            push @bug_comment_lines, $line;
        }
    }

    my $bug_comment = join( "\n", @bug_comment_lines );
    $bug_comment =~ s/^\s+//;    # Remove leading whitespace
    $bug_comment =~ s/\s+$//;    # Remove trailing whitespace

    # Parse bug field updates using Template module
    my $bug_updates = GitBz::Template::parse_bug_fields( $content, $bug );

    if ($bug_comment) {
        $bug_updates->{comment} = { body => $bug_comment };
    }

    return ( $bug_comment, \@obsoletes, $bug_updates );
}

1;
