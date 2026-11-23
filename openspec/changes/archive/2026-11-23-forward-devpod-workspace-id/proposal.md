# Proposal

## Why

Shell prompts inside `sd-vpnc` runtime containers (including Starship's existing environment-variable display) cannot show which DevPod workspace launched the container, because the host's `DEVPOD_WORKSPACE_ID` is not passed through. Forwarding that single variable restores the context without exposing the rest of the host environment.

## What Changes

- Add `-e DEVPOD_WORKSPACE_ID=<host value>` to both the interactive/regular runtime launch and the detached `tun` launch, only when the host variable is set and non-empty. When it is unset or empty, no environment argument is added and launch arguments are unchanged.
- Forward only this one allowlisted variable; do not pass the host environment wholesale and do not forward any other variable.
- Extend the fake-engine runtime argument tests to cover set and unset cases for both launch paths, and assert that unrelated host variables are not forwarded.
- Document the behavior in the README.
- Out of scope: other host variables and any Starship configuration change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `dotfiles-repository-setup`: Add a requirement that runtime containers conditionally receive only the host `DEVPOD_WORKSPACE_ID`, and that the README documents it.

## Impact

Affects the `run_container` and `start_tun` engine argument lists in `sd-vpnc`, the runtime argument tests in `tests/test-dotfiles-build.sh`, and `README.md`. No new dependency, mount, or image change. Risk is low; existing arguments are unchanged when the variable is unset.
