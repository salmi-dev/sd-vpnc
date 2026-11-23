# Proposal

## Why

The repository does not currently declare its development tool versions, and the host `flock` prerequisite needs different installation guidance on macOS and Linux. The existing macOS example, `brew install util-linux`, does not install the standalone Homebrew `flock` formula. A focused root-level mise configuration can pin the requested development tools and offer platform-appropriate `flock` provisioning without changing runtime locking behavior.

## What Changes

- Add a root `mise.toml` that pins Node.js 24, ShellCheck 0.11.0, and `npm:@fission-ai/openspec` 2.1.1.
- Declare only the standalone Homebrew `flock` formula (`brew:flock`) as a mise bootstrap package, filtered to macOS.
- Document `mise install` for the pinned development tools and `mise bootstrap packages apply` for configured host packages.
- Clarify that Linux hosts need `flock` from `util-linux`; replace the macOS `brew install util-linux` guidance with `brew install flock`.
- Keep the runtime's fail-closed `flock` check and the CI workflow unchanged. Do not add Podman or Docker as mise tools.

## Capabilities

### New Capabilities

- `developer-toolchain`: repository tool versions, macOS-only Homebrew `flock` provisioning, and platform-specific host dependency guidance.

### Modified Capabilities

None.

## Impact

The planned implementation affects root `mise.toml`, `README.md`, and the missing-`flock` guidance in `sd-vpnc`, plus this capability specification. CI configuration and container-engine selection remain unchanged. Runtime lifecycle behavior continues to require host `flock` before changing container state and fails closed when it is unavailable.
