# Spec Delta

## ADDED Requirements

### Requirement: Preserve initial TUN creation and mapping syntax

`sd-vpnc tun HOST MAPPING...` SHALL remain the initial tunnel-creation interface and continue to accept one or more complete `LOCAL:REMOTE` or `LOCAL:HOST:REMOTE` mappings. Successful publications SHALL remain bound to host loopback.

#### Scenario: Initial tunnel accepts existing mapping forms
- **WHEN** a user runs `sd-vpnc tun HOST` with one or more valid mappings
- **THEN** sd-vpnc starts an initial tunnel without requiring a prior tunnel or a port-management command

#### Scenario: Initial readiness timeout cleans up failed start
- **WHEN** an initial `tun HOST MAPPING...` start does not reach the existing 110-second readiness signal
- **THEN** sd-vpnc treats start as failed, stops/removes the partial tunnel, clears pending and active manifest state, returns nonzero with retry guidance, and leaves no running unmanageable tunnel

### Requirement: Prove initial TUN target absence before starting

Before initial tunnel creation, sd-vpnc SHALL reject pending transactions and use a successful authoritative full-ID/name listing. With no manifest, the exact TUN name must be absent. With a valid private manifest, both its saved ID and the exact name must be absent before clearing stale state. A failed inspect is not absence evidence. Uncertain state fails closed.

#### Scenario: Initial start without a manifest verifies the exact target name
- **WHEN** a user starts a tunnel and no manifest exists
- **THEN** sd-vpnc starts only after the authoritative full-ID/name listing proves the exact `TUN_CONTAINER_NAME` absent

#### Scenario: Valid stale manifest is cleared only after both saved ID and name are absent
- **WHEN** an existing valid manifest refers to a container ID and neither that ID nor the exact TUN name appears in authoritative listing
- **THEN** sd-vpnc clears the stale manifest and may start a fresh tunnel, even if a separate name inspect would fail

#### Scenario: Saved container ID survives under another name
- **WHEN** initial start finds the manifest's saved full container ID listed under a name other than `TUN_CONTAINER_NAME`
- **THEN** it fails before running a replacement, preserves manifest/pending state, leaves the renamed container untouched, and directs the user to `tun --stop` recovery

#### Scenario: Initial target absence cannot be established
- **WHEN** the exact name is occupied, the manifest is malformed/insecure, or engine/listing state is uncertain
- **THEN** initial start fails without creating a container or clearing recovery state and directs the user to `tun --stop`

### Requirement: Validate tunnel mapping ports and hosts

Initial and mutation mappings SHALL accept decimal local/remote ports in `1..65535`, including leading-zero spellings, and use the existing optional remote-host syntax. Local ports SHALL be unique after numeric normalization. For removal matching, sd-vpnc SHALL numerically normalize both the requested local port and the local-port field of each saved mapping; equivalent decimal spellings identify the same port.

#### Scenario: Invalid mapping is rejected before start
- **WHEN** a mapping is malformed, has an invalid host or out-of-range/non-decimal port, or duplicates a local port
- **THEN** sd-vpnc reports the invalid mapping and does not start a tunnel

### Requirement: Add one complete mapping

`sd-vpnc tun-add-port MAPPING [--yes]` SHALL accept exactly one full mapping in the existing `LOCAL:REMOTE` or `LOCAL:HOST:REMOTE` syntax and SHALL reject an already-published local port.

#### Scenario: Add one new mapping
- **WHEN** `tun-add-port` receives one valid mapping whose local port is not published
- **THEN** sd-vpnc proposes adding that mapping to the current complete mapping list

#### Scenario: Add rejects a duplicate local port
- **WHEN** the requested mapping duplicates a current local port, including when one spelling has leading zeroes (for example, adding `08080:80` when `8080` is already mapped)
- **THEN** sd-vpnc reports a duplicate and leaves the tunnel unchanged

### Requirement: Remove only a specified local port

`sd-vpnc tun-rm-port LOCAL_PORT [--yes]` SHALL accept exactly one local port without a remote endpoint and SHALL require that the valid in-range port exists in the current mapping list.

#### Scenario: Remove an existing local port
- **WHEN** `tun-rm-port` receives one valid local port present in the current mapping list
- **THEN** sd-vpnc proposes removing that mapping

#### Scenario: Remove matches a saved mapping with leading zeroes
- **WHEN** `tun-rm-port 8080` is invoked and the saved mapping list contains `08080:80`
- **THEN** sd-vpnc numerically matches the requested port and saved local-port field and proposes removing that mapping

#### Scenario: Remove rejects malformed or absent ports
- **WHEN** the requested local port is malformed, out of range, or absent from the current mapping list
- **THEN** sd-vpnc reports the error and leaves the tunnel unchanged

### Requirement: Restrict port mutations to the verified named TUN container

Add/remove SHALL target only the current user's exact `TUN_CONTAINER_NAME` and require that it is running, verifiably sd-vpnc-managed, and bound to a valid private tunnel manifest.

#### Scenario: Mutate a verified managed tunnel
- **WHEN** a valid add/remove request finds the exact named running tunnel with matching ownership and manifest evidence
- **THEN** sd-vpnc changes only that named tunnel after confirmation

### Requirement: Do not start a tunnel implicitly for port mutations

If the named tunnel is absent, stopped, unrecognized, or lacks a valid manifest, add/remove SHALL fail without starting, stopping, removing, or recreating any container. The diagnostic SHALL direct the user to run `tun --stop` and then start fresh with `tun HOST MAPPING...`.

#### Scenario: Add cannot start a tunnel
- **WHEN** `tun-add-port` is invoked without a verified running named tunnel and valid manifest
- **THEN** it fails with fresh-start guidance and does not issue an engine start command

#### Scenario: Unrecognized or manifest-less tunnel fails closed
- **WHEN** an add/remove operation finds the named running container but cannot verify its ownership, identity, or valid manifest
- **THEN** it leaves the container untouched and tells the user to stop it through sd-vpnc before starting a fresh tunnel

### Requirement: Save private state for successful tunnel recreation

After tunnel readiness, sd-vpnc SHALL atomically write a versioned mode-`0600` manifest in its private per-user state directory. The manifest SHALL record the SSH host, full mappings, container identity, effective startup options, and source paths, but not source file contents or credential bytes. Add/remove recreation and rollback SHALL read current contents from saved paths; edits since initial start apply to the next confirmed reconfiguration.

#### Scenario: Successful start records tunnel state
- **WHEN** an initial tunnel becomes ready
- **THEN** the private manifest records its host, mappings, container identity, and effective startup options

#### Scenario: Manifest commit fails
- **WHEN** the tunnel becomes ready but its manifest cannot be safely committed
- **THEN** sd-vpnc stops/removes the just-started tunnel and reports failure

#### Scenario: Changed source contents take effect on reconfiguration
- **WHEN** a user changes a VPN, configuration, credential, or SSH source file after initial start and then confirms an add/remove reconfiguration
- **THEN** sd-vpnc reads the current contents at the saved source paths instead of using a contents snapshot from initial start

#### Scenario: Rollback uses current source contents
- **WHEN** a requested recreation fails after the old tunnel is stopped
- **THEN** rollback attempts the old SSH host and mapping set with its saved startup paths and effective options, reading current file contents rather than restoring previous contents; rollback may fail if current source contents are missing or invalid

### Requirement: Confirm before disruptive port changes

Add/remove that changes mappings SHALL warn about tunnel and forwarded-connection interruption and require explicit affirmative confirmation before stopping/recreating. `--yes` SHALL supply consent for automation. Without it, non-interactive invocation SHALL fail without changing state. Final-port removal uses the same confirmation; `tun --stop` remains prompt-free.

#### Scenario: Interactive change requests confirmation
- **WHEN** a valid interactive add/remove is invoked without `--yes`
- **THEN** sd-vpnc warns about disruption and requires an explicit affirmative response before stopping the tunnel

#### Scenario: Declined or absent confirmation preserves state
- **WHEN** a user declines or a non-interactive caller omits `--yes`
- **THEN** sd-vpnc leaves the container and manifest unchanged

#### Scenario: Automation explicitly confirms
- **WHEN** add/remove is invoked with `--yes`
- **THEN** sd-vpnc performs the validated change without prompting

#### Scenario: Removing the last mapping requires confirmation
- **WHEN** a user requests removal of the only remaining mapping
- **THEN** sd-vpnc requires confirmation before stopping/removing the tunnel and clearing its state

### Requirement: Serialize TUN lifecycle changes

Initial start, `tun --stop`, `tun-add-port`, and `tun-rm-port` SHALL use the existing per-user host lifecycle lock for validation and mutation. After a confirmation wait, add/remove SHALL revalidate the reviewed container identity and manifest under the lock and fail without mutation if either changed.

#### Scenario: Concurrent TUN operations serialize
- **WHEN** start, stop, add, and remove operations overlap
- **THEN** the lifecycle lock orders their container and manifest mutations

#### Scenario: Tunnel changes during confirmation
- **WHEN** container identity or manifest changes after confirmation preflight
- **THEN** sd-vpnc rejects the stale confirmation and does not mutate the tunnel

### Requirement: Final-port removal clears tunnel state

Removing the last mapping after confirmation SHALL stop/remove the exact managed TUN container and clear active tunnel state instead of recreating a zero-forward tunnel.

#### Scenario: Remove the final mapping
- **WHEN** the confirmed remove operation deletes the only mapping
- **THEN** the named container is removed and active tunnel manifest state is cleared

### Requirement: Explicit stop remains prompt-free and clears state

`tun --stop` SHALL stop/remove only the exact named TUN container if present and clear active or stale tunnel state without prompting, including for a legacy or unrecognized named target.

#### Scenario: Stop an unrecognized named target
- **WHEN** `tun --stop` finds a legacy or unrecognized container at the exact TUN name
- **THEN** it stops/removes only that container and clears tunnel manifest state without confirmation

### Requirement: Refuse interrupted tunnel transactions

A pending tunnel transaction SHALL NOT be treated as a valid active manifest. If an interrupted transaction is found, start/add/remove SHALL fail without mutation and direct the user to `tun --stop`, then a fresh `tun HOST MAPPING...` start.

#### Scenario: Pending transaction blocks further mutation
- **WHEN** start/add/remove finds a pending transaction left by an interrupted operation
- **THEN** it fails without changing the container and instructs the user to clear state with `tun --stop` before a fresh start

### Requirement: Recover when tunnel recreation fails

If a confirmed non-empty mapping update fails after stopping the old tunnel, sd-vpnc SHALL remove partial replacements and attempt rollback to the old SSH host/mapping set using saved startup paths and effective options. Rollback SHALL use current source contents, not a prior-content snapshot. On success, commit state bound to the restored container; on failure, make no claim of an active tunnel and give fresh-start recovery guidance.

#### Scenario: Rollback restores the old tunnel
- **WHEN** requested recreation fails but the prior configuration can be started
- **THEN** sd-vpnc restores the prior tunnel, commits its manifest, and reports the requested change failed

#### Scenario: Rollback also fails
- **WHEN** both requested recreation and rollback fail, including because current source contents at saved paths are invalid
- **THEN** sd-vpnc does not represent a partial container as active and explains how to clear state and start a fresh tunnel

### Requirement: Document tunnel port management

The README SHALL document mutation syntax, validation, running-managed-tunnel prerequisites, no-auto-start behavior, confirmation and `--yes`, saved recreation state, final-port removal, recovery, and the unchanged initial `tun HOST MAPPING...` workflow.

#### Scenario: User reviews port-management guidance
- **WHEN** a user consults the README for tunnel port changes
- **THEN** it explains prerequisites, syntax, validation, confirmation, and recovery
