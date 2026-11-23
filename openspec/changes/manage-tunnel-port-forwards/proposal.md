# Proposal

## Why

`sd-vpnc tun` publishes host ports when it creates the detached TUN container, but container port publications cannot be changed in place. Users currently have to stop and recreate the entire tunnel to change a forward, and the invocation state needed to reproduce that tunnel is not retained. Add focused commands for changing forwards without risking an unrelated or unrecognized container or silently disrupting an active tunnel.

## What Changes

- Add `tun-add-port MAPPING [--yes]` for exactly one complete `LOCAL:REMOTE` or `LOCAL:HOST:REMOTE` mapping and `tun-rm-port LOCAL_PORT [--yes]` for exactly one local port. Validate the existing port/host syntax and port ranges, reject duplicate local ports on add, and require the selected local port to exist on removal.
- Operate only on the per-user named `TUN_CONTAINER_NAME`. Adding/removing a mapping requires that this exact container is running, is verified as sd-vpnc-managed, and has a valid private tunnel manifest. Add/remove fail without starting a tunnel when these preconditions do not hold.
- Warn that changing a published port stops and recreates the tunnel, and require explicit interactive confirmation before interruption. `--yes` supplies consent for automation; a non-interactive invocation without `--yes` fails without stopping the tunnel.
- Persist the SSH host, complete mapping list, effective startup options, and source paths in a private mode-0600 manifest after `tun` reaches readiness, without storing source file contents or credential bytes. Add/remove recreation and rollback read current contents from those saved paths, so edits since initial start apply to the next confirmed reconfiguration; rollback restores the old host/mapping set using current source contents and can fail if they are invalid. `tun --stop` remains explicit and non-interactive, and clears tunnel state.
- Treat the existing 110-second initial `tun` readiness timeout as a failed start: stop/remove the partial tunnel, clear pending/active manifest state, and return nonzero with retry guidance instead of leaving an unmanageable running tunnel.
- If the last mapping is removed, stop/remove the managed TUN container and clear its manifest instead of recreating a tunnel with no forwards. Preserve `tun HOST MAPPING...` as the initial tunnel-creation interface.
- Serialize TUN start, stop, add, and remove using the existing per-user host lifecycle lock. Attempt rollback to the prior tunnel configuration if replacement fails after stopping the old container.

## Capabilities

### New Capabilities

- `tunnel-port-management`: Define safe mutation of forwards on a verified running TUN container, saved recreation state, confirmation, lifecycle serialization, and failed-recreation recovery.

### Modified Capabilities

None.

## Non-goals

- Change VPN session-manager behavior or its container lifecycle.
- Make `tun-add-port` start a tunnel when none is already running.
- Change the initial `tun HOST MAPPING...` interface or add unrelated tunnel behavior.
- Implement unrelated DevPod or WireGuard work.
- Edit tracker issues or status.

## Impact

The proposal affects the `sd-vpnc` TUN command surface, tunnel state under the existing private per-user state directory, and future TUN lifecycle/argument regression coverage and user guidance. It does not modify application code, documentation, or tests in this proposal-only change.
