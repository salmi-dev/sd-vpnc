# Tasks

## 1. Build flow

- [x] 1.1 In `sd-vpnc`, sanitize the clone's Git metadata (remove remotes, clone reflog, `FETCH_HEAD`/`ORIG_HEAD`; repack and drop alternates), then move `.git` to `$build_dir/dotfiles-git`.
- [x] 1.2 Generate the installer step with `RUN --mount=type=bind,source=dotfiles-git,target=/home/dev/.dotfiles/.git[,z] ...` (same installer command; `z` for Podman only) followed by `RUN rm -rf /home/dev/.dotfiles/.git`.
- [x] 1.3 Pass `-f "$build_dir/Containerfile"` to the engine build.

## 2. Tests

- [x] 2.1 Fake engine requires `-f <context>/Containerfile`, stages `dotfiles-git` separately and rejects a sentinel token in the staged metadata or Containerfile; fake Git models remotes and clone reflog.
- [x] 2.2 Regression installers: fake-Git/Containerfile structure check, and with real Git per ref (branch, tag, commit) the generated installer command runs `git rev-parse --is-inside-work-tree` and checks `HEAD` equals the selected commit in the mounted checkout; sentinel absent from staged metadata.
- [x] 2.3 Hermetic local alternates fixture: staged metadata has no alternates and, with the originals moved away, passes `git fsck --full` and keeps the selected HEAD and reachable history (unreachable objects are not asserted).
- [x] 2.4 Docker path test (no Podman on `PATH`): build uses `docker`, passes `-f`, and does not use `z`.
- [x] 2.5 Existing no-installer, permission, failure, ref-selection and unconfigured-build tests still pass.

## 3. Docs and verification

- [x] 3.1 Update `README.md` for sanitized temporary `.git` availability, engine requirements and the narrowed guarantee.
- [x] 3.2 Syntax, ShellCheck 0.11.0, the test suite, mutation checks, CLI smoke tests, and the opt-in real Podman check (unique image tag, fails on leaks) pass. Docker not installed; not run against real Docker.
