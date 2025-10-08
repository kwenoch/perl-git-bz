# git-bz-perl

A Perl rewrite of git-bz for Koha development workflow using Bugzilla's REST API.

## Features

- **REST API Integration**: Uses Bugzilla's modern REST API
- **Exception Handling**: Structured exception hierarchy  
- **OO Design**: Clean object-oriented architecture
- **Git Integration**: Seamless git workflow integration
- **Dependency Cascading**: Automatically handles bug dependencies

## Installation

```bash
# Install dependencies
cpanm --installdeps .

# Make executable available
export PATH="$PWD/bin:$PATH"
```

## Configuration

```bash
# Set default Bugzilla tracker
git config bz.default-tracker bugs.koha-community.org

# Set credentials
export BUGZILLA_USER=your-email@example.com
export BUGZILLA_PASSWORD=your-password
```

## Usage

```bash
# Apply patches from a bug (with dependency resolution)
git bz apply 38224

# Attach commits as patches to a bug
git bz attach 12345 HEAD~2..HEAD

# Edit a bug directly
git bz edit 12345

# Edit bugs referenced in commits
git bz edit HEAD~2..HEAD
```

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
