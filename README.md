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
sd-vpnc ssh -L 8080:localhost:80 vpn-host
sd-vpnc ssh -o ConnectTimeout=10 vpn-host
sd-vpnc tun vpn-host 8080:80 8443:localhost:443
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
accepts a tmux session name. `tun` takes a host and one or more local port
mappings: `LOCAL:REMOTE` forwards to `localhost:REMOTE`, while
`LOCAL:HOST:REMOTE` specifies the destination host from the SSH server's side.

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
not built with a host-specific UID or GID.

## Security

The command grants the container `NET_ADMIN` and access to `/dev/net/tun`, which
are required for OpenVPN. Only use configurations and images you trust.
Provider configuration and credentials are bind-mounted read-only. Credentials
are not copied into the image.

## Version and CI/CD

`sd-vpnc` follows SemVer. The version is kept in the `VERSION` variable in the
executable. CI validates shell syntax, runs ShellCheck, and smoke-tests help,
version, and agent guidance on pull requests and pushes to `main`.

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
