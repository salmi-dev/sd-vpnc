## 1. Persistent manager and exec sessions

- [x] 1.1 Add an explicit manager entrypoint mode that seeds runtime state, starts OpenVPN once, reports readiness, remains alive independently of client commands, and owns OpenVPN cleanup on stop or watcher-driven exit.
- [x] 1.2 Add an in-container session launcher/registry. Register the launcher's PID/start identity before `exec`-replacing it with the requested command; preserve local shell and remote SSH/tmux behavior. Have the host coordinator release the lease on normal engine-exec return and handled termination.
- [x] 1.3 Add a fresh manager-generation runtime registry and the in-container lock utility; verify an engine `exec` client never starts or owns a second OpenVPN process.
- [x] 1.4 Add a manager-side watcher that polls under the registry lock, does not idle-stop before the first-registration grace expires, and atomically transitions an empty post-registration manager to `STOPPING` before PID 1 exits. Define the bounded 30-second first-registration grace and clean up failed launch after that grace.

## 2. Host lifecycle coordination and startup options

- [x] 2.1 Add a private per-user lifecycle state directory and host `flock` transaction. Check for the utility before runtime changes and fail closed with installation guidance when absent.
- [x] 2.2 Start exactly one detached, owned manager on the first request; wait for readiness and session registration before releasing the transition lock. Route later regular `shell`, `ssh`, and `ssh-tmux` invocations through separate engine exec sessions.
- [x] 2.3 Serialize final lease reconciliation and stop against attach registration; coordinate host cleanup with the manager watcher through the registry `ACTIVE`/`STOPPING` transition. Stop/remove only a verified sd-vpnc manager after the last session, and leave unknown/legacy containers untouched.
- [x] 2.4 Record the first manager's effective engine/context, user, image, VPN/config/credentials and SSH source paths, workdir, rootless mode, and workspace identifier. Reject mismatches without disclosing sensitive values. Reject `--rebuild` while a live session exists; verify an idle owned manager is stopped before rebuild/restart.
- [x] 2.6 If watcher shutdown wins after a host has checked a matching manager but before registry registration, verify STOPPING/ownership (or completed auto-removal), wait under the lifecycle lock, start a replacement manager, and retry registration/session exactly once; a rejected launcher must not execute the user command or create a lease.
- [x] 2.7 Hold the lifecycle lock across `image --rebuild` idle-manager validation/stop and the complete image build; release after success and by descriptor cleanup on failure.
- [x] 2.8 Close fd 9 in the background engine-exec child only, retaining the host lock through registration acknowledgement.
- [x] 2.9 Preserve `/work` as the engine-exec cwd and regression-test the configured workdir.
- [x] 2.5 Preserve the current separate tunnel-container behavior, including `shell` target preference when that container is running; record target unification as a follow-up rather than changing tunnel behavior in this change.

## 3. Recovery and status accounting

- [x] 3.1 Record per-session process identity and manager generation. Reap only leases whose complete recorded in-container process identity is absent/exited or demonstrably reused; treat host-client death alone as insufficient evidence.
- [x] 3.2 Keep the manager running and report indeterminate lease IDs whenever process inspection, engine communication, or identity comparison fails. Make manager registry state fresh on restart and ensure stale records from an older generation cannot keep a new manager's count live.
- [x] 3.3 Extend `status` to report manager ownership and live/stale/indeterminate session counts and reconcile only provably stale leases.

## 4. Regression coverage

- [x] 4.1 Add fake-engine lifecycle tests for one first-start under concurrent requests, manager readiness, one exec per session, shell/SSH/SSH-tmux behavior, watcher-driven last-session exit, and exactly-once cleanup.
- [x] 4.2 Add deterministic attach-versus-last-release race tests, plus manager ownership, startup-option mismatch, `-C`, VPN/config/SSH source, workspace ID, and `--rebuild` cases.
- [x] 4.3 Add abnormal-exit tests for SIGKILL leaving a stale session lease, host frontend death followed by the final in-container session exit and automatic manager cleanup, stale PID/PID reuse, generation changes, and indeterminate inspection; assert that no live or uncertain lease can cause stop.
- [x] 4.4 Test startup/registration grace, failed initial exec cleanup, the rule that no manager exits before its first registration during the grace, and registration racing with watcher-driven idle shutdown under the shared registry lock.
- [x] 4.5 Add conditional Podman/Docker lifecycle smoke tests against only an already-local application image with pulls disabled; skip with a clear reason when engines/images are unavailable.
- [x] 4.6 Add a fake-engine watcher-wins-STOPPING regression proving the original launcher is rejected before its command and the host starts one replacement and retries once.
- [x] 4.7 Add deterministic build-vs-start serialization tests gated inside the fake engine; a concurrent start waits for build completion, and a failed build releases the lock on process exit.
- [x] 4.8 Kill the host before registration acknowledgement while its fake engine exec survives; prove the child does not retain the lifecycle lock and its unacknowledged command never runs.
- [x] 4.9 Functionally run the generated manager entrypoint with stubbed OpenVPN/tun readiness and assert watcher-driven shutdown executes observable OpenVPN cleanup.
- [x] 4.10 Assert every managed engine exec uses `/work` as its working directory.
- [x] 4.11 Cover `tun --rebuild` rejection for live/indeterminate leases, idle/no-manager success, and build serialization against concurrent managed start.

## 5. Documentation and validation

- [x] 5.1 Document shared manager behavior, first-session option selection/mismatch, `flock` host dependency, recovery/status behavior, `--rebuild`, and the unchanged tunnel-shell target interaction in the README.
- [x] 5.2 Run syntax checks, both behavior suites, CLI smoke checks, diff-check, and strict OpenSpec validation. Attempt ShellCheck and accurately report when the tool is unavailable; report skipped local-engine smoke checks.
