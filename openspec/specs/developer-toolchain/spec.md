# developer-toolchain Specification

## Purpose

Define the pinned mise development toolchain and platform-specific host `flock` provisioning while preserving fail-closed runtime requirements.

## Requirements

### Requirement: Repository development tools have pinned versions

The repository root SHALL declare Node.js version `24`, ShellCheck version `0.11.0`, and the OpenSpec CLI package `npm:@fission-ai/openspec` version `2.1.1` as mise development tools. The documented `mise install` command SHALL install the configured development tools. The tool configuration SHALL NOT include Podman or Docker.

#### Scenario: Developer installs the repository toolchain

- **WHEN** a developer runs `mise install` from the repository root
- **THEN** mise installs the configured Node.js 24, ShellCheck 0.11.0, and OpenSpec CLI 2.1.1 versions
- **AND** no container engine is installed or selected by the repository tool configuration

### Requirement: Mise provisions the macOS flock formula only on macOS

The root mise bootstrap package configuration SHALL declare the standalone Homebrew `flock` formula as `brew:flock` and SHALL restrict that entry to macOS with the mise operating-system filter. The documented `mise bootstrap packages apply` command SHALL apply that configured package on macOS when Homebrew is available, and the entry SHALL NOT cause mise to attempt a Homebrew install on Linux.

#### Scenario: macOS applies the configured package

- **WHEN** a macOS developer runs `mise bootstrap packages apply` with Homebrew available
- **THEN** mise applies the standalone Homebrew `flock` formula

#### Scenario: Linux does not apply the Homebrew entry

- **WHEN** a Linux developer runs `mise bootstrap packages apply`
- **THEN** the macOS-filtered `brew:flock` entry is not applied
- **AND** the developer guidance directs the host to obtain `flock` from the Linux distribution's `util-linux` package

### Requirement: Host flock guidance preserves fail-closed lifecycle behavior

The README and missing-utility diagnostic SHALL document `flock` installation by platform: macOS guidance SHALL use `brew install flock`, and Linux guidance SHALL identify `util-linux` as the package providing `flock`. The documentation and provisioning configuration SHALL NOT change the runtime contract: lifecycle operations SHALL check for host `flock` before changing container state and SHALL fail closed without a fallback when it is unavailable.

#### Scenario: macOS user follows the host dependency guidance

- **WHEN** a macOS user needs to install the host `flock` executable manually
- **THEN** the guidance identifies the standalone formula using `brew install flock`
- **AND** it does not recommend `brew install util-linux`

#### Scenario: Linux user follows the host dependency guidance

- **WHEN** a Linux user needs to install the host `flock` executable
- **THEN** the guidance identifies `util-linux` as the package that provides it

#### Scenario: Lifecycle operation runs without host flock

- **WHEN** a lifecycle operation runs on a host without the `flock` executable
- **THEN** it fails before changing container state
- **AND** it does not fall back to an unsafe lock implementation
