# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
