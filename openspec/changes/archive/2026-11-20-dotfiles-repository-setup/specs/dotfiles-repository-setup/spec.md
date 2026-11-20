## ADDED Requirements

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
A configured dotfiles image build SHALL use a unique temporary build context beneath the cache root, remove `.git` before invoking the container build, and remove the entire per-run context after success or any failure, including clone/ref/build failures when a partial checkout exists. An unconfigured build SHALL retain the existing `$cache_home/sd-vpnc/build` context and SHALL remove a stale `build/dotfiles` directory before building.

#### Scenario: Successful configured build uses and removes a unique context
- **WHEN** a configured repository is cloned and the container image build completes
- **THEN** its context path is unique beneath the cache root, `.git` is absent, and the entire context is removed afterward

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
The final runtime image SHALL contain the selected repository source at `/home/dev/.dotfiles`, without `.git` metadata. This source SHALL remain in the final image so installer-created symlinks into it continue to resolve. The copy/setup process SHALL preserve file modes and SHALL NOT change modes on installer outputs.

#### Scenario: Configured repository is copied into the final image
- **WHEN** an image is built with a configured repository
- **THEN** its selected source is available at `/home/dev/.dotfiles` and no `.git` directory or Git credential configuration is included

#### Scenario: Installer output modes are preserved
- **WHEN** repository files or installer outputs have restrictive permissions
- **THEN** the dotfiles integration does not chmod those files or replace their permissions

### Requirement: Build-time root installer behavior
During the image build, `sd-vpnc` SHALL run a repository-root `install.sh`, if present, as root from `/home/dev/.dotfiles` using `HOME=/home/dev`, current working directory `/home/dev/.dotfiles`, the command `bash ./install.sh`, and closed stdin. The installer SHALL be noninteractive; a nonzero exit SHALL fail image creation. If the root installer is absent, setup SHALL succeed without running the script or automatically linking dotfiles. Any system changes and files made by a successful installer SHALL persist in the final image. The integration SHALL not promise tools beyond the base image; the script may use Fedora package tooling available there.

#### Scenario: Root installer succeeds
- **WHEN** the cloned repository contains a root `install.sh` that completes successfully
- **THEN** it runs as root via `bash ./install.sh` with `HOME=/home/dev`, cwd `/home/dev/.dotfiles`, and stdin closed, and its image changes persist

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
The `README.md` SHALL explain that `/home/dev` and the copied repository are baked into the image and root-owned, are not host-persisted or generally writable by the runtime host UID, and that restrictive root-owned file modes may make outputs unreadable by that UID. It SHALL advise installers to create runtime-readable configuration rather than secrets, and SHALL explain that no host UID build arguments or permission rewrites are provided. It SHALL state that the runtime host's read-only SSH directory masks `/home/dev/.ssh` and that `/work` is mounted.

#### Scenario: User reads runtime ownership guidance
- **WHEN** a user configures dotfiles setup
- **THEN** the README describes image-baked root ownership, runtime writability/readability limitations, preserved modes, and the required non-secret runtime-readable outputs

#### Scenario: User reads runtime mount guidance
- **WHEN** a user plans to use dotfiles configuration at runtime
- **THEN** the README explains the `/home/dev/.ssh` read-only host mount and the `/work` mount

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
