# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-06-30

### Added

- Validate-then-apply with last-good rollback: a source error is surfaced with
  the failing file and tmux's own message, and the previous working config is
  restored instead of leaving a half-applied edit.
- Auto-discovery of sourced files: `source` and `source-file` directives are
  parsed and those files are watched too, re-evaluated after every reload so a
  newly added include starts being watched on its own.
- Editor atomic-save handling by also watching each file's parent directory, so
  rename-on-save from vim, Neovim, and others is caught.
- Content-hash dedupe so a save that only bumps the mtime without changing the
  bytes does not trigger a reload.
- Deferred reload while a client is in copy-mode or at a command prompt, so a
  reload never interrupts a selection.
- Selective reload of only the entrypoint whose include subtree owns the changed
  file, opt-in via `@autoreload_revamped_selective`.
- `entr` added to the watcher chain after fswatch and inotifywait.
- Self-healing watcher: a dead or stale pid is detected and replaced on the next
  load, still one watcher per server.
- Failure backoff so a repeatedly failing reload stops retrying on every tick.
- Optional desktop notification and a brief visual flash on reload, and the
  reload message now names the changed file.
- `pause`, `resume`, `toggle`, and `status` subcommands.
- New options: `@autoreload_revamped_discover`, `_atomic`, `_validate`,
  `_defer`, `_selective`, `_backoff_max`, `_flash`, and `_notify`.

## [1.0.1] - 2026-06-23

### Changed

- Reviewed the upstream `b0o/tmux-autoreload` issues. macOS support already works
  through the BSD `stat -f` fallback (#3), and a new watcher always kills the
  previous one through the pid kept in a server option, so reloads never stack up
  duplicate watchers (PR #2). No code change needed.

## [1.0.0] - 2026-06-22

### Added

- Watch the loaded tmux config and source it automatically on any change.
- Three backends picked automatically: fswatch, inotifywait, or a pure-shell
  polling fallback that needs no extra dependency.
- One watcher per server, tracked by pid, so reloads never stack watchers.
- Configurable extra files, entrypoints, poll interval, and a quiet mode.
