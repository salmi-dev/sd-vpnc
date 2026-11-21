# Design

## Context

The image currently keeps its final home at `/home/dev` with root-owned files, and the root installer runs there before `.git` cleanup. Runtime containers use the caller's numeric `--user UID:GID`, mount the host SSH directory read-only at `/home/dev/.ssh`, and mount the host work directory at `/work`. Interactive shell paths currently invoke Bash directly. See `proposal.md` for motivation and the spec delta for observable behavior.

## Goals / Non-Goals

**Goals:**
- Make `/home/dev` and conventional cache/state/data paths writable by the numeric runtime user without changing its user namespace or broadening file permissions.
- Keep the baked `/home/dev` at its existing image path and preserve readable setup content in a separate source for runtime seeding.
- Use the same shell-selection behavior from `sd-vpnc shell` and bare `sd-vpnc ssh` without SSH arguments, while retaining remote SSH behavior for `sd-vpnc ssh HOST`.

**Non-Goals:**
- Persist container home state, change the host UID/GID mapping, install Zsh in the base image, or alter the `/work` and SSH bind mounts.
- Make root-only image content readable to the runtime user or change its ownership/mode.

## Decisions

### Use engine-specific home tmpfs ownership without changing the user namespace

Keep `--user "$uid:$gid"` and `HOME=/home/dev`. For Podman, add `--mount type=tmpfs,destination=/home/dev,tmpfs-mode=0700,U=true,notmpcopyup`; `U` sets tmpfs owner/group from the container user, while `notmpcopyup` keeps root-owned image children out of the fresh mount until runtime seeding. Without `notmpcopyup`, Podman copies root-owned `/home/dev/.config/atuin` into the tmpfs; `U=true` changes only the mount root and the runtime user then cannot write there. Rootless Podman was tested with both `1000:1000` and `12345:6789`: the no-copy-up tmpfs appeared with the corresponding in-container owner and mode 0700, and writes succeeded. Do not use `--userns=keep-id`: it changes the mapping for the whole container, including `/work`.

For Docker, use `--tmpfs "/home/dev:rw,uid=$uid,gid=$gid,mode=0700"`; keep this form unchanged. Docker's documented `--tmpfs` options include `uid`, `gid`, and `mode`; its `--mount type=tmpfs` interface does not document uid/gid. The Docker form has documentation evidence but was not tested against a daemon in this environment. Avoid host-owned writable home binds, build-time UID/GID mapping, world-writable modes, and broad chown/chmod changes.

### Preserve the baked home and seed a separate runtime template

After the root installer has completed and the temporary `.git` mount point has been removed, copy the finalized `/home/dev` into a separate image template (for example, `/usr/share/sd-vpnc/home-template`). Leave the original image home and `/home/dev/.dotfiles` at their existing locations. Exclude `.ssh` from the template; the existing read-only host mount remains authoritative at runtime.

At entrypoint startup, copy readable/traversable template entries into the tmpfs as the runtime UID:GID, preserving ordinary file modes and symlinks without preserving root ownership. Skip unreadable entries without failing startup and propagate unrelated copy failures.

Treat disposable roots specially rather than inheriting baked directory modes: never seed `.cache`, `.local/state`, `.atuin`, or legacy `.local/share/atuin`. Temporarily set `umask 077` while creating fresh runtime-owned mode-0700 `/home/dev/.cache`, `/home/dev/.local`, `/home/dev/.local/state`, `/home/dev/.local/share`, `/home/dev/.atuin`, and `/home/dev/.atuin/data` directories, then restore the prior umask so files created on `/work` keep their existing mode behavior. Do not copy the source `.local` or `.local/share` directory modes; instead copy their other readable children into the fresh parents, excluding `state` and `atuin`. Skip a source `.local` symlink entirely and skip a `.local/share` symlink before checking/traversing it, so external targets are not seeded. Preserve ordinary symlinks found inside readable template content. This preserves available `.local/bin` and other readable tool/config content while ensuring restrictive parents cannot block state/data creation. Leave the image template and its modes unchanged. Set `XDG_CACHE_HOME=/home/dev/.cache`, `XDG_STATE_HOME=/home/dev/.local/state`, `XDG_DATA_HOME=/home/dev/.local/share`, and `ATUIN_HOME=/home/dev/.atuin`; place Zsh/Bash history under the state home and Atuin data under `$ATUIN_HOME/data`. Add a conditional Podman regression smoke against a local `localhost/sd-vpnc:$VERSION` image when it contains a root-owned `.config/atuin`: demonstrate that the default copy-up blocks a runtime write, then verify the no-copy-up mount followed by seeding makes the directory runtime-writable. Never pull an image to run this check. The runtime tmpfs and these state paths are session-only and disappear when the container stops.

The new tmpfs is added to both regular and detached runtime launches. Keep the existing `/work` and `/home/dev/.ssh` bind arguments byte-for-byte unchanged. The tmpfs does not use a host path and therefore requires no SELinux bind relabel option.

### Share one interactive shell selector

Install a small helper in the image and invoke it from the entrypoint's bare `ssh` path (no host or SSH arguments) and `sd-vpnc shell` when entering an existing container. The helper sets history under writable state, then executes `zsh -l -i` when `zsh` is available; otherwise it executes `/bin/bash --login -i`. Do not add Zsh to the base package list. `sd-vpnc ssh HOST` continues to invoke remote SSH and open the remote default shell when no remote command is supplied; other remote SSH commands and tmux sessions remain unchanged.

## Risks / Trade-offs

- A full-home tmpfs hides the baked home at runtime → seed from the separate post-installer template before opening shells; recreate `.cache` and `.local` runtime roots instead of inheriting restrictive source modes; exclude `.ssh` and disposable state roots; test readable siblings, symlinks, modes, and unreadable entries.
- Root-only template entries cannot be seeded by the runtime UID → omit only inaccessible entries without failing; retain the existing contract that such files are not runtime-readable.
- Runtime cache, shell history, Atuin data, and state disappear at container stop → document this explicitly; persistence is not part of the issue acceptance and existing regular connection containers are removed on exit.
- Tmpfs uses container memory and may be subject to swap → keep it private and document session-only semantics; do not treat tmpfs as persistent or guaranteed secure erasure.
- Docker behavior is based on the documented tmpfs options rather than a local engine test → add engine-argument regression coverage and run a conditional Docker smoke check only when a daemon and test image are already available; never pull an image from the default test suite and retain the explicit note that Docker was not locally runtime-tested here.

## Migration Plan

No host data migration is required. Existing images retain their baked home until rebuilt; rebuilding produces the template and runtime mounts. To roll back, rebuild the previous image and remove the runtime tmpfs and shell-selector invocation changes; the existing `/work` and SSH mounts are unchanged throughout.
