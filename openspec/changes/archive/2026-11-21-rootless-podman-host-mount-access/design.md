# Design

## Context

See `proposal.md` for the motivation and the complete scope. Both regular and detached launches currently retain `--user UID:GID`, use a private `/home/dev` tmpfs, and bind the host configuration directory read-only at `/config`, the host SSH directory read-only at `/home/dev/.ssh`, and the host work directory writable at `/work`. The entrypoint enters `/work` before reading the VPN configuration and later reads SSH configuration, so each bind must be accessible before the normal workflow can proceed.

The reported rootless mapping has container UID 0 mapped to host UID 1000 and container UID 1000 mapped to subordinate host UID 525287. The host bind roots are mode 0700 and owned by host UID 1000. Under SELinux Enforcing, the sources have `data_home_t`, `config_home_t`, and `ssh_home_t` labels not accessible to the container's `container_t` domain.

## Goals / Non-Goals

**Goals:**
- Make the existing three binds accessible to the configured runtime identity for rootless Podman while preserving their paths and read/write permissions.
- Keep SELinux confinement enabled and allow concurrent regular and detached containers to share these sources.
- Ensure rootful Podman and Docker invocation arguments and behavior remain unchanged.

**Non-Goals:**
- Support rootless Docker, change host ownership/modes, or replace the existing host binds.
- Disable SELinux labeling or use a private per-container label for shared sources.
- Change the existing `/home/dev` tmpfs/template seeding contract.

## Decisions

### Gate changes on rootless Podman detection

For the Podman engine, use `podman info --format '{{.Host.Security.Rootless}}'` to identify rootless operation. Only an explicit `true` selects the rootless argument set; a false result retains the existing rootful Podman arguments. Do not run this probe for Docker. If the probe fails or returns an unusable result, report the detection failure instead of silently launching Podman without the required rootless access configuration; this avoids treating an unknown rootless engine as rootful.

### Preserve the numeric user and add keep-id for rootless launches

Add `--userns=keep-id` to rootless Podman launches and retain the existing `--user UID:GID`. This maps the invoking host UID/GID into the same numeric container identity used by `--user`, so mode-0700 host-owned directories are traversable without changing their DAC permissions. Apply the same user-namespace behavior to regular and detached launch paths. Do not add the option to rootful Podman or Docker. Unlike changing host permissions, keep-id does affect how ownership across the container's whole namespace is presented, so runtime tests must verify `/work` files are owned by the caller and home tmpfs ownership/template seeding still work.

### Use shared SELinux relabeling on all three rootless bind sources

For rootless Podman only, use the shared `:z` relabel option on the `/config:ro`, `/home/dev/.ssh:ro`, and `/work` bind mounts. Retain `ro` on config and SSH and the default writable mode on `/work`. A shared label is required because regular and detached containers can overlap while using the same host directories. Do not use `:Z`, which assigns a private label and can conflict with concurrently running containers. Do not use `label=disable`, which would remove SELinux confinement rather than granting narrowly scoped access to the required mounts.

The relabel recursively changes SELinux labels persistently across all three host source trees, including SSH contents and VPN configuration and credentials. Document that this broadens access to `container_t` domains, not just the initiating container, and provide `restorecon -Rv` recovery guidance for the actual host config directory, SSH directory, and selected workdir. Keep source ownership and mode unchanged.

### Validate both argument selection and actual mount behavior

Extend fake-engine tests for regular and detached launch paths. Simulate rootless Podman and assert `--userns=keep-id`, the retained `--user UID:GID` and home tmpfs, and the three expected shared relabeled binds with config/SSH still read-only. Simulate rootful Podman and Docker and assert no rootless-only userns or relabel options and no change to their existing mount arguments. Verify the detection probe is only used for Podman.

Add conditional real rootless Podman smokes using temporary local work, config, and SSH directories owned by the test user, with mode-0700 directories and mode-0600 files. Use an already-present application image only; skip when Podman is unavailable/not rootless or the image is absent, and never pull. A single-container smoke verifies config and SSH reads, failed writes to read-only sources, a successful `/work` write owned by the host UID:GID, and existing `/home/dev` tmpfs/template seeding under keep-id.

Add a separate overlap smoke that starts two containers concurrently with `--userns=keep-id`, the retained `--user UID:GID`, and the same shared-`:z` config, SSH, and work sources. Keep both running while checking from each that VPN config and SSH files are readable, config/SSH writes fail, and distinct work files can be created with host UID:GID ownership. On SELinux-Enforcing hosts, run these checks while enforcement is active; both containers must retain access throughout the overlap. Skip only the enforcement-specific assertion when SELinux is not Enforcing, while still exercising overlapping Podman mounts. Stop and remove both containers and temporary sources in cleanup.

## Risks / Trade-offs

- `:z` persistently relabels all three source trees, including SSH contents and VPN config/credentials, and broadens access to `container_t` domains → explain this security boundary in README and document `restorecon -Rv` recovery for the host config directory, SSH directory, and selected workdir.
- `container_t` access is broader than access to a single container → use only the shared label required by concurrent regular/detached containers; preserve SELinux enforcement and the read-only config/SSH mounts.
- `--userns=keep-id` changes UID/GID mapping throughout the container, unlike home tmpfs ownership alone → explain the distinction in README, retain the explicit `--user UID:GID`, and test host ownership, home tmpfs, and template seeding under rootless Podman.
- The rootless detection probe can fail or return an unexpected value → fail visibly rather than silently run with a mapping that cannot access the host sources; cover rootless/rootful selection and probe failure with fake-engine tests.
- Rootless Docker is not handled by this Podman-specific strategy → state this limitation in README; do not modify or infer Docker rootless behavior in this change.

## Migration Plan

No host data migration or image rebuild is required. The first rootless Podman run applies shared labels recursively to the three existing source trees, including their contents. To roll back, remove the rootless-only arguments and run `restorecon -Rv` on the actual host config directory, SSH directory, and selected workdir to restore policy-default labels; the original rootless DAC failure may then recur. Docker and rootful Podman need no migration.
