<div align="center">

<h1>tmux-autoreload-revamped</h1>

**Edit your tmux config, save, and watch it reload itself, no key, no command.**

[![Tests](https://github.com/gufranco/tmux-autoreload-revamped/actions/workflows/tests.yml/badge.svg)](https://github.com/gufranco/tmux-autoreload-revamped/actions/workflows/tests.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

</div>

**3** watcher backends · **no entr** · **tmux 1.9 to 3.5** · **42** tests · **95%+** coverage

Watches every loaded tmux config file and sources it the moment it changes. It uses `fswatch` or `inotifywait` when they are installed, and a built-in polling loop otherwise, so it works out of the box with no extra dependency. One watcher per server, tracked by pid, so reloads never stack up.

Built from [tmux-plugin-template](https://github.com/gufranco/tmux-plugin-template).

<table>
<tr>
<td><strong>Three backends</strong><br>fswatch, inotifywait, or a pure-shell poll fallback, picked automatically.</td>
<td><strong>No dependency</strong><br>The poll fallback needs nothing but tmux and a shell. No entr, no Python.</td>
</tr>
<tr>
<td><strong>No stacking</strong><br>The watcher pid lives in a server option; each load kills the previous watcher first.</td>
<td><strong>Watches everything</strong><br>Every file tmux actually loaded, plus any extra files you name.</td>
</tr>
</table>

## Usage

Install it and forget it. Save your `~/.tmux.conf`, or any sourced file, and tmux reloads on its own with a brief "tmux config reloaded" message.

## Install

With [TPM](https://github.com/tmux-plugins/tpm), add to `~/.tmux.conf`:

```tmux
set -g @plugin 'gufranco/tmux-autoreload-revamped'
```

Press `prefix + I`. For event-driven reloads install [fswatch](https://github.com/emcrisostomo/fswatch) or inotify-tools; without them the polling fallback takes over automatically.

## Configuration

| Option | Default | Meaning |
|--------|---------|---------|
| `@autoreload_revamped_files` | empty | the exact files to watch, comma or space separated, with `~` expanded; when set it replaces the default, so you can watch only your own config. Empty means watch every file tmux loaded |
| `@autoreload_revamped_entrypoints` | loaded config | files to source on reload |
| `@autoreload_revamped_interval` | `2` | seconds between checks in the polling fallback |
| `@autoreload_revamped_quiet` | `0` | set to `1` to suppress the reload message |

## Compatibility

Works on every tmux version TPM supports, 1.9 and up, on Linux (x86_64 and arm64) and macOS (Intel and Apple Silicon). The mtime check reads GNU `stat -c` first and BSD `stat -f` as a fallback, so it is correct on Linux, on native macOS, and on a Mac with GNU coreutils in `PATH`. The `#{config_files}` source list needs tmux 3.2 and up; on older tmux, name your files with `@autoreload_revamped_files`.

## Development

```bash
make test    # bats suite
make lint    # shellcheck
make coverage  # kcov line coverage on Linux
```

Watcher selection, change detection, and path normalization live in [`src/lib/autoreload/autoreload.sh`](src/lib/autoreload/autoreload.sh) as pure functions, with the blocking watch loop split behind seams so the reload logic is fully tested without a real watcher.

## License

[MIT](LICENSE), copyright Gustavo Franco.
