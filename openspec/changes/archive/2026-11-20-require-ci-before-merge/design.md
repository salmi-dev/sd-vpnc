# Design

## Context

`.github/workflows/ci.yml` runs `Shell validation` on pull requests and pushes to `main`. It already runs `sh tests/test-dotfiles-build.sh` alongside syntax checks, ShellCheck, and CLI smoke tests. `.github/workflows/auto-release.yml` receives CI completion events, but its automatic release job requires a successful `push` run on `main` and checks the CI run's display title. A `pull_request` run cannot satisfy the `push` condition.

## Goals / Non-Goals

Require the existing check for normal merges to `main`. Preserve the original role bypass used for direct release pushes, enforcement, ref targets, and all deletion, non-fast-forward, PR and review settings. Do not change the test suite, CLI, workflows, or release triggers.

## Decisions

- **Require the check by name and source.** GitHub reported `Shell validation` from GitHub Actions (app ID `15368`) on `main` commit `eef66b73b20d314ca8697e7da56ec4e58bcc27f4`. Require that context and integration, not the workflow `CI` or job ID `shell`. Set `strict_required_status_checks_policy` to `false`: passing CI need not also prove the PR branch is up to date.
- **Restore only the original role bypass.** The release workflow uses an admin PAT for `git push origin HEAD:main`. Removing the bypass caused Auto Release run `44762835562` to fail that push: `GH013` required a PR and `Shell validation`. The approved final policy restores `RepositoryRole` ID `5` in `always` mode on `protect-main` (ID `27733297`) rather than changing the release workflow.

## Risks / Trade-offs

- A renamed, missing or mismatched check can block merges. Confirm its name and source against the latest successful `main` CI run before applying; coordinate any future rename with the ruleset.
- This exception is role-wide, not release-specific. An authorized role holder can bypass the entire ruleset, including CI and review. For merges without bypass, passing CI clears only the CI condition.

## Migration Plan

The initial update added the check and removed the bypass (version `58792916` → `58801090`). Following the blocked release push, the user approved restoring the original actor while retaining the check. Compare the live state with the saved `58801090` snapshot and stop on drift. Restore only the bypass list from the original snapshot in one update. Read back the ruleset and effective `main` rules to verify the check, exception and unchanged settings. Do not attempt a merge, push a release commit or rerun Auto Release to test the exception.
