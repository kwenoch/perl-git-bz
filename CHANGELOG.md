# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- [#30] Fix UTF-8 "Wide character in print" warnings in apply command progress indicators
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

[1.0.0]: https://gitlab.com/koha-community/git-bz/-/tags/v1.0.0
