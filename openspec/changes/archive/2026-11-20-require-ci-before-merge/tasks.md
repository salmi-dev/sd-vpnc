# Tasks

## 1. Verify the existing CI and release behavior

- [x] 1.1 Confirm `.github/workflows/ci.yml` runs on PRs and `main` pushes. Syntax, image-build suite, CLI smoke and ShellCheck passed locally (installed ShellCheck `0.11.0`, invoked directly because the shim has no configured version). All CI steps passed in GitHub Actions run `44762768002`. No code, workflow or test edits are needed.
- [x] 1.2 Inspect `.github/workflows/auto-release.yml`: a successful `pull_request` completion is neither manual dispatch nor a `push` CI run, so the release job is skipped.

## 2. Require the existing CI result on main and preserve the release role

- [x] 2.1 Save the live `protect-main` ruleset (`27733297`) and compare it with pre-approval version `58792916`: active on the default branch, one `RepositoryRole` bypass, no required check. Confirm `Shell validation` from app `15368` (successful check run `136379069381`).
- [x] 2.2 Apply the initially approved check (non-strict) and bypass removal. Read back version `58801090`; confirm Auto Release run `44762835562` failed its direct push with `GH013`. Record the user's superseding decision: restore the original role, not the pre-change ruleset.
- [x] 2.3 Compare the live ruleset to the saved version `58801090` (no drift). Restore only the original `RepositoryRole` ID `5`, `always`, in one update to version `58802265`.
- [x] 2.4 Read back `protect-main`: original sole bypass restored; all other settings unchanged. Confirm `rules/branches/main` lists `Shell validation` (app `15368`, non-strict), PR/review, deletion and non-fast-forward rules. Normal merges still require CI and reviews; the role can bypass the entire ruleset. No merge, push or release rerun was attempted.
