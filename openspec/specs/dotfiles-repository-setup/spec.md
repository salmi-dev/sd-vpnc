# dotfiles-repository-setup Specification

## Purpose
Specify the opt-in image-build workflow that clones a host-configured dotfiles repository, runs its root installer, and retains both the source and setup results in the `sd-vpnc` runtime image.

## Requirements

### Requirement: Optional host-side repository configuration
`sd-vpnc` SHALL use a nonempty `SD_VPNC_DOTFILES` as the optional dotfiles repository location during image builds and SHALL clone it with host Git. Repository URL and path forms supported by host Git and host-local Git configuration SHALL be honored; relative paths SHALL resolve from the caller's current working directory. Empty values for `SD_VPNC_DOTFILES` and `SD_VPNC_DOTFILES_REF` SHALL be treated as unset. When both values are empty or unset, `sd-vpnc` SHALL preserve the current image-build behavior exactly and SHALL NOT require host Git. Host Git SHALL be required only when a nonempty repository is configured.

#### Scenario: Repository is configured
- **WHEN** an image is built with a nonempty `SD_VPNC_DOTFILES`
- **THEN** host Git clones the configured source before the container image build proceeds

#### Scenario: Empty or unset options preserve existing behavior
- **WHEN** `SD_VPNC_DOTFILES` and `SD_VPNC_DOTFILES_REF` are both empty or unset
- **THEN** the existing image build completes without requiring Git, cloning a repository, or running dotfiles setup

#### Scenario: Relative local repository path
- **WHEN** `SD_VPNC_DOTFILES` is a relative local path
- **THEN** host Git resolves that path from the caller's current working directory

#### Scenario: Ref without repository
- **WHEN** `SD_VPNC_DOTFILES` is empty or unset and `SD_VPNC_DOTFILES_REF` is nonempty
- **THEN** image creation fails with an error that does not print the repository URL

### Requirement: Repository ref selection and Git failure handling
When a nonempty `SD_VPNC_DOTFILES_REF` is supplied with a configured repository, `sd-vpnc` SHALL select that branch, tag, or commit before using the repository for image setup. A nonempty ref beginning with `-` SHALL be rejected before invoking Git. A clone or ref-selection failure SHALL fail image creation. The operation SHALL NOT initialize submodules recursively and SHALL NOT require or support interactive prompts.

#### Scenario: Optional ref is selected
- **WHEN** a repository and a ref naming a branch, tag, or commit are configured
- **THEN** image setup uses the repository state selected by that ref

#### Scenario: Clone or ref selection fails
- **WHEN** host Git cannot clone the configured repository or select the requested ref
- **THEN** image creation fails and does not proceed as if dotfiles setup succeeded

#### Scenario: Git would require an interactive prompt
- **WHEN** host Git authentication or host-key verification would require user input
- **THEN** the operation fails noninteractively rather than prompting

#### Scenario: Repository has submodules
- **WHEN** the configured repository contains submodules
- **THEN** cloning does not recursively initialize those submodules

#### Scenario: Ref begins with a dash
- **WHEN** `SD_VPNC_DOTFILES_REF` begins with `-`
- **THEN** image creation fails before Git is invoked, rather than treating the ref as an option

### Requirement: Host authentication and error-output boundary
Repository cloning SHALL use host Git's normal configuration and authentication mechanisms. `sd-vpnc` SHALL NOT forward host credentials or authentication agents into the container build. Private repository access SHALL depend on host Git already being able to authenticate noninteractively. The host askpass helpers SHALL be disabled, while noninteractive credential helpers and SSH-agent authentication remain available. SSH command selection SHALL follow Git precedence (`GIT_SSH_COMMAND`, global/system `core.sshCommand`, `GIT_SSH`, then default `ssh`) and append `-o BatchMode=yes`; caller-project local Git config SHALL NOT supply `core.sshCommand`. A `GIT_SSH` executable path SHALL be shell-quoted so paths containing spaces work. Custom SSH commands SHALL be OpenSSH-option-compatible. Error output SHALL NOT print the configured repository URL.

#### Scenario: Private repository is accessible to host Git
- **WHEN** host Git has noninteractive authentication configured for a private repository
- **THEN** host-side cloning can proceed without forwarding credentials into the build container

#### Scenario: Private repository is not accessible noninteractively
- **WHEN** host Git cannot authenticate to the configured private repository without prompting
- **THEN** cloning and image creation fail without printing the configured URL

#### Scenario: Askpass and terminal prompting are disabled
- **WHEN** host Git clones or selects a ref
- **THEN** `GIT_ASKPASS` and `SSH_ASKPASS` point to `/bin/false`, `SSH_ASKPASS_REQUIRE=never`, `GIT_TERMINAL_PROMPT=0`, `GCM_INTERACTIVE=never`, stdin is closed, and SSH uses BatchMode

#### Scenario: Noninteractive host credentials remain available
- **WHEN** host Git has a noninteractive credential helper or SSH agent configured
- **THEN** that host-side authentication remains available without forwarding credentials or agents into the image build

#### Scenario: SSH command precedence and path with spaces
- **WHEN** more than one of `GIT_SSH_COMMAND`, global/system `core.sshCommand`, and `GIT_SSH` is configured, or the `GIT_SSH` executable path contains spaces
- **THEN** Git precedence is preserved, BatchMode is appended, and the executable path is passed as one command name

#### Scenario: Caller project SSH config is ignored
- **WHEN** image creation is invoked from a project with a local `core.sshCommand`
- **THEN** that project-local command is not selected; global/system SSH configuration or the documented environment precedence is used

### Requirement: Build context isolation and cleanup
A configured dotfiles image build SHALL use a unique temporary build context beneath the cache root. After clone and ref selection, it SHALL move the checkout's `.git` directory out of the source tree that is copied into the image, to a separate path in the same build context (after sanitizing it as specified in "Staged Git metadata is sanitized and self-contained"), before invoking the container build, and SHALL remove the entire per-run context (including that metadata) after success or any failure, including clone/ref/build failures when a partial checkout exists. An unconfigured build SHALL retain the existing `$cache_home/sd-vpnc/build` context and SHALL remove a stale `build/dotfiles` directory before building.

#### Scenario: Successful configured build uses and removes a unique context
- **WHEN** a configured repository is cloned and the container image build completes
- **THEN** its context path is unique beneath the cache root, the copied source tree contains no `.git`, the Git metadata is in a separate path in that context, and the entire context is removed afterward

#### Scenario: Concurrent configured builds do not share checkouts
- **WHEN** two configured image builds run concurrently with the same cache root
- **THEN** they use distinct contexts and each builds from its own selected checkout

#### Scenario: Failed configured build removes its temporary context
- **WHEN** cloning, ref selection, or the container image build fails after a temporary context has been created
- **THEN** the failure is reported and the entire per-run context is removed

#### Scenario: Unconfigured build removes stale dotfiles checkout
- **WHEN** an image is built with no repository configured and a stale `build/dotfiles` exists
- **THEN** the stale checkout is removed and the legacy `$cache_home/sd-vpnc/build` context is retained

### Requirement: Final image retains the repository without Git metadata
The final runtime image SHALL contain the selected repository source at `/home/dev/.dotfiles`. The integration SHALL NOT copy or commit the checkout's Git metadata into any image layer and SHALL remove any `.git` mount point, so `/home/dev/.dotfiles/.git` does not exist in the final image filesystem. This guarantee covers what the integration adds to the image; it does not prevent an installer, which runs arbitrary code as root, from deliberately copying mounted data elsewhere. This source SHALL remain in the final image so installer-created symlinks into it continue to resolve. The copy/setup process SHALL preserve file modes and SHALL NOT change modes on installer outputs.

#### Scenario: Configured repository is copied into the final image
- **WHEN** an image is built with a configured repository
- **THEN** its selected source is available at `/home/dev/.dotfiles`, the integration commits no Git metadata to any layer, and no `.git` entry exists at `/home/dev/.dotfiles/.git` in the final image

#### Scenario: Installer deliberately copies mounted metadata
- **WHEN** an installer itself copies the mounted `.git` contents to another location
- **THEN** that copy is installer behavior outside this guarantee; the metadata contains no host clone URL or credentials

#### Scenario: Installer output modes are preserved
- **WHEN** repository files or installer outputs have restrictive permissions
- **THEN** the dotfiles integration does not chmod those files or replace their permissions

### Requirement: Build-time root installer behavior
During the image build, `sd-vpnc` SHALL run a repository-root `install.sh`, if present, as root from `/home/dev/.dotfiles` using `HOME=/home/dev`, current working directory `/home/dev/.dotfiles`, the command `bash ./install.sh`, and closed stdin. While the installer step runs, the selected checkout's Git metadata SHALL be available at `/home/dev/.dotfiles/.git` through a read-only build-time bind mount that is not committed to an image layer (with the SELinux relabel option when building with Podman), so the installer can verify it runs from a Git checkout. After that step, any remaining mount-point `.git` entry SHALL be removed. The installer SHALL be noninteractive; a nonzero exit SHALL fail image creation. If the root installer is absent, setup SHALL succeed without running the script or automatically linking dotfiles. Any system changes and files made by a successful installer SHALL persist in the final image, except for the temporary Git metadata. The integration SHALL not promise tools beyond the base image; the script may use Fedora package tooling available there.

#### Scenario: Root installer succeeds
- **WHEN** the cloned repository contains a root `install.sh` that completes successfully
- **THEN** it runs as root via `bash ./install.sh` with `HOME=/home/dev`, cwd `/home/dev/.dotfiles`, and stdin closed, and its image changes persist

#### Scenario: Installer verifies a Git checkout
- **WHEN** the root `install.sh` checks that `/home/dev/.dotfiles` is a Git checkout
- **THEN** the check can succeed during the build, including `git rev-parse --is-inside-work-tree` and `git rev-parse HEAD` returning the selected commit when Git is available, because the sanitized checkout metadata is mounted at `/home/dev/.dotfiles/.git` for that step; image creation succeeds if the installer exits zero

#### Scenario: Git metadata mount point is absent after the installer step
- **WHEN** image creation completes
- **THEN** `/home/dev/.dotfiles/.git` does not exist in the final image, while the selected source and installer effects remain

#### Scenario: Root installer is missing
- **WHEN** the cloned repository does not contain a root `install.sh`
- **THEN** image creation continues successfully with source kept at `/home/dev/.dotfiles` and no automatic dotfile links created

#### Scenario: Root installer fails
- **WHEN** the root `install.sh` exits nonzero
- **THEN** image creation fails

#### Scenario: Container starts after image creation
- **WHEN** a container is started from the built image
- **THEN** dotfiles are not fetched or installed again at container startup

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

### Requirement: User-facing security and authentication documentation
The `README.md` SHALL explain that the installer executes arbitrary code as root during image build and that dotfiles startup code may execute at runtime with access to mounted SSH keys, VPN configuration and credentials, writable `/work`, and VPN connectivity. It SHALL tell users to trust the repository and ref and not store secrets in the repository, which remains in the final image. It SHALL explain that authentication uses host Git configuration, recommend a host credential helper or SSH agent, state that credentials are not forwarded and prompts are unsupported, and warn users not to embed tokens in URLs or expose repository URLs in errors. It SHALL not promise tools beyond the base image and may note available Fedora package tooling.

#### Scenario: User reads security and private-authentication guidance
- **WHEN** a user configures a private dotfiles repository
- **THEN** the README describes build-time and runtime code execution risks, sensitive resource access, source retention, host authentication constraints, and no credential forwarding

#### Scenario: User selects repository authentication
- **WHEN** a user needs host Git authentication
- **THEN** the README recommends host-side credential-helper or SSH-agent setup, disallows prompt-dependent authentication, and warns against tokens in URLs and URL disclosure in errors

### Requirement: Configuration directory mount documentation
The `README.md` SHALL describe the runtime bind mount as the host `sd-vpnc` configuration directory mounted read-only at `/config`, and SHALL state that VPN credentials stored in that mounted directory are not copied into the image. It SHALL NOT imply that arbitrary per-file `SD_VPNC_CONFIG` or `SD_VPNC_CREDENTIALS` override paths are mounted individually.

#### Scenario: User reads configuration mount guidance
- **WHEN** a user configures VPN paths and considers runtime credentials
- **THEN** the README describes the read-only configuration-directory mount and image-copy boundary accurately

### Requirement: Dotfiles changes require image rebuild
Dotfiles setup SHALL be captured at image-build time and SHALL NOT automatically reflect repository, selected-ref, or content changes after that build. The `README.md` SHALL explain how to rebuild using `sd-vpnc image --rebuild` and document local image-build validation cases, including a symlink into `/home/dev/.dotfiles`, restrictive file permissions, missing installer behavior, and runtime mount/ownership effects.

#### Scenario: Repository changes after image build
- **WHEN** repository contents or the configured ref changes after an image has been built
- **THEN** the existing image remains unchanged until it is rebuilt

#### Scenario: User rebuilds after dotfiles changes
- **WHEN** a user runs `sd-vpnc image --rebuild` after repository, ref, or content changes
- **THEN** the build uses the currently configured repository state and ref

#### Scenario: User reviews local build validation cases
- **WHEN** a user wants to validate image behavior locally
- **THEN** the README documents checks for symlinks, restrictive modes, missing installer, and runtime ownership/mount behavior

### Requirement: Staged Git metadata is sanitized and self-contained for reachable history
Before staging the checkout's `.git` for the installer mount, `sd-vpnc` SHALL remove its configured remotes (and therefore the clone URL and any credentials embedded in it), the clone reflog and `FETCH_HEAD`/`ORIG_HEAD`. If the checkout depends on `objects/info/alternates` or `objects/info/http-alternates`, `sd-vpnc` SHALL make the selected commit and its reachable history self-contained (repacking the borrowed reachable objects) and remove those files, so the metadata does not reference host paths. Unreachable objects are not guaranteed to be preserved. Sanitizing SHALL NOT change clone, ref selection, authentication or the selected commit, and failures SHALL fail image creation without printing the repository URL.

#### Scenario: Clone URL and credentials are not staged
- **WHEN** a repository URL contains an embedded token and the build context is created
- **THEN** the token appears nowhere in the staged Git metadata, the copied source's Git data, or the generated Containerfile, and the staged repository has no remote

#### Scenario: Source repository uses alternates
- **WHEN** the configured local source borrows objects through `objects/info/alternates`
- **THEN** the staged metadata has no alternates file and passes `git fsck --full` with the original repositories unavailable, with the selected commit and its reachable history intact (unreachable objects are not guaranteed)

### Requirement: Explicit container build file and engine options
`sd-vpnc` SHALL pass the generated `Containerfile` to the container engine explicitly with `-f`, so Docker, which looks for `Dockerfile` by default, and Podman build the same generated file. When the engine is `podman`, the installer bind mount SHALL include the `z` relabel option so installers can read the mounted metadata on SELinux-enforcing hosts; for other engines the option SHALL be omitted. The README SHALL state that the installer mount requires an engine supporting `RUN --mount=type=bind` and that this was verified with Podman, with Docker/BuildKit behavior (including Git `safe.directory` ownership checks) not verified here.

#### Scenario: Podman or Docker builds the generated file
- **WHEN** the image is built with either engine
- **THEN** the build command includes `-f <build context>/Containerfile`

#### Scenario: Podman on an SELinux-enforcing host
- **WHEN** the image is built with Podman
- **THEN** the installer mount uses `z` so the installer can read the mounted Git metadata

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

### Requirement: Runtime containers receive only the host DevPod workspace identifier
Both the regular runtime launch and the detached `tun` launch SHALL pass `-e DEVPOD_WORKSPACE_ID=<value>` to the container engine when the host `DEVPOD_WORKSPACE_ID` environment variable is set and non-empty. When it is unset or empty, they SHALL add no environment argument for it and SHALL otherwise keep their existing arguments. No other host environment variable SHALL be forwarded by this behavior, and the whole host environment SHALL NOT be passed through.

#### Scenario: Regular runtime launch with the variable set
- **WHEN** the host sets `DEVPOD_WORKSPACE_ID` and a regular runtime container is launched
- **THEN** the engine arguments contain `-e` followed by `DEVPOD_WORKSPACE_ID=<host value>` alongside the existing `HOME=/home/dev` environment argument

#### Scenario: Detached tunnel launch with the variable set
- **WHEN** the host sets `DEVPOD_WORKSPACE_ID` and a detached `tun` container is launched
- **THEN** the engine arguments contain `-e` followed by `DEVPOD_WORKSPACE_ID=<host value>` alongside the existing `HOME=/home/dev` environment argument

#### Scenario: Variable unset
- **WHEN** the host does not set `DEVPOD_WORKSPACE_ID` (or sets it to an empty value) and either launch path runs
- **THEN** the engine arguments contain no `DEVPOD_WORKSPACE_ID` argument and launch succeeds with its existing arguments

#### Scenario: Unrelated host variables are not forwarded
- **WHEN** the host sets other variables (for example a variable whose name merely resembles `DEVPOD_WORKSPACE_ID`) and either launch path runs
- **THEN** no engine argument forwards them

### Requirement: DevPod workspace identifier forwarding is documented
The `README.md` SHALL state that the host `DEVPOD_WORKSPACE_ID` is forwarded to regular and detached runtime containers when set and non-empty, that nothing is forwarded when it is unset or empty, and that no other host environment variables are forwarded.

#### Scenario: User reads environment forwarding guidance
- **WHEN** a user reviews the runtime guidance in the README
- **THEN** it explains the conditional forwarding of `DEVPOD_WORKSPACE_ID` to both launch paths and that no other host variable is passed
