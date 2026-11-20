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
not expect input. A missing `install.sh` is a successful skip; no dotfiles are
automatically linked. Installer-created symlinks into `.dotfiles`, files, and
system changes persist in the image. Only tools already in the Fedora base
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

A connection command keeps its named container alive until that SSH/shell
session exits. While it is running, open another terminal and run:

```bash
sd-vpnc shell
# `sd-vpnc cli` is an alias
```

This opens an additional shell in the existing VPN-connected container. If no
container is active, `shell` starts a VPN container and opens its interactive
shell. The active container is shown in `sd-vpnc status`; it stops when the
connection shell or SSH session exits.

`--workdir`/`-C` mounts a host directory as `/work` inside the container. The
option is the reliable way to choose a project directory; a container cannot
change the current directory of its parent shell.

## Runtime requirements

- Podman or Docker
- `/dev/net/tun` on the host
- Permission to run containers with `NET_ADMIN`
- An OpenVPN provider configuration

The container runs with the invoking host UID/GID so files in the mounted work
directory and SSH directory retain normal host ownership. The image itself is
not built with a host-specific UID or GID. `/work` is mounted from the host;
the host's SSH directory is mounted read-only at `/home/dev/.ssh`, masking any
image content at that path.

When dotfiles are configured, `/home/dev` and `/home/dev/.dotfiles` are baked
into the image and root-owned, not host-persisted, and not generally writable
by the runtime host UID. File modes are preserved: a restrictive root-owned
file such as mode `0600` may be unreadable by the runtime UID. Installers should
create runtime-readable, non-secret configuration and must not rely on the
feature changing ownership or permissions. No host UID/GID build arguments or
permission rewrites are applied.

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
  source remains in the final image and the symlink resolves there. Verify the
  cloned `.git` metadata is absent and the temporary checkout is removed from
  the host build context after both successful and failed builds.
- Have the installer create a restrictive root-owned file (for example mode
  `0600`); confirm its mode is preserved and that the runtime host UID may be
  unable to read it. Use only runtime-readable, non-secret configuration for
  normal operation.
- Build once with no root `install.sh`; confirm the repository remains in the
  image but no automatic links are created. Separately test a failing script
  and a system-level change to confirm failure propagation and persistence.
- At runtime, confirm the host's read-only SSH mount masks image content under
  `/home/dev/.ssh` and that `/work` remains the mounted writable host directory.

## Version and CI/CD

`sd-vpnc` follows SemVer. The version is kept in the `VERSION` variable in the
executable. CI validates shell syntax, runs ShellCheck, tests dotfiles image
build behavior with fake Git/container commands and a local repository, and
smoke-tests help, version, and agent guidance on pull requests and pushes to
`main`. The behavior tests need no network access or Docker/Podman engine.

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
