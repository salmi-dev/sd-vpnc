# Spec Delta

## MODIFIED Requirements

### Requirement: Runtime ownership and mount limitations are documented
The README SHALL describe baked root-owned home, private session-only runtime home, template seeding/omissions, XDG/shell/Atuin paths, mount paths, and no build-time UID arguments or permission rewrites. It SHALL distinguish home tmpfs ownership (no mapping change) from rootless Podman `--userns=keep-id` (retains `--user UID:GID` but changes mapping for the whole container). It SHALL document shared `:z` effects and recovery, unchanged rootful Podman/Docker, and unsupported rootless Docker.

#### Scenario: User reads runtime ownership guidance
- **WHEN** a user configures dotfiles setup and reviews runtime ownership guidance
- **THEN** the README explains the root-owned image template, private runtime tmpfs, fresh writable XDG state/cache/Atuin data paths, readable-only seeding without chown/chmod, omitted unreadable content, and session-only state

#### Scenario: User reads runtime mount guidance
- **WHEN** a user plans to use dotfiles configuration at runtime
- **THEN** the README explains that the host SSH directory remains mounted read-only at `/home/dev/.ssh`, `/config` remains read-only, and `/work` remains writable at its existing host-mounted path

#### Scenario: User reads interactive shell guidance
- **WHEN** a user chooses an interactive shell path
- **THEN** the README explains that `sd-vpnc shell` and bare `sd-vpnc ssh` use login Zsh when installed and interactive login Bash otherwise, Zsh is not installed by the base image, `sd-vpnc ssh HOST` still starts a remote SSH shell, and history is written under `/home/dev/.local/state`

#### Scenario: User reads rootless Podman UID mapping guidance
- **WHEN** a user reads the runtime ownership guidance for rootless Podman
- **THEN** the README distinguishes home tmpfs ownership, which does not change UID mappings, from `--userns=keep-id`, which retains `--user UID:GID` but changes the mapping for the entire container

#### Scenario: User reads rootless Podman mount security guidance
- **WHEN** a user runs rootless Podman and reviews runtime mount guidance
- **THEN** the README explains that shared `:z` persistently relabels all three host source trees, including SSH contents and VPN configuration and credentials, broadens SELinux access to `container_t` domains, and supports overlapping containers; it gives `restorecon -Rv` recovery guidance for the host config directory, SSH directory, and selected workdir, while stating config/SSH stay read-only and `/work` stays writable

#### Scenario: User reads engine compatibility guidance
- **WHEN** a user selects a container engine
- **THEN** the README states that this rootless mount-access behavior applies only to rootless Podman, Docker and rootful Podman behavior is unchanged, and rootless Docker is unsupported and outside this change

## ADDED Requirements

### Requirement: Rootless Podman can access the required host mounts
Rootless Podman runtime containers SHALL map the configured numeric UID:GID to the invoking host identity and access the existing `/work`, `/config`, and SSH bind sources. Docker and rootful Podman SHALL retain their existing user-namespace and bind behavior.

#### Scenario: Rootless Podman accesses private host directories
- **WHEN** a rootless Podman container runs with host-owned mode-0700 bind sources and mode-0600 config and SSH files
- **THEN** the configured container user can enter and write `/work`, read `/config/client.ovpn` and SSH configuration, and cannot write to the read-only `/config` or SSH mount

#### Scenario: Rootless Podman runs with SELinux enforcing
- **WHEN** a rootless Podman container accesses these host binds on an SELinux-enforcing host
- **THEN** the container can use `/work`, `/config`, and SSH under normal SELinux confinement, with config and SSH still read-only

#### Scenario: Two containers overlap under SELinux Enforcing
- **WHEN** two rootless Podman containers overlap on an SELinux-Enforcing host while using the same temporary host config, SSH, and work sources
- **THEN** both containers can read the VPN configuration and SSH configuration, cannot write to config or SSH, and can create distinct `/work` files owned by the host UID:GID without relabel conflict

#### Scenario: Other engine modes remain unchanged
- **WHEN** Docker or rootful Podman launches a runtime container
- **THEN** it retains the existing `--user UID:GID`, bind paths, mount permissions, and user-namespace behavior without rootless-only relabeling
