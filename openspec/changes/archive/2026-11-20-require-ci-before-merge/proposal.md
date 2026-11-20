# Proposal

## Why

Pull requests already run `Shell validation`, including automated tests. Before this change, `protect-main` did not require the result. Issue #3 asks that a normal pull request cannot merge to `main` while CI is failing or still running.

## What Changes

- Require the existing `Shell validation` check from GitHub Actions (app ID `15368`) on `protect-main`, without requiring branches to be up to date.
- Retain the original sole bypass actor (`RepositoryRole` ID `5`, `always`) so release automation can still push directly to `main`. This role can bypass the entire ruleset, including the CI, PR and review requirements; normal merges cannot.
- Specify the behavior already provided by CI and release automation: PRs run the image-build test suite alongside shell validation and smoke checks, and PR runs do not publish releases.

## Capabilities

### New Capabilities

- `pull-request-ci`: Defines what CI checks on a pull request, how the result gates a merge to `main`, and why a PR run cannot produce an automatic release.

### Modified Capabilities

None.

## Impact

Only ruleset `27733297` changes. Removing the bypass during rollout blocked Auto Release's direct push (`GH013`, run `44762835562`); restoring the original role preserves that release path. The only net policy change is the required check. No code, test or workflow changes are needed.
