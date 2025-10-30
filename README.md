# git-bz-perl

A Perl implementation of git-bz for Koha development workflow using Bugzilla's REST API.

## Features

- **REST API Integration**: Uses Bugzilla's modern REST API
- **Exception Handling**: Structured exception hierarchy  
- **OO Design**: Clean object-oriented architecture
- **Git Integration**: Seamless git workflow integration
- **Dependency Cascading**: Automatically handles bug dependencies
- **UTF-8 Support**: Proper handling of non-ASCII characters in commit messages

## Installation

```bash
# Install dependencies
cpanm --installdeps .

# Make executable available
export PATH="$PWD/bin:$PATH"
```

## Configuration

### Standard Setup

```bash
# Set default Bugzilla tracker
git config bz.default-tracker bugs.koha-community.org

# Set credentials
git config bz-tracker.bugs.koha-community.org.bz-user your-email@example.com
git config bz-tracker.bugs.koha-community.org.bz-password your-password
```

### Alternative: Environment Variables

```bash
# Set default Bugzilla tracker
git config bz.default-tracker bugs.koha-community.org

# Set credentials via environment variables
export BUGZILLA_USER=your-email@example.com
export BUGZILLA_PASSWORD=your-password
```

### Optional: Git Credential Helper (In Development)

For enhanced security using git's credential management system:

```bash
# Set default Bugzilla tracker
git config bz.default-tracker bugs.koha-community.org

# Configure git credential helper
git config --global credential.helper 'cache --timeout 3600'  # timeout in seconds
git config --global credential.https://bugs.koha-community.org.username your-email@example.com
git config --global bz-tracker.bugs.koha-community.org.use-git-credential true
```

**Alternative credential helpers:**
```bash
# Use system keychain (macOS/Linux)
git config --global credential.helper osxkeychain  # macOS
git config --global credential.helper libsecret    # Linux

# Use Windows Credential Manager
git config --global credential.helper manager-core # Windows
```

**Testing git credential availability:**
```bash
# Test if git credential is available
git credential fill
# (Press Ctrl+C to cancel if it waits for input - this means it's working)

# Check current credential helper
git config --global credential.helper
```

## Usage

```bash
# Apply patches from a bug (with dependency resolution)
git bz apply 38224

# Attach commits as patches to a bug
git bz attach 12345 HEAD~2..HEAD

# Attach with interactive editing of bug fields
git bz attach -e 12345 HEAD~2..HEAD

# Skip confirmation prompts
git bz attach -y 12345 HEAD

# Edit a bug directly
git bz edit 12345

# Edit bugs referenced in commits
git bz edit HEAD~2..HEAD
```

## Attach Command Behavior

The `attach` command provides flexible patch attachment with optional bug field editing:

### Standard Mode
- Each commit becomes an attachment with the commit message as the attachment comment
- Attachment description uses the commit subject line
- No user interaction required

### Edit Mode (`-e` flag)
- Shows an interactive form for bug-level updates
- Each attachment still gets the original commit message as comment
- Allows adding optional bug-level comment (separate from attachment comments)
- Supports updating bug status, patch complexity, dependencies
- Smart detection of patches to obsolete based on commit subjects
- All bug updates happen in a single API call after attachments

### Benefits
- **Predictable**: Each commit always becomes an attachment with its original message
- **Separated concerns**: Attachment comments vs bug-level comments are distinct
- **UTF-8 safe**: Proper encoding handling for international characters
- **Bulk operations**: Edit mode works across multiple commits efficiently

## Dependency Cascading

When applying a bug with `git bz apply`, the tool automatically:

1. **Detects dependencies**: Checks the bug's `depends_on` field
2. **Filters by status**: Only prompts for dependencies in applicable states:
   - Needs Signoff, Signed Off, Failed QA, Passed QA, BLOCKED
3. **Prompts user**: "Bug X depends on bug Y (Status). Follow? [(y)es, (n)o]"
4. **Applies recursively**: If user chooses yes, applies dependency first
5. **Tracks applied bugs**: Prevents duplicate applications in dependency chains

This ensures patches are applied in the correct dependency order automatically.

## Commands

- `apply` - Apply patches from a bug with dependency resolution ✅
- `attach` - Attach commits as patches to a bug ✅  
- `edit` - Edit bug details and add comments ✅
