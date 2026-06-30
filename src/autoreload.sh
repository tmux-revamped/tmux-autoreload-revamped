#!/usr/bin/env bash
#
# autoreload.sh: command dispatcher for tmux-autoreload-revamped.
#
# Usage: autoreload.sh watch | reload | tick | event | pause | resume | toggle |
#        status | ensure
#
# watch blocks, using fswatch, inotifywait, entr, or a polling fallback, and
# sources the config whenever a watched file really changes. Every tmux call,
# file read, watcher, sleep, and notification sits behind a seam, so the
# change-detect-validate-reload logic is tested without a real watcher and
# without reloading real config. Runtime state lives in tmux server options; the
# only file writes are last-good backups under a cache dir for rollback.

AR_SELF="${BASH_SOURCE[0]}"
PLUGIN_DIR="$(cd "$(dirname "${AR_SELF}")/.." && pwd)"
AR_CACHE_DIR="${AR_CACHE_DIR:-${HOME}/.tmux/autoreload-revamped}"

# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/tmux/tmux-ops.sh"
# shellcheck source=/dev/null
source "${PLUGIN_DIR}/src/lib/autoreload/autoreload.sh"

# --- seams. Tests override these so nothing real is watched, sourced, or run ---

# Single tmux seam. Every tmux interaction routes through it for one mock point.
_tmux() { tmux "$@"; }
_config_files() { _tmux display-message -p '#{config_files}' 2>/dev/null; }
# Source a file and echo any tmux error text; the return code is tmux's own.
_source_file() { { _tmux source-file "${1}" >/dev/null; } 2>&1; }
_message() { _tmux display-message "${1}" >/dev/null 2>&1; }
_flash() { _tmux display-message "#[reverse]${1}#[default]" >/dev/null 2>&1; return 0; }
# Busy when any pane is in copy-mode or view-mode, so a reload never yanks a
# user out of a selection or a command prompt.
_client_busy() {
  case "$(_tmux list-panes -a -F '#{pane_in_mode}' 2>/dev/null)" in
    *1*) return 0 ;;
    *) return 1 ;;
  esac
}
_notify() {
  if has_command osascript; then
    osascript -e "display notification \"${2}\" with title \"${1}\"" >/dev/null 2>&1
  elif has_command notify-send; then
    notify-send "${1}" "${2}" >/dev/null 2>&1
  fi
  return 0
}
# GNU stat (-c) first, BSD stat (-f) as the fallback. GNU stat reads -f as
# --file-system, which prints a fluctuating free-block count; trying -c first
# avoids that false-change trap.
_file_mtime() { stat -c '%Y' "${1}" 2>/dev/null || stat -f '%m' "${1}" 2>/dev/null; }
_file_content() { cat "${1}" 2>/dev/null; }
_hash_content() { cksum 2>/dev/null; }
_sleep() { sleep "${1}"; }
_poll_continue() { true; }
_exec_fswatch() { fswatch -o "$@" 2>/dev/null | head -n1 >/dev/null; }
_exec_inotify() { inotifywait -q -e modify,move,create,delete,close_write "$@" >/dev/null 2>&1; }
_exec_entr() { printf '%s\n' "$@" | entr -d -n -p -z true >/dev/null 2>&1; }
_pid_alive() { kill -0 "${1}" 2>/dev/null; }
_kill_pid() { kill "${1}" 2>/dev/null || true; }
_spawn_watcher() {
  "${AR_SELF}" watch >/dev/null 2>&1 &
  disown 2>/dev/null || true
  echo "$!"
}

# --- backups for validate-then-apply rollback (cache dir, never a temp dir) ---

_backup_dir() { printf '%s/backup' "${AR_CACHE_DIR}"; }
_backup_path() { printf '%s/%s' "$(_backup_dir)" "$(printf '%s' "${1}" | tr -c 'A-Za-z0-9._-' '_')"; }
_save_backup() {
  mkdir -p "$(_backup_dir)" 2>/dev/null || return 0
  _file_content "${1}" > "$(_backup_path "${1}")" 2>/dev/null || true
}
_restore_backup() {
  local b
  b="$(_backup_path "${1}")"
  [[ -f "${b}" ]] && _source_file "${b}" >/dev/null 2>&1
  return 0
}

# --- watched file set --------------------------------------------------------

# ar_base_files -> the configured watch list: the exact @autoreload_revamped_files
# when set, otherwise every file tmux loaded. A leading ~ expands to $HOME.
ar_base_files() {
  local custom raw p
  custom="$(get_tmux_option "@autoreload_revamped_files" "")"
  if [[ -n "${custom}" ]]; then raw="${custom}"; else raw="$(_config_files)"; fi
  while IFS= read -r p; do
    [[ -n "${p}" ]] && printf '%s\n' "$(autoreload_expand_path "${p}")"
  done <<< "$(autoreload_split "${raw}")"
}

# ar_discover FILE [DEPTH] -> FILE plus every file it sources, recursively and
# bounded, so a newly added `source` directive gets watched too.
ar_discover() {
  local start="${1}" depth="${2:-0}" child resolved
  [[ -n "${start}" ]] || return 0
  if (( depth > 8 )); then return 0; fi
  printf '%s\n' "${start}"
  if [[ "$(get_tmux_option "@autoreload_revamped_discover" "1")" != "1" ]]; then return 0; fi
  while IFS= read -r child; do
    [[ -n "${child}" ]] || continue
    resolved="$(autoreload_resolve "${start}" "${child}")"
    ar_discover "${resolved}" "$(( depth + 1 ))"
  done <<< "$(_file_content "${start}" | autoreload_parse_sources)"
}

# ar_files -> the full de-duplicated watched set, with sourced includes folded in
# when discovery is on.
ar_files() {
  local base f
  base="$(ar_base_files)"
  if [[ "$(get_tmux_option "@autoreload_revamped_discover" "1")" == "1" ]]; then
    { while IFS= read -r f; do
        [[ -n "${f}" ]] && ar_discover "${f}"
      done <<< "${base}"; } | awk 'NF && !seen[$0]++'
  else
    printf '%s\n' "${base}" | awk 'NF && !seen[$0]++'
  fi
}

# ar_event_targets -> what to hand a watcher to subscribe to: the watched files
# plus, for atomic-save handling, their parent directories.
ar_event_targets() {
  local files atomic
  files="$(ar_files)"
  atomic="$(get_tmux_option "@autoreload_revamped_atomic" "1")"
  { printf '%s\n' "${files}"
    [[ "${atomic}" == "1" ]] && printf '%s\n' "${files}" | autoreload_watch_dirs
  } | awk 'NF && !seen[$0]++'
}

# ar_snapshot -> "<file> <mtime>" for every watched file, one per line.
ar_snapshot() {
  local f
  while IFS= read -r f; do
    [[ -n "${f}" ]] && printf '%s %s\n' "${f}" "$(_file_mtime "${f}")"
  done <<< "$(ar_files)"
}

# ar_content_hash -> one checksum over the concatenated content of every watched
# file, so a no-op save that only bumps mtime can be told apart from a real edit.
ar_content_hash() {
  local f
  { while IFS= read -r f; do
      [[ -n "${f}" ]] && _file_content "${f}"
    done <<< "$(ar_files)"; } | _hash_content
}

# --- reload pipeline ---------------------------------------------------------

# ar_entrypoints -> files to source on reload: @autoreload_revamped_entrypoints
# when set, otherwise the loaded config list.
ar_entrypoints() {
  autoreload_split "$(get_tmux_option "@autoreload_revamped_entrypoints" "$(_config_files)")"
}

# ar_closure_contains ENTRY CHANGED -> 0 when any changed file lives in ENTRY's
# source closure, used to pick the affected subtree for a selective reload.
ar_closure_contains() {
  local entry="${1}" changed="${2}" closure c
  closure="$(ar_discover "${entry}")"
  while IFS= read -r c; do
    [[ -n "${c}" ]] || continue
    printf '%s\n' "${closure}" | grep -Fxq -- "${c}" && return 0
  done <<< "${changed}"
  return 1
}

# ar_affected_entrypoints CHANGED -> the entrypoints whose subtree owns a changed
# file; falls back to every entrypoint when nothing matches.
ar_affected_entrypoints() {
  local changed="${1}" entries e any=""
  entries="$(ar_entrypoints)"
  while IFS= read -r e; do
    [[ -n "${e}" ]] || continue
    if ar_closure_contains "${e}" "${changed}"; then printf '%s\n' "${e}"; any=1; fi
  done <<< "${entries}"
  [[ -z "${any}" ]] && printf '%s\n' "${entries}"
  return 0
}

# ar_surface_error FILE ERR -> show the failing file and the captured tmux error
# so a broken edit is visible instead of silently half-applied.
ar_surface_error() {
  local f="${1}" err="${2}" msg
  if [[ -n "${err}" ]]; then
    msg="tmux config error in ${f##*/}: ${err}"
  else
    msg="tmux config error in ${f##*/}"
  fi
  _message "${msg}"
}

# ar_save_backups LIST -> snapshot each entrypoint's content as the new last-good.
ar_save_backups() {
  local f
  while IFS= read -r f; do
    [[ -n "${f}" ]] && _save_backup "${f}"
  done <<< "${1}"
}

# ar_source_all LIST -> source each file. On a tmux error, surface it and, when
# validation is on, roll back to the last-good backup; on full success, refresh
# the backups. Returns non-zero when any file failed.
ar_source_all() {
  local list="${1}" validate f err rc
  validate="$(get_tmux_option "@autoreload_revamped_validate" "1")"
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    err="$(_source_file "${f}")"
    rc=$?
    if [[ "${rc}" -ne 0 || -n "${err}" ]]; then
      ar_surface_error "${f}" "${err}"
      [[ "${validate}" == "1" ]] && _restore_backup "${f}"
      return 1
    fi
  done <<< "${list}"
  [[ "${validate}" == "1" ]] && ar_save_backups "${list}"
  return 0
}

# ar_apply CHANGED -> source the right entrypoints, selectively when enabled.
ar_apply() {
  local changed="${1}" targets
  if [[ "$(get_tmux_option "@autoreload_revamped_selective" "0")" == "1" ]]; then
    targets="$(ar_affected_entrypoints "${changed}")"
  else
    targets="$(ar_entrypoints)"
  fi
  ar_source_all "${targets}"
}

# ar_announce CHANGED -> the success surface: message naming the changed file,
# plus an optional visual flash and desktop notification.
ar_announce() {
  local changed="${1}" name count msg
  name="$(printf '%s' "${changed}" | head -n1)"
  name="${name##*/}"
  count="$(printf '%s\n' "${changed}" | awk 'NF' | wc -l | tr -d ' ')"
  if [[ "${count}" -gt 1 ]]; then
    msg="tmux config reloaded (${name} +$(( count - 1 )) more)"
  else
    msg="tmux config reloaded (${name})"
  fi
  [[ "$(get_tmux_option "@autoreload_revamped_quiet" "0")" == "1" ]] || _message "${msg}"
  [[ "$(get_tmux_option "@autoreload_revamped_flash" "0")" == "1" ]] && _flash "${msg}"
  [[ "$(get_tmux_option "@autoreload_revamped_notify" "0")" == "1" ]] && _notify "tmux-autoreload" "${msg}"
  return 0
}

# ar_record_failure -> bump the consecutive-failure counter that drives backoff.
ar_record_failure() {
  local n
  n="$(get_tmux_option "@autoreload_revamped_fail_count" "0")"
  [[ "${n}" =~ ^[0-9]+$ ]] || n=0
  set_tmux_option "@autoreload_revamped_fail_count" "$(( n + 1 ))"
}

# ar_paused -> 0 when the user has paused autoreload.
ar_paused() {
  [[ "$(get_tmux_option "@autoreload_revamped_paused" "0")" == "1" ]]
}

# ar_content_unchanged -> 0 when the watched content matches the stored hash (an
# mtime-only no-op save). Stores the fresh hash whenever content differs.
ar_content_unchanged() {
  local prev cur
  prev="$(get_tmux_option "@autoreload_revamped_hash" "")"
  cur="$(ar_content_hash)"
  if [[ -n "${prev}" && "${prev}" == "${cur}" ]]; then
    return 0
  fi
  set_tmux_option "@autoreload_revamped_hash" "${cur}"
  return 1
}

# ar_should_defer -> 0 when a reload should wait because a client is mid-action.
ar_should_defer() {
  [[ "$(get_tmux_option "@autoreload_revamped_defer" "1")" == "1" ]] || return 1
  _client_busy
}

# ar_reload -> the manual reload command: source every entrypoint and announce.
ar_reload() {
  local list
  list="$(ar_entrypoints)"
  ar_source_all "${list}"
  ar_announce "${list}"
}

# ar_event -> one change check. Reloads only when a watched file's content really
# changed, the content is not a no-op duplicate, and no client is mid-action.
ar_event() {
  if ar_paused; then return 0; fi
  local old new changed
  old="$(get_tmux_option "@autoreload_revamped_snapshot" "")"
  new="$(ar_snapshot)"
  changed="$(autoreload_diff_files "${old}" "${new}")"
  if [[ -z "${changed}" ]]; then return 0; fi
  if ar_content_unchanged; then
    set_tmux_option "@autoreload_revamped_snapshot" "${new}"
    return 0
  fi
  if ar_should_defer; then return 0; fi
  if ar_apply "${changed}"; then
    set_tmux_option "@autoreload_revamped_fail_count" "0"
    set_tmux_option "@autoreload_revamped_snapshot" "$(ar_snapshot)"
    ar_announce "${changed}"
  else
    ar_record_failure
  fi
  return 0
}

# --- watch backends. Each loop sits behind _poll_continue so a test breaks it --

_poll_interval() {
  local i
  i=$(get_tmux_option "@autoreload_revamped_interval" "2")
  [[ "${i}" =~ ^[0-9]+$ ]] && (( i > 0 )) || i=2
  echo "${i}"
}

_poll_sleep_interval() {
  local base fails max
  base="$(_poll_interval)"
  fails="$(get_tmux_option "@autoreload_revamped_fail_count" "0")"
  max="$(get_tmux_option "@autoreload_revamped_backoff_max" "30")"
  autoreload_backoff_delay "${base}" "${fails}" "${max}"
}

_watch_poll() {
  while _poll_continue; do
    _sleep "$(_poll_sleep_interval)"
    ar_event
  done
}

_watch_fswatch() {
  local targets
  while _poll_continue; do
    targets="$(ar_event_targets | tr '\n' ' ')"
    # shellcheck disable=SC2086 # word splitting the target list is intended
    if _exec_fswatch ${targets}; then ar_event; else break; fi
  done
}

_watch_inotify() {
  local targets
  while _poll_continue; do
    targets="$(ar_event_targets | tr '\n' ' ')"
    # shellcheck disable=SC2086 # word splitting the target list is intended
    if _exec_inotify ${targets}; then ar_event; else break; fi
  done
}

_watch_entr() {
  local targets
  while _poll_continue; do
    targets="$(ar_event_targets | tr '\n' ' ')"
    # shellcheck disable=SC2086 # word splitting the target list is intended
    if _exec_entr ${targets}; then ar_event; else break; fi
  done
}

ar_watch() {
  set_tmux_option "@autoreload_revamped_fail_count" "0"
  set_tmux_option "@autoreload_revamped_snapshot" "$(ar_snapshot)"
  set_tmux_option "@autoreload_revamped_hash" "$(ar_content_hash)"
  case "$(autoreload_select_watcher)" in
    fswatch)     _watch_fswatch ;;
    inotifywait) _watch_inotify ;;
    entr)        _watch_entr ;;
    *)           _watch_poll ;;
  esac
}

# --- pause / status / self-heal ---------------------------------------------

ar_pause() { set_tmux_option "@autoreload_revamped_paused" "1"; _message "autoreload paused"; }
ar_resume() { set_tmux_option "@autoreload_revamped_paused" "0"; _message "autoreload resumed"; }
ar_toggle() {
  if ar_paused; then ar_resume; else ar_pause; fi
}

ar_status() {
  local state pid
  if ar_paused; then state="paused"; else state="active"; fi
  pid="$(get_tmux_option "@autoreload_revamped_pid" "")"
  printf 'autoreload-revamped: %s; watcher pid %s; backend %s\n' \
    "${state}" "${pid:-none}" "$(autoreload_select_watcher)"
}

# ar_watcher_alive -> 0 when the tracked pid names a live watcher.
ar_watcher_alive() {
  local pid
  pid="$(get_tmux_option "@autoreload_revamped_pid" "")"
  [[ -n "${pid}" ]] || return 1
  _pid_alive "${pid}"
}

# ar_ensure -> keep exactly one live watcher per server. A healthy one is left
# alone; a dead or stale pid is cleaned up and a fresh watcher started.
ar_ensure() {
  if ar_watcher_alive; then return 0; fi
  local pid newpid
  pid="$(get_tmux_option "@autoreload_revamped_pid" "")"
  [[ -n "${pid}" ]] && _kill_pid "${pid}"
  newpid="$(_spawn_watcher)"
  set_tmux_option "@autoreload_revamped_pid" "${newpid}"
}

main() {
  case "${1:-}" in
    watch)  ar_watch ;;
    reload) ar_reload ;;
    tick)   ar_event ;;
    event)  ar_event ;;
    pause)  ar_pause ;;
    resume) ar_resume ;;
    toggle) ar_toggle ;;
    status) ar_status ;;
    ensure) ar_ensure ;;
    *)      return 0 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
