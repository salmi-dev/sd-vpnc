## Why

Users currently have no supported way for `sd-vpnc` to seed `/home/dev` from their dotfiles while retaining the repository for symlinks and runtime shell configuration. An opt-in image-build setup should make the selected repository and installer effects part of the image, without changing the existing behavior when the option is not configured.

## What Changes

- Add optional host-side cloning via `SD_VPNC_DOTFILES` and optional branch/tag/commit selection via `SD_VPNC_DOTFILES_REF`. Empty values are unset; a ref without a repository is an error. Use host Git's supported URL/path and local configuration behavior, resolve relative paths from the caller's working directory, do not initialize submodules, and do not support interactive prompts.
- Remove `.git` metadata before building and always remove the cloned checkout from the build context after the build attempt, including failure paths. Fail on clone, ref-selection, or installer errors without printing the repository URL.
- Include the repository source at `/home/dev/.dotfiles` in the final image, without `.git`, and run its root `install.sh` as root during image build using `HOME=/home/dev`, cwd `/home/dev/.dotfiles`, `bash ./install.sh`, and closed stdin. A missing script succeeds without creating links; installer system changes and symlinks into `.dotfiles` persist in the final image. Preserve file modes and do not chmod installer outputs.
- Document root ownership and image-baked home behavior, runtime mounts and access to sensitive resources, trust/authentication limits, secrets guidance, and rebuilding after repository/ref/content changes.
- Add fake-Git/container tests, static generated-Containerfile assertions, and documented local-image manual checks without requiring network or a container engine for automated tests.

## Capabilities

### New Capabilities
- `dotfiles-repository-setup`: Configure optional host-side dotfiles cloning, image-baked repository installation and runtime behavior, errors, cleanup, authentication boundaries, and rebuild guidance.

### Modified Capabilities

None.

## Impact

- `sd-vpnc`: host-side image-build orchestration and generated Containerfile.
- `README.md`: configuration, lifecycle, runtime/security constraints, authentication, and manual validation guidance.
- Tests and CI: fake Git/container commands and static Containerfile checks.
- When both dotfiles variables are unset, the current image-build behavior remains unchanged; no Git dependency is added to that path.
