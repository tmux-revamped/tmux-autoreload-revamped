# tmux-autoreload-revamped

Guidance for anyone, human or agent, changing tmux-autoreload-revamped. What it is and how to use it lives in [README.md](README.md).

[FAMILY.md](FAMILY.md) holds everything this plugin shares with the rest of the tmux-revamped family, and it is the same in every member. This file holds only what is exclusive to tmux-autoreload-revamped, under the same headings as the agent guide of every member. Read both before changing anything; a rule that would serve the other members goes into [`FAMILY.md`](FAMILY.md) instead of here.

## Layout

| Path | Holds |
|:-----|:------|
| [`autoreload-revamped.tmux`](autoreload-revamped.tmux) | The entry point TPM runs |
| [`src/autoreload.sh`](src/autoreload.sh) | The script the placeholders, keys and popups call |
| [`src/lib/autoreload/`](src/lib/autoreload) | This member's modules |
| [`src/lib/utils/constants.sh`](src/lib/utils/constants.sh) | This member's constants, including its version |
| [`src/lib/utils/`](src/lib/utils), [`src/lib/tmux/`](src/lib/tmux) | The shared library. Every file there except `constants.sh` is owned by the family |
| [`test/`](test) | The bats suite. `helpers.bash` and `tmux_helpers.bash` are owned; this member's own mocks go in the `_local` files |
| [`family/`](family) | The family tooling, owned |

## Names

- Settings are tmux options named `@autoreload_revamped_<setting>`.
- Placeholders include `#{config_files}`.
- Public functions carry `ar_`; private ones start with `_`.
- The version constant is `AUTORELOAD_REVAMPED_VERSION`.
- `AR_CACHE_DIR` is read from the environment.
- Its command-line tool, once it exists, is `autoreload-revamped`.

## Behaviour

- Watches every tmux config file and sources it again when it is saved, with no key and no command.
- Loading the plugin starts one watcher per server, unless one is already alive.
- A change is detected by comparing modification times and a checksum, so saving an unchanged file reloads nothing.
- A reload that fails shows the error and sources the last good copy again.
- A desktop notification for each reload goes through the shared notifier behind `@autoreload_revamped_notify`, off by default.

## Domain rules

- The watcher uses the first tool it finds: `fswatch`, `inotifywait`, `entr`, then a polling loop. The polling loop doubles its wait after each failed reload, up to `@autoreload_revamped_backoff_max` seconds.
- The watcher records the tmux server's pid when it starts and exits when that server is gone or a different server answers on the socket.
- Backups of the entry points live under `~/.tmux/autoreload-revamped/backup`, written when the watcher starts and after each reload that succeeds. `AR_CACHE_DIR` moves them.

## Release

- `AUTORELOAD_REVAMPED_VERSION` in [`src/lib/utils/constants.sh`](src/lib/utils/constants.sh) holds the version. It must equal the newest versioned heading in [`CHANGELOG.md`](CHANGELOG.md) and the README's version badge, which the `version` job in `tests.yml` checks.
- A push to `main` whose version has no tag yet makes the `release` job in `tests.yml` tag `vX.Y.Z` and publish a GitHub release with that changelog section.
- Unreleased changes sit under `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md) until a release is cut.

## Gaps against FAMILY.md

As of 2026-11-15:

- Every script is bash, under `#!/usr/bin/env bash`, not POSIX `sh`, so it is untested under `dash`, `zsh` and BusyBox `sh`.
- The code lives in [`src/`](src) and [`src/lib/`](src/lib); there is no `bin/autoreload-revamped`, `lib/state.sh` or `lib/core.sh`.
- No `autoreload-revamped` command with `help`, `version` and `doctor` in the family's form, no man page, no completions and no `manifest.json`.
- No gum interface: no `lib/ui.sh`, `lib/table.awk`, themes or `test/bin/gum`.
- No `screens/` and no recordings in the README.
- The README sections are not the family's order of Quick start, Usage, topic sections, Portability, Development and License.
- Coverage is kcov with a 95 percent floor on Linux, not bashcov at 100 percent merged from macOS and Linux.
- CI tests GNU, BSD and uutils tools in `tests.yml`, but not the six toolsets through `.github/scripts/toolset.sh`, and no shell matrix under `sh`, `dash`, `bash` and `zsh`.
- No golden transcripts, `call.sh`, `run-matrix.sh` or `linux-container.sh`.
- The version is written by hand and released by `tests.yml`; there is no semantic-release, `package.json`, `release.yml` with `recover`, `bot-merge.yml` or Renovate.
- CI is `tests.yml`, `family.yml` and `security.yml`, not `ci.yml`, and no job starts with `step-security/harden-runner`.
- No `.editorconfig`, `.yamllint.yml`, `scripts/check-names.sh` or shfmt; the Makefile has `help`, `test`, `test-unit`, `coverage`, `lint` and `clean`, not the family's targets.
