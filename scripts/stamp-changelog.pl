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

# stamp-changelog.pl <version>
#
# Stamps the ## [Unreleased] section in CHANGELOG.md with the given version
# and today's date, inserts a fresh ## [Unreleased] section at the top, and
# updates the reference links at the bottom.
#
# Usage: perl scripts/stamp-changelog.pl v1.0.4

use strict;
use warnings;
use POSIX qw(strftime);

my $version = shift or die "Usage: $0 <version>\n";
(my $bare = $version) =~ s/^v//;   # "1.0.4"  — used in headers and link keys
my $tag  = "v$bare";                # "v1.0.4" — used in URLs and git tags
my $date = strftime('%Y-%m-%d', localtime);

open my $fh, '<', 'CHANGELOG.md' or die "Cannot read CHANGELOG.md: $!\n";
my $content = do { local $/; <$fh> };
close $fh;

# 1. Stamp [Unreleased] -> [1.0.4] - DATE
$content =~ s/^## \[Unreleased\]/## [$bare] - $date/m
    or die "Could not find '## [Unreleased]' in CHANGELOG.md\n";

# 2. Insert a fresh empty [Unreleased] section before the stamped release
$content =~ s/(## \[\Q$bare\E\] - $date)/## [Unreleased]\n\n$1/m;

# 3. Update [Unreleased] compare link to point from the new tag
my $repo = 'https://gitlab.com/koha-community/perl-git-bz';
$content =~ s{^\[Unreleased\]: \S+$}
             {[Unreleased]: $repo/-/compare/$tag...main}m
    or die "Could not find '[Unreleased]: ...' link in CHANGELOG.md\n";

# 4. Insert the new version's tag link immediately after [Unreleased] link
$content =~ s{(\[Unreleased\]: [^\n]+\n)}
             {$1\[$bare\]: $repo/-/tags/$tag\n};

open my $out, '>', 'CHANGELOG.md' or die "Cannot write CHANGELOG.md: $!\n";
print $out $content;
close $out;

print "Stamped CHANGELOG.md: [Unreleased] -> [$bare] - $date\n";
