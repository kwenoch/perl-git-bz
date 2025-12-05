# git-bz

[![pipeline status](https://gitlab.com/koha-community/perl-git-bz/badges/main/pipeline.svg)](https://gitlab.com/koha-community/perl-git-bz/-/commits/main)
[![Latest Release](https://gitlab.com/koha-community/perl-git-bz/-/badges/release.svg)](https://gitlab.com/koha-community/perl-git-bz/-/releases)

A command-line tool for integrating Git workflows with Bugzilla bug tracking. Designed for the Koha project development workflow, git-bz streamlines the process of applying patches from bugs, attaching commits as patches, and managing bug metadata directly from your terminal.

## Features

- **Apply patches from bugs** - Download and apply patches with automatic dependency resolution
- **Attach commits as patches** - Upload Git commits as Bugzilla attachments
- **Edit bug metadata** - Update bug status, complexity, sponsors, and dependencies
- **Dependency cascading** - Automatically follow and apply dependent bugs
- **Smart obsoletes** - Auto-detect patches to obsolete based on commit subjects
- **UTF-8 support** - Proper handling of international characters
- **Secure credentials** - Integration with Git credential helpers
- **REST API** - Uses Bugzilla's modern REST API

## Installation

```bash
# Install dependencies
cpanm --installdeps .

# Add to PATH (adjust path to match your clone location)
echo 'export PATH="$HOME/git/perl-git-bz/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Configuration

### Basic Setup

```bash
# Set default Bugzilla tracker
git config bz.default-tracker bugs.koha-community.org

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

### Optional Settings

```bash
# Control verbosity (0=quiet, 1=default, 2=verbose)
git config bz.verbose 1
```

## Commands

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
- Update status, patch complexity, sponsors, sponsorship, dependencies
- Add optional bug-level comment (separate from attachment comments)
- Select patches to obsolete
- All updates applied in single API call

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
