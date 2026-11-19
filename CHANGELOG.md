# Changelog

# [2.1.0](https://github.com/tmux-revamped/tmux-autoreload-revamped/compare/v2.0.0...v2.1.0) (2026-11-19)


### Bug Fixes

* fold a table wider than the terminal ([a3a7666](https://github.com/tmux-revamped/tmux-autoreload-revamped/commit/a3a7666bea14fb36fc41176d273b1e5dc36ea430))
* read the grep of macOS as bsd in doctor ([bca70dd](https://github.com/tmux-revamped/tmux-autoreload-revamped/commit/bca70dd1875b89fa8a964f6625c72953b6a69d69))
* stop a recording that hangs ([0976bdc](https://github.com/tmux-revamped/tmux-autoreload-revamped/commit/0976bdcff9c6d3600a92280e55bcdec67896bf66))


### Features

* name unknown setting values in doctor ([3f75282](https://github.com/tmux-revamped/tmux-autoreload-revamped/commit/3f7528283791a267c80922cc34d2d52791da4a03))

# [2.0.0](https://github.com/tmux-revamped/tmux-autoreload-revamped/compare/v1.1.1...v2.0.0) (2026-11-18)


* feat!: rewrite the plugin in POSIX sh ([d0b7ff5](https://github.com/tmux-revamped/tmux-autoreload-revamped/commit/d0b7ff57c87f191800c0025587efc9060507e74b))


### Bug Fixes

* load a save made while a reload runs ([b97b048](https://github.com/tmux-revamped/tmux-autoreload-revamped/commit/b97b04803cb6ce754e96a47383fbba0c3d6b243a))
* read the files setting from the environment ([06b6c04](https://github.com/tmux-revamped/tmux-autoreload-revamped/commit/06b6c046ddd441e97d2092a674fac9e6813d9c9d))
* reload on the save itself with fswatch 1.22 ([67fe738](https://github.com/tmux-revamped/tmux-autoreload-revamped/commit/67fe738e9564271406ad2ca2f39ac31fe5bfd6ff))
* stop counting some characters twice ([7a1f08f](https://github.com/tmux-revamped/tmux-autoreload-revamped/commit/7a1f08fb09ff2fff8965509b616365a812cdac70))


### BREAKING CHANGES

* the script moved from src/autoreload.sh to
bin/autoreload-revamped, so a key bound to the old path needs the new
one. The AR_CACHE_DIR variable is replaced by the option
@autoreload_revamped_backup_dir. @autoreload_revamped_backoff_max is
gone: a reload that fails shows its error once and is not retried
until the file changes. @autoreload_revamped_snapshot, _hash and
_fail_count are no longer written. bash is no longer required.

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-11-15

### Fixed

- A desktop notification whose title or message held a double quote or a
  backslash broke the AppleScript that showed it, and text after the quote ran
  as AppleScript. Notifications now go through the family's shared notifier,
  which hands the title and message to `osascript` and `notify-send` as
  arguments.
- Every reload failed on tmux 3.7, which lists default config paths that do
  not exist in `#{config_files}`. Autoreload sourced the first missing one,
  failed, and never reached the real config. Missing paths are now skipped.
- An edit saved while a pane was in copy-mode was never applied. The
  content hash was recorded before the defer check, so the follow-up
  event saw no change. The hash is now recorded only after a successful
  reload.
- A `source -q` of a file that does not exist was handed to the watcher,
  which exited on the missing path and stopped autoreload. Watched paths
  that do not exist are now dropped.
- The entr backend stopped after an editor's atomic save. `entr -d`
  exits with status 2 when a file appears in a watched directory, which
  the loop treated as a dead watcher. Status 2 now triggers a change
  check and re-arms the watcher.
- The fswatch backend reloaded one event late. `fswatch -o | head -n1`
  only ends when fswatch writes a second line and meets the closed pipe.
  fswatch now runs with `-1` and exits after the first event.
- A watcher outlived its tmux server and kept running. The watcher now
  records the server pid when it starts and exits once the server is
  gone or a different server answers on the socket.
- The `reload` subcommand announced "tmux config reloaded" right after
  showing a source error. It now announces only a reload that succeeded.
- A broken edit made before the first successful reload had nothing to
  roll back to, because backups were written only after a reload
  succeeded. The watcher now snapshots the entrypoints when it starts.
- A watched path containing a space was split into separate words
  before reaching fswatch, inotifywait or entr. Targets are now passed
  as an array, one argument per path.

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
