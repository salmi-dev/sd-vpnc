# Proposal

## Why

`sd-vpnc` currently owns one SSH or shell command as the VPN container's main process. A second SSH or SSH-tmux request is rejected while that container is running, and the container exits with the first command. A shared manager process and per-session leases are needed so shell, SSH, and SSH-tmux clients can share one VPN connection and the VPN container is stopped only after the final managed session ends.

## What Changes

- Start the regular VPN container once in detached, auto-remove manager mode. Its entrypoint starts OpenVPN and remains alive independently of interactive clients; after the final lease is gone, an in-container watcher transitions it to stopping and exits PID 1 even if the host coordinator disappeared. It no longer owns an SSH or shell session.
- Run each requested shell, remote SSH, or SSH-tmux command as a separate `docker exec`/`podman exec` session in that manager container. Preserve bare `ssh` as the local interactive shell, `ssh HOST` as remote SSH, and existing SSH-tmux command behavior.
- Add a serialized host lifecycle transaction and per-session leases in the container. Register a session before releasing the start/attach transaction; reconcile leases and stop only an sd-vpnc-managed container after the last live lease is gone. Keep a newly ready manager in a 30-second first-registration grace state; clean up a failed launch after the grace or immediately when the host confirms registration failed.
- Require the host `flock` utility for the short lifecycle critical sections. Do not assume it is part of POSIX `sh` or preinstalled; fail before changing container state if it is unavailable, and document installation/runtime requirements. Include the needed lock utility in the runtime image for the in-container lease registry.
- Snapshot the first manager's effective engine, identity, image, VPN/config/SSH/workdir sources, and forwarded workspace identifier. Reject later sessions whose effective launch options differ rather than silently attaching with the first caller's mounts or environment. Reject `--rebuild` while live sessions are attached; if the manager is idle after lease reconciliation, stop it before rebuilding and starting a new manager.
- Account for normal exit, signal handling, abrupt client termination, and host restart. A manager-side lease watcher automatically reaps provably stale leases and shuts down after at least one session has registered and no live or indeterminate lease remains. If liveness cannot be established, preserve the lease and container and report the uncertainty.
- Extend lifecycle regression tests and document sharing, first-session options, dependency/recovery behavior, and validation guidance.
- Out of scope: tunnel-container lifecycle and tunnel-port operations, DevPod engine support, and WireGuard support.

## Capabilities

### New Capabilities

- `vpn-container-session-lifecycle`: Specify shared manager startup, session attachment and accounting, safe shutdown/recovery, option consistency, and user guidance.

### Modified Capabilities

None.

## Impact

Affects the runtime launch and shell/SSH/SSH-tmux dispatch in `sd-vpnc`, the generated container entrypoint/session helper, runtime dependencies, lifecycle regression coverage, and README guidance. It does not change image publishing or the separate tunnel workflow. Requiring host `flock` is an explicit compatibility tradeoff: systems without it must install a compatible implementation before using managed sessions; `sd-vpnc` will fail closed rather than substitute a racy stale-lock protocol.
