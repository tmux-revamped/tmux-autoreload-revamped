#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

DISPATCHER="${BATS_TEST_DIRNAME}/../../../src/autoreload.sh"

setup() {
  setup_test_environment
  export AR_CACHE_DIR="${BATS_TEST_TMPDIR}/cache"
  unset _AUTORELOAD_REVAMPED_LOADED
  source "${DISPATCHER}"
  # Default seams: nothing real is watched, sourced, run, or notified.
  _config_files() { echo "main.conf"; }
  _file_mtime() { echo "100"; }
  _file_content() { echo "content:${1}"; }
  _source_file() { echo "SOURCE:${1}" >> "${BATS_TEST_TMPDIR}/src"; }
  _message() { echo "MSG:${1}" >> "${BATS_TEST_TMPDIR}/msg"; }
  _flash() { echo "FLASH:${1}" >> "${BATS_TEST_TMPDIR}/flash"; }
  _notify() { echo "NOTIFY:${2}" >> "${BATS_TEST_TMPDIR}/notify"; }
  _client_busy() { return 1; }
}

teardown() {
  cleanup_test_environment
}

# --- structure ---------------------------------------------------------------

@test "dispatcher functions are defined" {
  function_exists ar_watch
  function_exists ar_reload
  function_exists ar_event
  function_exists ar_ensure
  function_exists ar_status
}

# --- watched file set --------------------------------------------------------

@test "ar_base_files uses the custom list with tilde expansion" {
  _config_files() { echo "/opt/etc/tmux.conf"; }
  set_tmux_option "@autoreload_revamped_files" "~/.tmux.conf"
  run ar_base_files
  [[ "${output}" == "${HOME}/.tmux.conf" ]]
  [[ "${output}" != *"/opt/etc"* ]]
}

@test "ar_base_files falls back to every loaded config file" {
  _config_files() { echo "/a.conf /b.conf"; }
  run ar_base_files
  [[ "${output}" == *"/a.conf"* ]]
  [[ "${output}" == *"/b.conf"* ]]
}

@test "ar_discover folds in sourced files" {
  _file_content() { case "${1}" in *a.conf) echo "source b.conf" ;; *) echo "" ;; esac; }
  run ar_discover "/dir/a.conf"
  [[ "${output}" == *"/dir/a.conf"* ]]
  [[ "${output}" == *"/dir/b.conf"* ]]
}

@test "ar_discover returns only the file when discovery is off" {
  set_tmux_option "@autoreload_revamped_discover" "0"
  _file_content() { echo "source other.conf"; }
  run ar_discover "/dir/a.conf"
  [[ "${output}" == "/dir/a.conf" ]]
}

@test "ar_discover is bounded against a source cycle" {
  _file_content() { echo "source /loop.conf"; }
  run ar_discover "/loop.conf"
  [[ "${#lines[@]}" -eq 9 ]]
}

@test "ar_files folds includes and de-duplicates" {
  _file_content() { case "${1}" in *main.conf) echo "source extra.conf" ;; *) echo "" ;; esac; }
  run ar_files
  [[ "${output}" == *"main.conf"* ]]
  [[ "${output}" == *"extra.conf"* ]]
  [[ "$(printf '%s\n' "${output}" | grep -c 'main.conf')" == "1" ]]
}

@test "ar_files skips discovery when disabled" {
  set_tmux_option "@autoreload_revamped_discover" "0"
  _file_content() { echo "source extra.conf"; }
  run ar_files
  [[ "${output}" == "main.conf" ]]
}

@test "ar_event_targets adds parent directories when atomic-save handling is on" {
  _config_files() { echo "/etc/tmux/main.conf"; }
  run ar_event_targets
  [[ "${output}" == *"/etc/tmux/main.conf"* ]]
  [[ "${output}" == *"/etc/tmux"* ]]
}

@test "ar_event_targets lists only files when atomic handling is off" {
  set_tmux_option "@autoreload_revamped_atomic" "0"
  _config_files() { echo "/etc/tmux/main.conf"; }
  run ar_event_targets
  [[ "${output}" == "/etc/tmux/main.conf" ]]
}

@test "ar_snapshot pairs files with mtimes" {
  run ar_snapshot
  [[ "${output}" == "main.conf 100" ]]
}

@test "ar_content_hash changes with content and is stable for identical content" {
  local h1 h2
  h1="$(ar_content_hash)"
  h2="$(ar_content_hash)"
  [[ "${h1}" == "${h2}" ]]
  _file_content() { echo "different"; }
  [[ "$(ar_content_hash)" != "${h1}" ]]
}

# --- reload pipeline ---------------------------------------------------------

@test "ar_entrypoints defaults to the loaded config and honors the override" {
  run ar_entrypoints
  [[ "${output}" == "main.conf" ]]
  set_tmux_option "@autoreload_revamped_entrypoints" "x.conf,y.conf"
  run ar_entrypoints
  [[ "${output}" == *"x.conf"* ]]
  [[ "${output}" == *"y.conf"* ]]
}

@test "ar_closure_contains matches a changed file inside the subtree" {
  _file_content() { case "${1}" in *root.conf) echo "source child.conf" ;; *) echo "" ;; esac; }
  run ar_closure_contains "/d/root.conf" "/d/child.conf"
  [[ "${status}" -eq 0 ]]
  run ar_closure_contains "/d/root.conf" "/other.conf"
  [[ "${status}" -eq 1 ]]
}

@test "ar_affected_entrypoints selects the owning subtree and falls back to all" {
  set_tmux_option "@autoreload_revamped_entrypoints" "/d/root.conf /e/other.conf"
  _file_content() { echo ""; }
  run ar_affected_entrypoints "/d/root.conf"
  [[ "${output}" == "/d/root.conf" ]]
  run ar_affected_entrypoints "/nomatch.conf"
  [[ "${output}" == *"/d/root.conf"* ]]
  [[ "${output}" == *"/e/other.conf"* ]]
}

@test "ar_surface_error names the file with and without captured text" {
  run ar_surface_error "/d/main.conf" "line 5: unknown command"
  run cat "${BATS_TEST_TMPDIR}/msg"
  [[ "${output}" == *"main.conf"* ]]
  [[ "${output}" == *"line 5"* ]]
  rm -f "${BATS_TEST_TMPDIR}/msg"
  run ar_surface_error "/d/main.conf" ""
  run cat "${BATS_TEST_TMPDIR}/msg"
  [[ "${output}" == *"error in main.conf"* ]]
}

@test "_save_backup and _restore_backup round-trip the last-good copy" {
  _save_backup "/x.conf"
  [[ -f "$(_backup_path /x.conf)" ]]
  run _restore_backup "/x.conf"
  [[ "$(cat "${BATS_TEST_TMPDIR}/src")" == *"SOURCE:"* ]]
}

@test "_restore_backup is a noop when no backup exists" {
  run _restore_backup "/missing.conf"
  [[ "${status}" -eq 0 ]]
  [[ ! -f "${BATS_TEST_TMPDIR}/src" ]]
}

@test "ar_source_all sources every file and saves backups on success" {
  run ar_source_all "$(printf '%s\n' /a.conf /b.conf)"
  [[ "${status}" -eq 0 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/src")" == *"SOURCE:/a.conf"* ]]
  [[ -f "$(_backup_path /a.conf)" ]]
}

@test "ar_source_all surfaces the error and rolls back on failure" {
  _save_backup "/x.conf"
  _source_file() { echo "syntax error at line 5"; return 1; }
  run ar_source_all "/x.conf"
  [[ "${status}" -eq 1 ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/msg")" == *"error"* ]]
}

@test "ar_source_all skips rollback and backups when validation is off" {
  set_tmux_option "@autoreload_revamped_validate" "0"
  run ar_source_all "/a.conf"
  [[ "${status}" -eq 0 ]]
  [[ ! -f "$(_backup_path /a.conf)" ]]
  _source_file() { echo "err"; return 1; }
  run ar_source_all "/a.conf"
  [[ "${status}" -eq 1 ]]
}

@test "ar_apply reloads all entrypoints by default and the subtree when selective" {
  run ar_apply "main.conf"
  [[ "$(cat "${BATS_TEST_TMPDIR}/src")" == *"SOURCE:main.conf"* ]]
  rm -f "${BATS_TEST_TMPDIR}/src"
  set_tmux_option "@autoreload_revamped_selective" "1"
  set_tmux_option "@autoreload_revamped_entrypoints" "/d/root.conf /e/other.conf"
  _file_content() { echo ""; }
  run ar_apply "/d/root.conf"
  [[ "$(cat "${BATS_TEST_TMPDIR}/src")" == *"SOURCE:/d/root.conf"* ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/src")" != *"other.conf"* ]]
}

@test "ar_announce names the changed file" {
  run ar_announce "/d/main.conf"
  [[ "$(cat "${BATS_TEST_TMPDIR}/msg")" == *"reloaded (main.conf)"* ]]
}

@test "ar_announce summarizes multiple changed files" {
  run ar_announce "$(printf '%s\n' /a.conf /b.conf)"
  [[ "$(cat "${BATS_TEST_TMPDIR}/msg")" == *"+1 more"* ]]
}

@test "ar_announce stays silent when quiet" {
  set_tmux_option "@autoreload_revamped_quiet" "1"
  run ar_announce "/d/main.conf"
  [[ ! -f "${BATS_TEST_TMPDIR}/msg" ]]
}

@test "ar_announce flashes and notifies when enabled" {
  set_tmux_option "@autoreload_revamped_flash" "1"
  set_tmux_option "@autoreload_revamped_notify" "1"
  run ar_announce "/d/main.conf"
  [[ "$(cat "${BATS_TEST_TMPDIR}/flash")" == *"reloaded"* ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/notify")" == *"reloaded"* ]]
}

@test "ar_record_failure increments and resets a non-numeric counter" {
  ar_record_failure
  [[ "$(get_tmux_option "@autoreload_revamped_fail_count")" == "1" ]]
  set_tmux_option "@autoreload_revamped_fail_count" "junk"
  ar_record_failure
  [[ "$(get_tmux_option "@autoreload_revamped_fail_count")" == "1" ]]
}

@test "ar_paused reflects the option" {
  run ar_paused
  [[ "${status}" -eq 1 ]]
  set_tmux_option "@autoreload_revamped_paused" "1"
  run ar_paused
  [[ "${status}" -eq 0 ]]
}

@test "ar_content_unchanged dedupes a no-op save and stores fresh hashes" {
  run ar_content_unchanged
  [[ "${status}" -eq 1 ]]
  run ar_content_unchanged
  [[ "${status}" -eq 0 ]]
  _file_content() { echo "changed"; }
  run ar_content_unchanged
  [[ "${status}" -eq 1 ]]
}

@test "ar_should_defer waits only when defer is on and a client is busy" {
  set_tmux_option "@autoreload_revamped_defer" "0"
  run ar_should_defer
  [[ "${status}" -eq 1 ]]
  set_tmux_option "@autoreload_revamped_defer" "1"
  _client_busy() { return 1; }
  run ar_should_defer
  [[ "${status}" -eq 1 ]]
  _client_busy() { return 0; }
  run ar_should_defer
  [[ "${status}" -eq 0 ]]
}

@test "ar_reload sources entrypoints and announces" {
  run ar_reload
  [[ "$(cat "${BATS_TEST_TMPDIR}/src")" == *"SOURCE:main.conf"* ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/msg")" == *"reloaded"* ]]
}

# --- ar_event branches -------------------------------------------------------

@test "ar_event does nothing while paused" {
  set_tmux_option "@autoreload_revamped_paused" "1"
  run ar_event
  [[ ! -f "${BATS_TEST_TMPDIR}/src" ]]
}

@test "ar_event does nothing when no watched file changed" {
  set_tmux_option "@autoreload_revamped_snapshot" "main.conf 100"
  run ar_event
  [[ ! -f "${BATS_TEST_TMPDIR}/src" ]]
}

@test "ar_event skips a no-op save where only the mtime moved" {
  set_tmux_option "@autoreload_revamped_snapshot" "main.conf 99"
  set_tmux_option "@autoreload_revamped_hash" "$(ar_content_hash)"
  run ar_event
  [[ ! -f "${BATS_TEST_TMPDIR}/src" ]]
  [[ "$(get_tmux_option "@autoreload_revamped_snapshot")" == "main.conf 100" ]]
}

@test "ar_event defers while a client is mid-action" {
  set_tmux_option "@autoreload_revamped_snapshot" "main.conf 99"
  _client_busy() { return 0; }
  run ar_event
  [[ ! -f "${BATS_TEST_TMPDIR}/src" ]]
}

@test "ar_event reloads, resets failures, and announces on a real change" {
  set_tmux_option "@autoreload_revamped_snapshot" "main.conf 99"
  set_tmux_option "@autoreload_revamped_fail_count" "3"
  run ar_event
  [[ "$(cat "${BATS_TEST_TMPDIR}/src")" == *"SOURCE:main.conf"* ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/msg")" == *"reloaded"* ]]
  [[ "$(get_tmux_option "@autoreload_revamped_fail_count")" == "0" ]]
}

@test "ar_event records a failure when the reload errors" {
  set_tmux_option "@autoreload_revamped_snapshot" "main.conf 99"
  _source_file() { echo "boom"; return 1; }
  run ar_event
  [[ "$(get_tmux_option "@autoreload_revamped_fail_count")" == "1" ]]
}

# --- watch backends ----------------------------------------------------------

@test "_poll_interval defaults, accepts a valid value, and rejects junk" {
  [[ "$(_poll_interval)" == "2" ]]
  set_tmux_option "@autoreload_revamped_interval" "5"
  [[ "$(_poll_interval)" == "5" ]]
  set_tmux_option "@autoreload_revamped_interval" "junk"
  [[ "$(_poll_interval)" == "2" ]]
}

@test "_poll_sleep_interval applies backoff from the failure count" {
  set_tmux_option "@autoreload_revamped_fail_count" "2"
  [[ "$(_poll_sleep_interval)" == "4" ]]
}

@test "_watch_poll runs one iteration then stops" {
  printf '0' > "${BATS_TEST_TMPDIR}/cnt"
  _poll_continue() {
    [[ "$(cat "${BATS_TEST_TMPDIR}/cnt")" == "0" ]] && { printf '1' > "${BATS_TEST_TMPDIR}/cnt"; return 0; }
    return 1
  }
  _sleep() { :; }
  ar_event() { echo "EVENT" > "${BATS_TEST_TMPDIR}/ev"; }
  run _watch_poll
  [[ "$(cat "${BATS_TEST_TMPDIR}/ev")" == "EVENT" ]]
}

@test "_watch_fswatch reloads on an event then stops, no real watcher" {
  printf '0' > "${BATS_TEST_TMPDIR}/cnt"
  _poll_continue() {
    [[ "$(cat "${BATS_TEST_TMPDIR}/cnt")" == "0" ]] && { printf '1' > "${BATS_TEST_TMPDIR}/cnt"; return 0; }
    return 1
  }
  _exec_fswatch() { return 0; }
  ar_event() { echo "E" > "${BATS_TEST_TMPDIR}/ev"; }
  run _watch_fswatch
  [[ "$(cat "${BATS_TEST_TMPDIR}/ev")" == "E" ]]
}

@test "_watch_fswatch breaks when the watcher exits" {
  _poll_continue() { return 0; }
  _exec_fswatch() { return 1; }
  ar_event() { echo "E" > "${BATS_TEST_TMPDIR}/ev"; }
  run _watch_fswatch
  [[ ! -f "${BATS_TEST_TMPDIR}/ev" ]]
}

@test "_watch_inotify reloads on an event then stops, no real watcher" {
  printf '0' > "${BATS_TEST_TMPDIR}/cnt"
  _poll_continue() {
    [[ "$(cat "${BATS_TEST_TMPDIR}/cnt")" == "0" ]] && { printf '1' > "${BATS_TEST_TMPDIR}/cnt"; return 0; }
    return 1
  }
  _exec_inotify() { return 0; }
  ar_event() { echo "E" > "${BATS_TEST_TMPDIR}/ev"; }
  run _watch_inotify
  [[ "$(cat "${BATS_TEST_TMPDIR}/ev")" == "E" ]]
}

@test "_watch_inotify breaks when the watcher exits" {
  _poll_continue() { return 0; }
  _exec_inotify() { return 1; }
  ar_event() { echo "E" > "${BATS_TEST_TMPDIR}/ev"; }
  run _watch_inotify
  [[ ! -f "${BATS_TEST_TMPDIR}/ev" ]]
}

@test "_watch_entr reloads on an event then stops, no real watcher" {
  printf '0' > "${BATS_TEST_TMPDIR}/cnt"
  _poll_continue() {
    [[ "$(cat "${BATS_TEST_TMPDIR}/cnt")" == "0" ]] && { printf '1' > "${BATS_TEST_TMPDIR}/cnt"; return 0; }
    return 1
  }
  _exec_entr() { return 0; }
  ar_event() { echo "E" > "${BATS_TEST_TMPDIR}/ev"; }
  run _watch_entr
  [[ "$(cat "${BATS_TEST_TMPDIR}/ev")" == "E" ]]
}

@test "_watch_entr breaks when the watcher exits" {
  _poll_continue() { return 0; }
  _exec_entr() { return 1; }
  ar_event() { echo "E" > "${BATS_TEST_TMPDIR}/ev"; }
  run _watch_entr
  [[ ! -f "${BATS_TEST_TMPDIR}/ev" ]]
}

@test "ar_watch initializes state and routes to each backend" {
  _watch_poll() { echo "POLL" > "${BATS_TEST_TMPDIR}/w"; }
  _watch_fswatch() { echo "FS" > "${BATS_TEST_TMPDIR}/w"; }
  _watch_inotify() { echo "IN" > "${BATS_TEST_TMPDIR}/w"; }
  _watch_entr() { echo "ENTR" > "${BATS_TEST_TMPDIR}/w"; }
  autoreload_select_watcher() { echo "poll"; }
  run ar_watch
  [[ "$(cat "${BATS_TEST_TMPDIR}/w")" == "POLL" ]]
  [[ "$(get_tmux_option "@autoreload_revamped_fail_count")" == "0" ]]
  autoreload_select_watcher() { echo "fswatch"; }
  run ar_watch
  [[ "$(cat "${BATS_TEST_TMPDIR}/w")" == "FS" ]]
  autoreload_select_watcher() { echo "inotifywait"; }
  run ar_watch
  [[ "$(cat "${BATS_TEST_TMPDIR}/w")" == "IN" ]]
  autoreload_select_watcher() { echo "entr"; }
  run ar_watch
  [[ "$(cat "${BATS_TEST_TMPDIR}/w")" == "ENTR" ]]
}

# --- pause / status / self-heal ---------------------------------------------

@test "ar_pause and ar_resume flip the option and announce" {
  run ar_pause
  [[ "$(get_tmux_option "@autoreload_revamped_paused")" == "1" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/msg")" == *"paused"* ]]
  run ar_resume
  [[ "$(get_tmux_option "@autoreload_revamped_paused")" == "0" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/msg")" == *"resumed"* ]]
}

@test "ar_toggle flips both ways" {
  run ar_toggle
  [[ "$(get_tmux_option "@autoreload_revamped_paused")" == "1" ]]
  run ar_toggle
  [[ "$(get_tmux_option "@autoreload_revamped_paused")" == "0" ]]
}

@test "ar_status reports active and paused state" {
  autoreload_select_watcher() { echo "poll"; }
  run ar_status
  [[ "${output}" == *"active"* ]]
  set_tmux_option "@autoreload_revamped_paused" "1"
  set_tmux_option "@autoreload_revamped_pid" "4242"
  run ar_status
  [[ "${output}" == *"paused"* ]]
  [[ "${output}" == *"4242"* ]]
}

@test "ar_watcher_alive is false without a pid and follows the liveness probe" {
  run ar_watcher_alive
  [[ "${status}" -eq 1 ]]
  set_tmux_option "@autoreload_revamped_pid" "4242"
  _pid_alive() { return 0; }
  run ar_watcher_alive
  [[ "${status}" -eq 0 ]]
  _pid_alive() { return 1; }
  run ar_watcher_alive
  [[ "${status}" -eq 1 ]]
}

@test "ar_ensure keeps a healthy watcher" {
  set_tmux_option "@autoreload_revamped_pid" "4242"
  _pid_alive() { return 0; }
  _spawn_watcher() { echo "SPAWNED" >> "${BATS_TEST_TMPDIR}/spawn"; echo "9999"; }
  run ar_ensure
  [[ ! -f "${BATS_TEST_TMPDIR}/spawn" ]]
  [[ "$(get_tmux_option "@autoreload_revamped_pid")" == "4242" ]]
}

@test "ar_ensure replaces a dead watcher and records the new pid" {
  set_tmux_option "@autoreload_revamped_pid" "4242"
  _pid_alive() { return 1; }
  _kill_pid() { echo "KILL:${1}" >> "${BATS_TEST_TMPDIR}/kill"; }
  _spawn_watcher() { echo "9999"; }
  run ar_ensure
  [[ "$(cat "${BATS_TEST_TMPDIR}/kill")" == "KILL:4242" ]]
  [[ "$(get_tmux_option "@autoreload_revamped_pid")" == "9999" ]]
}

@test "ar_ensure starts a watcher when no pid is tracked" {
  _spawn_watcher() { echo "9999"; }
  run ar_ensure
  [[ "$(get_tmux_option "@autoreload_revamped_pid")" == "9999" ]]
}

# --- main subcommands --------------------------------------------------------

@test "main dispatches every subcommand" {
  ar_watch() { echo "watch" >> "${BATS_TEST_TMPDIR}/m"; }
  ar_reload() { echo "reload" >> "${BATS_TEST_TMPDIR}/m"; }
  ar_event() { echo "event" >> "${BATS_TEST_TMPDIR}/m"; }
  ar_pause() { echo "pause" >> "${BATS_TEST_TMPDIR}/m"; }
  ar_resume() { echo "resume" >> "${BATS_TEST_TMPDIR}/m"; }
  ar_toggle() { echo "toggle" >> "${BATS_TEST_TMPDIR}/m"; }
  ar_status() { echo "status" >> "${BATS_TEST_TMPDIR}/m"; }
  ar_ensure() { echo "ensure" >> "${BATS_TEST_TMPDIR}/m"; }
  main watch; main reload; main tick; main event; main pause
  main resume; main toggle; main status; main ensure
  run cat "${BATS_TEST_TMPDIR}/m"
  [[ "${output}" == *"watch"* ]]
  [[ "${output}" == *"reload"* ]]
  [[ "${output}" == *"event"* ]]
  [[ "${output}" == *"pause"* ]]
  [[ "${output}" == *"resume"* ]]
  [[ "${output}" == *"toggle"* ]]
  [[ "${output}" == *"status"* ]]
  [[ "${output}" == *"ensure"* ]]
}

@test "main with no subcommand or an unknown one produces no output" {
  run main
  [[ -z "${output}" ]]
  run main bogus
  [[ -z "${output}" ]]
}

# --- seams (mocked; never a real watcher, source, or notification) ----------

@test "_tmux forwards to tmux" {
  run _tmux show-option -gqv "@whatever"
  [[ "${status}" -eq 0 ]]
}

@test "_source_file echoes captured error text and returns the tmux status" {
  source "${DISPATCHER}"
  _tmux() { return 0; }
  run _source_file "/x.conf"
  [[ -z "${output}" ]]
  [[ "${status}" -eq 0 ]]
  _tmux() { echo "parse error" >&2; return 1; }
  run _source_file "/x.conf"
  [[ "${output}" == *"parse error"* ]]
  [[ "${status}" -eq 1 ]]
}

@test "_client_busy detects a pane in mode" {
  source "${DISPATCHER}"
  _tmux() { printf '0\n1\n'; }
  run _client_busy
  [[ "${status}" -eq 0 ]]
  _tmux() { printf '0\n0\n'; }
  run _client_busy
  [[ "${status}" -eq 1 ]]
}

@test "_notify routes to osascript, then notify-send, then nothing" {
  source "${DISPATCHER}"
  has_command() { [[ "${1}" == "osascript" ]]; }
  osascript() { echo "OSA:$*" >> "${BATS_TEST_TMPDIR}/osa"; }
  run _notify "t" "m"
  [[ -f "${BATS_TEST_TMPDIR}/osa" ]]
  has_command() { [[ "${1}" == "notify-send" ]]; }
  function notify-send { echo "NS:$*" >> "${BATS_TEST_TMPDIR}/ns"; }
  run _notify "t" "m"
  [[ "${status}" -eq 0 ]]
  has_command() { return 1; }
  run _notify "t" "m"
  [[ "${status}" -eq 0 ]]
}

@test "_flash, _config_files, _message run through the tmux seam" {
  source "${DISPATCHER}"
  _tmux() { return 0; }
  run _flash "hi"
  [[ "${status}" -eq 0 ]]
  run _config_files
  [[ "${status}" -eq 0 ]]
  run _message "hi"
  [[ "${status}" -eq 0 ]]
}

@test "_file_content and _hash_content are callable" {
  source "${DISPATCHER}"
  printf "data" > "${BATS_TEST_TMPDIR}/f"
  run _file_content "${BATS_TEST_TMPDIR}/f"
  [[ "${output}" == "data" ]]
  run _file_content "/nonexistent-xyz"
  [[ -z "${output}" ]]
  printf "data" | _hash_content
}

@test "_exec_fswatch consumes one event via a shadowed command" {
  source "${DISPATCHER}"
  fswatch() { printf '1\n1\n'; }
  run _exec_fswatch "/x"
  [[ "${status}" -eq 0 ]]
}

@test "_exec_inotify waits via a shadowed command" {
  source "${DISPATCHER}"
  inotifywait() { return 0; }
  run _exec_inotify "/x"
  [[ "${status}" -eq 0 ]]
}

@test "_exec_entr waits via a shadowed command" {
  source "${DISPATCHER}"
  entr() { return 0; }
  run _exec_entr "/x"
  [[ "${status}" -eq 0 ]]
}

@test "_sleep, _poll_continue, _pid_alive, _kill_pid are callable" {
  source "${DISPATCHER}"
  _sleep() { :; }
  run _sleep 0
  run _poll_continue
  [[ "${status}" -eq 0 ]]
  run _pid_alive 999999
  run _kill_pid 999999
  [[ "${status}" -eq 0 ]]
}

@test "_file_mtime reads GNU stat and ignores its -f filesystem output" {
  source "${DISPATCHER}"
  local bin="${BATS_TEST_TMPDIR}/gnu"
  mkdir -p "${bin}"
  printf '#!/bin/sh\n[ "$1" = "-c" ] && { echo 1700000000; exit 0; }\necho "Blocks: Total: 1 Free: $$"; exit 1\n' > "${bin}/stat"
  chmod +x "${bin}/stat"
  PATH="${bin}:${PATH}" run _file_mtime /any/file
  [[ "${output}" == "1700000000" ]]
}

@test "_file_mtime falls back to BSD stat when -c is unsupported" {
  source "${DISPATCHER}"
  local bin="${BATS_TEST_TMPDIR}/bsd"
  mkdir -p "${bin}"
  printf '#!/bin/sh\n[ "$1" = "-f" ] && { echo 1700000000; exit 0; }\necho "stat: illegal option -- c" >&2; exit 1\n' > "${bin}/stat"
  chmod +x "${bin}/stat"
  PATH="${bin}:${PATH}" run _file_mtime /any/file
  [[ "${output}" == "1700000000" ]]
}

@test "_spawn_watcher backgrounds a process and echoes its pid, no real watcher" {
  source "${DISPATCHER}"
  AR_SELF="$(command -v true)"
  run _spawn_watcher
  [[ "${output}" =~ ^[0-9]+$ ]]
}

@test "running the script directly dispatches through the guard" {
  run bash "${DISPATCHER}" bogus
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}
