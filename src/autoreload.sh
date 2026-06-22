#!/usr/bin/env bash
#
# autoreload.sh: command dispatcher for tmux-autoreload-revamped.
#
# Usage: autoreload.sh watch | reload | tick
#
# watch blocks, using fswatch or inotifywait when present and a polling fallback
# otherwise, and sources the config whenever a watched file changes. State is one
# tmux option (the watcher pid); no temp file is involved. The blocking loop sits
# behind seams so the change-and-reload logic stays fully testable.

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/tmux/tmux-ops.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/autoreload/autoreload.sh"

# Host-probe seams. Tests override these.
_config_files() { tmux display-message -p '#{config_files}' 2>/dev/null; }
_source_file() { tmux source-file "${1}" 2>/dev/null; }
_message() { tmux display-message "${1}" 2>/dev/null; }
# GNU stat (-c, Linux and GNU coreutils on macOS) first, BSD stat (-f, native
# macOS) as the fallback. GNU stat reads -f as --file-system, which prints a
# fluctuating free-block count; trying -c first avoids that false-change trap.
_file_mtime() { stat -c '%Y' "${1}" 2>/dev/null || stat -f '%m' "${1}" 2>/dev/null; }
_sleep() { sleep "${1}"; }
_poll_continue() { true; }
_exec_fswatch() { fswatch -o "$@" 2>/dev/null; }
_exec_inotify() { inotifywait -q -e modify,move,create,delete "$@" >/dev/null 2>&1; }

# ar_files -> the watched file list. When @autoreload_revamped_files is set it is
# the exact list, so you can watch only your own config; otherwise every file tmux
# loaded. A leading ~ in a path is expanded to $HOME.
ar_files() {
  local custom raw p
  custom="$(get_tmux_option "@autoreload_revamped_files" "")"
  if [[ -n "${custom}" ]]; then raw="${custom}"; else raw="$(_config_files)"; fi
  while IFS= read -r p; do
    [[ -n "${p}" ]] && printf '%s\n' "$(autoreload_expand_path "${p}")"
  done <<< "$(autoreload_split "${raw}")"
}

# ar_snapshot -> "<file> <mtime>" for every watched file, one per line.
ar_snapshot() {
  local f
  while IFS= read -r f; do
    [[ -n "${f}" ]] && printf '%s %s\n' "${f}" "$(_file_mtime "${f}")"
  done <<< "$(ar_files)"
}

# ar_reload -> source every entrypoint and announce it, unless quiet.
ar_reload() {
  local f
  while IFS= read -r f; do
    [[ -n "${f}" ]] && _source_file "${f}"
  done <<< "$(autoreload_split "$(get_tmux_option "@autoreload_revamped_entrypoints" "$(_config_files)")")"
  [[ "$(get_tmux_option "@autoreload_revamped_quiet" "0")" == "1" ]] || _message "tmux config reloaded"
}

# ar_poll_tick OLD -> reload when the snapshot changed; echo the current snapshot.
ar_poll_tick() {
  local new
  new="$(ar_snapshot)"
  [[ "$(autoreload_changed "${1}" "${new}")" == "1" ]] && ar_reload
  printf '%s' "${new}"
}

_poll_interval() {
  local i
  i=$(get_tmux_option "@autoreload_revamped_interval" "2")
  [[ "${i}" =~ ^[0-9]+$ ]] && (( i > 0 )) || i=2
  echo "${i}"
}

_watch_poll() {
  local snap interval
  snap="$(ar_snapshot)"
  interval="$(_poll_interval)"
  while _poll_continue; do
    _sleep "${interval}"
    snap="$(ar_poll_tick "${snap}")"
  done
}

_watch_fswatch() {
  local files
  files="$(ar_files | tr '\n' ' ')"
  # shellcheck disable=SC2086
  _exec_fswatch ${files} | while IFS= read -r _; do ar_reload; done
}

_watch_inotify() {
  local files
  files="$(ar_files | tr '\n' ' ')"
  # shellcheck disable=SC2086
  while _exec_inotify ${files}; do ar_reload; done
}

ar_watch() {
  case "$(autoreload_select_watcher)" in
    fswatch)     _watch_fswatch ;;
    inotifywait) _watch_inotify ;;
    *)           _watch_poll ;;
  esac
}

main() {
  case "${1:-}" in
    watch)  ar_watch ;;
    reload) ar_reload ;;
    tick)   ar_poll_tick "" >/dev/null ;;
    *)      return 0 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
