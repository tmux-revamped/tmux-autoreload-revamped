<div align="center">

<h1>tmux-autoreload-revamped</h1>

**Edit your tmux config, save, and watch it reload itself, no key, no command.**

[![Tests](https://github.com/tmux-revamped/tmux-autoreload-revamped/actions/workflows/tests.yml/badge.svg)](https://github.com/tmux-revamped/tmux-autoreload-revamped/actions/workflows/tests.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE) [![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)](CHANGELOG.md)

</div>

**4** watcher backends · **fswatch · inotify · entr · poll** · **tmux 1.9 to 3.5** · **105** tests · **95%+** coverage

Watches every loaded tmux config file, and the files they source, and applies your config the moment it really changes. It uses `fswatch`, `inotifywait`, or `entr` when they are installed, and a built-in polling loop otherwise, so it works out of the box with no extra dependency. One watcher per server, tracked by pid and self-healing, so reloads never stack up. A broken edit is caught, surfaced, and rolled back to the last working config instead of half-applying.

Built from [tmux-plugin-template](https://github.com/tmux-revamped/tmux-plugin-template).

<table>
<tr>
<td><strong>Four backends</strong><br>fswatch, inotifywait, entr, or a pure-shell poll fallback, picked automatically.</td>
<td><strong>Validate then apply</strong><br>A failing edit is surfaced with its error and rolled back to the last good config, never half-applied.</td>
</tr>
<tr>
<td><strong>Follows your includes</strong><br>Parses every <code>source</code> and <code>source-file</code> and watches those files too, re-checked after each reload.</td>
<td><strong>No noise</strong><br>Atomic-save aware, content-hash deduped so a no-op save is ignored, and deferred while you are mid-selection or at a prompt.</td>
</tr>
<tr>
<td><strong>Self-healing</strong><br>One watcher per server, tracked by pid; a dead or stale watcher is replaced on the next load.</td>
<td><strong>Tells you what changed</strong><br>Names the changed file, with optional desktop notification and a brief visual flash.</td>
</tr>
</table>

## Usage

Install it and forget it. Save your `~/.tmux.conf`, or any file it sources, and tmux reloads on its own with a brief "tmux config reloaded (filename)" message. If an edit has an error, the message names the failing file and line and your last working config stays in place.

Bind the optional subcommands to keys, replacing the path with your plugin directory:

```tmux
bind R run-shell "~/.tmux/plugins/tmux-autoreload-revamped/src/autoreload.sh reload"
bind P run-shell "~/.tmux/plugins/tmux-autoreload-revamped/src/autoreload.sh toggle"
```

| Subcommand | Effect |
|------------|--------|
| `reload` | source the entrypoints now |
| `pause` / `resume` / `toggle` | stop or resume reacting to changes |
| `status` | print the current state, watcher pid, and backend |

## Install

With [TPM](https://github.com/tmux-plugins/tpm), add to `~/.tmux.conf`:

```tmux
set -g @plugin 'tmux-revamped/tmux-autoreload-revamped'
```

Press `prefix + I`. For event-driven reloads install [fswatch](https://github.com/emcrisostomo/fswatch), inotify-tools, or [entr](https://eradman.com/entrproject/); without any of them the polling fallback takes over automatically.

## Configuration

| Option | Default | Meaning |
|--------|---------|---------|
| `@autoreload_revamped_files` | empty | the exact files to watch, comma or space separated, with `~` expanded; when set it replaces the default, so you can watch only your own config. Empty means watch every file tmux loaded |
| `@autoreload_revamped_entrypoints` | loaded config | files to source on reload |
| `@autoreload_revamped_interval` | `2` | seconds between checks in the polling fallback |
| `@autoreload_revamped_quiet` | `0` | set to `1` to suppress the reload message |
| `@autoreload_revamped_discover` | `1` | parse `source`/`source-file` directives and watch those files too; set to `0` to watch only the top-level files |
| `@autoreload_revamped_atomic` | `1` | also watch each file's parent directory so editor rename-on-save is caught; set to `0` to watch files only |
| `@autoreload_revamped_validate` | `1` | on a source error, roll back to the last good config; set to `0` to apply without rollback |
| `@autoreload_revamped_defer` | `1` | wait to reload while a client is in copy-mode or at a prompt; set to `0` to reload immediately |
| `@autoreload_revamped_selective` | `0` | set to `1` to re-source only the entrypoint whose include subtree owns the changed file |
| `@autoreload_revamped_backoff_max` | `30` | maximum seconds the polling backoff grows to after repeated reload failures |
| `@autoreload_revamped_flash` | `0` | set to `1` for a brief reverse-video flash on reload |
| `@autoreload_revamped_notify` | `0` | set to `1` for a desktop notification on reload (`osascript` or `notify-send`) |

## Compatibility

Works on every tmux version TPM supports, 1.9 and up, on Linux (x86_64 and arm64) and macOS (Intel and Apple Silicon). The mtime check reads GNU `stat -c` first and BSD `stat -f` as a fallback, so it is correct on Linux, on native macOS, and on a Mac with GNU coreutils in `PATH`. The `#{config_files}` source list needs tmux 3.2 and up; on older tmux, name your files with `@autoreload_revamped_files`. The `entr` backend is used when neither `fswatch` nor `inotifywait` is present but `entr` is.

## Development

```bash
make test    # bats suite
make lint    # shellcheck
make coverage  # kcov line coverage on Linux
```

Watcher selection, change detection, and path normalization live in [`src/lib/autoreload/autoreload.sh`](src/lib/autoreload/autoreload.sh) as pure functions, with the blocking watch loop split behind seams so the reload logic is fully tested without a real watcher.

## License

[MIT](LICENSE), copyright Gustavo Franco.

<!-- family:begin -->

## The tmux-revamped family

This plugin is one member of the tmux-revamped family. Every member carries the
same contract in [`FAMILY.md`](FAMILY.md), the same tooling under `family/`, and
the same shared library, all held byte-identical by a checksum manifest. They are
built to be installed together: no member claims a key or a tmux option that
another member claims.

A defect found in one member is hunted across all of them before the fix is
called done. That obligation is written into the contract rather than left to
memory, and `family/bin/sweep` is how it is discharged.

| Member | What it does |
|---|---|
| [`tmux-autoreload-revamped`](https://github.com/tmux-revamped/tmux-autoreload-revamped) | **this plugin**, Edit your tmux config, save, and watch it reload itself, no key, no command |
| [`tmux-battery-revamped`](https://github.com/tmux-revamped/tmux-battery-revamped) | Battery status for your tmux status bar, without ever blocking the status render |
| [`tmux-bluetooth-revamped`](https://github.com/tmux-revamped/tmux-bluetooth-revamped) | Every connected Bluetooth device and its battery in your tmux status bar, without blocking the render |
| [`tmux-cpu-revamped`](https://github.com/tmux-revamped/tmux-cpu-revamped) | CPU load, temperature, and frequency in your tmux status bar, without ever blocking the render |
| [`tmux-disk-revamped`](https://github.com/tmux-revamped/tmux-disk-revamped) | Disk usage for your tmux status bar, without ever blocking the status render |
| [`tmux-extract-revamped`](https://github.com/tmux-revamped/tmux-extract-revamped) | Fuzzy-grab any URL, path, or word off the screen and paste it, pure shell, no Python |
| [`tmux-fzf-revamped`](https://github.com/tmux-revamped/tmux-fzf-revamped) | Jump to any session, window, or pane, or kill it, from one fzf popup |
| [`tmux-git-revamped`](https://github.com/tmux-revamped/tmux-git-revamped) | Git repository status in your tmux status bar, without ever blocking the render |
| [`tmux-gpu-revamped`](https://github.com/tmux-revamped/tmux-gpu-revamped) | GPU load, temperature, frequency, and memory for your tmux status bar |
| [`tmux-kube-revamped`](https://github.com/tmux-revamped/tmux-kube-revamped) | Current Kubernetes context and namespace in your tmux status bar, async, kubectl-free, never blocking |
| [`tmux-launcher-revamped`](https://github.com/tmux-revamped/tmux-launcher-revamped) | Launch any TUI app in a popup or a window, scoped to the current pane's directory, with one configurable bindi |
| [`tmux-logging-revamped`](https://github.com/tmux-revamped/tmux-logging-revamped) | Capture any pane to a file: live logging, full scrollback, or a one-shot screenshot |
| [`tmux-music-revamped`](https://github.com/tmux-revamped/tmux-music-revamped) | Now playing in your tmux status bar, without ever blocking the status render |
| [`tmux-network-revamped`](https://github.com/tmux-revamped/tmux-network-revamped) | Network throughput in your tmux status bar, without ever blocking the render |
| [`tmux-pain-control-revamped`](https://github.com/tmux-revamped/tmux-pain-control-revamped) | Standard pane and window management bindings for tmux, version aware, vim friendly, and fully configurable |
| [`tmux-persist-revamped`](https://github.com/tmux-revamped/tmux-persist-revamped) | One plugin that captures every session, window, pane, layout, and working |
| [`tmux-plugin-template`](https://github.com/tmux-revamped/tmux-plugin-template) | A template for building non-blocking tmux status plugins |
| [`tmux-pomodoro-revamped`](https://github.com/tmux-revamped/tmux-pomodoro-revamped) | A Pomodoro timer in your tmux status bar, with zero temp files: all state lives in tmux options |
| [`tmux-ram-revamped`](https://github.com/tmux-revamped/tmux-ram-revamped) | RAM usage for your tmux status bar, without ever blocking the status render |
| [`tmux-scroll-revamped`](https://github.com/tmux-revamped/tmux-scroll-revamped) | Mouse wheel that does the right thing: scroll the app directly, copy-mode everywhere else. No app names to con |
| [`tmux-sensible-revamped`](https://github.com/tmux-revamped/tmux-sensible-revamped) | Sensible tmux defaults that normalize behavior across every tmux version, OS, and terminal, without clobbering |
| [`tmux-tiling-revamped`](https://github.com/tmux-revamped/tmux-tiling-revamped) | --- |
| [`tmux-time-revamped`](https://github.com/tmux-revamped/tmux-time-revamped) | Local clock and world clocks in your tmux status bar, without ever blocking the render |
| [`tmux-weather-revamped`](https://github.com/tmux-revamped/tmux-weather-revamped) | Weather in your tmux status bar, fetched in the background so the render never waits on the network |

### Checking an installation

With every member on disk, one command reports any conflict between them:

```sh
family/bin/doctor --live
```

It reads each member and the running tmux server, and reports duplicate keys,
duplicate status placeholders, options outside the naming grammar, and any
member whose contract version has fallen behind.

<!-- family:end -->
