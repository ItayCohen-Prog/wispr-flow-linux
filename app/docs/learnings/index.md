[< Back to docs index](../index.md)

# Learnings

The non-obvious mechanics behind the helper and the packaging pipeline, most
of them inherited from the upstream port. Each page digs into one mechanic and
the failure modes that bit. If you are about to touch one of these subsystems,
read its page first.

| Deep-dive | What it covers |
|---|---|
| [Electron 42 / V8 14.8 / sqlite](electron42-v8-sqlite.md) | The V8 14.8 ABI patch that lets `better-sqlite3-multiple-ciphers` compile. |
| [The isPackaged / launcher rename](ispackaged-rename.md) | Why an `electron`-named launcher silently breaks DB migrations ("no such table"). |
| [Wayland injection](wayland-injection.md) | In-process `/dev/uinput` virtual keyboard + `ext-data-control` clipboard. |
| [Global key monitor](global-key-monitor.md) | Push-to-talk lives in the helper: evdev `/dev/input` → `KeypressEvent`, and why both PTT and the shortcut recorder were dead without it. |
| [Helper spawn env](helper-spawn-env.md) | The app spawns the helper with a replacement env (no `process.env`), starving it of `WAYLAND_DISPLAY`/`DISPLAY` → silent no-op `stub` injector; recording works, injection doesn't. |
| [Platform gates](platform-gates.md) | The darwin/win32 carve-outs Linux falls through: the `.linux`-matches-no-CSS bug behind the shifted side menu, the three gate-shape rules, and how to re-audit a new Wispr version. |
| [Patching minified JS](patching-minified-js.md) | Rules for patches that survive re-minification: `[\w$]+` for identifiers, anchor on developer strings, assert the match count, marker-based idempotency, verify against shipped bytes. |

The "why this and not that" behind them lives in [decisions.md](../decisions.md).
