## Context

`sd-vpnc` generates a Containerfile and build context for Docker or Podman. The legacy unconfigured image build uses `$XDG_CACHE_HOME/sd-vpnc/build` (or `~/.cache/sd-vpnc/build`). Configured dotfiles builds need isolated contexts because host-side clone/ref selection and cleanup happen while other image builds may be running. The selected repository source intentionally remains in the final image at `/home/dev/.dotfiles`, without Git metadata, so installer-created symlinks continue to resolve.

## Goals / Non-Goals

**Goals:**
- Preserve the exact existing build path when both dotfiles variables are empty, remove any stale `build/dotfiles` checkout before that legacy build, and require host Git only when a nonempty repository is configured.
- Use host Git URL/path and local configuration behavior; resolve relative paths from the caller's current working directory, reject a nonempty ref without a repository and refs beginning with `-`, and select branch, tag, or commit refs safely.
- Disable prompts while retaining noninteractive host credential-helper and SSH-agent authentication; explicitly disable askpass helpers and document custom SSH command constraints.
- Use a unique temporary context beneath the cache root for every configured build and remove the entire context after success or failure.
- Keep repository source at `/home/dev/.dotfiles` in the final image and run its root installer in that image so symlinks and system changes persist.
- Preserve file modes; avoid changing ownership/modes to accommodate host UIDs or secrets.
- Document root execution, image-baked home/runtime limitations, host authentication constraints, sensitive runtime mounts, rebuild behavior, and local validation cases.
- Test behavior with fake Git/container commands and static Containerfile assertions; also exercise branch/tag/commit selection against a temporary local Git repository without network.

**Non-Goals:**
- Fetch or update dotfiles at container startup, initialize Git submodules, forward host credentials into the build container, or add host UID/GID build arguments.
- Support askpass UI helpers, interactive prompts, non-OpenSSH-compatible custom SSH commands, install tools beyond the existing base image, or make `/home/dev` host-persistent or generally writable by the runtime host UID.
- Treat a configured repository as a secret store or sandbox its code.

## Decisions

1. **Clone and resolve refs with host Git.** Treat empty `SD_VPNC_DOTFILES` and `SD_VPNC_DOTFILES_REF` as unset. If a nonempty ref is supplied without a nonempty repository, fail; reject refs beginning with `-` so Git cannot parse them as command options. Use host Git's supported URL/path forms and local configuration, resolving relative local paths from the caller's current working directory. Resolve local branches, tags, remote branches, and commit-ish values to a commit before detached checkout. Do not recursively initialize submodules. Suppress Git output on clone/ref errors to prevent URL leakage.

2. **Isolate configured builds and preserve the legacy unconfigured context.** For a configured repository, create a unique `mktemp -d` context beneath the cache root, clone/select the ref there, remove `.git` before the container build, and remove the entire per-run context via exit/signal cleanup on success and all failures. For an unconfigured build, keep `$cache_home/sd-vpnc/build` and remove its stale `dotfiles` directory unconditionally before writing the existing Containerfile. This prevents configured builds from sharing or racing over checkout state without changing the default context path.

3. **Bake source and run installation in the final image build.** Copy the selected checkout, without `.git`, to `/home/dev/.dotfiles` in the final image before running setup. Run as root with `HOME=/home/dev`, cwd `/home/dev/.dotfiles`, and `bash ./install.sh </dev/null` only if the root script exists. Propagate a nonzero exit; if it is missing, succeed without running or linking anything automatically. Running setup in the final image ensures that symlinks into `.dotfiles`, created files, and system/package changes persist. Retain the repository source in the final image by design.

4. **Preserve modes and make runtime ownership limitations explicit.** Do not add host UID/GID build args, chown the baked home to the host UID, chmod repository contents, or rewrite installer outputs' permissions. `/home/dev` and `.dotfiles` are image-baked and root-owned; the runtime process uses the host UID/GID, so that user is not generally able to write to the baked home and may not read restrictive root-owned outputs. The `/home/dev/.ssh` path is overlaid by the host's read-only SSH mount at runtime, and `/work` is mounted separately. Documentation must tell installers to create runtime-readable configuration, not secrets, and explain these constraints.

5. **Use host authentication without interactive askpass.** Set `GIT_ASKPASS` and `SSH_ASKPASS` to `/bin/false`, set `SSH_ASKPASS_REQUIRE=never`, `GIT_TERMINAL_PROMPT=0`, `GCM_INTERACTIVE=never`, and close Git stdin. Retain host credential helpers and SSH-agent access for noninteractive authentication. Resolve SSH command precedence as `GIT_SSH_COMMAND`, global `core.sshCommand`, system `core.sshCommand`, `GIT_SSH`, then default `ssh`. Query global/system scopes explicitly so a local `core.sshCommand` from the caller's project cannot redirect the clone. Quote `GIT_SSH` as an executable path so spaces work. Append `-o BatchMode=yes`; custom SSH commands must accept OpenSSH-compatible `-o` options. Document that limit.

6. **Keep the default image path unchanged and the image a build-time snapshot.** With no nonempty repository and no ref, do not require Git or alter existing generated image behavior apart from removing a stale checkout. With a repository configured, subsequent repository/ref/content changes do not alter an existing image; users rebuild with `sd-vpnc image --rebuild` to refresh it.

7. **Describe runtime mounts accurately and test the config boundary.** The README SHALL describe the runtime bind mount as the host configuration directory at `/config`, and credentials in that directory as supplied by the mount rather than copied into the image. Preserve the existing arbitrary per-file override behavior; record its mismatch with the directory-only mount in `.work/gh-1/FOLLOWUPS.md` for separate work.

8. **Test at process and generated-container-definition boundaries.** Fake Git and Docker/Podman commands verify configured/unconfigured paths, URL/ref handling, askpass/SSH environments and precedence, rejection of caller-local SSH config, failures, context cleanup, stale checkout removal, and concurrent context isolation without network or a real engine. Static Containerfile assertions verify `.dotfiles` placement, `HOME`, cwd, Bash invocation, closed stdin, missing-script skip, failure propagation, and `.git` exclusion. A hermetic local Git fixture tests branch, tag, and commit selection without network. Document local image-build checks for symlinks, file modes/ownership/readability, runtime mounts, missing installer, and persisted system changes.

## Risks / Trade-offs

- **[Repository code runs as root at build time and may execute again through shell startup files at runtime]** → Document the arbitrary-code and runtime access risks; require users to trust the repository/ref and never store secrets in it.
- **[Host Git authentication may be unavailable noninteractively]** → Recommend preconfigured host credential helpers or SSH-agent use; disable askpass UI and prompts.
- **[Custom SSH commands may not accept BatchMode options]** → Preserve host command precedence and path handling, append BatchMode, and document the OpenSSH-compatible-command requirement.
- **[Source remains inspectable in the final image and baked files are root-owned]** → State this explicitly; `.git` is excluded, modes are preserved, and users must create runtime-readable non-secret configuration.
- **[Shared context mutation could expose a checkout or `.git` during concurrent builds]** → Use unique configured contexts with whole-context cleanup; keep and clean the legacy no-config context separately.
- **[The selected tree is a snapshot]** → Document `sd-vpnc image --rebuild` after repository, ref, or content changes.

## Open Questions

None. The behavior and security decisions above are finalized.
