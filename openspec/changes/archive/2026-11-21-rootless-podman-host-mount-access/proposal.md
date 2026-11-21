# Proposal

## Why

After the home tmpfs change, rootless Podman still fails before VPN startup because the configured container UID maps to a subordinate host UID that cannot traverse the mode-0700 `/work` directory; SELinux also denies access to host home/config/SSH labels. The entrypoint first changes to `/work`, then reads `/config/client.ovpn` and later SSH configuration, so all three host binds must be addressed for users to test gh-7.

## What Changes

- Detect rootless Podman at runtime and, only for that case, add `--userns=keep-id` while retaining the existing `--user UID:GID`.
- Apply shared SELinux `:z` relabeling to the rootless Podman binds for `/work`, read-only `/config`, and read-only `/home/dev/.ssh`. Preserve mount destinations, read/write modes, and the existing rootful Podman and Docker behavior.
- Document that home tmpfs ownership alone does not change UID mappings, while rootless Podman `--userns=keep-id` changes the mapping for the entire container and retains `--user UID:GID`. Explain that shared `:z` persistently relabels all three source trees (including SSH contents and VPN config/credentials), broadens access to `container_t` domains, and can be undone with `restorecon -Rv` on the host config directory, SSH directory, and selected workdir. Keep Docker and rootful Podman unchanged; rootless Docker remains unsupported and outside this change.
- Add fake-engine assertions and conditional real rootless Podman smoke tests for config/SSH reads, `/work` writes and host ownership, existing home tmpfs/template seeding, and two overlapping containers sharing the same config/SSH/work sources. The concurrent smoke verifies both containers can use the binds, especially under SELinux Enforcing. Tests use only a local image and skip when unavailable; they never pull.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `dotfiles-repository-setup`: Specify rootless Podman access to all required host mounts and the associated README guidance, without changing Docker or rootful Podman behavior.

## Impact

Changes runtime argument construction in `sd-vpnc`, its runtime fake-engine and conditional Podman smoke coverage, the `dotfiles-repository-setup` contract, and README runtime/security guidance. No new dependency or persistent host data mount is introduced; rootless Podman intentionally changes its user-namespace mapping and shared SELinux labels for the three existing mounts.
