# Development Guide

This document explains how to set up a local development environment for running tests.

## Prerequisites

- Docker installed on your system
- Access to the project source code

## Setting up the Test Environment

### Option 1: Using Docker (Recommended)

This approach mirrors the GitLab CI environment and ensures consistency across different development machines.

#### 1. Create and Start the Container

```bash
# From the project root directory
docker run -d --name perl-git-bz-test \
  -v "$(pwd)":/app \
  -w /app \
  perl:latest \
  tail -f /dev/null
```

This creates a persistent container named `perl-git-bz-test` with:
- The project directory mounted at `/app`
- Working directory set to `/app`
- Perl latest version (currently 5.42)

#### 2. Install Dependencies

```bash
docker exec perl-git-bz-test cpanm --installdeps --notest .
```

This installs all dependencies listed in `cpanfile` including:
- Runtime dependencies (Modern::Perl, Try::Tiny, IPC::Run3, etc.)
- Test dependencies (Test::More, Test::Exception, Test::MockModule, etc.)

#### 3. Run Tests

```bash
# Set PERL5LIB for proper module loading
export PERL5LIB=$PERL5LIB:lib/:.

# Run all tests
docker exec perl-git-bz-test bash -c "export PERL5LIB=\$PERL5LIB:lib/:. && prove -lr t/"

# Run specific test file
docker exec perl-git-bz-test bash -c "export PERL5LIB=\$PERL5LIB:lib/:. && prove -v t/00-load.t"

# Run tests with JUnit output (like CI)
docker exec perl-git-bz-test bash -c "export PERL5LIB=\$PERL5LIB:lib/:. && prove -lr t/ --harness=TAP::Harness::JUnit"
```

#### 4. Interactive Development

```bash
# Get a shell inside the container
docker exec -it perl-git-bz-test bash

# Inside the container, set PERL5LIB first:
export PERL5LIB=$PERL5LIB:lib/:.

# Then you can:
perl -c bin/git-bz                    # Check syntax
prove -v t/specific-test.t            # Run specific tests
perl -Ilib bin/git-bz --help          # Test the application
```

#### 5. Container Management

```bash
# Stop the container
docker stop perl-git-bz-test

# Start existing container
docker start perl-git-bz-test

# Remove container (when done)
docker rm -f perl-git-bz-test
```

### Option 2: Local Perl Installation

If you prefer to use your local Perl installation:

#### 1. Install cpanm (if not already installed)

```bash
curl -L https://cpanmin.us | perl - --sudo App::cpanminus
```

#### 2. Install Dependencies

```bash
cpanm --installdeps --notest .
```

#### 3. Run Tests

```bash
# Set PERL5LIB for proper module loading
export PERL5LIB=$PERL5LIB:lib/:.

# Run tests
prove -lr t/
```

## Test Structure

The test suite includes:

- `t/00-load.t` - Basic module loading tests
- `t/Apply.t` - Tests for the Apply command functionality
- `t/StatusWorkflow.t` - Status workflow tests
- `t/apply_*.t` - Various apply command scenarios
- `t/attach_*.t` - Attachment handling tests
- `t/git-*.t` - Git integration tests
- `t/utf8-handling.t` - UTF-8 encoding tests

## Continuous Integration

The project uses GitLab CI with the following configuration:
- Tests run on Perl versions: 5.36, 5.38, 5.40, 5.42
- Dependencies installed with `cpanm --installdeps --notest .`
- Tests executed with `prove -lr t/ --harness=TAP::Harness::JUnit`
- JUnit XML output generated for test reporting

## Development Workflow

1. Make your changes to the code
2. Run the relevant tests to ensure they pass
3. Add new tests for new functionality
4. Run the full test suite before committing
5. Ensure all tests pass in the Docker environment

## Troubleshooting

### Container Issues

If the container fails to start or behaves unexpectedly:

```bash
# Check container status
docker ps -a

# View container logs
docker logs perl-git-bz-test

# Recreate container
docker rm -f perl-git-bz-test
# Then run the creation command again
```

### Dependency Issues

If dependency installation fails:

```bash
# Try installing with verbose output
docker exec perl-git-bz-test cpanm --installdeps --verbose .

# Install dependencies one by one to identify issues
docker exec perl-git-bz-test cpanm Modern::Perl
docker exec perl-git-bz-test cpanm Try::Tiny
# etc.
```

### Test Failures

If tests fail:

1. Run individual tests to isolate the issue:
   ```bash
   docker exec perl-git-bz-test prove -v t/failing-test.t
   ```

2. Check for missing dependencies or environment issues

3. Ensure the container has the latest code (the volume mount should sync automatically)

## Notes

- The Docker approach ensures consistency with the CI environment
- All changes to the source code are immediately reflected in the container due to volume mounting
- The container persists between runs, so dependencies only need to be installed once
- Test data and temporary files are handled within the container's filesystem
