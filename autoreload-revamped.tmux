#!/usr/bin/env bash
#
# autoreload-revamped.tmux: TPM entry point.
#
# Starts one background watcher for the tmux config. Any watcher from a previous
# load is killed first, using a pid kept in a server option, so reloads never
# stack watchers.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AR_CMD="${CURRENT_DIR}/src/autoreload.sh"

chmod +x "${AR_CMD}" 2>/dev/null || true

old_pid=$(tmux show-option -gqv "@autoreload_revamped_pid")
if [[ -n "${old_pid}" ]]; then
  kill "${old_pid}" 2>/dev/null || true
fi

"${AR_CMD}" watch >/dev/null 2>&1 &
disown 2>/dev/null || true

tmux set-option -g "@autoreload_revamped_pid" "$!"
