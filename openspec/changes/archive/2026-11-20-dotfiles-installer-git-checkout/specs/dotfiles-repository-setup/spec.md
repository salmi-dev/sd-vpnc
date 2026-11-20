## MODIFIED Requirements

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

## ADDED Requirements

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
