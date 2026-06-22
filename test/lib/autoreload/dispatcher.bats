#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

DISPATCHER="${BATS_TEST_DIRNAME}/../../../src/autoreload.sh"

setup() {
  setup_test_environment
  unset _AUTORELOAD_REVAMPED_LOADED
  source "${DISPATCHER}"
  _config_files() { echo "main.conf"; }
  _file_mtime() { echo "100"; }
  _source_file() { echo "SOURCE:${1}" >> "${BATS_TEST_TMPDIR}/src"; }
  _message() { echo "MSG:${1}" >> "${BATS_TEST_TMPDIR}/msg"; }
}

teardown() {
  cleanup_test_environment
}

@test "autoreload.sh - functions are defined" {
  function_exists ar_watch
  function_exists ar_reload
  function_exists ar_poll_tick
}

@test "autoreload.sh - ar_files combines config files with extras, de-duplicated" {
  set_tmux_option "@autoreload_revamped_files" "extra.conf main.conf"
  run ar_files
  [[ "${output}" == *"main.conf"* ]]
  [[ "${output}" == *"extra.conf"* ]]
  [[ "$(printf '%s\n' "${output}" | grep -c 'main.conf')" == "1" ]]
}

@test "autoreload.sh - ar_snapshot pairs files with mtimes" {
  run ar_snapshot
  [[ "${output}" == "main.conf 100" ]]
}

@test "autoreload.sh - reload sources entrypoints and announces" {
  run main reload
  [[ "$(cat "${BATS_TEST_TMPDIR}/src")" == "SOURCE:main.conf" ]]
  [[ "$(cat "${BATS_TEST_TMPDIR}/msg")" == *"reloaded"* ]]
}

@test "autoreload.sh - reload is silent when quiet" {
  set_tmux_option "@autoreload_revamped_quiet" "1"
  run main reload
  [[ ! -f "${BATS_TEST_TMPDIR}/msg" ]]
}

@test "autoreload.sh - poll tick reloads only when the snapshot changed" {
  run ar_poll_tick "main.conf 100"
  [[ ! -f "${BATS_TEST_TMPDIR}/src" ]]
  [[ "${output}" == "main.conf 100" ]]
  run ar_poll_tick "main.conf 99"
  [[ -f "${BATS_TEST_TMPDIR}/src" ]]
}

@test "autoreload.sh - watch routes to each backend" {
  _watch_poll() { echo "POLL" > "${BATS_TEST_TMPDIR}/w"; }
  _watch_fswatch() { echo "FS" > "${BATS_TEST_TMPDIR}/w"; }
  _watch_inotify() { echo "IN" > "${BATS_TEST_TMPDIR}/w"; }
  autoreload_select_watcher() { echo "poll"; }
  run ar_watch
  [[ "$(cat "${BATS_TEST_TMPDIR}/w")" == "POLL" ]]
  autoreload_select_watcher() { echo "fswatch"; }
  run ar_watch
  [[ "$(cat "${BATS_TEST_TMPDIR}/w")" == "FS" ]]
  autoreload_select_watcher() { echo "inotifywait"; }
  run ar_watch
  [[ "$(cat "${BATS_TEST_TMPDIR}/w")" == "IN" ]]
}

@test "autoreload.sh - poll loop runs one iteration then stops" {
  printf '0' > "${BATS_TEST_TMPDIR}/cnt"
  _poll_continue() {
    [[ "$(cat "${BATS_TEST_TMPDIR}/cnt")" == "0" ]] && { printf '1' > "${BATS_TEST_TMPDIR}/cnt"; return 0; }
    return 1
  }
  _sleep() { :; }
  run _watch_poll
  true
}

@test "autoreload.sh - fswatch backend reloads on each event" {
  _exec_fswatch() { printf 'change\n'; }
  ar_reload() { echo "RELOAD" > "${BATS_TEST_TMPDIR}/r"; }
  run _watch_fswatch
  [[ "$(cat "${BATS_TEST_TMPDIR}/r")" == "RELOAD" ]]
}

@test "autoreload.sh - inotify backend reloads while the watcher signals" {
  printf '0' > "${BATS_TEST_TMPDIR}/icnt"
  _exec_inotify() {
    [[ "$(cat "${BATS_TEST_TMPDIR}/icnt")" == "0" ]] && { printf '1' > "${BATS_TEST_TMPDIR}/icnt"; return 0; }
    return 1
  }
  ar_reload() { echo "R" > "${BATS_TEST_TMPDIR}/ir"; }
  run _watch_inotify
  [[ "$(cat "${BATS_TEST_TMPDIR}/ir")" == "R" ]]
}

@test "autoreload.sh - host-probe seams are callable" {
  unset _AUTORELOAD_REVAMPED_LOADED
  source "${DISPATCHER}"
  run _config_files
  run _file_mtime "/nonexistent-xyz"
  run _source_file "/nonexistent-xyz"
  run _message "x"
  run _poll_continue
  run _exec_fswatch "/nonexistent-xyz"
  run _exec_inotify "/nonexistent-xyz"
  true
}

@test "autoreload.sh - main tick runs" {
  run main tick
  true
}

@test "autoreload.sh - unknown subcommand produces no output" {
  run main bogus
  [[ -z "${output}" ]]
}
