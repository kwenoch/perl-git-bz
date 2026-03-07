# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
## [Unreleased]

### Added

- [#41] Support for assignee field in `attach -e` and `edit` commands
  - View and edit the assignee field in interactive editor
  - Template defaults to current user's email for easy self-assignment
  - Support for clearing the field with empty value
  - Field appears after QA Contact in the editor template
  - Interactive user search/selection with email validation
- [#44] Add 'skip all remaining' option when prompting to obsolete patches
  - Press 'a' to skip all remaining obsolete prompts at once

### Fixed

- [#33] Fix visual glitches from long progress messages
  - Add terminal width detection with caching for proper message display
  - Truncate long messages with ellipsis (…) to prevent line wrapping
  - Prevent visual artifacts where carriage returns couldn't clear previous spinner frames
  - Comprehensive unit tests covering terminal width detection and message truncation
- [#36] Improve QA contact validation UX
  - Validate QA contact emails proactively before API submission
  - Interactive user search/selection with clear error messaging
- [#39] Progress output improvements
  - Add indentation level support to Progress print methods
  - Replace ✔ with ✓ for console output consistency
  - Use Progress functions more consistently throughout codebase
- [#40] Pass authentication token when fetching bug info and attachments

## [1.0.3] - 2025-12-24

### Added

- [#38] Add GPLv3 license badge to README
- [#36] Support for QA Contact field in `attach -e` and `edit` commands
  - View and edit QA Contact field in interactive editor
  - Template defaults to current user's email for easy self-assignment
  - Support for clearing the field with empty value
  - Field appears after Status in the editor template

### Fixed

- [#35] Write dowloaded attachments in raw mode to avoid encoding corruption

## [1.0.2] - 2025-12-09

### Fixed
- [#30] Fix UTF-8 "Wide character in print" warnings in Progress.pm
  - Root cause: Term::ANSIColor::colored() returns strings with UTF-8 flag set (wide characters)
  - Even with STDOUT having :utf8 layer, Perl's internal state becomes inconsistent when printing these strings
  - Solution: Call binmode(STDOUT, ':utf8') before printing in all functions using colored()
  - This refreshes the layer state, ensuring proper handling of wide characters
  - Applied to: print_success, print_error, print_info, print_warning, stop_spinner, update_progress_line
- [#32] Improve apply command progress output: show all patches being applied and add summary after preparing

## [1.0.1] - 2025-12-09

- [#31] Switch `require` to `use` for modules
- [#29] Fix bagde and release URL

## [1.0.0] - 2025-12-05

### Added

#### Core Commands
- `apply` - Apply patches from Bugzilla bugs with automatic dependency resolution
- `attach` - Attach Git commits as patches to bugs with optional metadata editing
- `edit` - Interactive bug metadata editing with field validation
- `open` - Open bugs in default web browser

#### Dependency Management
- Automatic dependency detection and cascading when applying bugs
- Smart filtering of dependencies by relevant statuses
- Recursive dependency resolution with duplicate prevention
- Interactive prompts for following dependency chains

#### Bug Metadata Management
- Interactive template-based editing for bug fields
- Support for Status, Resolution, Patch-complexity, Sponsors, Sponsorship, Dependencies
- Workflow validation for status transitions
- Add/remove tracking for sponsors and dependencies (like git diff)
- Auto-update sponsorship status when adding sponsors
- Formatted table display of changes before applying

#### Sponsor Support
- One sponsor per line in edit templates
- Add/remove tracking with `+` and `-` indicators
- Automatic extraction of sponsors from commit trailers (`Sponsored-by:`)
- Merge sponsors from bug and commits in attach mode
- Auto-update sponsorship status from "Seeking sponsor" to "Sponsored"

#### Patch Management
- Smart obsolete detection based on commit subject matching
- Interactive patch selection when applying
- Auto-uncomment obsoletes for matching patches in attach mode
- Support for obsoleting attachments in edit mode

#### Developer Experience
- UTF-8 support throughout (commit messages, bug comments, field values)
- Formatted table output for field changes with Unicode box drawing
- Progress indicators with spinners for long operations
- Verbosity control (quiet/default/verbose modes)
- Comprehensive error handling with structured exceptions

#### Security & Credentials
- Git credential helper integration for secure password storage
- Support for multiple credential storage backends (keychain, libsecret, etc.)
- Automatic approval/rejection feedback to credential helpers
- Fallback to environment variables and git config

#### Testing
- Comprehensive test suite with 116 tests across 21 test files
- Unit tests for all major components (Bug, Template, StatusWorkflow, etc.)
- Integration tests for commands and workflows
- UTF-8 handling tests
- Sponsor and dependency management tests

#### Architecture
- Modern Perl with REST API integration (no screen scraping)
- Object-oriented design with clean separation of concerns
- Centralized template generation and parsing (GitBz::Template)
- Reusable bug field update system (GitBz::Bug)
- Structured exception hierarchy

### Technical Details

- **REST API**: Uses Bugzilla's modern REST API for all operations
- **Git Integration**: Seamless integration with git-am workflow
- **Encoding**: Proper UTF-8 handling with binmode and encoding layers
- **Progress**: Non-blocking spinners with line-replacement output
- **Validation**: Status workflow validation from Bugzilla API

[Unreleased]: https://gitlab.com/koha-community/perl-git-bz/-/compare/v1.0.3...main
[1.0.3]: https://gitlab.com/koha-community/perl-git-bz/-/tags/v1.0.3
[1.0.2]: https://gitlab.com/koha-community/perl-git-bz/-/tags/v1.0.2
[1.0.1]: https://gitlab.com/koha-community/perl-git-bz/-/tags/v1.0.1
[1.0.0]: https://gitlab.com/koha-community/perl-git-bz/-/tags/v1.0.0
