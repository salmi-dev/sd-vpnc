# Tasks

## 1. Clean the diagnosed ShellCheck findings

- [x] 1.1 Replace the ambiguous `&&`/`||` conditional in `sd-vpnc` with an explicit conditional that preserves the same failure behavior; verify `shellcheck sd-vpnc` passes.
- [x] 1.2 Preserve the literal expected entrypoint text in `tests/test-dotfiles-build.sh` with warning-free quoting; verify ShellCheck and `sh tests/test-dotfiles-build.sh` pass.
- [x] 1.3 Quote the directory expansions in all three lease globs and simplify the one-item utility loop in `tests/test-container-session-manager.sh`; verify ShellCheck and `sh tests/test-container-session-manager.sh` pass.

## 2. Validate the complete pull-request check

- [x] 2.1 Run ShellCheck on all three specified files, `sh -n` on each, both behavior suites, and the CLI smoke checks from `.github/workflows/ci.yml`; verify every command passes.
- [x] 2.2 Verify strict OpenSpec validation with `openspec validate shellcheck-clean-session-manager --strict --type change` passes.
- [x] 2.3 Before the approved push, verify the existing workflow configuration and local CI-equivalent checks cover the full check sequence; GitHub CI itself remains pending until the approved push.
