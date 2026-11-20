# Proposal

## Why

Issue #5: with `SD_VPNC_DOTFILES` set, `sd-vpnc image --rebuild` fails when the repository's `install.sh` verifies that `/home/dev/.dotfiles` is a Git checkout. `sd-vpnc` removes `.git` on the host before the container build, so the installer cannot see the checkout it runs from. The runtime image must still not contain Git metadata.

## What Changes

- Keep the cloned checkout's `.git` out of the copied source tree but make it available to the installer at `/home/dev/.dotfiles/.git` only for the duration of the installer `RUN` step, using a build-time bind mount (not a layer).
- Remove the empty mount point left behind so the final image has no `.git` entry at all.
- Sanitize the staged metadata (no remote/credentials/clone reflog) and make the selected commit and its reachable history independent of alternates; unreachable objects are not guaranteed to be preserved.
- Keep the selected source, installer invocation, installer effects, mode preservation, host clone/ref/authentication behavior and unconfigured builds unchanged.
- Add regression tests (installer that requires a Git checkout; no Git metadata in copied source or image instructions) and update the README.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `dotfiles-repository-setup`: build context isolation, final-image contents and installer environment now cover temporary Git metadata availability.

## Impact

`sd-vpnc` (generated Containerfile and build context), `tests/test-dotfiles-build.sh`, `README.md`, and the `dotfiles-repository-setup` spec. The build now needs `RUN --mount=type=bind` support (Podman/Buildah, or Docker with BuildKit).
