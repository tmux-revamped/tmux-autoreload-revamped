#!/usr/bin/env bash
#
# autoreload.sh: pure helpers for tmux-autoreload-revamped.
#
# Watcher selection, change detection, and path normalization are pure. The actual
# file watching, mtime reads, and config sourcing sit behind seams in the
# dispatcher, so the tests touch no real watcher and reload no real config.

[[ -n "${_AUTORELOAD_REVAMPED_LOADED:-}" ]] && return 0
_AUTORELOAD_REVAMPED_LOADED=1

_AR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_AR_LIB_DIR}/../utils/has-command.sh"

# autoreload_select_watcher -> the best available watcher: fswatch (macOS and
# Linux), inotifywait (Linux), or poll as the universal fallback.
autoreload_select_watcher() {
  if has_command fswatch; then
    echo "fswatch"
  elif has_command inotifywait; then
    echo "inotifywait"
  else
    echo "poll"
  fi
}

# autoreload_changed OLD NEW -> "1" when the snapshots differ, else "0".
autoreload_changed() {
  if [[ "${1}" != "${2}" ]]; then
    echo "1"
  else
    echo "0"
  fi
}

# autoreload_split LIST -> LIST normalized to one path per line, splitting on
# commas and whitespace, with blanks and duplicates removed.
autoreload_split() {
  printf '%s' "${1}" | tr ',[:space:]' '\n' | awk 'NF && !seen[$0]++'
}

export -f autoreload_select_watcher
export -f autoreload_changed
export -f autoreload_split
