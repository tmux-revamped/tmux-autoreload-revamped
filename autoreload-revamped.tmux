#!/usr/bin/env bash
#
# autoreload-revamped.tmux: TPM entry point.
#
# Ensures exactly one live config watcher per server. A healthy watcher from a
# previous load is left running; a dead or stale one, tracked by a pid kept in a
# server option, is cleaned up and replaced, so reloads never stack watchers and
# a crashed watcher self-heals on the next load.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AR_CMD="${CURRENT_DIR}/src/autoreload.sh"

chmod +x "${AR_CMD}" 2>/dev/null || true

"${AR_CMD}" ensure >/dev/null 2>&1
