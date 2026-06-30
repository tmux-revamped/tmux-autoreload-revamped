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

@test "autoreload_select_watcher prefers fswatch, then inotifywait, then entr, then poll" {
  has_command() { [[ "${1}" == "fswatch" ]]; }
  [[ "$(autoreload_select_watcher)" == "fswatch" ]]
  has_command() { [[ "${1}" == "inotifywait" ]]; }
  [[ "$(autoreload_select_watcher)" == "inotifywait" ]]
  has_command() { [[ "${1}" == "entr" ]]; }
  [[ "$(autoreload_select_watcher)" == "entr" ]]
  has_command() { return 1; }
  [[ "$(autoreload_select_watcher)" == "poll" ]]
}

@test "autoreload_changed reports difference" {
  [[ "$(autoreload_changed "a 1" "a 2")" == "1" ]]
  [[ "$(autoreload_changed "a 1" "a 1")" == "0" ]]
}

@test "autoreload_expand_path expands a leading tilde" {
  [[ "$(autoreload_expand_path "~/.tmux.conf")" == "${HOME}/.tmux.conf" ]]
  [[ "$(autoreload_expand_path "~")" == "${HOME}" ]]
  [[ "$(autoreload_expand_path "/abs/x")" == "/abs/x" ]]
}

@test "autoreload_split normalizes commas and whitespace and de-duplicates" {
  run autoreload_split "a.conf, b.conf  a.conf"
  [[ "${lines[0]}" == "a.conf" ]]
  [[ "${lines[1]}" == "b.conf" ]]
  [[ "${#lines[@]}" == "2" ]]
}

@test "autoreload_resolve keeps absolute and tilde paths, resolves relative ones" {
  [[ "$(autoreload_resolve "/home/u/.tmux.conf" "/etc/x.conf")" == "/etc/x.conf" ]]
  [[ "$(autoreload_resolve "/home/u/.tmux.conf" "~/y.conf")" == "${HOME}/y.conf" ]]
  [[ "$(autoreload_resolve "/home/u/.tmux.conf" "theme.conf")" == "/home/u/theme.conf" ]]
  [[ "$(autoreload_resolve "bare.conf" "theme.conf")" == "./theme.conf" ]]
}

@test "autoreload_parse_sources extracts source and source-file targets" {
  run autoreload_parse_sources <<< "$(printf '%s\n' \
    'source-file ~/.config/tmux/a.conf' \
    '  source ./b.conf' \
    'source-file -q "spaced.conf"' \
    "source-file '\''quoted.conf'\''" \
    'set -g status on' \
    'source-file')"
  [[ "${output}" == *"~/.config/tmux/a.conf"* ]]
  [[ "${output}" == *"./b.conf"* ]]
  [[ "${output}" == *"spaced.conf"* ]]
  [[ "${output}" == *"quoted.conf"* ]]
  [[ "${output}" != *"status"* ]]
}

@test "autoreload_watch_dirs prints unique parent directories" {
  run autoreload_watch_dirs <<< "$(printf '%s\n' /a/b/x.conf /a/b/y.conf /c/z.conf root)"
  [[ "${output}" == *"/a/b"* ]]
  [[ "${output}" == *"/c"* ]]
  [[ "$(printf '%s\n' "${output}" | grep -c '/a/b')" == "1" ]]
}

@test "autoreload_diff_files reports changed and new files only" {
  local old new
  old="$(printf '%s\n' "/a 1" "/b 2")"
  new="$(printf '%s\n' "/a 1" "/b 9" "/c 3")"
  run autoreload_diff_files "${old}" "${new}"
  [[ "${output}" != *"/a"* ]]
  [[ "${output}" == *"/b"* ]]
  [[ "${output}" == *"/c"* ]]
}

@test "autoreload_backoff_delay doubles per failure and caps at max" {
  [[ "$(autoreload_backoff_delay 2 0 30)" == "2" ]]
  [[ "$(autoreload_backoff_delay 2 1 30)" == "2" ]]
  [[ "$(autoreload_backoff_delay 2 2 30)" == "4" ]]
  [[ "$(autoreload_backoff_delay 2 3 30)" == "8" ]]
  [[ "$(autoreload_backoff_delay 2 9 30)" == "30" ]]
  [[ "$(autoreload_backoff_delay x y z)" == "2" ]]
}
