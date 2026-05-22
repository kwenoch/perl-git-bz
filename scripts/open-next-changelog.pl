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

# open-next-changelog.pl <version>
#
# Inserts a fresh ## [Unreleased] section at the top of CHANGELOG.md
# and adds the [Unreleased] compare link.
#
# Usage: perl scripts/open-next-changelog.pl v1.0.4

use strict;
use warnings;

my $version = shift or die "Usage: $0 <version>\n";
(my $bare = $version) =~ s/^v//;
my $tag = "v$bare";

my $repo = 'https://gitlab.com/koha-community/perl-git-bz';

open my $fh, '<', 'CHANGELOG.md' or die "Cannot read CHANGELOG.md: $!\n";
my $content = do { local $/; <$fh> };
close $fh;

# Insert fresh [Unreleased] section before the latest release heading
$content =~ s/(## \[\Q$bare\E\])/## [Unreleased]\n\n$1/m;

# Insert [Unreleased] compare link before the version's tag link
$content =~ s{(\[\Q$bare\E\]: \S+)}{[Unreleased]: $repo/-/compare/$tag...main\n$1}m;

open my $out, '>', 'CHANGELOG.md' or die "Cannot write CHANGELOG.md: $!\n";
print $out $content;
close $out;

print "Opened CHANGELOG.md for next development cycle\n";
