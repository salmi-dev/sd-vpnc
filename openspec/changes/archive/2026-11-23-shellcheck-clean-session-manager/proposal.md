# Proposal

## Why

PR #14 fails the `Shell validation` job on six ShellCheck diagnostics across `sd-vpnc` and its two shell behavior tests, so the downstream tests and smoke checks are skipped. Clean only these diagnosed findings and make the existing manager-related ShellCheck coverage explicit so the full CI job can be verified.

## What Changes

- Correct the six reported findings (SC2015, SC2016, three SC2231 findings, and SC2043) in the diagnosed files while preserving their behavior and intentional literal assertions.
- Clarify the `pull-request-ci` requirement that ShellCheck covers `sd-vpnc`, `tests/test-dotfiles-build.sh`, and `tests/test-container-session-manager.sh`, including shell code and tests changed or introduced for the session manager.
- Run the relevant local checks and verify the pull-request CI job completes ShellCheck, both behavior suites, and CLI smoke checks.
- Do not change runtime behavior, dependencies, `mise.toml`, CI workflow configuration, or unrelated files.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `pull-request-ci`: Specify the manager-related shell implementation and behavior test scripts covered by ShellCheck.

## Impact

The implementation cleanup is limited to `sd-vpnc`, `tests/test-dotfiles-build.sh`, and `tests/test-container-session-manager.sh`. The existing CI workflow already invokes ShellCheck on these three files, so no workflow change is intended. No APIs, runtime behavior, dependencies, or toolchain configuration change.
