# Design

## Context

`build_image` clones the repository into `$build_dir/dotfiles`, deletes `.git`, and the generated Containerfile does `COPY dotfiles /home/dev/.dotfiles` followed by `bash ./install.sh`. Installers that run `git rev-parse`/check for `.git` therefore fail (issue #5).

## Goals / Non-Goals

Goals: installer sees a real Git checkout at `/home/dev/.dotfiles`; no `.git` content in the final image or its layers; no change to installer semantics otherwise.

Non-goals: changing clone, ref selection, authentication, or retaining Git metadata in the runtime image.

## Decisions

- **Bind mount, not a layer.** After clone/ref selection the host sanitizes the checkout metadata and moves `$checkout_dir/.git` to `$build_dir/dotfiles-git` (outside the `dotfiles` copy source). The installer step is `RUN --mount=type=bind,source=dotfiles-git,target=/home/dev/.dotfiles/.git[,z] ...`. The integration never copies the metadata into a layer, unlike copying it and deleting it later (which would leave it in an earlier layer). The mount is read-only by engine default. The guarantee is limited to the integration: an installer (arbitrary root code) could copy mounted data elsewhere, but the sanitized metadata contains no host clone URL or credentials.
- **Sanitize on the host, using Git.** `git remote remove` for every remote (drops the URL and tracking refs/config), delete `logs/`, `FETCH_HEAD`, `ORIG_HEAD` (the clone reflog records the source URL). If the clone uses `objects/info/alternates` (local source with alternates), `git repack -a -d` absorbs the borrowed objects reachable from the clone's refs (the selected commit and its reachable history) and the alternates files are removed so the staged metadata does not point at host paths. Unreachable (dangling) objects may reference borrowed objects that are not copied; they are not guaranteed to be preserved and the installer must not rely on them. This runs after ref selection and does not alter clone/ref/auth behavior.
- **SELinux relabel for Podman.** On SELinux-enforcing hosts Podman's bind mount of the build-context directory is unreadable to the container (directory reads denied; Git reports "not a git repository") unless `z` is given. `z` applies only to Podman because BuildKit rejects it.
- **Explicit `-f`.** Docker does not pick up `Containerfile`; `-f "$build_dir/Containerfile"` is passed for every engine.
- **Rejected: multi-stage build.** An installer changes arbitrary system state (packages, files under `/home/dev`, `/etc`); a later stage cannot copy forward only the "cleaned" result without enumerating those changes or losing them. Rejected: build with `--squash`, which is not portable across Podman/Docker.
- **Remove the mount point.** Some engines leave an empty `.git` directory at the mount target. A separate `RUN rm -rf /home/dev/.dotfiles/.git` ensures the final filesystem has none.
- **Same installer command.** The `bash ./install.sh </dev/null` invocation, `HOME=/home/dev`, cwd and missing-installer skip are unchanged; the mount option is the only addition and applies in both cases for a uniform Containerfile.
- **Single stage kept.** The Containerfile still has one `FROM`.

## Risks / Trade-offs

- Requires bind-mount support in `RUN` (Podman/Buildah; Docker needs BuildKit). Older engines fail the build with an engine error.
- Verified manually with real Podman on an SELinux-enforcing Fedora host only. Docker is covered by the fake-engine suite (explicit `-f`, no `z`) but not run against a real Docker daemon; host-owned `.git` metadata may trigger Git's `safe.directory` ownership check for Git commands in the installer, which the installer can configure. Rootless Podman maps host ownership to root.
- Self-containment covers the selected commit and reachable history only; dangling objects from a local clone may be incomplete once the source repositories are gone (`git fsck --full` still passes).
- The installer still sees the checked-out commit history and objects; secrets committed to the repository are visible (the README already warns not to store secrets in it).
- The CI suite uses a fake engine; the real-engine check is an opt-in local script, not part of CI.
