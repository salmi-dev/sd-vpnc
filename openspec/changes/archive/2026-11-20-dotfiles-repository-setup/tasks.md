## 1. Host-side repository lifecycle

- [x] 1.1 Add `SD_VPNC_DOTFILES` and optional `SD_VPNC_DOTFILES_REF` handling in `sd-vpnc`: treat empty values as unset, fail for a nonempty ref without a repository, require host Git only when a nonempty repository is configured, and preserve the no-config image build exactly.
- [x] 1.2 Clone/select branch, tag, or commit using host Git from the caller's working directory; support host Git URL/path and local configuration behavior, avoid interactive prompts and recursive submodules, reject refs beginning with `-`, and ensure errors never print the configured URL.
- [x] 1.3 Remove `.git` before image build and guarantee cleanup of the cloned or partial checkout from the build context after success and every failure path, including clone, ref-selection, container build, and installer failures.
- [x] 1.4 Give each configured build a unique temporary context beneath the cache root and remove the entire context on all exits; preserve the legacy unconfigured context and unconditionally remove stale `build/dotfiles` before using it.
- [x] 1.5 Disable askpass/terminal prompts while retaining noninteractive host credential-helper/agent auth; preserve `GIT_SSH_COMMAND`/global-system `core.sshCommand`/`GIT_SSH` precedence without reading caller-project local config, append BatchMode, and quote `GIT_SSH` executable paths with spaces.

## 2. Image setup and final image behavior

- [x] 2.1 Update the generated Containerfile to place the selected source at `/home/dev/.dotfiles` in the final image without `.git`, then conditionally run `bash ./install.sh` as root from that directory with `HOME=/home/dev` and stdin closed; a missing script succeeds without auto-linking, while a nonzero exit fails the build.
- [x] 2.2 Ensure successful installer symlinks, file outputs, and system changes persist in the final image; preserve file modes and do not add host UID/GID build args, chown baked home to the host UID, chmod repository contents, or rewrite installer output permissions.

## 3. Behavior and generated Containerfile tests

- [x] 3.1 Add tests with fake Git and Docker/Podman commands for configured and unset/empty options, ref-without-repository errors, host Git URL/path/ref handling, caller-relative local paths, private-auth/noninteractive failure handling, clone/ref/build failure propagation, URL redaction, `.git` removal, and cleanup on success and failures; tests must require neither network nor a real container engine.
- [x] 3.2 Add static generated-Containerfile assertions for `/home/dev/.dotfiles`, `.git` exclusion, `HOME=/home/dev`, cwd, root `bash ./install.sh`, closed stdin, missing-script skip/no auto-links, nonzero installer failure, persistent image-stage changes, and unchanged no-config behavior; integrate automated tests into CI.
- [x] 3.3 Test stale no-config cleanup, unique/concurrent configured contexts, Git-unavailable context cleanup, askpass environment, custom SSH precedence/path quoting, and leading-dash ref rejection.
- [x] 3.4 Add a hermetic no-network test against a temporary local Git repository to verify branch, tag, and commit ref selection with global/system config disabled.
- [x] 3.5 Test that SSH command config lookup honors global/system scopes but ignores caller-project local `core.sshCommand`.

## 4. Documentation and manual validation

- [x] 4.1 Document environment variables and edge behavior, host Git URL/path and authentication constraints, relative-path resolution, no prompts/submodule initialization, no credential forwarding, URL-token/error-output precautions, clone cleanup, rebuild with `sd-vpnc image --rebuild`, and the unchanged no-config path in `README.md`.
- [x] 4.2 Document arbitrary root code execution during build and possible runtime startup-code access to SSH keys, VPN configuration/credentials, writable `/work`, and VPN connectivity; warn against untrusted repositories and storing secrets in the retained source tree.
- [x] 4.3 Document that `/home/dev` is image-baked/root-owned rather than host-persisted or generally writable by the runtime host UID, modes are preserved and restrictive outputs may be unreadable, installers must create runtime-readable non-secret configuration, `/home/dev/.ssh` is masked by the read-only host SSH mount, `/work` is mounted, and no tools beyond the base image are promised (Fedora package tooling may be available).
- [x] 4.4 Include manual local-image validation cases for a symlink into `.dotfiles`, restrictive file permissions/runtime readability, missing installer/no automatic links, persisted system changes, and runtime SSH/work mount behavior.
- [x] 4.5 Document the askpass and custom SSH compatibility policy, configured-context lifecycle, and update the CI description and manual-validation heading.
- [x] 4.6 Clarify that the runtime mounts the config directory read-only rather than separately mounting `SD_VPNC_CONFIG`/`SD_VPNC_CREDENTIALS` paths; note that credentials in the directory are not copied into the image and record the existing override/mount mismatch in `.work/gh-1/FOLLOWUPS.md`.
