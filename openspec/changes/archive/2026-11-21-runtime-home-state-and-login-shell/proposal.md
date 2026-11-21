# Proposal

## Why

The image's root-owned `/home/dev` prevents the actual runtime UID:GID from creating normal cache and state files, while interactive `sd-vpnc shell` currently forces Bash even when Zsh is available. A host-independent runtime home and consistent shell selection address both issues without weakening permissions or changing existing work and SSH mounts.

## What Changes

- Preserve the baked `/home/dev` and its root-owned image content, while retaining a separate image template and seeding readable entries into a private mode-0700 runtime tmpfs owned by the numeric runtime UID:GID. Never seed disposable `.cache`, `.local/state`, or Atuin data from `.atuin` (or legacy `.local/share/atuin`); create fresh writable runtime paths including `/home/dev/.atuin/data`, export `ATUIN_HOME=/home/dev/.atuin`, and seed other readable `.local` children into fresh `.local` parents. Skip unreadable entries and symlinked `.local`/`.local/share` source roots without failing startup, exclude `.ssh`, and do not change source modes or ownership in the image.
- Use engine-specific tmpfs ownership options: Podman's `--mount ... U=true,notmpcopyup` and Docker's documented numeric `uid`/`gid` `--tmpfs` options. Disable Podman image-home copy-up so prepopulated root-owned configuration cannot shadow the runtime seed. Keep XDG cache/state/data paths, Zsh history, and Atuin data under the fresh runtime directories. Runtime home and all such state are session-only and disappear when the container stops.
- Make `sd-vpnc shell` and bare `sd-vpnc ssh` (no SSH arguments) start login Zsh when present, with an explicit interactive login Bash fallback. Keep Zsh optional and store shell history under writable home state; `sd-vpnc ssh HOST` continues to open the remote SSH shell.
- Update the existing OpenSpec contract, README, and regression coverage. Keep the current `--user UID:GID`, `/work` mount, and read-only SSH mount behavior unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `dotfiles-repository-setup`: Define writable session-only runtime home state, template seeding and mount boundaries, shell selection/fallback, and corresponding user guidance.

## Impact

Affects generated image setup and entrypoint/runtime arguments in `sd-vpnc`, shell invocation in both interactive paths, image/runtime behavior tests, and README guidance. No new dependency or persistent host mount is required; Zsh remains optional.
