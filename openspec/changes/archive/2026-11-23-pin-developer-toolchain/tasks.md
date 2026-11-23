# Tasks

## 1. Pin development tools and provision macOS flock

- [x] 1.1 Add a root `mise.toml` declaring Node.js `24`, ShellCheck `0.11.0`, and `npm:@fission-ai/openspec` `2.1.1` as development tools.
- [x] 1.2 Add only the standalone `brew:flock` bootstrap package entry and restrict it to macOS with the mise OS filter; do not add Podman or Docker.
- [x] 1.3 Verify the mise configuration parses and that `mise install` recognizes the configured tool versions; verify the package dry-run skips the macOS-only Homebrew entry on Linux.

## 2. Update host dependency guidance without changing runtime safety

- [x] 2.1 Document `mise install` and `mise bootstrap packages apply` in the README, distinguishing development tools from host package provisioning.
- [x] 2.2 Document Linux `flock` from `util-linux` and macOS `brew install flock` in the README, built-in usage text, and missing-`flock` guidance; replace the incorrect `brew install util-linux` example.
- [x] 2.3 Preserve the existing pre-mutation `flock` check and fail-closed behavior when unavailable; retain coverage that no container state is changed when the utility is absent.

## 3. Validate scope and specifications

- [x] 3.1 Run strict OpenSpec change validation and the relevant shell syntax/behavior tests.
- [x] 3.2 Confirm the CI workflow is unchanged and review that no Podman/Docker tool entries or Linux Homebrew package entries were added.
