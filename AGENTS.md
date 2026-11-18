# tmux-autoreload-revamped

Guidance for anyone, human or agent, changing tmux-autoreload-revamped. What it is and how to use it lives in [README.md](README.md).

[FAMILY.md](FAMILY.md) holds everything this plugin shares with the rest of the tmux-revamped family, and it is the same in every member. This file holds only what is exclusive to tmux-autoreload-revamped, under the same headings as the agent guide of every member. Read both before changing anything; a rule that would serve the other members goes into [`FAMILY.md`](FAMILY.md) instead of here.

## Layout

| Path | Holds |
|:-----|:------|
| [`autoreload-revamped.tmux`](autoreload-revamped.tmux) | The entry point TPM runs: it runs `bin/autoreload-revamped apply` |
| [`bin/autoreload-revamped`](bin/autoreload-revamped) | The command: `apply`, `watch`, `reload`, `pause`, `resume`, `toggle`, `status`, `doctor`, `version`, `help` and the menu. `apply` and `watch` run without loading the interface modules |
| [`lib/autoreload.sh`](lib/autoreload.sh) | Reading the settings, the list of watched files, the snapshot, the reload and the watcher |
| [`lib/state.sh`](lib/state.sh) | Every global, including `AUTORELOAD_REVAMPED_SETTINGS`, the table of setting names and defaults the rest reads |
| [`lib/core.sh`](lib/core.sh) | The version |
| [`lib/`](lib) | Every other file is the shared library, identical in every member |
| [`test/autoreload.bats`](test/autoreload.bats), [`test/watch.bats`](test/watch.bats), [`test/commands.bats`](test/commands.bats), [`test/entrypoint.bats`](test/entrypoint.bats), [`test/backends.bats`](test/backends.bats) | This member's suites: the library and the watcher through stand-in tools, the commands, the plugin on a private tmux server started with a real config, and each watcher tool for real where it is installed. The first three share [`test/autoreload_helpers.bash`](test/autoreload_helpers.bash) and the last two [`test/server_helpers.bash`](test/server_helpers.bash) |
| [`screens/`](screens) | The tapes and the recording's tmux config, which points the plugin at a config file in the demo folder |

## Names

- Settings are the tmux options `@autoreload_revamped_<setting>` listed in `AUTORELOAD_REVAMPED_SETTINGS`, the long options with dashes, such as `--backup-dir`, and the environment variables `AUTORELOAD_REVAMPED_<SETTING>`.
- `@autoreload_revamped_pid` holds the watcher's pid and `@autoreload_revamped_paused` the pause; they are state, never settings.
- It has no status placeholders and binds no key.
- The version constant is `AUTORELOAD_REVAMPED_VERSION`.
- The command's own functions and the library's never share a name, because the command is sourced after the library and would replace it.

## Behaviour

- Every command reads the settings, the server's pid, the pause, the watcher's pid and `#{config_files}` with one `tmux display-message` call and one `env` read. An empty tmux option means its default.
- `apply` starts `watch` in the background with its input, output and errors on `/dev/null`, records its pid and returns. A watcher that inherits the entry point's input keeps `run-shell` from returning.
- `apply` keeps a living watcher and replaces a dead one, so one watcher runs per tmux server.
- A reload sources every entry point, shows `tmux config reloaded` with the first changed file, and saves a copy of each entry point. With `@autoreload_revamped_selective` on it sources only the entry points whose tree holds the changed file.
- A reload that fails shows `tmux config error in` with the file and tmux's message once, sources the last good copy when `@autoreload_revamped_validate` is on, and records the snapshot, so the same broken content is never retried.
- A desktop notification for each reload goes through the shared notifier behind `@autoreload_revamped_notify`, off by default.
- The entry point clears every inherited `REVAMPED_` variable except the test switches, and every `AUTORELOAD_REVAMPED_*_LOADED` guard; every other global is assigned outright in the state file.

## Domain rules

- The watched files are `@autoreload_revamped_files` when set, else the files tmux loaded, plus every file they `source` or `source-file`, followed up to 8 levels, each once, missing ones skipped.
- A snapshot is one `cksum` run over every watched file. A change is a row that differs, so a save that changes no byte reloads nothing, and no modification time is read.
- After a reload the watcher keeps the snapshot it loaded, never a fresh one, and takes a fresh row only for a file that just joined the list. A fresh snapshot would record a save made while the reload ran as already loaded.
- The watcher uses the first tool it finds: `fswatch`, `inotifywait`, `entr`, then a check every `@autoreload_revamped_interval` seconds. `fswatch` is run as `fswatch -1`, never with `-o`: fswatch 1.22 prints a count per batch with `-o` and never exits, so each save would wait for the guard. With `@autoreload_revamped_atomic` on, the tool is also given each file's folder.
- An event backend compares the snapshot first and starts its tool only when nothing changed, so a save made while a reload ran is loaded at once and no tool is started for it. The watcher never signals a tool it has just started: a signal that reaches a helper before it has become its program can be dropped, and the watcher would then wait on it forever. A guard beside the tool checks every 5 seconds that the tmux server is alive and the snapshot unchanged, and ends the tool otherwise, so a watcher never outlives its server and a save the tool missed is loaded within that time.
- `entr` exits with 2 when a folder it watches changes; that is a reason to check, never a failure. Any other failure of a tool waits one interval before the next round.
- A reload held back by a pane in a mode, or by a pause, is checked again every interval on every backend, since no file event announces a pane leaving copy-mode.
- The watcher records the tmux server's pid when it starts and ends when a different server answers on the socket.
- Stopping a tool or the guard after the tool ended is a `kill` followed by a `wait`, so the shell reports no ended job. A signal to the watcher itself sends one `kill` to each and exits without waiting.

## Release

- `AUTORELOAD_REVAMPED_VERSION` in [`lib/core.sh`](lib/core.sh) holds the version. Nobody edits it by hand.
- After a green `ci` run on `main`, [`release.yml`](.github/workflows/release.yml) runs semantic-release: a `feat` or `fix` since the last tag publishes a release, [`set-version.sh`](.github/scripts/set-version.sh) stamps the constant, and the notes go into [`CHANGELOG.md`](CHANGELOG.md).
- [`ci.yml`](.github/workflows/ci.yml) and [`test/linux-container.sh`](test/linux-container.sh) install `fswatch`, `inotify-tools` and `entr` on Linux and `fswatch` and `entr` on macOS, so [`test/backends.bats`](test/backends.bats) runs each tool for real there. A tool that is missing fails its tests instead of skipping them, so a local gate cannot pass with a backend untested; on macOS that means `brew install fswatch entr` first. Only `inotifywait` is skipped on macOS, where it does not exist.

## Gaps against FAMILY.md

As of 2026-11-17, none.
