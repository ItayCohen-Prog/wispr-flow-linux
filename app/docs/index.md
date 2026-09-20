# Documentation

Wispr Flow on Omarchy: the build pipeline, the clean-room helper and the
native liquid glass Flow Bar. Setup steps live in the
[repository README](../../README.md); this folder holds the reference material.

## Using it

- [**Configuration**](configuration.md) — the launcher's environment variables,
  where state lives, `/dev/uinput` access, clipboard and AT-SPI requirements,
  and how the native Flow Bar fits together.
- [**Troubleshooting**](troubleshooting.md) — symptom-keyed fixes and how to
  read `wispr-flow --doctor`.
- [**Glass capsule**](glass-capsule.md) — the liquid glass material, its
  snapshot design and limits, the preview harness and the checks.
- [**Glass validation**](glass-validation.md) — what was measured on real
  hardware, and what was not.

## Building and hacking

- [**Building from source**](building.md) — what `./build.sh` does step by
  step, the network-dependent pieces, and how to rebuild the native sqlite
  modules.
- [**scripts/README.md**](../scripts/README.md) — the staging pipeline and
  every patch, one line each.
- [**Testing**](../tests/README.md) — bats, Node, QML and artifact tests.
- [**Decision log**](decisions.md) — ADR-format record of what is shipped and
  why, including the decisions inherited from upstream.
- [**Learnings**](learnings/index.md) — the non-obvious mechanics of patching
  a minified Electron app and injecting text on Wayland.
- [**Bash style guide**](styleguides/bash_styleguide.md) — the shell
  conventions every script follows.

## Reference

- [**IPC contract**](reference/ipc-contract.md) — the stdin/fd-3 protocol the
  helper implements (`keycodes.json`, `commands.json` alongside).
