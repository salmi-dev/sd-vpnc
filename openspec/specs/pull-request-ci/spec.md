# pull-request-ci Specification

## Purpose

Give reviewers a test result for each pull request and use that result to protect `main` without publishing releases from PR runs.

## Requirements

### Requirement: Pull requests run automated tests

CI SHALL run the image-build behavior suite, shell syntax validation, ShellCheck, and CLI smoke checks on pull requests and report the result as `Shell validation`. ShellCheck SHALL cover `sd-vpnc`, `tests/test-dotfiles-build.sh`, and `tests/test-container-session-manager.sh`, including shell code and test scripts introduced or changed for the container session manager.

#### Scenario: Pull request opened or updated

- **WHEN** a pull request is opened or a new commit is pushed to it
- **THEN** CI runs the checks for that revision, including tests for checkout cleanup and build failure propagation
- **AND** ShellCheck analyzes the session-manager implementation and behavior test scripts
- **AND** a failing test or ShellCheck diagnostic makes `Shell validation` fail

#### Scenario: ShellCheck passes and downstream checks run

- **WHEN** ShellCheck passes for the pull request revision
- **THEN** CI runs the image-build behavior suite, shared-session behavior suite, and CLI smoke checks
- **AND** `Shell validation` passes only if all those checks pass

### Requirement: Pull request CI does not release

A CI run triggered by `pull_request` SHALL NOT cause an automatic release.

#### Scenario: Successful PR run completes

- **WHEN** the release workflow receives a completion event for a successful PR CI run
- **THEN** the release job is skipped; it does not push a release commit, create a tag, or publish a release

### Requirement: Pull requests to main require the CI check

For merges to `main` without bypass, `protect-main` SHALL require `Shell validation` from GitHub Actions (app ID `15368`) on the revision being evaluated for merge, in addition to the existing PR and review requirements. The ruleset SHALL retain its sole bypass actor (`RepositoryRole` ID `5`, `always`). This role may bypass the entire ruleset, including CI, PR and review requirements.

#### Scenario: Release automation pushes directly to main

- **WHEN** the existing release automation pushes a release commit to `main` using credentials for the authorized role
- **THEN** `protect-main` permits the role to bypass the ruleset without a PR, reviews or a passing `Shell validation` check

#### Scenario: Test failure blocks merge

- **WHEN** a pull request to `main` meets all other merge requirements but `Shell validation` fails and no bypass is used
- **THEN** the pull request cannot merge

#### Scenario: Check result is outstanding

- **WHEN** `Shell validation` is pending or has not yet been reported for a pull request to `main` and no bypass is used
- **THEN** the pull request cannot merge

#### Scenario: Check passes and reviews are satisfied

- **WHEN** `Shell validation` passes and the pull request satisfies all other merge requirements
- **THEN** GitHub permits the pull request to merge to `main`

#### Scenario: Passing CI does not replace review

- **WHEN** `Shell validation` passes but a required review is missing and no bypass is used
- **THEN** the pull request cannot merge
