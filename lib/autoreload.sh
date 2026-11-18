#!/bin/sh

[ -n "${AUTORELOAD_REVAMPED_AUTORELOAD_LOADED:-}" ] && return 0
AUTORELOAD_REVAMPED_AUTORELOAD_LOADED=1

# shellcheck source=SCRIPTDIR/state.sh
. "${REVAMPED_LIB:?}/state.sh"
# shellcheck source=SCRIPTDIR/platform.sh
. "${REVAMPED_LIB}/platform.sh"
# shellcheck source=SCRIPTDIR/command.sh
. "${REVAMPED_LIB}/command.sh"

autoreload_revamped_format() {
  printf '%s\n' "${AUTORELOAD_REVAMPED_SETTINGS}" | awk -F '\t' -v pid="${AUTORELOAD_REVAMPED_PID}" -v paused="${AUTORELOAD_REVAMPED_PAUSED}" '{ printf "%s#{@autoreload_revamped_%s}", (NR > 1 ? "\t" : ""), $1 } END { printf "\t#{pid}\t#{%s}\t#{%s}\t#{config_files}", paused, pid }'
}

autoreload_revamped_resolve() {
  env | AUTORELOAD_REVAMPED_ROWS="${AUTORELOAD_REVAMPED_SETTINGS}" AUTORELOAD_REVAMPED_LIVE="$1" awk '
    BEGIN {
      count = split(ENVIRON["AUTORELOAD_REVAMPED_ROWS"], rows, "\n")
      split(ENVIRON["AUTORELOAD_REVAMPED_LIVE"], live, "\t")
      for (i = 1; i <= count; i++) {
        split(rows[i], field, "\t")
        name[i] = field[1]
        value[i] = (live[i] != "") ? live[i] : field[2]
        want["AUTORELOAD_REVAMPED_" toupper(field[1])] = i
      }
    }
    {
      at = index($0, "=")
      key = substr($0, 1, at - 1)
      if (key in want) { value[want[key]] = substr($0, at + 1) }
    }
    END {
      for (i = 1; i <= count; i++) { print name[i] "\t" value[i] }
      print "server\t" live[count + 1]
      print "paused\t" live[count + 2]
      print "watcher\t" live[count + 3]
      print "config\t" live[count + 4]
    }
  '
}

autoreload_revamped_load() {
  autoreload_revamped_load_format=$(autoreload_revamped_format)
  autoreload_revamped_load_live=$(tmux display-message -p "${autoreload_revamped_load_format}" 2>/dev/null) || autoreload_revamped_load_live=""
  autoreload_revamped_load_values=$(autoreload_revamped_resolve "${autoreload_revamped_load_live}")
  while IFS='	' read -r autoreload_revamped_load_name autoreload_revamped_load_value; do
    IFS= read -r "AUTORELOAD_REVAMPED_S_${autoreload_revamped_load_name}" <<EOF
${autoreload_revamped_load_value}
EOF
  done <<EOF
${autoreload_revamped_load_values}
EOF
}

autoreload_revamped_with() {
  autoreload_revamped_with_list="$1"
  shift
  autoreload_revamped_with_ifs="${IFS}"
  set -f
  IFS='
'
  # shellcheck disable=SC2086
  set -- "$@" ${autoreload_revamped_with_list}
  IFS="${autoreload_revamped_with_ifs}"
  set +f
  "$@"
}

autoreload_revamped_split() {
  printf '%s\n' "$1" | awk -v between="${2:-[, \t]+}" '
    {
      count = split($0, part, between)
      for (i = 1; i <= count; i++) {
        path = part[i]
        if (path == "" || seen[path]++) { continue }
        if (path == "~") { path = ENVIRON["HOME"] } else if (path ~ /^~\//) { path = ENVIRON["HOME"] substr(path, 2) }
        print path
      }
    }
  '
}

autoreload_revamped_existing() {
  while IFS= read -r autoreload_revamped_existing_path; do
    [ ! -e "${autoreload_revamped_existing_path}" ] || printf '%s\n' "${autoreload_revamped_existing_path}"
  done
}

autoreload_revamped_children() {
  awk -v quote="${AUTORELOAD_REVAMPED_QUOTE}" '
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      count = split(line, word, /[ \t]+/)
      if ((word[1] != "source" && word[1] != "source-file") || count < 2) { next }
      path = word[count]
      first = substr(path, 1, 1)
      if (first == "\"" || first == quote) { path = substr(path, 2) }
      last = substr(path, length(path), 1)
      if (last == "\"" || last == quote) { path = substr(path, 1, length(path) - 1) }
      if (path == "" || path ~ /^-/) { next }
      folder = FILENAME
      if (!sub(/\/[^\/]*$/, "", folder)) { folder = "." }
      if (path == "~") { path = ENVIRON["HOME"] } else if (path ~ /^~\//) { path = ENVIRON["HOME"] substr(path, 2) } else if (path !~ /^\//) { path = folder "/" path }
      print path
    }
  ' "$@"
}

autoreload_revamped_fresh() {
  printf '%s\n' "$2" | AUTORELOAD_REVAMPED_KNOWN="$1" awk '
    BEGIN { count = split(ENVIRON["AUTORELOAD_REVAMPED_KNOWN"], known, "\n"); for (i = 1; i <= count; i++) { seen[known[i]] = 1 } }
    NF && !seen[$0]++
  '
}

autoreload_revamped_discover() {
  autoreload_revamped_discover_list=$(printf '%s\n' "$1" | autoreload_revamped_existing)
  autoreload_revamped_discover_front="${autoreload_revamped_discover_list}"
  autoreload_revamped_discover_depth=0
  while [ "${autoreload_revamped_discover_depth}" -lt "${AUTORELOAD_REVAMPED_DEPTH}" ] && [ -n "${autoreload_revamped_discover_front}" ]; do
    autoreload_revamped_discover_depth=$((autoreload_revamped_discover_depth + 1))
    autoreload_revamped_discover_kids=$(autoreload_revamped_with "${autoreload_revamped_discover_front}" autoreload_revamped_children | autoreload_revamped_existing)
    autoreload_revamped_discover_front=$(autoreload_revamped_fresh "${autoreload_revamped_discover_list}" "${autoreload_revamped_discover_kids}")
    [ -z "${autoreload_revamped_discover_front}" ] || autoreload_revamped_discover_list="${autoreload_revamped_discover_list}
${autoreload_revamped_discover_front}"
  done
  printf '%s\n' "${autoreload_revamped_discover_list}"
}

autoreload_revamped_base() {
  if [ -n "${AUTORELOAD_REVAMPED_S_files}" ]; then
    autoreload_revamped_split "${AUTORELOAD_REVAMPED_S_files}"
    return 0
  fi
  autoreload_revamped_split "${AUTORELOAD_REVAMPED_S_config}" ,
}

autoreload_revamped_files() {
  autoreload_revamped_files_base=$(autoreload_revamped_base)
  if [ "${AUTORELOAD_REVAMPED_S_discover}" = 1 ]; then
    autoreload_revamped_discover "${autoreload_revamped_files_base}"
    return 0
  fi
  printf '%s\n' "${autoreload_revamped_files_base}" | autoreload_revamped_existing
}

autoreload_revamped_entrypoints() {
  if [ -n "${AUTORELOAD_REVAMPED_S_entrypoints}" ]; then
    autoreload_revamped_split "${AUTORELOAD_REVAMPED_S_entrypoints}"
    return 0
  fi
  autoreload_revamped_split "${AUTORELOAD_REVAMPED_S_config}" , | autoreload_revamped_existing
}

autoreload_revamped_snapshot() {
  [ -n "$1" ] || return 0
  autoreload_revamped_with "$1" cksum 2>/dev/null || :
}

autoreload_revamped_rows() {
  printf '%s\n' "$3" | AUTORELOAD_REVAMPED_BEFORE="$2" awk -v mode="$1" '
    function name(row) { sub(/^[^ ]* [^ ]* /, "", row); return row }
    BEGIN {
      count = split(ENVIRON["AUTORELOAD_REVAMPED_BEFORE"], before, "\n")
      for (i = 1; i <= count; i++) { if (before[i] != "") { was[name(before[i])] = before[i] } }
    }
    NF && mode == "changed" { path = name($0); if (!(path in was) || was[path] != $0) { print path } }
    NF && mode == "loaded" { path = name($0); print (path in was) ? was[path] : $0 }
  '
}

autoreload_revamped_changed() {
  autoreload_revamped_rows changed "$1" "$2"
}

autoreload_revamped_folders() {
  awk '{ folder = $0; if (!sub(/\/[^\/]*$/, "", folder)) { next } if (folder == "") { folder = "/" } if (!seen[folder]++) { print folder } }'
}

autoreload_revamped_targets() {
  printf '%s\n' "${AUTORELOAD_REVAMPED_TRACKED}"
  [ "${AUTORELOAD_REVAMPED_S_atomic}" != 1 ] || printf '%s\n' "${AUTORELOAD_REVAMPED_TRACKED}" | autoreload_revamped_folders
}

autoreload_revamped_affected() {
  autoreload_revamped_affected_all=$(autoreload_revamped_entrypoints)
  autoreload_revamped_affected_hit=""
  while IFS= read -r autoreload_revamped_affected_entry; do
    [ -n "${autoreload_revamped_affected_entry}" ] || continue
    autoreload_revamped_affected_tree=$(autoreload_revamped_discover "${autoreload_revamped_affected_entry}")
    autoreload_revamped_affected_new=$(autoreload_revamped_fresh "${autoreload_revamped_affected_tree}" "$1")
    [ "${autoreload_revamped_affected_new}" != "$1" ] || continue
    autoreload_revamped_affected_hit="${autoreload_revamped_affected_hit}${autoreload_revamped_affected_entry}
"
  done <<EOF
${autoreload_revamped_affected_all}
EOF
  if [ -n "${autoreload_revamped_affected_hit}" ]; then
    printf '%s' "${autoreload_revamped_affected_hit}"
    return 0
  fi
  printf '%s\n' "${autoreload_revamped_affected_all}"
}

autoreload_revamped_backup_dir() {
  if [ -n "${AUTORELOAD_REVAMPED_S_backup_dir}" ]; then
    autoreload_revamped_split "${AUTORELOAD_REVAMPED_S_backup_dir}" '\n'
    return 0
  fi
  printf '%s\n' "${HOME}/.tmux/autoreload-revamped/backup"
}

autoreload_revamped_backup_of() {
  autoreload_revamped_backup_of_name=$(printf '%s' "$2" | tr -c 'A-Za-z0-9._-' '_')
  printf '%s/%s\n' "$1" "${autoreload_revamped_backup_of_name}"
}

autoreload_revamped_save() {
  autoreload_revamped_save_dir=$(autoreload_revamped_backup_dir)
  mkdir -p "${autoreload_revamped_save_dir}" 2>/dev/null || return 0
  while IFS= read -r autoreload_revamped_save_file; do
    [ -f "${autoreload_revamped_save_file}" ] || continue
    autoreload_revamped_save_copy=$(autoreload_revamped_backup_of "${autoreload_revamped_save_dir}" "${autoreload_revamped_save_file}")
    cat "${autoreload_revamped_save_file}" >"${autoreload_revamped_save_copy}.tmp" 2>/dev/null && mv -f "${autoreload_revamped_save_copy}.tmp" "${autoreload_revamped_save_copy}"
  done <<EOF
$1
EOF
}

autoreload_revamped_say() {
  autoreload_revamped_say_text=$(printf '%s\n' "$1" | sed -e 's/#/##/g' -e 1q)
  tmux display-message "${2:-}${autoreload_revamped_say_text}${2:+#[default]}" >/dev/null 2>&1 || :
}

autoreload_revamped_fail() {
  autoreload_revamped_fail_text="tmux config error in ${1##*/}"
  [ -z "$2" ] || autoreload_revamped_fail_text="${autoreload_revamped_fail_text}: $2"
  autoreload_revamped_say "${autoreload_revamped_fail_text}"
  [ "${AUTORELOAD_REVAMPED_S_validate}" = 1 ] || return 0
  autoreload_revamped_fail_dir=$(autoreload_revamped_backup_dir)
  autoreload_revamped_fail_copy=$(autoreload_revamped_backup_of "${autoreload_revamped_fail_dir}" "$1")
  [ ! -f "${autoreload_revamped_fail_copy}" ] || tmux source-file "${autoreload_revamped_fail_copy}" >/dev/null 2>&1 || :
}

autoreload_revamped_source() {
  while IFS= read -r autoreload_revamped_source_file; do
    [ -n "${autoreload_revamped_source_file}" ] || continue
    autoreload_revamped_source_error=$(tmux source-file "${autoreload_revamped_source_file}" 2>&1 >/dev/null) && [ -z "${autoreload_revamped_source_error}" ] && continue
    autoreload_revamped_fail "${autoreload_revamped_source_file}" "${autoreload_revamped_source_error}"
    return 1
  done <<EOF
$1
EOF
  [ "${AUTORELOAD_REVAMPED_S_validate}" != 1 ] || autoreload_revamped_save "$1"
}

autoreload_revamped_announce() {
  autoreload_revamped_announce_text=$(printf '%s\n' "$1" | awk 'NF { count++; if (count == 1) { name = $0; sub(/.*\//, "", name) } } END { if (count > 1) { printf "tmux config reloaded (%s +%d more)", name, count - 1 } else { printf "tmux config reloaded (%s)", name } }')
  [ "${AUTORELOAD_REVAMPED_S_quiet}" = 1 ] || autoreload_revamped_say "${autoreload_revamped_announce_text}"
  [ "${AUTORELOAD_REVAMPED_S_flash}" != 1 ] || autoreload_revamped_say "${autoreload_revamped_announce_text}" '#[reverse]'
  [ "${AUTORELOAD_REVAMPED_S_notify}" = 1 ] || return 0
  # shellcheck source=SCRIPTDIR/notify.sh
  . "${REVAMPED_LIB}/notify.sh"
  revamped_notify_send "${AUTORELOAD_REVAMPED_TITLE}" "${autoreload_revamped_announce_text}"
}

autoreload_revamped_busy() {
  autoreload_revamped_busy_modes=$(tmux list-panes -a -F '#{pane_in_mode}' 2>/dev/null) || autoreload_revamped_busy_modes=""
  case "${autoreload_revamped_busy_modes}" in
  *1*) return 0 ;;
  *) return 1 ;;
  esac
}

autoreload_revamped_track() {
  AUTORELOAD_REVAMPED_TRACKED=$(autoreload_revamped_files)
  AUTORELOAD_REVAMPED_SNAPSHOT=$(autoreload_revamped_snapshot "${AUTORELOAD_REVAMPED_TRACKED}")
}

autoreload_revamped_settle() {
  AUTORELOAD_REVAMPED_TRACKED=$(autoreload_revamped_files)
  autoreload_revamped_settle_now=$(autoreload_revamped_snapshot "${AUTORELOAD_REVAMPED_TRACKED}")
  AUTORELOAD_REVAMPED_SNAPSHOT=$(autoreload_revamped_rows loaded "$1" "${autoreload_revamped_settle_now}")
}

autoreload_revamped_reload_for() {
  if [ "${AUTORELOAD_REVAMPED_S_selective}" = 1 ]; then
    autoreload_revamped_reload_for_list=$(autoreload_revamped_affected "$1")
  else
    autoreload_revamped_reload_for_list=$(autoreload_revamped_entrypoints)
  fi
  autoreload_revamped_source "${autoreload_revamped_reload_for_list}" || return 0
  autoreload_revamped_announce "$1"
}

autoreload_revamped_event() {
  AUTORELOAD_REVAMPED_HELD=0
  if [ "${AUTORELOAD_REVAMPED_S_paused}" = 1 ]; then
    AUTORELOAD_REVAMPED_HELD=1
    return 0
  fi
  autoreload_revamped_event_now=$(autoreload_revamped_snapshot "${AUTORELOAD_REVAMPED_TRACKED}")
  [ "${autoreload_revamped_event_now}" != "${AUTORELOAD_REVAMPED_SNAPSHOT}" ] || return 0
  autoreload_revamped_event_changed=$(autoreload_revamped_changed "${AUTORELOAD_REVAMPED_SNAPSHOT}" "${autoreload_revamped_event_now}")
  if [ -n "${autoreload_revamped_event_changed}" ] && [ "${AUTORELOAD_REVAMPED_S_defer}" = 1 ] && autoreload_revamped_busy; then
    AUTORELOAD_REVAMPED_HELD=1
    return 0
  fi
  [ -z "${autoreload_revamped_event_changed}" ] || autoreload_revamped_reload_for "${autoreload_revamped_event_changed}"
  autoreload_revamped_settle "${autoreload_revamped_event_now}"
}

autoreload_revamped_interval() {
  case "${AUTORELOAD_REVAMPED_S_interval}" in
  "" | *[!0-9]* | 0) printf '%s\n' "${AUTORELOAD_REVAMPED_DEFAULT_INTERVAL}" ;;
  *) printf '%s\n' "${AUTORELOAD_REVAMPED_S_interval}" ;;
  esac
}

autoreload_revamped_backend() {
  for autoreload_revamped_backend_tool in fswatch inotifywait entr; do
    if revamped_has_command "${autoreload_revamped_backend_tool}"; then
      printf '%s\n' "${autoreload_revamped_backend_tool}"
      return 0
    fi
  done
  printf 'poll\n'
}

autoreload_revamped_wait_fswatch() {
  exec fswatch -1 "$@" >/dev/null 2>&1
}

autoreload_revamped_wait_inotifywait() {
  exec inotifywait -q -e modify,move,create,delete,close_write "$@" >/dev/null 2>&1
}

autoreload_revamped_wait_entr() {
  autoreload_revamped_wait_entr_list=$(printf '%s\n' "$@")
  exec entr -d -n -p -z true >/dev/null 2>&1 <<EOF
${autoreload_revamped_wait_entr_list}
EOF
}

autoreload_revamped_pause() {
  autoreload_revamped_pause_seconds=$(autoreload_revamped_interval)
  sleep "${autoreload_revamped_pause_seconds}"
}

autoreload_revamped_guard() {
  while kill -0 "$1" 2>/dev/null && kill -0 "$2" 2>/dev/null; do
    sleep "$3"
    autoreload_revamped_guard_now=$(autoreload_revamped_snapshot "${AUTORELOAD_REVAMPED_TRACKED}")
    [ "${autoreload_revamped_guard_now}" = "${AUTORELOAD_REVAMPED_SNAPSHOT}" ] || break
  done
  kill "$2" 2>/dev/null || :
}

autoreload_revamped_end() {
  [ -n "$1" ] || return 0
  kill "$1" 2>/dev/null || :
  wait "$1" 2>/dev/null || :
}

autoreload_revamped_stop() {
  autoreload_revamped_end "${AUTORELOAD_REVAMPED_GUARD}"
  autoreload_revamped_end "${AUTORELOAD_REVAMPED_TOOL}"
  AUTORELOAD_REVAMPED_GUARD="" AUTORELOAD_REVAMPED_TOOL=""
}

autoreload_revamped_block() {
  autoreload_revamped_with "$2" "autoreload_revamped_wait_$1" </dev/null &
  AUTORELOAD_REVAMPED_TOOL=$!
  autoreload_revamped_block_now=$(autoreload_revamped_snapshot "${AUTORELOAD_REVAMPED_TRACKED}")
  if [ "${autoreload_revamped_block_now}" != "${AUTORELOAD_REVAMPED_SNAPSHOT}" ]; then
    autoreload_revamped_stop
    return 0
  fi
  autoreload_revamped_guard "${AUTORELOAD_REVAMPED_SERVER}" "${AUTORELOAD_REVAMPED_TOOL}" "${AUTORELOAD_REVAMPED_GUARD_SECONDS}" </dev/null >/dev/null 2>&1 &
  AUTORELOAD_REVAMPED_GUARD=$!
  autoreload_revamped_block_status=0
  wait "${AUTORELOAD_REVAMPED_TOOL}" || autoreload_revamped_block_status=$?
  autoreload_revamped_stop
  autoreload_revamped_block_now=$(autoreload_revamped_snapshot "${AUTORELOAD_REVAMPED_TRACKED}")
  [ "${autoreload_revamped_block_now}" = "${AUTORELOAD_REVAMPED_SNAPSHOT}" ] || return 0
  return "${autoreload_revamped_block_status}"
}

autoreload_revamped_wait() {
  autoreload_revamped_wait_on=$(autoreload_revamped_targets)
  if [ "$1" = poll ] || [ "${AUTORELOAD_REVAMPED_HELD}" -eq 1 ] || [ -z "${autoreload_revamped_wait_on}" ]; then
    autoreload_revamped_pause
    return 0
  fi
  autoreload_revamped_wait_status=0
  autoreload_revamped_block "$1" "${autoreload_revamped_wait_on}" || autoreload_revamped_wait_status=$?
  case "${autoreload_revamped_wait_status}" in
  0 | "${AUTORELOAD_REVAMPED_ENTR_REARM}") : ;;
  *) autoreload_revamped_pause ;;
  esac
}

autoreload_revamped_step() {
  autoreload_revamped_wait "$1"
  autoreload_revamped_load
  [ "${AUTORELOAD_REVAMPED_S_server}" = "${AUTORELOAD_REVAMPED_SERVER}" ] || return 1
  autoreload_revamped_event
}

autoreload_revamped_watch() {
  autoreload_revamped_load
  AUTORELOAD_REVAMPED_SERVER="${AUTORELOAD_REVAMPED_S_server}"
  [ -n "${AUTORELOAD_REVAMPED_SERVER}" ] || return 0
  autoreload_revamped_track
  if [ "${AUTORELOAD_REVAMPED_S_validate}" = 1 ]; then
    autoreload_revamped_watch_entries=$(autoreload_revamped_entrypoints)
    autoreload_revamped_save "${autoreload_revamped_watch_entries}"
  fi
  autoreload_revamped_watch_backend=$(autoreload_revamped_backend)
  trap 'autoreload_revamped_stop; exit 0' TERM INT HUP
  while autoreload_revamped_step "${autoreload_revamped_watch_backend}"; do
    :
  done
}

autoreload_revamped_running() {
  [ -n "${AUTORELOAD_REVAMPED_S_watcher}" ] || return 1
  kill -0 "${AUTORELOAD_REVAMPED_S_watcher}" 2>/dev/null
}

autoreload_revamped_apply() {
  autoreload_revamped_load
  ! autoreload_revamped_running || return 0
  "${REVAMPED_LIB%/lib}/bin/autoreload-revamped" watch </dev/null >/dev/null 2>&1 &
  tmux set-option -gq "${AUTORELOAD_REVAMPED_PID}" "$!"
}

autoreload_revamped_reload() {
  autoreload_revamped_load
  autoreload_revamped_reload_list=$(autoreload_revamped_entrypoints)
  autoreload_revamped_source "${autoreload_revamped_reload_list}" || return 1
  autoreload_revamped_announce "${autoreload_revamped_reload_list}"
}

autoreload_revamped_set_paused() {
  tmux set-option -gq "${AUTORELOAD_REVAMPED_PAUSED}" "$1"
  autoreload_revamped_say "$2"
}

autoreload_revamped_toggle() {
  autoreload_revamped_load
  if [ "${AUTORELOAD_REVAMPED_S_paused}" = 1 ]; then
    autoreload_revamped_set_paused 0 "autoreload resumed"
    return 0
  fi
  autoreload_revamped_set_paused 1 "autoreload paused"
}

autoreload_revamped_state() {
  autoreload_revamped_load
  autoreload_revamped_state_name=active
  [ "${AUTORELOAD_REVAMPED_S_paused}" != 1 ] || autoreload_revamped_state_name=paused
  autoreload_revamped_state_pid=none
  ! autoreload_revamped_running || autoreload_revamped_state_pid="${AUTORELOAD_REVAMPED_S_watcher}"
  autoreload_revamped_state_backend=$(autoreload_revamped_backend)
  printf '%s\t%s\t%s\n' "${autoreload_revamped_state_name}" "${autoreload_revamped_state_pid}" "${autoreload_revamped_state_backend}"
}

autoreload_revamped_setting_name() {
  autoreload_revamped_setting_name_raw=$(printf '%s\n' "${1#--}" | tr '-' '_')
  case " ${AUTORELOAD_REVAMPED_NAMES} " in
  *" ${autoreload_revamped_setting_name_raw} "*) printf '%s\n' "${autoreload_revamped_setting_name_raw}" ;;
  *) printf '\n' ;;
  esac
}
