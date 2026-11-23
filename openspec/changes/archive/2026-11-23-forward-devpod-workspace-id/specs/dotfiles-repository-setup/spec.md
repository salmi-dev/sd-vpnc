# Spec Delta

## ADDED Requirements

### Requirement: Runtime containers receive only the host DevPod workspace identifier
Both the regular runtime launch and the detached `tun` launch SHALL pass `-e DEVPOD_WORKSPACE_ID=<value>` to the container engine when the host `DEVPOD_WORKSPACE_ID` environment variable is set and non-empty. When it is unset or empty, they SHALL add no environment argument for it and SHALL otherwise keep their existing arguments. No other host environment variable SHALL be forwarded by this behavior, and the whole host environment SHALL NOT be passed through.

#### Scenario: Regular runtime launch with the variable set
- **WHEN** the host sets `DEVPOD_WORKSPACE_ID` and a regular runtime container is launched
- **THEN** the engine arguments contain `-e` followed by `DEVPOD_WORKSPACE_ID=<host value>` alongside the existing `HOME=/home/dev` environment argument

#### Scenario: Detached tunnel launch with the variable set
- **WHEN** the host sets `DEVPOD_WORKSPACE_ID` and a detached `tun` container is launched
- **THEN** the engine arguments contain `-e` followed by `DEVPOD_WORKSPACE_ID=<host value>` alongside the existing `HOME=/home/dev` environment argument

#### Scenario: Variable unset
- **WHEN** the host does not set `DEVPOD_WORKSPACE_ID` (or sets it to an empty value) and either launch path runs
- **THEN** the engine arguments contain no `DEVPOD_WORKSPACE_ID` argument and launch succeeds with its existing arguments

#### Scenario: Unrelated host variables are not forwarded
- **WHEN** the host sets other variables (for example a variable whose name merely resembles `DEVPOD_WORKSPACE_ID`) and either launch path runs
- **THEN** no engine argument forwards them

### Requirement: DevPod workspace identifier forwarding is documented
The `README.md` SHALL state that the host `DEVPOD_WORKSPACE_ID` is forwarded to regular and detached runtime containers when set and non-empty, that nothing is forwarded when it is unset or empty, and that no other host environment variables are forwarded.

#### Scenario: User reads environment forwarding guidance
- **WHEN** a user reviews the runtime guidance in the README
- **THEN** it explains the conditional forwarding of `DEVPOD_WORKSPACE_ID` to both launch paths and that no other host variable is passed
