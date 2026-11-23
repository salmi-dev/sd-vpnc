# Design

## Context

`start_tun` launches a detached container under the per-user `TUN_CONTAINER_NAME`, publishing each supplied local port to `127.0.0.1`. The container engine fixes those publications at container creation. TUN operations use the existing host lifecycle lock and private per-user state directory. Initial start must distinguish a genuinely absent target from stale or ambiguous saved state before it removes any manifest or creates a replacement container.

## Goals / Non-Goals

**Goals:**
- Add and remove forwards only on the running, verified sd-vpnc TUN container named by `TUN_CONTAINER_NAME`.
- Never start a tunnel implicitly from `tun-add-port` or `tun-rm-port`.
- Preserve the existing SSH host, forward set, and effective startup configuration when recreating a tunnel after a confirmed change.
- Serialize all TUN lifecycle mutations against one another and other users of the host lifecycle lock.
- Recover the previous tunnel configuration when a replacement cannot be completed.

**Non-Goals:**
- Change regular VPN session-manager lifecycle or shell/SSH behavior.
- Change initial `tun HOST MAPPING...` mapping syntax or readiness behavior; its target-absence and stale-manifest checks are strengthened to fail closed.
- Add support for DevPod engines or WireGuard.
- Edit tracker state.

## Decisions

### Keep the initial tunnel command and validate mutation arguments independently

Keep `tun HOST MAPPING...` as the command that creates a tunnel from scratch. Add two separate top-level commands:

- `tun-add-port LOCAL:REMOTE [--yes]` or `tun-add-port LOCAL:HOST:REMOTE [--yes]` accepts exactly one full mapping.
- `tun-rm-port LOCAL_PORT [--yes]` accepts exactly one local port and no remote endpoint.

Reuse the mapping rules of initial `tun`: local and remote ports are decimal values in `1..65535`, including leading-zero spellings; the optional remote host uses the existing allowed hostname character set; and local ports must be unique by numeric value. Compare numeric values for duplicate detection and removal matching, normalizing both the requested `LOCAL_PORT` and each saved mapping's local-port field. For example, `tun-rm-port 8080` removes a saved mapping spelled `08080:80`, and either spelling of the same port is a duplicate when adding. Removal validates the same range and fails if that numeric port is not in the saved mapping list. Construct the proposed full mapping list before touching the running container. Do not widen these commands into arbitrary engine/container selection: every inspect, stop, removal, and recreation targets only the current user's exact `TUN_CONTAINER_NAME`.

### Bind managed ownership to the named running container and private manifest

Add a stable sd-vpnc TUN ownership label when creating a TUN container and record its engine container ID in a versioned tunnel manifest. A manifest is valid only when its private file has the required mode and format, the named container is running and carries the expected ownership label, and its inspected container ID matches the manifest. Validate the saved mapping list and startup fields before use. Treat inspection failure, an invalid/insecure manifest, an ID mismatch, a stopped container, or a missing container as a failed add/remove precondition. Report that the user can explicitly run `tun --stop` and start a fresh tunnel with `tun HOST MAPPING...`; do not attempt to repair, start, stop, or remove the target as part of add/remove failure handling.

Store the manifest in the existing private per-user `sd-vpnc` state directory, with restrictive directory permissions and mode `0600` for the file. Write through a private temporary file and atomically rename it only after the container reaches tunnel readiness. Include the SSH destination, ordered complete mappings, inspected container identity, and the effective values required to recreate the same tunnel (selected engine/connection context, runtime identity, image, work directory, VPN/config/credentials and SSH source paths, mount mode, and forwarded workspace identifier state/value where applicable). Store source paths and effective settings, not source file contents or credential bytes. Whenever add/remove recreates a tunnel or attempts rollback, read the current contents at the saved source paths; edits made since initial start therefore take effect on the next confirmed reconfiguration. Use a versioned, unambiguous data format; never source/evaluate manifest contents as shell code. If a successful container start cannot be committed to a valid manifest, stop/remove that just-started container and report failure rather than leave a tunnel that cannot be safely managed.

An existing running container with no valid ownership/manifest evidence is not eligible for add/remove or automatic recreation. Before initial start, reject pending transactions, verify the engine, then use the authoritative `container ls --all --no-trunc --format '{{.ID}}|{{.Names}}'` listing: without a manifest, require the exact `TUN_CONTAINER_NAME` to be absent; with a valid private manifest, require both its saved full container ID and that exact name to be absent before clearing the stale manifest. A saved ID still listed under another name, an occupied exact name, a malformed/insecure manifest, or uncertain engine/listing state fails closed, retains recovery files, and directs the user to explicit `tun --stop` recovery. Never use a failed name inspect as proof of absence and never unconditionally remove the manifest. The initial `tun HOST MAPPING...` start retains its existing 110-second readiness timeout. If readiness is not reached within that timeout, treat startup as failed: stop/remove the partial tunnel, clear pending and active manifest state only after absence is verified, return nonzero, and direct the user to retry `tun HOST MAPPING...`; do not leave a running unmanageable tunnel. `tun --stop` remains an explicit cleanup operation for the exact named target and never searches for or changes other containers.

### Confirm disruption before replacing immutable port publications

After validating the proposed mapping set and current manifest, explain that engine port publications are immutable and that the operation will interrupt SSH forwards while it stops and recreates the tunnel. An interactive caller must explicitly confirm before the old container is stopped. `--yes` is an explicit opt-in for automation and suppresses the prompt. If no confirmation flag was supplied and stdin is not a terminal, fail without changing container or manifest state; do not infer consent from redirected input or output. Apply this confirmation rule to both add/remove reconfiguration, including removal of the final mapping. The explicit `tun --stop` command remains prompt-free.

Perform preflight and confirmation without holding the shared lifecycle lock while waiting for user input. Record the exact container ID and manifest contents that were reviewed; after confirmation, acquire the lock and revalidate that the running target and manifest still match that snapshot. If another lifecycle operation changed them, fail without stopping anything and ask the caller to retry against the current tunnel. For `--yes`, acquire the lock and validate immediately before mutation. Hold the lock across each actual start, stop, add, remove, or recreate transaction, including waiting for readiness and committing state. This keeps the potentially long human response outside the critical section while preventing stale confirmation from authorizing a different tunnel.

### Recreate from the saved startup state and recover the old mapping set on failure

For a confirmed non-empty mapping update, retain the verified old manifest and write a private pending-operation record before stopping the old container. Recreate using the saved SSH host and effective startup options, changing only the validated mapping list. Retain the existing loopback-only publication behavior. Wait for the normal tunnel readiness signal before atomically replacing the active manifest with one bound to the new container ID; remove the pending record only after the new manifest is committed. Read current source contents from the saved paths for this recreation, not copies captured when the old tunnel started.

If stop/recreate/readiness/manifest commit fails after the old tunnel has been stopped, remove any partial replacement and make a best-effort rollback by recreating the prior SSH host and mapping set using its saved startup paths and effective options. Rollback reads current source contents at those saved paths; it does not restore a snapshot of previous file contents and can fail if the current contents are missing or invalid. If rollback succeeds, commit a manifest bound to the restored container and return an error explaining that the requested change failed and the previous tunnel was restored. If rollback also fails, leave no partially managed container or claim of a successful update, clear the active manifest, retain recovery diagnostics/state only as needed for explicit cleanup, and report that the tunnel is down and must be started again with `tun HOST MAPPING...`. `tun --stop` clears any remaining pending and active tunnel state.

When removal produces an empty mapping list, after confirmation stop/remove the verified named container and atomically clear the active manifest; do not start a zero-forward replacement. Add and remove never change mappings on a different named or selected container.

If the host process is interrupted while a pending-operation record exists, do not treat either the pending target or the old container as a verified current tunnel. Until the user explicitly runs `tun --stop` to remove the exact named target and clear transaction state, fail further start/add/remove operations without mutation and direct the user to stop then start a fresh tunnel. This is a fail-closed recovery path for interruption outside the live process's best-effort rollback window.

### Serialize tunnel lifecycle mutations through the existing host lock

Use the existing per-user host `lifecycle.lock` for `tun HOST MAPPING...`, `tun --stop`, `tun-add-port`, and `tun-rm-port`. Hold it from the final state recheck through stop/start/readiness/manifest commit or clear. Ensure `--rebuild` on initial `tun` uses the already-held lifecycle transaction rather than trying to reacquire the same lock recursively; retain existing rebuild safety and release the lock on success and failure. Keep engine build/start/stop calls and state-file changes inside the transaction so concurrent TUN operations cannot race or overwrite one another. Continue to fail closed when the existing host lock dependency is unavailable.

## Risks / Trade-offs

- Recreating a tunnel interrupts all its active SSH port forwards, even when one mapping is changed → require explicit confirmation, display the exact proposed change, and preserve `--yes` only as explicit automation consent.
- A process/host failure between stopping the old container and committing the replacement can leave interrupted state → retain a mode-0600 pending record; fail later start/add/remove operations closed and require explicit `tun --stop` followed by a fresh start. Never interpret a stale manifest as proof that the current container is managed.
- The existing host lifecycle lock also protects regular VPN manager transitions → avoid holding it while waiting at an interactive prompt, then recheck container ID and manifest under lock before changing anything. A slow build/readiness wait still serializes host lifecycle operations by design.
- A manifest contains host paths, SSH destination, and effective engine settings → keep it under the private state directory at mode `0600`, never store source file contents or credential bytes, and keep validation/diagnostics from echoing potentially sensitive values. Reconfiguration and rollback consume current contents from saved paths, so changed or invalid source files affect the next operation.
- A container can be manually removed/recreated under the same name, or renamed while its manifest remains → bind the manifest to an ownership marker and inspected container ID; before a fresh start require the full ID and exact target name to be absent from authoritative listing, and fail closed on either match or uncertainty.
- Failure to recreate both the requested and previous tunnel can leave no working tunnel → report the state clearly, preserve actionable recovery guidance, and ensure explicit `tun --stop` clears stale state before a fresh initial `tun` command.

## Validation Strategy

- Fake-engine regression tests verify the exact target name, ownership label/container-ID binding, mode-0600 atomic manifest creation, saved host/mappings/effective options, add/remove mapping changes, safe initial target-absence checks, and that add/remove without a running verified tunnel never invoke engine start.
- Cover syntax, numeric range, and leading-zero decimal spellings; verify duplicate-local-port and remove-port matching normalize both requested and saved local-port values (including removing saved `08080:80` with `tun-rm-port 8080`) before stop/recreate; verify that initial `tun HOST MAPPING...` continues accepting multiple mappings.
- Verify warning and confirmation behavior for interactive and non-interactive callers, including `--yes`, redirected input, final-port removal, and refusal without any stop when confirmation is missing.
- Race concurrent start/stop/add/remove calls against the shared lifecycle lock; verify that a changed manifest/container ID between confirmation and lock reacquisition causes a safe retry error without mutation.
- Change VPN/config/credential/SSH source contents after initial start; verify the next confirmed add/remove recreation reads the current contents at saved paths. Inject replacement start, readiness, and manifest-commit failures after the old tunnel is stopped; verify rollback attempts the old SSH host/mapping set/startup paths using current source contents (not a prior-content snapshot), succeeds when those current contents are valid, and may fail with recovery guidance when they are invalid. Verify rollback failure leaves no falsely managed tunnel.
- Verify initial start with no manifest requires the authoritative full-ID/name listing to show the exact TUN name absent. Verify a valid stale manifest is cleared only after its saved ID and exact name are both absent; saved-ID rename, an occupied exact name, malformed/insecure manifest, engine failure, or listing failure must retain state and issue `tun --stop` recovery guidance. Inject failed name inspection alongside positive/negative listing evidence to prove inspection is not absence evidence. Verify the initial 110-second `tun` readiness timeout stops/removes the partial container only after authoritative absence is verified, clears pending/active manifest state, returns nonzero with retry guidance, and leaves no running unmanageable tunnel. Verify last-port removal stops/removes the exact TUN container and clears active/pending state; verify `tun --stop` remains prompt-free for the exact legacy/unrecognized named target.
- Run shell syntax checks, ShellCheck, all three regression suites, CLI smoke checks, diff checks, and strict OpenSpec validation for implementation work.
