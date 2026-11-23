# Design

## Context

The lifecycle manager uses the host `flock` utility to serialize state transitions. Existing guidance identifies `util-linux` as its source, but the suggested Homebrew command (`brew install util-linux`) is not the standalone Homebrew formula used to provide `flock` on macOS. The repository also has no root mise configuration for its requested development tools.

## Goals / Non-Goals

**Goals:**
- Declare the exact requested Node.js, ShellCheck, and OpenSpec CLI versions in the repository's root mise configuration.
- Let mise bootstrap the standalone Homebrew `flock` formula on macOS only.
- Document the appropriate setup commands and platform-specific `flock` sources.
- Preserve fail-closed runtime locking and leave CI unchanged.

**Non-goals:**
- Create or alter runtime/container toolchain dependencies, including Podman or Docker.
- Change the lifecycle lock implementation, its requirement for `flock`, or its failure behavior when `flock` is missing.
- Add Linux package-manager provisioning, alter the CI workflow, or install tools as part of CI.

## Decisions

- **Pin repository development tools in root mise.toml.** Declare Node.js `24`, ShellCheck `0.11.0`, and `npm:@fission-ai/openspec` `2.1.1` as mise tools. `mise install` is the explicit command for installing those configured versions. Do not declare Podman or Docker.
- **Use the Homebrew package with a macOS filter.** Under `[bootstrap.packages]`, declare the standalone formula as `"brew:flock" = { os = "macos" }`. The OS filter prevents mise from attempting the Homebrew package on Linux or other platforms. `mise bootstrap packages apply` applies configured host packages; Homebrew must be available on macOS.
- **Keep Linux package installation host-managed.** Document that Linux users need the `flock` executable from their distribution's `util-linux` package. Do not add Linux distribution-specific package entries to this focused change.
- **Separate package provisioning from the runtime safety contract.** Update the diagnostic/documentation guidance to distinguish macOS (`brew install flock`) from Linux (`util-linux`), but do not weaken the pre-mutation executable check, add a lock fallback, or treat mise installation as a runtime guarantee. If `flock` is absent, lifecycle commands continue to fail before changing container state.
- **Keep CI independent of mise.** Do not edit workflow files or add a tool installation step to CI.

## Risks / Trade-offs

- macOS bootstrap requires Homebrew to be installed and available to mise. Users may use `brew install flock` directly instead.
- Linux distribution package names and package-manager commands vary; documenting the common `util-linux` source avoids a distro-specific bootstrap policy.
- The `os = "macos"` package filter and manager-qualified package syntax depend on mise's bootstrap package configuration. Verify the checked-in configuration with mise validation/dry-run on the available host, and validate the macOS-specific behavior on macOS when possible.
- The requested Node.js version is a major-line pin (`24`); ShellCheck and OpenSpec use exact release pins.
