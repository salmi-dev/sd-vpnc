# Design

## Context

The CI workflow already runs ShellCheck explicitly on `sd-vpnc`, `tests/test-dotfiles-build.sh`, and `tests/test-container-session-manager.sh`, before the behavior tests and CLI smoke checks. The reported run found SC2015 in `sd-vpnc`, SC2016 in the dotfiles-build test, three SC2231 findings and one SC2043 finding in the session-manager test. See `proposal.md` for the motivation and the `pull-request-ci` delta for the coverage contract.

## Goals / Non-Goals

**Goals:**
- Remove only the six reported ShellCheck findings without changing script behavior.
- Keep CI's explicit three-file ShellCheck invocation and verify that successful lint allows the downstream checks to run.

**Non-Goals:**
- Refactor surrounding shell code or tests beyond what is needed for the reported diagnostics.
- Change workflow configuration, runtime behavior, dependencies, `mise.toml`, or unrelated files.

## Decisions

- **Fix the underlying shell expressions rather than broadly suppressing diagnostics.** Make the conditional intent explicit for SC2015, preserve the test's literal expected shell text with correct quoting for SC2016, quote the directory portion of the lease globs for SC2231, and remove the redundant single-item loop for SC2043. These are local edits that preserve the existing checks and execution behavior; broad rewrites or warning suppressions would obscure the intent.
- **Keep the existing ShellCheck target list.** All manager-related shell implementation and behavior test files named in this change are already passed to ShellCheck by `.github/workflows/ci.yml`. The change clarifies that coverage in the specification; modifying workflow configuration or adding lint tooling is unnecessary.
- **Verify the entire CI sequence after lint succeeds.** Run ShellCheck and the same syntax, behavior, and CLI checks locally, then require a passing PR CI run. A green result must include the steps that were skipped after ShellCheck failed in the reported run.

## Risks / Trade-offs

- **A quoting cleanup could change the literal text asserted by the test** → retain the exact expected string and run the dotfiles-build behavior test.
- **A local ShellCheck pass could fail to catch workflow coverage drift** → verify the existing file list and inspect the PR CI result, including downstream job steps.
- **A test failure could be hidden if only lint is rerun** → require both behavior suites and the CLI smoke checks to complete successfully.
