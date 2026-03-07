package GitBz::Commands::Create;

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

GitBz::Commands::Create - Submit a new bug report to Bugzilla

=head1 SYNOPSIS

    git bz create --summary "Title" --desc "Description" \
                  --product "Koha" --comp "OPAC" --version "master" \
                  --severity "normal" --depends "12345" --blocks "67890"
    git bz create --summary "Title" ... --dry-run
    git bz create --summary "Title" ... --non-interactive --json

=head1 DESCRIPTION

Creates a new Bugzilla bug report from the command line. Supports dry-run mode
for duplicate detection and non-interactive mode for use in scripts and AI agents.

=cut

use Modern::Perl;

use Getopt::Long qw(GetOptionsFromArray);
use Try::Tiny    qw(catch try);
use File::Temp;
use JSON;

use GitBz::Exception;
use GitBz::Progress;

# Standard Bugzilla severity values (used for interactive pick-list)
my @SEVERITY_VALUES = qw(blocker critical major normal minor trivial enhancement);

=head2 new

    my $create = GitBz::Commands::Create->new($commands);

Constructor.

=cut

sub new {
    my ( $class, $commands ) = @_;
    bless {
        commands => $commands,
        client   => $commands->{client},
    }, $class;
}

=head2 execute

    $create->execute(@args);

Main entry point for the create command.

=cut

sub execute {
    my ( $self, @args ) = @_;

    my %opts;
    GetOptionsFromArray(
        \@args,
        'summary=s'       => \$opts{summary},
        'desc=s'          => \$opts{desc},
        'product=s'       => \$opts{product},
        'comp=s'          => \$opts{comp},
        'version=s'       => \$opts{version},
        'severity=s'      => \$opts{severity},
        'depends=s'       => \$opts{depends},
        'blocks=s'        => \$opts{blocks},
        'dry-run'         => \$opts{dry_run},
        'non-interactive' => \$opts{non_interactive},
        'json'            => \$opts{json},
        'yes|y'           => \$opts{yes},
    ) or GitBz::Exception->throw("Invalid options");

    if ( $opts{dry_run} ) {
        return $self->_run_dry_run( \%opts );
    }

    return $self->_run_create( \%opts );
}

=head2 _run_dry_run

    $create->_run_dry_run(\%opts);

Validates fields and searches for potential duplicates without creating the bug.

=cut

sub _run_dry_run {
    my ( $self, $opts ) = @_;

    my $client = $self->{client};

    my @missing;
    push @missing, 'summary' unless $opts->{summary};
    push @missing, 'desc'    unless $opts->{desc};
    push @missing, 'product' unless $opts->{product};
    push @missing, 'comp'    unless $opts->{comp};
    push @missing, 'version' unless $opts->{version};

    my $duplicates = [];
    if ( $opts->{summary} ) {
        $duplicates = eval { $client->search_bugs( $opts->{summary} ) } || [];
    }

    if ( $opts->{json} ) {
        print encode_json(
            {
                duplicates     => $duplicates,
                missing_fields => \@missing,
            }
        ) . "\n";
    } else {
        if (@$duplicates) {
            print "Potential duplicates:\n";
            for my $bug (@$duplicates) {
                print "  Bug $bug->{id} - $bug->{summary} [$bug->{status}]\n";
            }
        } else {
            print "Potential duplicates: (none)\n";
        }
        print "\n";
        if (@missing) {
            print "Missing fields: " . join( ', ', @missing ) . "\n";
        } else {
            print "Missing fields: (none)\n";
        }
    }
}

=head2 _run_create

    $create->_run_create(\%opts);

Validates, prompts if interactive, confirms, and creates the bug.

=cut

sub _run_create {
    my ( $self, $opts ) = @_;

    my $client = $self->{client};

    my @missing;
    push @missing, 'summary' unless $opts->{summary};
    push @missing, 'desc'    unless $opts->{desc};
    push @missing, 'product' unless $opts->{product};
    push @missing, 'comp'    unless $opts->{comp};
    push @missing, 'version' unless $opts->{version};

    if (@missing) {
        if ( $opts->{non_interactive} ) {
            my $msg = "Missing required fields: " . join( ', ', @missing );
            if ( $opts->{json} ) {
                print encode_json( { status => 'error', message => $msg } ) . "\n";
            }
            GitBz::Exception->throw($msg);
        }

        $self->_prompt_missing_fields($opts);
    }

    # Confirm before creating (unless --yes or --non-interactive)
    unless ( $opts->{yes} || $opts->{non_interactive} ) {
        print "\nReady to create bug:\n";
        print "  Product:    $opts->{product}\n";
        print "  Component:  $opts->{comp}\n";
        print "  Version:    $opts->{version}\n";
        print "  Severity:   $opts->{severity}\n" if $opts->{severity};
        print "  Summary:    $opts->{summary}\n";
        print "  Depends on: $opts->{depends}\n"  if $opts->{depends};
        print "  Blocks:     $opts->{blocks}\n"   if $opts->{blocks};
        print "\nProceed? [Y/n]: ";
        my $response = <STDIN>;
        chomp $response;
        if ( $response =~ /^[nN]/ ) {
            print "Cancelled.\n";
            return;
        }
    }

    my %bug_params = (
        summary     => $opts->{summary},
        description => $opts->{desc},
        product     => $opts->{product},
        component   => $opts->{comp},
        version     => $opts->{version},
    );
    $bug_params{severity}   = $opts->{severity} if $opts->{severity};
    $bug_params{depends_on} = [ split /\s*,\s*/, $opts->{depends} ] if $opts->{depends};
    $bug_params{blocks}     = [ split /\s*,\s*/, $opts->{blocks} ]  if $opts->{blocks};

    try {
        my $result = GitBz::Progress::with_spinner(
            "Creating bug",
            sub { $client->create_bug(%bug_params) },
            1
        );

        my $bug_id  = $result->{id};
        my $bug_url = $client->get_bug_url($bug_id);

        if ( $opts->{json} ) {
            print encode_json( { status => 'ok', id => $bug_id, url => $bug_url } ) . "\n";
        } else {
            GitBz::Progress::print_success( "Bug $bug_id created: $bug_url", 0 );
        }
    } catch {
        my $error = $_;
        if ( $opts->{json} ) {
            $self->_json_error( $opts, $error );
        }
        GitBz::Exception->throw("$error");
    };
}

=head2 _prompt_missing_fields

    $create->_prompt_missing_fields(\%opts);

Interactively prompts for any fields not already set in C<%opts>, in this
order: product, component, version, severity, summary, description, depends on,
blocks. Fields with known accepted values (product, component, version,
severity) offer a numbered pick-list; the user may also type a value freehand.
Depends-on and blocks accept a comma-separated list of bug IDs and may be left
empty.

=cut

sub _prompt_missing_fields {
    my ( $self, $opts ) = @_;

    my $client = $self->{client};

    # Fetch product data once if we'll need it for product / comp / version
    my $products_data = undef;
    if ( !$opts->{product} || !$opts->{comp} || !$opts->{version} ) {
        $products_data = GitBz::Progress::with_spinner(
            "Fetching available products",
            sub { eval { $client->get_products() } || [] },
            1
        );
    }

    my %product_by_name = map { $_->{name} => $_ } @{ $products_data || [] };

    # --- Product ---
    unless ( $opts->{product} ) {
        my @products = @{ $products_data || [] };
        if (@products) {
            print "\nSelect product:\n";
            for my $i ( 0 .. $#products ) {
                printf "  %2d) %s\n", $i + 1, $products[$i]{name};
            }
            print "Choice (number or name): ";
            my $input = <STDIN>;
            chomp $input;
            $opts->{product} =
                ( $input =~ /^\d+$/ && $input >= 1 && $input <= @products )
                ? $products[ $input - 1 ]{name}
                : $input;
        } else {
            print "Enter product: ";
            my $v = <STDIN>;
            chomp $v;
            $opts->{product} = $v;
        }
    }

    my $current_product = $product_by_name{ $opts->{product} };

    # --- Component ---
    unless ( $opts->{comp} ) {
        my @comps = @{ $current_product->{components} || [] };
        if (@comps) {
            print "\nSelect component:\n";
            for my $i ( 0 .. $#comps ) {
                printf "  %2d) %s\n", $i + 1, $comps[$i];
            }
            print "Choice (number or name): ";
            my $input = <STDIN>;
            chomp $input;
            $opts->{comp} =
                ( $input =~ /^\d+$/ && $input >= 1 && $input <= @comps )
                ? $comps[ $input - 1 ]
                : $input;
        } else {
            print "Enter component: ";
            my $v = <STDIN>;
            chomp $v;
            $opts->{comp} = $v;
        }
    }

    # --- Version ---
    unless ( $opts->{version} ) {
        my @versions = @{ $current_product->{versions} || [] };
        if (@versions) {
            print "\nSelect version:\n";
            for my $i ( 0 .. $#versions ) {
                printf "  %2d) %s\n", $i + 1, $versions[$i];
            }
            print "Choice (number or name): ";
            my $input = <STDIN>;
            chomp $input;
            $opts->{version} =
                ( $input =~ /^\d+$/ && $input >= 1 && $input <= @versions )
                ? $versions[ $input - 1 ]
                : $input;
        } else {
            print "Enter version: ";
            my $v = <STDIN>;
            chomp $v;
            $opts->{version} = $v;
        }
    }

    # --- Severity (optional, pick-list) ---
    unless ( $opts->{severity} ) {
        print "\nSelect severity:\n";
        for my $i ( 0 .. $#SEVERITY_VALUES ) {
            printf "  %2d) %s\n", $i + 1, $SEVERITY_VALUES[$i];
        }
        print "Choice (number or name, Enter to skip): ";
        my $input = <STDIN>;
        chomp $input;
        if ( $input =~ /^\d+$/ && $input >= 1 && $input <= @SEVERITY_VALUES ) {
            $opts->{severity} = $SEVERITY_VALUES[ $input - 1 ];
        } elsif ( $input =~ /\S/ ) {
            $opts->{severity} = $input;
        }
        # Empty input leaves severity unset (Bugzilla uses its default)
    }

    # --- Summary ---
    unless ( $opts->{summary} ) {
        print "\nEnter summary: ";
        my $v = <STDIN>;
        chomp $v;
        $opts->{summary} = $v;
    }

    # --- Description (editor, required) ---
    unless ( $opts->{desc} ) {
        $opts->{desc} = $self->_edit_description( $opts->{summary} );
    }

    # --- Depends on (optional, comma-separated bug IDs) ---
    unless ( defined $opts->{depends} ) {
        print "\nEnter bug IDs this bug depends on (comma-separated, or Enter to skip): ";
        my $v = <STDIN>;
        chomp $v;
        $opts->{depends} = $v if $v =~ /\S/;
    }

    # --- Blocks (optional, comma-separated bug IDs) ---
    unless ( defined $opts->{blocks} ) {
        print "Enter bug IDs this bug blocks (comma-separated, or Enter to skip): ";
        my $v = <STDIN>;
        chomp $v;
        $opts->{blocks} = $v if $v =~ /\S/;
    }
}

=head2 _edit_description

    my $desc = $create->_edit_description($summary);

Opens C<$EDITOR> with a pre-populated template so the user can write a
multiline bug description. Lines beginning with C<#> are stripped. Returns
the resulting text, or throws if the user saves an empty file.

=cut

sub _edit_description {
    my ( $self, $summary ) = @_;

    my $template = '';
    $template .= "# Enter the bug description below.\n";
    $template .= "# Lines starting with '#' will be ignored.\n";
    $template .= "# Save and close the editor when done. Leave empty to abort.\n";
    $template .= "#\n";
    $template .= "# Summary: $summary\n" if $summary;
    $template .= "\n";

    my $temp = File::Temp->new( SUFFIX => '.txt' );
    print $temp $template;
    close $temp;

    $self->_run_editor( $temp->filename );

    open my $fh, '<', $temp->filename or die "Cannot read temp file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    # Strip comment lines and trim surrounding whitespace
    my $desc = join "\n", grep { !/^#/ } split /\n/, $content;
    $desc =~ s/\A\s+//;
    $desc =~ s/\s+\z//;

    GitBz::Exception->throw("Description is required") unless $desc =~ /\S/;

    return $desc;
}

=head2 _run_editor

    $create->_run_editor($filename);

Launches C<$GIT_EDITOR>, C<$EDITOR>, or C<vi> on the given file. Exists as a
separate method so tests can mock it without spawning a real editor process.

=cut

sub _run_editor {
    my ( $self, $filename ) = @_;
    my $editor = $ENV{GIT_EDITOR} || $ENV{EDITOR} || 'vi';
    system( $editor, $filename );
}

=head2 _error

    $create->_error(\%opts, $message);

Prints an error in the appropriate format (JSON or plain text to STDERR).

=cut

sub _error {
    my ( $self, $opts, $message ) = @_;

    if ( $opts->{json} ) {
        print encode_json( { status => 'error', message => $message } ) . "\n";
    } else {
        print STDERR "Error: $message\n";
    }
}

=head2 _json_error

    $create->_json_error(\%opts, $exception);

Prints a structured JSON error from a caught exception.

=cut

sub _json_error {
    my ( $self, $opts, $exception ) = @_;

    my $message = "$exception";
    my $code    = 0;

    # Extract code if the exception carries one
    if ( ref $exception && $exception->can('code') ) {
        $code = $exception->code || 0;
    }

    print encode_json( { status => 'error', code => $code, message => $message } ) . "\n";
}

1;
