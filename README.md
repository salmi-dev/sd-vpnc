# sd-vpnc

[![CI](https://github.com/salmi-dev/salmidev-tools-vpn-client/actions/workflows/ci.yml/badge.svg)](https://github.com/salmi-dev/salmidev-tools-vpn-client/actions/workflows/ci.yml)
[![Auto Release](https://github.com/salmi-dev/salmidev-tools-vpn-client/actions/workflows/auto-release.yml/badge.svg)](https://github.com/salmi-dev/salmidev-tools-vpn-client/actions/workflows/auto-release.yml)
[![Latest Release](https://img.shields.io/github/v/release/salmi-dev/salmidev-tools-vpn-client?label=release)](https://github.com/salmi-dev/salmidev-tools-vpn-client/releases/latest)
![POSIX sh](https://img.shields.io/badge/POSIX-sh-4EAA25)

`sd-vpnc` is a single executable that starts an OpenVPN container and then
optionally opens an SSH or tmux session through the VPN. It supports Podman and
Docker.

The executable contains the container definition and entrypoint. Users do not
need a separate `Containerfile`, build script, or runtime script.

## Install

Copy the executable somewhere on `PATH`:

```bash
install -m 755 sd-vpnc ~/.local/bin/sd-vpnc
```

The first run builds a local container image. Subsequent runs reuse it.
Rebuild explicitly after changing the executable or container definition:

```bash
sd-vpnc --rebuild
```

The image is built locally, so no registry account or published image is
required.

## Development setup

The repository pins its development tools in `mise.toml`. From the repository
root, install them with:

```bash
mise install
```

Apply configured host packages with:

```bash
mise bootstrap packages apply
```

The configured `flock` package is the standalone Homebrew formula and applies
only on macOS; Homebrew must be installed. On Linux, install `flock` from your
distribution's `util-linux` package instead.

## Configuration

Create the configuration directory and copy the example files:

```bash
mkdir -p ~/.config/sd-vpnc
cp config/client.ovpn.example ~/.config/sd-vpnc/client.ovpn
cp config/credentials.example ~/.config/sd-vpnc/credentials
chmod 700 ~/.config/sd-vpnc
chmod 600 ~/.config/sd-vpnc/credentials
```

Edit `client.ovpn` with the provider settings. The credentials file contains
exactly two lines: username and password. It is optional when the provider uses
certificate authentication or another authentication method.

The default paths are:

```text
~/.config/sd-vpnc/client.ovpn
~/.config/sd-vpnc/credentials
~/.ssh
~/.local/share/sd-vpnc/       default container work directory
~/.cache/sd-vpnc/             generated build context
```

`XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and `XDG_CACHE_HOME` are respected.
`SD_VPNC_CONFIG`, `SD_VPNC_CREDENTIALS`, and `SD_VPNC_SSH_CONFIG` can override
individual configuration paths. The default paths are printed by `sd-vpnc
--help` and `sd-vpnc status`.

### Optional dotfiles repository

An optional repository can seed the image's `/home/dev` during image build:

```bash
export SD_VPNC_DOTFILES=git@github.com:example/dotfiles.git
export SD_VPNC_DOTFILES_REF=main   # optional branch, tag, or commit
sd-vpnc image --rebuild
```

`SD_VPNC_DOTFILES` accepts repository URLs and paths understood by host Git,
including local paths. Relative local paths are resolved from the directory
where `sd-vpnc` is invoked. Empty values are treated as unset. A nonempty
`SD_VPNC_DOTFILES_REF` without a nonempty repository is an error. When both
are unset or empty, the current image build path is unchanged and Git is not
required. Refs beginning with `-` are rejected rather than being interpreted
as Git options. Host Git does not recursively initialize submodules, and
clone/ref selection do not support interactive prompts.

Host Git performs the clone and optional ref selection using its normal local
configuration and authentication. For private repositories, configure a host
credential helper or SSH agent that can authenticate without prompting. Host
credential helpers and agents that operate noninteractively remain available;
host credentials and agents are not forwarded into the image build. Askpass
helpers are not supported: `sd-vpnc` disables `GIT_ASKPASS` and `SSH_ASKPASS`,
disables terminal prompts, closes Git stdin, and requests SSH BatchMode. Do not
embed tokens in repository URLs; `sd-vpnc` suppresses Git error output so the
configured URL is not printed on clone/ref errors.

For SSH URLs, command precedence is `GIT_SSH_COMMAND`, global `core.sshCommand`,
system `core.sshCommand`, `GIT_SSH`, then the default `ssh`. Caller-project local
`core.sshCommand` is ignored for the dotfiles fetch; use `GIT_SSH_COMMAND` for a
per-invocation override. `sd-vpnc` appends `-o BatchMode=yes` to the chosen
command so authentication cannot prompt. Custom SSH commands therefore need to
accept OpenSSH-compatible `-o` options; `GIT_SSH` is treated as an executable
path (including paths with spaces), not a command string. SSH config and
agent-based authentication remain available.

Configured builds use a unique temporary context beneath the cache root and
remove that context after success or failure. Unconfigured builds retain the
existing cache `sd-vpnc/build` context (under `XDG_CACHE_HOME` or `~/.cache`)
and remove any stale dotfiles checkout there before building.

The selected source is copied into the final image at
`/home/dev/.dotfiles` without `.git` metadata. If the repository root contains
`install.sh`, image creation runs it as root with Bash from
`/home/dev/.dotfiles`, with `HOME=/home/dev` and stdin closed. The script must
not expect input. While it runs, a sanitized copy of the checkout's Git
metadata is bind-mounted read-only at `/home/dev/.dotfiles/.git`, so the
installer can verify it runs from a Git checkout (for example with `git
rev-parse --is-inside-work-tree` and `git rev-parse HEAD`, if it installs Git
first; the base image has none). The mounted metadata has no remote, so the
clone URL and any credentials embedded in it are not exposed, and no clone
reflog; for the selected commit and its reachable history, objects borrowed from
a source repository's alternates are copied in so they do not depend on host
paths (unreachable objects are not guaranteed to be preserved). `sd-vpnc` does not commit the
mounted metadata to an image layer and removes any `.git` mount point, so
`/home/dev/.dotfiles/.git` does not exist in the final image. This describes
what `sd-vpnc` adds to the image: an installer runs arbitrary root code and could
still copy the mounted data elsewhere. The build uses `RUN --mount=type=bind`, so
the engine must support it. This was verified with Podman (which `sd-vpnc` mounts
with the `z` relabel option so SELinux hosts allow the read); Docker with
BuildKit is passed `-f` for the generated `Containerfile` and is not
relabeled, but Docker was not run against a real daemon here, and Git's
`safe.directory` ownership check may affect installer Git commands there. The
installer still sees the repository's committed history and objects, so do not
store secrets in it. A missing `install.sh` is a successful skip; no dotfiles
are automatically linked. Installer-created symlinks into `.dotfiles`, files,
and system changes persist in the image. Only tools already in the Fedora base
image are available unless the installer adds more; Fedora package tooling
may be used during the build.

The repository itself remains in the image, so do not store secrets in it.
The installer is arbitrary root code during image build. Dotfiles startup code
may also run later at runtime with access to mounted SSH keys, VPN
configuration and credentials, writable `/work`, and VPN connectivity. Only
use a repository and ref you trust. Changes to repository contents or the
selected ref do not update an existing image; rebuild with
`sd-vpnc image --rebuild` after repository, ref, or content changes.

## Usage

Initialize the configuration directory:

```bash
sd-vpnc init
```

Inspect the local setup:

```bash
sd-vpnc status
```

For concise tool instructions intended for AI agents, run:

```bash
sd-vpnc agent
```

Connect with an interactive shell, SSH, or SSH plus tmux:

```bash
sd-vpnc ssh
sd-vpnc ssh vpn-host
sd-vpnc ssh -o ConnectTimeout=10 vpn-host
sd-vpnc tun vpn-host 8080:80 8443:localhost:443
sd-vpnc tun --stop
sd-vpnc ssh-tmux vpn-host work-session
```

Manage the local image explicitly:

```bash
sd-vpnc image
sd-vpnc image --rebuild
```

Global options may appear before the subcommand:

```bash
sd-vpnc -C "$PWD" ssh vpn-host
sd-vpnc --workdir ~/projects/my-repository ssh-tmux vpn-host work-session
sd-vpnc --help
sd-vpnc version
```

`ssh` passes all arguments after the subcommand directly to the OpenSSH client,
so use normal `ssh` argument ordering: options first, then the host, followed by
an optional remote command. With no arguments, it opens an interactive shell
in the connected VPN container. `ssh-tmux` requires a host and optionally
accepts a tmux session name. For SSH local forwarding that should be reachable
from the host machine, use `tun` rather than `ssh -L`:

- `LOCAL:REMOTE` forwards host `127.0.0.1:LOCAL` to `localhost:REMOTE` as seen
  from the SSH server.
- `LOCAL:HOST:REMOTE` forwards host `127.0.0.1:LOCAL` to `HOST:REMOTE` as seen
  from the SSH server.

For example, `sd-vpnc tun vpn-host 8080:80 8443:db.internal:443` publishes both
ports on the host's loopback interface. The command starts a detached container
and returns to your prompt once the VPN and SSH forwarding listeners are ready.
Stop the tunnel with `sd-vpnc tun --stop`.

Since the tunnel is detached, SSH authentication and host-key verification must
complete without prompts. Pre-accept the host key (e.g. by connecting with
`sd-vpnc ssh HOST`) and use a key that requires no passphrase prompt;
password/passphrase prompts are not supported by this command.

Regular `ssh`, `ssh-tmux`, and `shell` sessions share one detached VPN manager.
The first request starts the manager, which starts OpenVPN once and remains
alive independently of client commands. Each request uses its own engine `exec`
session; closing one shell/SSH/tmux session does not interrupt another. The
manager stops and is auto-removed after the final session ends. A container-side
watcher performs the same cleanup if the host command disappears.

The first manager selects the effective engine/context, numeric user, image,
VPN/config/credentials and SSH source paths, work directory, rootless mount
mode, and `DEVPOD_WORKSPACE_ID`. Later requests must use matching options;
`sd-vpnc` rejects mismatches without printing the stored values. End all sessions
before changing those options. `--rebuild` is rejected while any live or
indeterminate managed session exists; an idle owned manager is stopped before
rebuilding/restarting. `sd-vpnc image --rebuild` follows the same active-session
safety check and stops an idle owned manager before rebuilding.

On startup the manager allows up to 30 seconds for its first session to
register. Session leases record the manager generation and the in-container
process PID/start identity. `status` reconciles only provably stale leases and
reports live, stale, and indeterminate counts (including IDs for uncertain
leases). Host-client death alone is not evidence that a session ended. If
process/engine inspection is uncertain, the lease and manager are preserved;
this can leave a manager running until the uncertainty is resolved.

Lifecycle start/attach/last-session transitions require the host `flock`
utility (provided by Linux `util-linux`; on macOS, install it with
`brew install flock`). The command checks for it before changing container
state and fails closed with installation guidance if it is missing; there is
no racy shell-lock fallback. Private lifecycle metadata is stored in
`$XDG_STATE_HOME/sd-vpnc` or `~/.local/state/sd-vpnc`.

Open another terminal and run:

```bash
sd-vpnc shell
# `sd-vpnc cli` is an alias
```

This opens an additional local shell in the shared regular manager, or starts a
manager and shell if none exists. The exception is the existing separate tunnel
container: while it is running, `shell` continues to prefer that container.
Tunnel lifecycle and shell-target unification are unchanged and are separate
from the regular shared-session manager.

`sd-vpnc shell` and bare `sd-vpnc ssh` (without a destination or SSH arguments)
start login Zsh when Zsh is available, and otherwise start interactive login
Bash. Zsh is optional and is not installed by the base image; a dotfiles
installer may add it. Shell history is written under
`/home/dev/.local/state/sd-vpnc` for the lifetime of the container. By contrast,
`sd-vpnc ssh HOST` invokes remote SSH and opens the remote default shell when no
remote command is supplied; it does not select a local Zsh/Bash session.

When the host environment has a non-empty `DEVPOD_WORKSPACE_ID`, `sd-vpnc`
forwards its value to the regular VPN manager and detached `sd-vpnc tun`
container, so tools such as Starship can display it. If it
is unset or empty, nothing is forwarded and launch is unchanged. No other host
environment variable is forwarded.

`--workdir`/`-C` mounts a host directory as `/work` inside the container. The
option is the reliable way to choose a project directory; a container cannot
change the current directory of its parent shell.

## Runtime requirements

- Podman or Docker
- `/dev/net/tun` on the host
- Permission to run containers with `NET_ADMIN`
- The host `flock` utility for serialized manager lifecycle changes (Linux:
  `util-linux`; macOS: `brew install flock`)
- An OpenVPN provider configuration

The runtime process uses the invoking host UID:GID, and runtime files in `/work`
retain that host ownership. The image is not built with host-specific UID/GID
arguments. `/work` is mounted from the host; the host's SSH directory is
mounted read-only at `/home/dev/.ssh`, masking any image content at that path.

The baked `/home/dev` and `/home/dev/.dotfiles` remain root-owned in the image.
At runtime, a private mode-0700 tmpfs overlays `/home/dev` and is owned by the
invoking numeric UID:GID. Podman uses tmpfs `U=true,notmpcopyup` to set the
home mount's ownership without copying baked root-owned children into it;
Docker uses tmpfs `uid`, `gid`, and `mode` options. **Home tmpfs ownership by
itself does not change a container's UID mapping.** For rootless Podman only,
`sd-vpnc` also uses `--userns=keep-id` while retaining `--user UID:GID`; this
changes the mapping for the entire container so the configured runtime user
maps to the invoking host identity and can traverse the private host bind
sources. This is distinct from the home tmpfs ownership behavior. Rootful
Podman and Docker retain their existing user-namespace behavior; rootless Docker
is unsupported by this rootless mount-access behavior. No world-writable mode,
build-time host UID/GID argument, or image-home ownership/permission rewrite is
used.

Rootless Podman uses shared `:z` relabeling on the host configuration directory
mounted read-only at `/config`, the host SSH directory mounted read-only at
`/home/dev/.ssh`, and the writable host work directory mounted at `/work`. The
shared label is needed because regular and detached containers may overlap and
use the same sources; a private `:Z` label would conflict. This persistently
relabels all three source trees and their contents, including SSH files and VPN
configuration and credentials. The shared label broadens SELinux access to
`container_t` domains, while SELinux confinement remains enabled and config/SSH
remain read-only inside the container.

To restore the host policy-default labels after use, run `restorecon -Rv` on the
actual configuration directory, SSH directory, and selected work directory. For
the defaults (replace the final path when using `-C`/`--workdir`):

```sh
restorecon -Rv \
  "${XDG_CONFIG_HOME:-$HOME/.config}/sd-vpnc" \
  "${SD_VPNC_SSH_CONFIG:-$HOME/.ssh}" \
  "${XDG_DATA_HOME:-$HOME/.local/share}/sd-vpnc"
```

After the root installer and temporary `.git` cleanup, a separate image template
is made from the baked home without `.ssh`. At startup, readable ordinary files
and symlinks are seeded into the tmpfs as the runtime user, preserving their
modes but not root ownership. Unreadable root-owned entries are omitted without
failing startup; they remain unavailable to the runtime user. The template's
source modes and ownership are unchanged.

Disposable state roots are not seeded. Fresh private runtime-owned directories
are created for `/home/dev/.cache`, `/home/dev/.local/state`,
`/home/dev/.local/share`, `/home/dev/.atuin`, and `/home/dev/.atuin/data`; fresh
`.local` and `.local/share` parents prevent restrictive baked parent modes from
blocking writes. Other readable `.local` children, such as tools under
`.local/bin`, are seeded into the fresh parent. `XDG_CACHE_HOME`,
`XDG_STATE_HOME`, and `XDG_DATA_HOME` point to the corresponding runtime paths.
Zsh/Bash history goes under the state home; `ATUIN_HOME=/home/dev/.atuin`
places Atuin data under `/home/dev/.atuin/data`. Both `.atuin` and legacy
`.local/share/atuin` data are excluded from template seeding. The tmpfs, cache,
history, and Atuin data are session-only and disappear when the container
stops. Rebuild the image to refresh the baked home template; no `chown` or
`chmod` is applied to image home content.

The host's SSH directory is mounted read-only at `/home/dev/.ssh`, masking any
image content there; the host configuration directory is read-only at `/config`,
and the host work directory is writable at `/work`.

## Security

The command grants the container `NET_ADMIN` and access to `/dev/net/tun`, which
are required for OpenVPN. Only use configurations, images, and dotfiles
repositories you trust. The dotfiles installer executes arbitrary code as root
at image-build time. Dotfiles startup code may execute at runtime and can then
access the read-only mounted SSH directory, read-only VPN configuration and
credentials, writable `/work`, and VPN connectivity. Do not store secrets in
the dotfiles repository; its source is retained in the final image.

The host `sd-vpnc` configuration directory (`$XDG_CONFIG_HOME/sd-vpnc`, or
`~/.config/sd-vpnc` when `XDG_CONFIG_HOME` is unset) is mounted read-only at
`/config` when the container runs. VPN credentials stored in that mounted
directory are supplied through the mount and are not copied into the image.
Host Git credentials and authentication agents are used only by host Git during
image creation and are never forwarded into the build container.

### Manual local-image validation

In a disposable environment with a test repository, rebuild the image and
check the following before relying on the setup:

- Have `install.sh` create a symlink into `/home/dev/.dotfiles`; verify the
  source remains in the final image and the symlink resolves there. Verify an
  installer that requires a Git checkout succeeds, that `.git` is absent from
  the final image, and that the temporary checkout is removed from the host
  build context after both successful and failed builds.
- Have the installer create a restrictive root-owned file (for example mode
  `0600`); confirm its mode is preserved and that the runtime host UID may be
  unable to read it. Use only runtime-readable, non-secret configuration for
  normal operation.
- Build once with no root `install.sh`; confirm the repository remains in the
  image but no automatic links are created. Separately test a failing script
  and a system-level change to confirm failure propagation and persistence.
- At runtime, verify with a non-image UID:GID that `/home/dev` and fresh
  `.cache`, `.local/state`, `.local/share`, `.atuin`, and `.atuin/data` paths have
  mode `0700` and accept writes. Use template `.cache`, `.local`, state/share,
  and `.atuin` roots with mode `0555`; confirm readable sibling tools and
  symlinks are seeded, disposable markers are excluded, and source template
  modes remain unchanged. Confirm Zsh/Bash history and Atuin data point into the
  writable session paths, while `.ssh` remains read-only and `/work` is
  unchanged.
- Check generated rootless/rootful Podman and Docker runtime arguments with fake
  engines for regular and detached launches, including rootless-detection
  failures. When rootless Podman and a local `localhost/sd-vpnc:$VERSION` image
  are available, conditionally test private host config/SSH/work directories,
  read-only config/SSH access, writable host-owned `/work` files, and home tmpfs
  ownership/seeding. Also overlap two containers using the same `:z` sources
  and verify both retain access, including under SELinux Enforcing when
  available. Do not pull images; skip with a clear message if prerequisites
  are missing. When an accessible Docker daemon and local smoke-test image are
  available, conditionally run its existing tmpfs ownership/write smoke.
- When a local `localhost/sd-vpnc:$VERSION` image contains a root-owned
  `/home/dev/.config/atuin`, conditionally verify the default Podman tmpfs
  copy-up leaves it non-writable to the runtime UID, then verify
  `U=true,notmpcopyup` followed by runtime seeding makes it writable. Skip if
  the image or populated config path is unavailable; do not pull an image for
  this check.

## Version and CI/CD

`sd-vpnc` follows SemVer. The version is kept in the `VERSION` variable in the
executable. CI validates shell syntax, runs ShellCheck, tests dotfiles image
build behavior with fake Git/container commands and a local repository, tests
runtime home seeding and shell selection, and smoke-tests help, version, and
agent guidance on pull requests and pushes to `main`. Fake-engine tests do not
need Docker or Podman. Rootless Podman tmpfs behavior is smoke-tested where
available; Docker's tmpfs flags have a conditional runtime smoke check when a
daemon and local test image are available, otherwise only argument generation
and documentation are verified without pulling images.

After CI succeeds on a push to `main`, Auto Release creates a release commit
that increments the patch version, pushes that commit, and creates a GitHub
release with the executable attached as the `sd-vpnc` asset. The release step
creates the tag only after the release commit has been pushed. The release
commit triggers CI again but is excluded from a second automatic release.

You can also run the Auto Release workflow manually and choose `major`, `minor`,
or `patch`. The manual default is `minor`. See the
[releases](https://github.com/salmi-dev/salmidev-tools-vpn-client/releases) page
to download the executable.

## Name

The command is named `sd-vpnc` rather than `vpnc`. `vpnc` is already the widely
used name of the Cisco-compatible VPN client, so `sd-vpnc` avoids shadowing an
existing system command.
