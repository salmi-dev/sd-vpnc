# Tasks

## 1. Runtime forwarding

- [x] 1.1 Add a shared helper that yields `-e DEVPOD_WORKSPACE_ID=<value>` only when the host value is non-empty, and use it in both the regular runtime launch and the detached `tun` launch without changing other arguments; verify with shell syntax checks and ShellCheck.

## 2. Tests

- [x] 2.1 Extend the fake-engine runtime argument tests to cover set and unset (and empty) cases for the regular and detached launches, preserving values with spaces, and asserting unrelated and look-alike host variables are not forwarded; verify the tests fail without the implementation.

## 3. Documentation

- [x] 3.1 Document in the README that `DEVPOD_WORKSPACE_ID` is forwarded to regular and detached containers when set and non-empty, nothing is forwarded when unset, and no other host variable is forwarded.

## 4. Integration validation

- [x] 4.1 Run the complete behavior suite, shell syntax checks, ShellCheck, and strict OpenSpec validation.
