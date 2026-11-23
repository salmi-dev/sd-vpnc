# Pull request CI

## MODIFIED Requirements

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
