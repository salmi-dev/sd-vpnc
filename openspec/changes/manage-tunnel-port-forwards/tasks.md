# Tasks

## 1. TUN ownership and persisted state

- [x] 1.1 Add a recognizable sd-vpnc TUN ownership marker and a versioned private tunnel manifest bound to the exact inspected `TUN_CONTAINER_NAME` container ID.
- [x] 1.2 Persist SSH host, complete ordered mappings, effective startup options, and startup source paths after successful initial tunnel readiness; atomically write mode-0600 state without source file contents or credential bytes.
- [x] 1.3 Reuse and secure the existing per-user host lifecycle lock for initial TUN start and explicit stop, including stale manifest cleanup and existing `--rebuild` handling without recursively acquiring the lock.
- [x] 1.4 Before initial start, fail closed unless authoritative full-ID/name listing proves the exact TUN name absent and, for a valid stale manifest, its saved ID absent; preserve malformed/insecure or uncertain state and require explicit stop recovery.

## 2. Port mutation commands and confirmation

- [x] 2.1 Add `tun-add-port` and `tun-rm-port` argument parsing and usage; preserve `tun HOST MAPPING...` as the initial-start interface.
- [x] 2.2 Share mapping validation for decimal ports in range, existing optional host syntax, normalized duplicate local ports, and remove-port existence checks; reject invalid input before lifecycle mutation.
- [x] 2.3 Require a running verified named TUN container and valid matching manifest for add/remove; fail closed without starting a tunnel and provide stop/fresh-start guidance for missing, stopped, legacy, or invalid state.
- [x] 2.4 Add disruption warnings and explicit interactive confirmation, `--yes` automation support, and fail closed for non-interactive use without `--yes`; keep explicit `tun --stop` prompt-free.
- [x] 2.5 Revalidate container ID and manifest under the lifecycle lock after confirmation, then serialize all TUN start/stop/add/remove state transitions and manifest updates.

## 3. Recreate and recover

- [x] 3.1 Recreate a changed non-empty mapping set using only the saved SSH host, startup paths/effective options, and new validated mappings; read current contents from saved source paths, then wait for readiness before committing the new manifest.
- [x] 3.2 Stop/remove and clear state when the last mapping is removed; do not create a zero-forward tunnel.
- [x] 3.3 Retain pending transaction state and implement rollback to the previous SSH host and mapping set using saved startup paths/effective options and their current file contents, not a snapshot of prior file contents; report recovery guidance if rollback also fails, including when current contents are invalid.
- [x] 3.4 Detect pending state left by interruption and fail start/add/remove closed until explicit `tun --stop` clears it, then direct users to start fresh.

## 4. Regression coverage

- [x] 4.1 Add fake-engine tests for exact-name targeting, ownership/manifest validation, mode-0600 atomic persistence, initial start state, and add/remove requiring an already-running verified container without auto-start.
- [x] 4.2 Test input validation for existing mapping syntaxes, ranges, valid leading-zero decimal spellings, numeric duplicate normalization, and removal matching that normalizes both the requested local port and saved mapping local-port field (including `tun-rm-port 8080` removing saved `08080:80`); also test one-mapping add, local-port-only removal, and existence checks.
- [x] 4.3 Test interactive, negative, non-interactive, and `--yes` confirmation paths, including warning/confirmation when removing the final mapping and no mutation on stale confirmation.
- [x] 4.4 Test lifecycle-lock serialization across TUN start/stop/add/remove, existing `--rebuild` behavior, successful mapping recreation, last-port cleanup, and prompt-free `tun --stop` of a legacy named target.
- [x] 4.5 Inject replacement readiness and manifest-write failures; assert successful rollback restores the old SSH host/mapping set using current source contents and failed rollback does not leave a falsely managed container or manifest.
- [x] 4.6 Simulate host interruption with pending state and verify subsequent mutations fail without touching the container until `tun --stop` clears state.
- [x] 4.7 Change saved VPN/config/credential/SSH source contents after initial start and verify confirmed reconfiguration reads the new contents; verify rollback also reads current contents and can fail when they are invalid.
- [x] 4.8 Simulate initial `tun` failing its existing 110-second readiness timeout; verify partial-container stop/removal, pending/active manifest cleanup, nonzero exit with retry guidance, and no running tunnel.
- [x] 4.9 Cover initial fresh-start absence proof with no manifest, valid stale-manifest cleanup only after both saved ID and target name are absent, a renamed saved ID that blocks start without touching the container, occupied exact names, malformed/insecure manifests, and uncertain listings despite failed inspection.

## 5. User guidance and validation

- [x] 5.1 Document port command syntax, prerequisites, no-auto-start behavior, validation, confirmation/`--yes`, persisted recreation behavior, last-port removal, and recovery guidance in the README.
- [x] 5.2 Run shell syntax checks, existing behavior suites, targeted TUN tests, diff checks, and strict OpenSpec validation; record unavailable tools or skipped runtime-engine coverage accurately.
