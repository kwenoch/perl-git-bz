#!/usr/bin/env perl

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

# Verify that:
#   1. Every non-core module used in lib/ and bin/ is declared in cpanfile.
#   2. cpanfile.snapshot exists and covers every runtime requires in cpanfile.
#
# This catches the common mistake of adding a 'use Some::Module' to the source
# without updating cpanfile (and re-running 'carton install').

use strict;
use warnings;
use Test::More;
use File::Find qw(find);
use Module::CoreList;
use FindBin;

my $ROOT = "$FindBin::Bin/..";

# ── 1. Collect 'use' statements from source files ───────────────────────────

my @source_files;
find( sub { push @source_files, $File::Find::name if /\.pm$/ }, "$ROOT/lib" );
push @source_files, "$ROOT/bin/git-bz" if -f "$ROOT/bin/git-bz";

my %used;    # module => relative path of first file that uses it
for my $file (@source_files) {
    ( my $rel = $file ) =~ s{^\Q$ROOT/\E}{};
    open my $fh, '<', $file or die "Cannot open $file: $!";
    while ( my $line = <$fh> ) {
        next if $line =~ /^\s*#/;
        if ( $line =~ /^\s*use\s+([\w:]+)/ ) {
            my $mod = $1;
            next if $mod =~ /^\d/;       # use 5.010; style version pins
            next if $mod =~ /^GitBz::/;  # internal modules
            next if Module::CoreList::first_release($mod);  # core Perl
            $used{$mod} //= $rel;
        }
    }
    close $fh;
}

# ── 2. Parse cpanfile runtime requires ──────────────────────────────────────

my %declared;
{
    open my $fh, '<', "$ROOT/cpanfile" or die "Cannot open cpanfile: $!";
    my $in_block = 0;
    while ( my $line = <$fh> ) {
        $in_block = 1 if $line =~ /^on\s+/;
        $in_block = 0 if $in_block && $line =~ /^};/;
        next if $in_block;
        $declared{$1} = 1 if $line =~ /^\s*requires\s+'([\w:]+)'/;
    }
    close $fh;
}

# ── 3. Parse cpanfile.snapshot provides ─────────────────────────────────────
#
# Snapshot format (4-space attribute keys, 6-space provides entries):
#   ModuleName-1.00
#     pathname: ...
#     provides:
#       Module::Name 1.00
#     requirements:
#       ...

my %snapped;    # module name => 1
if ( -f "$ROOT/cpanfile.snapshot" ) {
    open my $fh, '<', "$ROOT/cpanfile.snapshot"
        or die "Cannot open cpanfile.snapshot: $!";
    my $in_provides = 0;
    while ( my $line = <$fh> ) {
        if    ( $line =~ /^    provides:/ )  { $in_provides = 1 }
        elsif ( $line =~ /^    \w+:/ )       { $in_provides = 0 }
        elsif ( $in_provides && $line =~ /^      ([\w:]+) / ) {
            $snapped{$1} = 1;
        }
    }
    close $fh;
}

# ── Tests ────────────────────────────────────────────────────────────────────

subtest 'all non-core modules used in source are declared in cpanfile' => sub {
    plan tests => scalar keys %used;
    for my $mod ( sort keys %used ) {
        # A module Foo::Bar is covered if cpanfile declares 'Foo::Bar' exactly
        # OR declares the top-level namespace 'Foo' (e.g. URI::Escape via URI).
        my ($top_ns) = $mod =~ /^(\w+)/;
        my $covered = $declared{$mod} || $declared{$top_ns};
        ok( $covered, "'$mod' (used in $used{$mod}) is declared in cpanfile" )
            or diag "  Add to cpanfile: requires '$mod';";
    }
};

subtest 'cpanfile.snapshot is present' => sub {
    ok( -f "$ROOT/cpanfile.snapshot",
        'cpanfile.snapshot exists (run: carton install)' );
};

subtest 'cpanfile.snapshot covers all runtime requires' => sub {
    my @non_core = sort grep { !Module::CoreList::first_release($_) } keys %declared;
  SKIP: {
        skip 'cpanfile.snapshot not present', scalar @non_core
            unless -f "$ROOT/cpanfile.snapshot";

        plan tests => scalar @non_core;
        for my $mod (@non_core) {
            ok( $snapped{$mod},
                "cpanfile requires '$mod' is provided in cpanfile.snapshot" )
                or diag "  Run: carton install";
        }
    }
};

done_testing();
