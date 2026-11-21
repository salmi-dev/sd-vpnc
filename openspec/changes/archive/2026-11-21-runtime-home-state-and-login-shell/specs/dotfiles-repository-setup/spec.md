# Spec Delta

## MODIFIED Requirements

### Requirement: Runtime ownership and mount limitations are documented
The `README.md` SHALL state that the baked home remains root-owned while runtime `/home/dev` is private, writable, and session-only. It SHALL document template seeding and unreadable/disposable-root omission, XDG paths, Zsh/Bash history, Atuin's `ATUIN_HOME` data location, optional login Zsh with login Bash fallback, bare-SSH versus remote-SSH behavior, unchanged `/work` and read-only SSH mounts, and the lack of host UID build arguments or permission rewrites.

#### Scenario: User reads runtime ownership guidance
- **WHEN** a user configures dotfiles setup and reviews runtime ownership guidance
- **THEN** the README explains the root-owned image template, private runtime tmpfs, fresh writable XDG state/cache/Atuin data paths, readable-only seeding without chown/chmod, omitted unreadable content, and session-only state

#### Scenario: User reads runtime mount guidance
- **WHEN** a user plans to use dotfiles configuration at runtime
- **THEN** the README explains that the host SSH directory remains mounted read-only at `/home/dev/.ssh` and `/work` remains mounted from the host

#### Scenario: User reads interactive shell guidance
- **WHEN** a user chooses an interactive shell path
- **THEN** the README explains that `sd-vpnc shell` and bare `sd-vpnc ssh` use login Zsh when installed and interactive login Bash otherwise, Zsh is not installed by the base image, `sd-vpnc ssh HOST` still starts a remote SSH shell, and history is written under `/home/dev/.local/state`

## ADDED Requirements

### Requirement: Runtime home state is writable without host ownership mapping
Each runtime container SHALL expose `/home/dev` as a private mode-0700 tmpfs owned by its configured numeric UID:GID. It SHALL seed readable template entries as that user, exclude `.ssh`, omit unreadable entries without failing startup, and discard runtime home state when the container stops.

#### Scenario: Arbitrary runtime UID:GID writes home state
- **WHEN** a container starts with a runtime UID:GID different from the image's root-owned files
- **THEN** `/home/dev` is owned by that UID:GID with mode 0700 and that user can create and write `/home/dev/.cache`, `/home/dev/.local/state`, and `/home/dev/.atuin/data` beneath it without world-writable permissions

#### Scenario: Readable template content is seeded safely
- **WHEN** the image template contains readable files, symlinks, unreadable root-owned entries, and `.ssh`
- **THEN** ordinary readable content is copied under the runtime UID:GID with its modes and symlinks preserved, unreadable entries are omitted without startup failure, and `.ssh`, `.cache`, `.local/state`, `.atuin`, and legacy `.local/share/atuin` data are not seeded

#### Scenario: Prepopulated Atuin config is writable after seeding
- **WHEN** the image home contains a root-owned readable `/home/dev/.config/atuin` directory and the runtime UID:GID starts with the home tmpfs
- **THEN** baked home children are not copied into the tmpfs before template seeding, and the template creates a runtime-owned writable `/home/dev/.config/atuin` in which that user can create or update `config.toml`

### Requirement: Disposable cache, state, and Atuin roots are fresh and writable
Runtime startup SHALL create fresh mode-0700 `.cache`, `.local/state`, `.local/share`, `.atuin`, and `.atuin/data` directories owned by the numeric runtime UID:GID. It SHALL exclude `.cache`, `.local/state`, `.atuin`, and legacy `.local/share/atuin` from seeding, create fresh writable `.local` and `.local/share` parents, seed other readable children, set XDG homes and `ATUIN_HOME=/home/dev/.atuin`, and leave source modes and ownership unchanged.

#### Scenario: Restrictive template ancestors do not block runtime state
- **WHEN** the template has mode-0555 `.cache`, `.local`, `.local/state`, `.local/share`, `.local/share/atuin`, `.atuin`, and `.atuin/data` roots containing stale markers and readable sibling tools
- **THEN** runtime `.cache`, `.local`, `.local/state`, `.local/share`, `.atuin`, and `.atuin/data` are fresh mode-0700 directories owned by the runtime UID:GID; cache, history, and Atuin data writes succeed, readable sibling tools retain their modes and symlinks, disposable markers are absent, and all source roots remain mode 0555

#### Scenario: Existing host mounts are unchanged
- **WHEN** a runtime container starts with the writable home tmpfs
- **THEN** the existing host `/work` mount remains writable at `/work` and the existing host SSH mount remains read-only at `/home/dev/.ssh`

#### Scenario: Runtime home state ends with the container
- **WHEN** a container using the runtime home tmpfs stops or is removed
- **THEN** its runtime home, cache, shell history, Atuin data, and state changes are not persisted into the image or host filesystem

### Requirement: Interactive shells prefer login Zsh with Bash fallback
Local interactive shell entry points SHALL prefer login Zsh when available, with interactive login Bash as fallback, without changing destination-based remote SSH behavior. Zsh SHALL remain optional.

#### Scenario: Zsh is available to sd-vpnc shell
- **WHEN** `sd-vpnc shell` opens an interactive session and Zsh is installed
- **THEN** it starts a login Zsh session instead of Bash

#### Scenario: Bare SSH starts the local interactive shell
- **WHEN** the user runs `sd-vpnc ssh` without a destination or SSH arguments and Zsh is installed
- **THEN** it starts the local login Zsh session instead of invoking remote SSH

#### Scenario: SSH destination keeps remote-shell behavior
- **WHEN** the user runs `sd-vpnc ssh HOST` without a remote command
- **THEN** the SSH client connects to `HOST` and opens the remote default shell without invoking the local shell selector

#### Scenario: Zsh is unavailable
- **WHEN** either interactive shell path runs without Zsh installed
- **THEN** it starts an interactive login Bash session

#### Scenario: Interactive history uses writable state
- **WHEN** either interactive shell saves history
- **THEN** Zsh/Bash history is placed under `/home/dev/.local/state` and Atuin uses `ATUIN_HOME=/home/dev/.atuin` with writable data under `/home/dev/.atuin/data` for the runtime UID:GID
