# Tasks

## 1. Runtime home and image template

- [x] 1.1 Add a separate home template after the installer and `.git` cleanup while retaining the baked `/home/dev` and `/home/dev/.dotfiles`; verify image-build tests confirm ordering, no `.git` or `.ssh` in the template, and preserved readable file modes and symlinks.
- [x] 1.2 Add the Podman `--mount type=tmpfs,destination=/home/dev,tmpfs-mode=0700,U=true,notmpcopyup` and Docker `--tmpfs /home/dev:rw,uid=$uid,gid=$gid,mode=0700` arguments to both regular and detached runtime launches; verify fake-engine tests preserve `--user UID:GID` and existing mounts, and conditional Podman/Docker smoke tests use only local images (never pull). Include the prepopulated local application-image `.config/atuin` copy-up regression when available.
- [x] 1.3 Seed readable template entries into the tmpfs as the runtime user, excluding `.ssh`, `.cache`, `.local/state`, `.atuin`, and legacy `.local/share/atuin`; create fresh private runtime-owned cache/state/Atuin roots and seed other readable `.local` children into fresh parents. Verify restrictive-mode (0555) cases, writable `.atuin/data`, session-only Atuin data, source-mode preservation, ordinary symlinks, symlinked `.local`/`.local/share` roots with an external sentinel, unreadable-entry omission, and writable `.config/atuin` from a prepopulated root-owned template.
- [x] 1.4 Update README runtime ownership and mount guidance to explain Podman no-copy-up, fresh XDG and `/home/dev/.atuin/data` locations, `.local` sibling seeding, omitted disposable roots, unchanged mounts, session-only state, and bare SSH versus remote SSH; verify Docker smoke guidance requires a local image and never promises a pull.

## 2. Interactive shell selection

- [x] 2.1 Add a shared selector for login Zsh when available and interactive login Bash otherwise, with history under `$XDG_STATE_HOME` and Atuin data under `$ATUIN_HOME/data`; verify tests exercise both executable choices and writable fresh state/data paths without adding Zsh to the base image.
- [x] 2.2 Route `sd-vpnc shell` and bare `sd-vpnc ssh` without SSH arguments through the selector, preserve remote `sd-vpnc ssh HOST` behavior, and document both paths; verify tests cover selector choices and that a destination is forwarded to remote SSH rather than treated as a local shell.

## 3. Integration validation

- [x] 3.1 Run the complete behavior suite, shell syntax checks, ShellCheck, and strict OpenSpec validation; verify runtime argument tests show no world-writable mode, chown/chmod rewrite, `/work` change, or SSH-mount change.
