# Contributing to git-bz

Thank you for your interest in contributing! This document describes the workflow for developing a feature, getting it merged, and seeing it released.

## Development workflow

Work is tracked in the GitLab project at
<https://gitlab.com/koha-community/perl-git-bz>. Each change is associated with
a GitLab issue.

1. **Pick or file an issue.** Browse the [issue tracker](https://gitlab.com/koha-community/perl-git-bz/-/issues)
   or open a new issue describing the bug or feature.
2. **Create a branch.** Name it after the issue number, e.g. `issue_51`.
3. **Set up your environment.** See [DEVELOPMENT.md](DEVELOPMENT.md) for Docker
   and local Perl installation instructions.
4. **Make your changes.** Keep commits focused and prefix each subject with the
   issue number:

   ```
   [#51] Short summary of the change
   ```
5. **Run the tests.** All tests must pass on the supported Perl versions
   (5.36 — 5.42):

   ```bash
   prove -lr t/
   ```
6. **Update `CHANGELOG.md`.** This is **required** for every merge request
   (see [Changelog policy](#changelog-policy) below).
7. **Open a merge request** against `main`. The pipeline will run tests and
   validate the changelog entry.
8. **Address review feedback.** Push additional commits to the same branch;
   the pipeline re-runs automatically.
9. **Merge.** Once approved and all jobs are green, a maintainer merges the MR.

## Changelog policy

This project follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Every merge request **must** add an entry under the `## [Unreleased]` section
of [CHANGELOG.md](CHANGELOG.md). The `check-changelog` CI job blocks merges
that omit this.

Group entries under the appropriate subsection:

- `### Added` — new features
- `### Changed` — changes to existing behaviour
- `### Deprecated` — soon-to-be-removed features
- `### Removed` — removed features
- `### Fixed` — bug fixes
- `### Security` — security-relevant fixes

Reference the issue number in square brackets at the start of each entry:

```markdown
### Added

- [#51] Document the contribution and release workflow in CONTRIBUTING.md
```

## Versioning

The canonical version string lives in [`lib/GitBz/Version.pm`](lib/GitBz/Version.pm)
as `our $VERSION = 'vX.Y.Z'`. It is reported in the HTTP User-Agent when
talking to Bugzilla and is the single source of truth for the release version.

Bump the version following SemVer:

- **MAJOR** (`vX.0.0`) — incompatible changes to CLI behaviour, configuration,
  or output formats.
- **MINOR** (`v1.Y.0`) — new, backwards-compatible functionality (e.g. a new
  command or flag).
- **PATCH** (`v1.0.Z`) — backwards-compatible bug fixes.

The version bump typically lands in the final merge request of a release
cycle, alongside the accumulated `[Unreleased]` entries.

## Release process

Releases are **automated by GitLab CI**. There is no manual tagging step.

When a merge request that modifies `lib/GitBz/Version.pm` is merged into
`main`, the `tag-release` job runs and:

1. Reads the new version from `lib/GitBz/Version.pm`.
2. Skips if the tag already exists.
3. Runs [`scripts/stamp-changelog.pl`](scripts/stamp-changelog.pl), which:
   - Renames `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`.
   - Inserts a fresh empty `## [Unreleased]` section at the top.
   - Updates the comparison links at the bottom of `CHANGELOG.md`.
4. Commits the stamped `CHANGELOG.md` back to `main` as `Release vX.Y.Z`.
5. Creates and pushes the `vX.Y.Z` git tag.

The new tag appears on the [Releases page](https://gitlab.com/koha-community/perl-git-bz/-/releases).

### To cut a release

1. Open a merge request that:
   - Bumps `our $VERSION` in `lib/GitBz/Version.pm`.
   - Adds any final notes to `## [Unreleased]` in `CHANGELOG.md`.
2. Get it reviewed and merged.
3. Watch the pipeline — the `tag-release` job handles the rest.

### Release token

The `tag-release` job needs push access to `main`. If branch protection blocks
`CI_JOB_TOKEN`, create a Project Access Token with `write_repository` scope,
store it as the `RELEASE_TOKEN` CI variable, and update `.gitlab-ci.yml` to use
it in place of `CI_JOB_TOKEN`.

## Code style

- Follow the existing patterns in `lib/GitBz/`.
- Keep modules focused; prefer extending the relevant `GitBz::Commands::*`
  module over adding logic to the dispatcher.
- Exceptions go through the `GitBz::Exception` hierarchy.
- Add tests under `t/` for new behaviour.

## Questions

Open an issue or reach out on the Koha community channels.
