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

Releases use `npm version` to bump the version, stamp the changelog, commit,
and tag — all in one step. CI creates the GitLab release when the tag is pushed.

### To cut a release

```bash
npm version patch   # or minor / major
git push --follow-tags
```

This runs the `preversion` hook which:

1. Updates `our $VERSION` in `lib/GitBz/Version.pm`.
2. Runs `scripts/stamp-changelog.pl` to stamp `## [Unreleased]` with the
   version and today's date (removes the `[Unreleased]` header entirely).
3. Stages all changes (`git add -u`).

Then `npm version` commits as `vX.Y.Z` and creates the `vX.Y.Z` tag.

The `postversion` hook then:

4. Runs `scripts/open-next-changelog.pl` to insert a fresh `## [Unreleased]`
   section above the just-released version.
5. Commits as `Open next development cycle`.

Pushing with `--follow-tags` triggers the CI `release` job, which creates
the GitLab release entry. The tagged commit contains a clean changelog
with no `[Unreleased]` section.

### Release token

No push token is needed in CI — tagging and pushing happen locally.

## Code style

- Follow the existing patterns in `lib/GitBz/`.
- Keep modules focused; prefer extending the relevant `GitBz::Commands::*`
  module over adding logic to the dispatcher.
- Exceptions go through the `GitBz::Exception` hierarchy.
- Add tests under `t/` for new behaviour.

## Questions

Open an issue or reach out on the Koha community channels.
