# git-bz

[![pipeline status](https://gitlab.com/koha-community/perl-git-bz/badges/main/pipeline.svg)](https://gitlab.com/koha-community/perl-git-bz/-/commits/main)
[![Latest Release](https://gitlab.com/koha-community/perl-git-bz/-/badges/release.svg)](https://gitlab.com/koha-community/perl-git-bz/-/releases)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

A command-line tool for integrating Git workflows with Bugzilla bug tracking. Designed for the Koha project development workflow, git-bz streamlines the process of applying patches from bugs, attaching commits as patches, and managing bug metadata directly from your terminal.

## Features

- **File new bug reports** - Create Bugzilla bugs from the command line, interactively or non-interactively
- **Discover valid field values** - List available products, components, and versions as JSON
- **Apply patches from bugs** - Download and apply patches with automatic dependency resolution
- **Attach commits as patches** - Upload Git commits as Bugzilla attachments
- **Edit bug metadata** - Update bug status, assignee, QA contact, complexity, sponsors, and dependencies
- **Dependency cascading** - Automatically follow and apply dependent bugs
- **Smart obsoletes** - Auto-detect patches to obsolete based on commit subjects
- **Local field cache** - Product/component/version data cached for one week for fast interactive use
- **UTF-8 support** - Proper handling of international characters
- **Secure credentials** - Integration with Git credential helpers
- **REST API** - Uses Bugzilla's modern REST API

## Installation

### Option 1: System packages (Debian/Ubuntu — recommended for Koha developers)

Install all runtime dependencies from your distribution's package manager, then
add the `bin/` directory to your PATH:

```bash
sudo apt install \
  libmodern-perl-perl \
  libtry-tiny-perl \
  libipc-run3-perl \
  libexception-class-perl \
  libjson-perl \
  libwww-perl \
  liblwp-protocol-https-perl \
  liburi-perl \
  libtext-unicodebox-table-perl

# Add to PATH (adjust path to match your clone location)
echo 'export PATH="$HOME/git/perl-git-bz/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

This is the fastest route for Koha developers already on Debian, Ubuntu, or
KTD containers, as all packages are available in the standard archive.

### Option 2: cpanm

Install dependencies into your system (or user) Perl with
[cpanminus](https://metacpan.org/pod/App::cpanminus):

```bash
# Install dependencies
cpanm --installdeps .

# Add to PATH (adjust path to match your clone location)
echo 'export PATH="$HOME/git/perl-git-bz/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

To install without root access, add `--local-lib ~/perl5` and export
`PERL5LIB=~/perl5/lib/perl5` in your shell profile.

### Option 3: Carton (reproducible, version-locked install)

[Carton](https://metacpan.org/pod/Carton) installs exact dependency versions
from the committed `cpanfile.snapshot` lockfile into a local `local/`
directory, keeping your system Perl untouched.

**Install Carton** (once, system-wide or via cpanm):

```bash
cpanm Carton
# or: sudo apt install carton
```

**Install dependencies** from the lockfile:

```bash
carton install --deployment
```

This populates `local/lib/perl5/` with every dependency at exactly the pinned
version. The `--deployment` flag refuses to install anything not already in the
snapshot, ensuring reproducible builds.

**Run git-bz via Carton:**

```bash
carton exec git-bz apply 12345
```

Or set `PERL5LIB` once in your shell profile so the installed `bin/git-bz`
script finds the vendored libraries automatically:

```bash
echo 'export PERL5LIB="$HOME/git/perl-git-bz/local/lib/perl5:$PERL5LIB"' >> ~/.bashrc
echo 'export PATH="$HOME/git/perl-git-bz/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for the workflow to update the lockfile
when adding or changing dependencies.

## Configuration

`git config` writes to the repo you run it in unless you pass `--global`. Add
`--global` only if you want the same settings available in every repo on your
machine (e.g. you run `git bz` from more than one Koha checkout) — otherwise,
run these commands inside each repo where you intend to use `git bz`.

### Basic Setup

```bash
# Tracker connection details (required — there is no built-in default for
# these two, so git-bz can't reach Bugzilla without them)
git config bz-tracker.bugs.koha-community.org.path /bugzilla3
git config bz-tracker.bugs.koha-community.org.https true

# Set credentials (choose one method)

# Method 1: Direct configuration
git config bz-tracker.bugs.koha-community.org.bz-user your-email@example.com
git config bz-tracker.bugs.koha-community.org.bz-password your-password

# Method 2: Environment variables
export BUGZILLA_USER=your-email@example.com
export BUGZILLA_PASSWORD=your-password

# Method 3: Git credential helper (recommended for security)
git config bz-tracker.bugs.koha-community.org.use-git-credential true
git config --global credential.helper osxkeychain  # macOS
# or: libsecret (Linux), manager-core (Windows), store (cross-platform)
git config --global credential.https://bugs.koha-community.org.username your-email@example.com
```

`bugs.koha-community.org` is already the default tracker
(`bz.default-tracker`), so you only need to set that key if you want to point
`git bz` at a different Bugzilla instance:

```bash
git config bz.default-tracker bugs.koha-community.org
```

### Optional Settings

```bash
# Control verbosity (0=quiet, 1=default, 2=verbose)
git config bz.verbose 1
```

## Commands

### create - File a new bug report

Creates a new Bugzilla bug report from the command line.

```bash
git bz create [options]
```

**Options:**

| Flag | Description |
|------|-------------|
| `--product` | Product name (required) |
| `--comp` | Component name (required) |
| `--version` | Version (required) |
| `--severity` | Severity: `blocker`, `critical`, `major`, `normal`, `minor`, `trivial`, `enhancement` (optional) |
| `--summary` | Bug title (required) |
| `--desc` | Bug description (required) |
| `--depends` | Comma-separated bug IDs this bug depends on (optional) |
| `--blocks` | Comma-separated bug IDs this bug blocks (optional) |
| `--dry-run` | Check for duplicates and validate fields without creating the bug |
| `--non-interactive` | Fail-fast: never prompt, exit non-zero on any missing required field |
| `--json` | Emit all output as JSON to STDOUT (including errors) |
| `-y, --yes` | Skip confirmation prompt |

**Interactive mode** (default when fields are missing):

Prompts for each missing field in order, with pick-lists for fields that have
known accepted values:

```
Select product:
   1) Koha
   2) Koha Plugin
Choice (number or name): 1

Select component:
   1) OPAC
   2) Staff interface
   3) Acquisitions
Choice (number or name): 2

Select version:
   1) master
   2) 23.11
Choice (number or name): 1

Select severity:
   1) blocker
   2) critical
   3) major
   4) normal
   ...
Choice (number or name, Enter to skip): 4

Enter summary: Login page crashes on empty username

# $EDITOR opens for multiline description
```

**Dry-run mode:**

```bash
git bz create --summary "Login page crashes" --product Koha --comp OPAC \
              --version master --dry-run
```
```
Potential duplicates:
  Bug 12345 - Login form broken on empty input [NEW]
  Bug 11900 - OPAC login error with blank fields [RESOLVED]

Missing fields: desc
```

**Non-interactive / scripting mode:**

```bash
git bz create \
  --product Koha --comp OPAC --version master \
  --severity major \
  --summary "Login page crashes on empty username" \
  --desc "Steps to reproduce: ..." \
  --depends "12345,12346" \
  --non-interactive --json
```
```json
{"status":"ok","id":99999,"url":"https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=99999"}
```

**JSON error output:**

```json
{"status":"error","code":0,"message":"Component 'Unknown' is not valid for Product 'Koha'."}
```

### info - Discover valid field values

Outputs available products, components, and versions as JSON so that scripts
and AI agents can populate `git bz create` flags without guessing invalid values.

```bash
git bz info --fields
git bz info --fields --refresh
```

**Options:**

| Flag | Description |
|------|-------------|
| `--fields` | List valid products, components, and versions as JSON |
| `--refresh` | Bypass the local cache and fetch fresh data from Bugzilla |

Results are **cached locally for one week** in `~/.cache/git-bz/` (respects
`$XDG_CACHE_HOME`), so repeated calls are fast. Use `--refresh` after a Bugzilla
admin adds a new product or component.

**Example output:**

```json
{
  "products": [
    {
      "name": "Koha",
      "components": ["Architecture, internals", "Acquisitions", "OPAC", "Staff interface"],
      "versions": ["master", "23.11", "23.05", "22.11"]
    }
  ]
}
```

### apply - Apply patches from bugs

Downloads and applies patches from a Bugzilla bug to your current branch.

```bash
git bz apply <bug-id>
git bz apply [options] <bug-id>
```

**Options:**
- `-v, --verbose` - Increase verbosity (can be repeated: -vv)
- `--continue` - Continue after resolving conflicts
- `--skip` - Skip current patch and continue
- `--abort` - Abort the apply operation

**Features:**
- Interactive patch selection
- Automatic dependency detection and resolution
- Prompts to apply dependent bugs first
- Handles git-am workflow (continue/skip/abort)
- Filters dependencies by relevant statuses

**Example:**
```bash
# Apply all patches from bug 38224
git bz apply 38224

# Apply with verbose output
git bz apply -vv 38224

# Continue after resolving conflicts
git bz apply --continue
```

### attach - Attach commits as patches

Uploads Git commits as patch attachments to a Bugzilla bug.

```bash
git bz attach [options] [<bug-id>] <commit-range>
```

**Options:**
- `-e, --edit` - Edit bug metadata before attaching
- `-y, --yes` - Skip confirmation prompts
- `-v, --verbose` - Increase verbosity

**Behavior:**

| Mode | Bug Metadata | Attachment Comments | Bug Comment | Obsoletes |
|------|--------------|---------------------|-------------|-----------|
| **Standard** | No changes | Commit message per patch | None | Auto-detect only |
| **Edit (-e)** | Interactive form | Commit message per patch | Optional | Interactive selection |

**Standard Mode:**
- Each commit becomes a separate attachment
- Attachment description = commit subject
- Attachment comment = full commit message
- Auto-detects patches to obsolete (matching subjects)
- No user interaction required

**Edit Mode (-e):**
- Opens interactive template for bug-level updates
- Update status, QA contact, assignee, patch complexity, sponsors, sponsorship, dependencies
- Add optional bug-level comment (separate from attachment comments)
- Select patches to obsolete (press 'a' to skip all remaining prompts)
- All updates applied in single API call
- Clearing the file and saving aborts the operation with no changes

**Examples:**
```bash
# Attach last 2 commits (extracts bug ID from commit message)
git bz attach HEAD~2..HEAD

# Attach to specific bug
git bz attach 12345 HEAD~2..HEAD

# Attach with interactive editing
git bz attach -e 12345 HEAD~2..HEAD

# Skip confirmation prompts
git bz attach -y 12345 HEAD
```

### edit - Edit bug metadata

Opens an interactive template to update bug fields and add comments.

```bash
git bz edit <bug-id>
git bz edit <commit>
git bz edit <revision-range>
```

**Editable Fields:**
- Status (with workflow validation)
- QA Contact (with email validation and user search)
- Assignee (with email validation and user search)
- Resolution
- Patch complexity
- Sponsors (one per line, add/remove tracking)
- Sponsorship status
- Dependencies (add/remove tracking)
- Comments
- Obsolete attachments

**Features:**
- Smart field validation
- Auto-updates sponsorship status when adding sponsors
- Displays changes in formatted table before applying
- Extracts bug IDs from commit messages

**Examples:**
```bash
# Edit bug directly
git bz edit 12345

# Edit bugs from commits
git bz edit HEAD~2..HEAD

# Edit bug from single commit
git bz edit HEAD
```

### open - Open bug in browser

Opens the bug in your default web browser.

```bash
git bz open <bug-id>
```

**Example:**
```bash
git bz open 12345
```

*NOTE:* Requires `xdg-open` (Linux), `open` (macOS), or `start` (Windows) to be available in PATH.
As such, is won't work within the **KTD** shell.

## Workflow Examples

### Filing a new bug report

```bash
# Interactive — prompts for everything with pick-lists
git bz create

# Pre-fill known fields, be prompted only for what's missing
git bz create --product Koha --comp OPAC --version master

# Check for duplicates before filing
git bz create --summary "Login crashes on empty input" \
              --product Koha --comp OPAC --version master --dry-run

# Fully scripted (AI agent / CI use)
git bz create \
  --product Koha --comp OPAC --version master \
  --severity major \
  --summary "Login crashes on empty input" \
  --desc "Steps to reproduce: navigate to /cgi-bin/koha/opac-user.pl ..." \
  --non-interactive --json

# Discover valid products/components/versions first
git bz info --fields
```

### Applying patches from a bug

```bash
# Apply patches with dependency resolution
git bz apply 38224

# If dependencies exist, you'll be prompted:
# "Bug 38224 depends on bug 38100 (Needs Signoff). Follow? [(y)es, (n)o]"

# Select patches interactively or apply all
# Patches are applied using git-am
```

### Attaching your work

```bash
# Make your commits
git commit -m "Bug 12345: Add regression tests"
git commit -m "Bug 12345: Fix the thing"

# Attach commits (extracts bug ID from messages)
git bz attach HEAD~2..

# Or attach with metadata updates
git bz attach -e 12345 HEAD~2..
```

### Updating bug metadata

```bash
# Edit bug fields
git bz edit 12345

# Template opens with current values:
# - Uncomment desired status
# - Add/remove sponsors (one per line)
# - Add/remove dependencies
# - Add comment
# - Select patches to obsolete

# Changes displayed in table before applying
```

## Field Update Display

When updating bug metadata, changes are displayed in a formatted table:

```
Updating bug 12345:
  ┌──────────────────┬───────────────┬───┬──────────────┐
  │ Status           │ NEW           │ → │ Needs Signoff│
  │ Patch-complexity │ ---           │ → │ Small patch  │
  │ Sponsors         │               │   │ + Sponsor One│
  │ Depends          │               │   │ + 12346      │
  └──────────────────┴───────────────┴───┴──────────────┘
```

## Dependency Resolution

When applying bugs, git-bz automatically:

1. Checks the bug's `depends_on` field
2. Filters dependencies by status (Needs Signoff, Signed Off, Failed QA, Passed QA, BLOCKED)
3. Prompts to apply dependencies first
4. Applies in correct order
5. Tracks applied bugs to prevent duplicates

If a patch conflicts partway through a dependency's patch set, resolve it as
usual (`git mergetool` or manual edits, `git add`, then `git bz apply
--continue`/`--skip`/`--abort`). `--continue`/`--skip` resume the entire
chain, not just the dependency that conflicted: once its remaining patches
are applied, git-bz carries on to the bug(s) that depended on it, and to any
other bugs originally passed on the command line.

## Sponsor Management

Sponsors are managed like dependencies with add/remove tracking:

```
# In edit template:
# Current sponsors: Existing Sponsor
# Add one sponsor per line:
Sponsors: Existing Sponsor
Sponsors: New Sponsor
# Sponsors: Example Name

# Results in:
# + New Sponsor (added)
# Existing Sponsor (unchanged)
```

Auto-updates sponsorship status to "Sponsored" when adding sponsors if current status is "Seeking sponsor" or "Unsponsored".

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for information on running tests and contributing.

## License

This project is licensed under the GNU General Public License v3.0 or later. See the source files for details.
