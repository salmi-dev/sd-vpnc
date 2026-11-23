# Design

## Context

`run_container` (regular launch) and `start_tun` (detached launch) in `sd-vpnc` build near-identical engine argument lists, each with a fixed `-e HOME=/home/dev`. Tests capture engine arguments through a fake Podman/Docker script. See `proposal.md` for motivation and the spec delta for observable behavior.

## Goals / Non-Goals

**Goals:**
- Forward only `DEVPOD_WORKSPACE_ID` when set and non-empty, in both launch paths, with identical argument construction.
- Leave arguments byte-identical when it is unset or empty.

**Non-Goals:**
- Forwarding any other variable, a configurable allowlist, or Starship configuration changes.

## Decisions

### Pass an explicit `NAME=value` argument, not a bare `-e NAME`

A shared helper, `devpod_env_arg`, sets a variable to `DEVPOD_WORKSPACE_ID=<host value>` when the host value is non-empty and to the empty string otherwise (in the style of `home_tmpfs_args`). Each engine call expands it with POSIX `${devpod_env_arg:+-e} ${devpod_env_arg:+"$devpod_env_arg"}`, which yields zero words when empty and exactly `-e` plus one unsplit word when set, so values containing spaces or metacharacters are preserved and no arrays are needed. An explicit value keeps the forwarded value visible in captured test arguments and avoids engine-specific bare-name semantics. Empty is treated as unset because an empty identifier carries no context.

### Share the helper between both paths

Both launch paths call the same helper so the behavior cannot drift. Both paths use the same conditional expansion, so no other argument construction changes.

## Risks / Trade-offs

- The value appears in the engine process arguments, as does `HOME`; the identifier is not secret. Quote it as a single argument so values with spaces or metacharacters are preserved.
