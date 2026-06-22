#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../../helpers.bash"

setup() {
  setup_test_environment
  unset _AUTORELOAD_REVAMPED_LOADED
  source "${BATS_TEST_DIRNAME}/../../../src/lib/autoreload/autoreload.sh"
}

teardown() {
  cleanup_test_environment
}

@test "autoreload_select_watcher prefers fswatch, then inotifywait, then poll" {
  has_command() { [[ "${1}" == "fswatch" ]]; }
  [[ "$(autoreload_select_watcher)" == "fswatch" ]]
  has_command() { [[ "${1}" == "inotifywait" ]]; }
  [[ "$(autoreload_select_watcher)" == "inotifywait" ]]
  has_command() { return 1; }
  [[ "$(autoreload_select_watcher)" == "poll" ]]
}

@test "autoreload_changed reports difference" {
  [[ "$(autoreload_changed "a 1" "a 2")" == "1" ]]
  [[ "$(autoreload_changed "a 1" "a 1")" == "0" ]]
}

@test "autoreload_split normalizes commas and whitespace and de-duplicates" {
  run autoreload_split "a.conf, b.conf  a.conf"
  [[ "${lines[0]}" == "a.conf" ]]
  [[ "${lines[1]}" == "b.conf" ]]
  [[ "${#lines[@]}" == "2" ]]
}
