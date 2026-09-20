# Documentation

Wispr Flow on Omarchy: the build pipeline, the clean-room helper and the
native liquid glass Flow Bar. Setup steps live in the
[repository README](../../README.md); this folder holds the reference material.

## Using it

- [**Configuration**](configuration.md). The launcher's environment variables,
  where state lives, `/dev/uinput` access, clipboard and AT-SPI requirements,
  and how the native Flow Bar fits together.
- [**Troubleshooting**](troubleshooting.md). Symptom-keyed fixes and how to
  read `wispr-flow --doctor`.
- [**Glass capsule**](glass-capsule.md). The liquid glass material, its
  snapshot design and limits, the preview harness and the checks.
- [**Glass validation**](glass-validation.md). What was measured on real
  hardware, and what was not.

## Building and hacking

- [**Building from source**](building.md). What `./build.sh` does step by
  step, the network-dependent pieces, and how to rebuild the native sqlite
  modules.
- [**scripts/README.md**](../scripts/README.md). The staging pipeline and
  every patch, one line each.
- [**Testing**](../tests/README.md). Bats, Node, QML and artifact tests.
- [**Decision log**](decisions.md). ADR-format record of what is shipped and
  why, including the decisions inherited from upstream.
- [**Learnings**](learnings/index.md). The non-obvious mechanics of patching
  a minified Electron app and injecting text on Wayland.
- [**Bash style guide**](styleguides/bash_styleguide.md). The shell
  conventions every script follows.

## Reference

- [**IPC contract**](reference/ipc-contract.md). The stdin/fd-3 protocol the
  helper implements (`keycodes.json`, `commands.json` alongside).
