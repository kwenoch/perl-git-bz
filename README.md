# git-bz-perl

A Perl rewrite of git-bz for Koha development workflow using Bugzilla's REST API.

## Features

- **REST API Integration**: Uses Bugzilla's modern REST API
- **Exception Handling**: Structured exception hierarchy  
- **OO Design**: Clean object-oriented architecture
- **Git Integration**: Seamless git workflow integration

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
# Apply patches from a bug
git bz apply 38224

# Attach commits as patches to a bug
git bz attach 12345 HEAD~2..HEAD

# Edit a bug directly
git bz edit 12345

# Edit bugs referenced in commits
git bz edit HEAD~2..HEAD
```

## Commands

- `apply` - Apply patches from a bug ✅
- `attach` - Attach commits as patches to a bug ✅  
- `edit` - Edit bug details and add comments ✅
