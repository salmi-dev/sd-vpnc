# vpn-container-session-lifecycle Specification

## Purpose
Specify how regular shell, SSH, and SSH-tmux sessions share a VPN manager container, how it starts and stops, and how session accounting recovers safely from abnormal termination.

## ADDED Requirements

### Requirement: A persistent VPN manager serves regular sessions

The first regular `shell`, `ssh`, or `ssh-tmux` request SHALL start one named detached manager. The manager SHALL start OpenVPN, wait for readiness, and remain alive independently of client commands. Each request SHALL run as its own engine exec session. A client ending SHALL NOT stop OpenVPN while any managed session lease remains.

#### Scenario: First session starts the manager
- **WHEN** a managed request arrives and no regular manager exists
- **THEN** `sd-vpnc` starts one detached manager, waits for VPN readiness, registers the request's lease, and launches the requested command through engine `exec`

#### Scenario: Additional sessions share the manager
- **WHEN** a matching regular manager is running and another managed request arrives
- **THEN** the request starts a new exec session without starting another container or OpenVPN process

#### Scenario: One session ends while another remains
- **WHEN** one managed session exits while another session lease is live
- **THEN** its lease is released and the shared manager and VPN remain running

#### Scenario: Last session exits
- **WHEN** the last managed session exits and reconciliation finds no live or indeterminate lease
- **THEN** the manager watcher atomically changes the manager to `STOPPING`, exits PID 1, and the detached auto-remove container stops; the host may clean up its local manager metadata

### Requirement: Local shell and remote SSH behavior is preserved

Bare `ssh` SHALL use the local login-shell selector. `ssh` with arguments SHALL invoke remote SSH, and `ssh-tmux` SHALL preserve its host/session command. `shell` SHALL use exec to attach to an existing regular manager or start a manager and shell session when none exists, subject to the existing tunnel-container target preference.

#### Scenario: First shell request starts a manager
- **WHEN** `shell` is requested and neither a regular manager nor the pre-existing tunnel-container shell target is active
- **THEN** `sd-vpnc` starts the manager and opens the local login-shell selector through engine `exec`

#### Scenario: Shell attaches to an existing regular manager
- **WHEN** `shell` is requested while the regular manager is running and no tunnel-container target takes precedence
- **THEN** `shell` runs the local login-shell selector through engine `exec` in that manager

#### Scenario: Managed exec uses the mounted work directory
- **WHEN** `sd-vpnc` starts any shell, SSH, or SSH-tmux session through engine `exec`
- **THEN** the exec process starts with `/work` as its working directory

#### Scenario: Remote SSH and SSH-tmux retain their command semantics
- **WHEN** `ssh` has SSH arguments or `ssh-tmux` has a host and optional session
- **THEN** the existing remote SSH/tmux command is executed inside the shared manager rather than replaced by the local shell selector

#### Scenario: Existing tunnel-container shell preference remains unchanged
- **WHEN** the separate tunnel container is running when `shell` is requested
- **THEN** the existing tunnel-container target preference is retained; tunnel-container lifecycle and target unification are outside this requirement

### Requirement: Host lifecycle transitions are serialized

Managed start, attach registration, final lease reconciliation, and stop decisions SHALL use one per-user host `flock` lock. The lock SHALL cover startup/registration or final reconciliation/stop, but not the interactive session. The implementation SHALL check for `flock` before changing runtime state and SHALL fail closed if it is unavailable; it SHALL NOT fall back to an unsafe lock protocol.

#### Scenario: Concurrent first requests race to start
- **WHEN** multiple managed requests arrive concurrently while no manager exists
- **THEN** serialization results in exactly one manager start and one registered exec session per request

#### Scenario: Attach races with the last-session close
- **WHEN** a new request arrives as the current final session exits
- **THEN** it either registers before the stop decision or starts a new manager after the old one stops; it never attaches to a container being stopped

#### Scenario: Watcher wins after the host's manager status check
- **WHEN** a matching owned manager passes the host status check but its watcher changes the registry to `STOPPING` before a new launcher registers
- **THEN** the registry rejects the launcher before its user command and lease can start; while retaining the host lock, the host verifies ownership and `STOPPING` (or completed stop/removal), waits for removal, starts a replacement, and retries exactly once

#### Scenario: Host dies before registration acknowledgement
- **WHEN** the host is killed before it acknowledges a registration and its background engine-exec client survives
- **THEN** the engine-exec child does not retain fd 9 or the host lifecycle lock, and its user command remains blocked until successful acknowledgement

#### Scenario: Host lock utility is unavailable
- **WHEN** `flock` is unavailable on the host
- **THEN** a managed request fails before starting, attaching to, stopping, or removing any container and explains the dependency

### Requirement: Session leases are registered and safely reconciled

The manager SHALL register each unique session lease before the attach transaction releases the host lock. Lease updates and reconciliation SHALL be serialized in the manager. A lease SHALL identify its process start and manager generation. Age or host-client death alone SHALL NOT make a lease stale. The manager SHALL stop only after a successful locked query finds no live or indeterminate lease and verifies manager ownership.

#### Scenario: A session registers before attach completes
- **WHEN** a session launcher is starting
- **THEN** it registers its lease before running the foreground shell/SSH/tmux command and before the host releases the attach transaction

#### Scenario: A launcher loses registration to STOPPING
- **WHEN** the registry lock orders `STOPPING` before a launcher's registration
- **THEN** that launcher exits without a lease or user command, allowing the locked host coordinator to replace the stopped manager and retry once

#### Scenario: A different or legacy container occupies the manager name
- **WHEN** the expected name exists but manager ownership/version cannot be verified
- **THEN** the request fails without attaching to, stopping, or removing that container

#### Scenario: Lease identity is indeterminate
- **WHEN** process inspection, manager communication, or identity comparison fails
- **THEN** the manager reports an indeterminate lease and remains running

### Requirement: Manager watcher autonomously shuts down after sessions drain

After readiness, the manager SHALL wait in `WAITING_FIRST_SESSION` for a bounded 30-second registration grace. After a session registers, its watcher SHALL reconcile leases under the registry lock. If no live or indeterminate leases remain, it SHALL atomically set `STOPPING` and exit PID 1. Uncertainty SHALL keep the manager running. A failed initial launch is stopped immediately by the host when possible, or by grace expiry if the host coordinator disappeared.

#### Scenario: Manager waits for first registration
- **WHEN** the manager has reached readiness but has not yet registered its first session and the grace period has not expired
- **THEN** the watcher keeps the manager alive in `WAITING_FIRST_SESSION`

#### Scenario: Initial session launch fails
- **WHEN** no first session registers before the bounded grace expires
- **THEN** the manager transitions to `STOPPING`, exits PID 1, and its auto-remove container is removed; if the host coordinator is still available and confirms registration failed with an empty registry, it may request this cleanup immediately

#### Scenario: Final lease is removed after host frontend death
- **WHEN** the host session coordinator has exited, then the last in-container session process exits and its lease becomes stale
- **THEN** the watcher reaps the stale lease and automatically transitions the empty manager to `STOPPING` and exits PID 1

#### Scenario: SIGKILL leaves a stale session lease
- **WHEN** the in-container session process is killed and no recorded process identity remains live
- **THEN** the watcher reaps the stale lease and automatically exits the manager after confirming no other live or indeterminate lease remains

#### Scenario: Session registration races with idle shutdown
- **WHEN** a new session registers while the watcher is reconciling an empty manager
- **THEN** the shared registry lock orders the operations: registration first counts the live lease, while `STOPPING` first rejects the session before its user command starts

#### Scenario: Watcher cannot establish lease liveness
- **WHEN** the watcher cannot inspect or reconcile one or more session leases
- **THEN** it reports/preserves the indeterminate lease and keeps the manager running

### Requirement: Abnormal session termination is recoverable

The host coordinator SHALL remove a lease after normal engine-exec return and attempt cleanup on catchable termination. The watcher, later attach, and `status` SHALL reap only leases whose in-container process identity is absent, exited/zombie, or mismatched by start identity/generation. A matching process keeps its lease even if the host client exited. Each manager generation starts with a fresh registry.

#### Scenario: Client exits normally or receives a handled signal
- **WHEN** a session command exits normally or receives a handled termination signal
- **THEN** the host coordinator attempts to release the lease and subsequent reconciliation corrects any record left behind

#### Scenario: Host client exits but in-container session remains live
- **WHEN** the host engine client exits abnormally while the in-container session identity still matches its lease
- **THEN** reconciliation retains the lease and SHALL NOT stop the manager

#### Scenario: Lease is stale or its PID was reused
- **WHEN** all recorded in-container process identities are absent, exited/zombie, or have a different start identity
- **THEN** reconciliation removes the stale lease before deciding whether the manager is empty

#### Scenario: Host or manager restarts
- **WHEN** the host or manager restarts and prior in-container session processes cannot survive that restart
- **THEN** the new manager generation starts with an empty registry and cannot count old records as live sessions

#### Scenario: Status follows an abnormal termination
- **WHEN** `status` is requested after client or host termination
- **THEN** it reports manager ownership and live/stale/indeterminate counts, reaps only provably stale records, and does not force-stop a manager with live or indeterminate leases

### Requirement: Startup options remain fixed while a manager runs

The first session's effective engine/context, numeric user, image, VPN/configuration and credentials sources, SSH source, workdir, rootless mount mode, and `DEVPOD_WORKSPACE_ID` state/value SHALL be retained for that manager. A later request with different effective options SHALL be rejected without disclosing credential contents or sensitive values and without replacing a manager that has live leases.

#### Scenario: Later request matches the manager options
- **WHEN** a later session uses the same effective startup options
- **THEN** it attaches to the existing manager

#### Scenario: Later request changes startup options
- **WHEN** a later session changes `-C`, VPN/config/credentials source, SSH source, engine/user, mount mode, image, or workspace identifier
- **THEN** it is rejected with a generic mismatch diagnostic and the existing manager remains unchanged

### Requirement: Rebuild does not replace a manager with live sessions

A `--rebuild` request SHALL NOT rebuild or replace the image while any managed session lease is live. If reconciliation proves the manager idle, `sd-vpnc` SHALL stop the owned idle manager before rebuilding and starting the request.

#### Scenario: Rebuild is requested with live sessions
- **WHEN** `--rebuild` is supplied while a managed session lease is live
- **THEN** the request is rejected before rebuilding or replacing the manager

#### Scenario: Rebuild is requested with an idle manager
- **WHEN** `--rebuild` is supplied and reconciliation finds no live or indeterminate lease
- **THEN** the owned idle manager is stopped before the image is rebuilt and the new request starts a manager from the rebuilt image

#### Scenario: Tunnel rebuild is guarded by managed sessions
- **WHEN** `tun --rebuild` is supplied while a managed lease is live or indeterminate
- **THEN** the request is rejected before rebuilding the image or starting the tunnel container

#### Scenario: Tunnel rebuild handles an idle or absent manager safely
- **WHEN** `tun --rebuild` is supplied and no managed session is live or indeterminate
- **THEN** an owned idle manager is stopped before rebuilding, while an absent manager remains untouched, and the tunnel starts from the rebuilt image

#### Scenario: Image and tunnel rebuilds serialize against managed start
- **WHEN** `image --rebuild` or `tun --rebuild` validates/stops an idle manager while another request starts
- **THEN** the rebuild holds the host lifecycle lock through build completion, preventing the concurrent request from starting or attaching until the build succeeds or fails

### Requirement: Manager lifecycle and recovery are documented

The README SHALL describe first-session manager startup, exec attachment, last-session shutdown, first-session option selection and mismatch rejection, abnormal-termination recovery, the host `flock` dependency and fail-closed behavior, `--rebuild` behavior with active sessions, and the unchanged separate tunnel-container shell-target interaction.

#### Scenario: User reviews shared-session and recovery guidance
- **WHEN** a user reads the README lifecycle guidance
- **THEN** it explains the manager/exec lifetime split, recovery of stale leases, preservation of uncertain sessions, startup-option rules, and the required host lock utility
