#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034

# shellcheck source=test/autoreload_helpers.bash
source "${BATS_TEST_DIRNAME:-.}/autoreload_helpers.bash"

bats_require_minimum_version 1.5.0

tool() {
  # shellcheck disable=SC2086
  run ${REVAMPED_TEST_SHELL:-sh} "${REVAMPED_TESTS_DIR}/../bin/autoreload-revamped" "$@"
}

plain_tty() {
  local shell_words
  read -r -a shell_words <<<"${REVAMPED_TEST_SHELL:-sh}"
  run python3 "${REVAMPED_TESTS_DIR}/on_tty.py" "${shell_words[@]}" "${REVAMPED_TESTS_DIR}/../bin/autoreload-revamped"
}

@test "commands - status names the state, the watcher and the backend" {
  # Arrange
  harness_hide fswatch inotifywait entr

  # Act
  tool status

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "autoreload-revamped: active; watcher pid none; backend poll" ]]
}

@test "commands - status --json prints one object, with the watcher as a number" {
  # Arrange
  harness_hide fswatch inotifywait entr
  tmux_loads "$(printf '\t\t\t\t\t\t\t\t\t\t\t\t42\t1\t%s\t' "$$")"

  # Act
  tool status --json

  # Assert
  [[ "${output}" == "{\"state\":\"paused\",\"watcher\":$$,\"backend\":\"poll\"}" ]]
}

@test "commands - status --json writes null when no watcher runs" {
  # Arrange
  harness_hide fswatch inotifywait entr

  # Act
  tool --json status

  # Assert
  [[ "${output}" == '{"state":"active","watcher":null,"backend":"poll"}' ]]
}

@test "commands - pause and resume set the state and say so" {
  # Arrange
  local first=pause

  # Act
  tool "${first}"
  tool resume

  # Assert
  [[ "${status}" -eq 0 ]]
  run grep -e '^set-option' -e '^display-message [a-z]' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == $'set-option -gq @autoreload_revamped_paused 1\ndisplay-message autoreload paused\nset-option -gq @autoreload_revamped_paused 0\ndisplay-message autoreload resumed' ]]
}

@test "commands - toggle flips the pause" {
  # Arrange
  option paused 1

  # Act
  tool toggle

  # Assert
  run grep '^set-option' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == "set-option -gq @autoreload_revamped_paused 0" ]]
}

@test "commands - reload sources the entry points given as an option, in both forms" {
  # Arrange
  conf one.conf 'set -g @x 1'
  conf two.conf 'set -g @y 1'

  # Act
  tool --entrypoints "${WORK}/one.conf" --quiet=1 reload
  tool --entrypoints="${WORK}/two.conf" reload

  # Assert
  [[ "${status}" -eq 0 ]]
  run grep -e '^source-file' -e '^display-message [a-z]' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == "source-file ${WORK}/one.conf"$'\n'"source-file ${WORK}/two.conf"$'\n'"display-message tmux config reloaded (two.conf)" ]]
}

@test "commands - reload exits 1 when a file fails to load" {
  # Arrange
  conf one.conf 'bogus'
  tmux_refuses "${WORK}/one.conf" "one.conf:1: unknown command: bogus"

  # Act
  tool --entrypoints "${WORK}/one.conf" reload

  # Assert
  [[ "${status}" -eq 1 ]]
}

@test "commands - apply starts the watcher and prints nothing" {
  # Arrange
  tmux_loads ""

  # Act
  # shellcheck disable=SC2086
  run --separate-stderr ${REVAMPED_TEST_SHELL:-sh} "${REVAMPED_TESTS_DIR}/../bin/autoreload-revamped" apply

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
  run grep -c '^set-option -gq @autoreload_revamped_pid [0-9]' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == "1" ]]
}

@test "commands - watch ends at once when no server answers" {
  # Arrange
  tmux_loads ""

  # Act
  tool watch

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ -z "${output}" ]]
}

@test "commands - the menu shows the status" {
  # Arrange
  harness_hide gum fswatch inotifywait entr

  # Act
  plain_tty <<<"1"

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"autoreload-revamped: active; watcher pid none; backend poll"* ]]
}

@test "commands - the menu reloads" {
  # Arrange
  harness_hide gum
  conf one.conf 'set -g @x 1'
  option entrypoints "${WORK}/one.conf"

  # Act
  plain_tty <<<"2"

  # Assert
  run sourced "${WORK}/one.conf"
  [[ "${output}" == "1" ]]
}

@test "commands - the menu pauses" {
  # Arrange
  harness_hide gum

  # Act
  plain_tty <<<"3"

  # Assert
  run grep '^set-option' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == "set-option -gq @autoreload_revamped_paused 1" ]]
}

@test "commands - the menu runs doctor" {
  # Arrange
  harness_hide gum

  # Act
  plain_tty <<<"4"

  # Assert
  [[ "${output}" =~ tmux\ +ok ]]
}

@test "commands - the menu shows the help page" {
  # Arrange
  harness_hide gum

  # Act
  plain_tty <<<"5"

  # Assert
  [[ "${output}" == *"autoreload-revamped apply     start the watcher, unless one is alive"* ]]
}

@test "commands - doctor names the watcher tool it would wait on" {
  # Arrange
  stub_command inotifywait
  harness_hide fswatch

  # Act
  tool doctor

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ watcher\ +ok\ +"${BATS_TEST_TMPDIR}/stubs/inotifywait" ]]
}

@test "commands - doctor warns when it would poll" {
  # Arrange
  harness_hide fswatch inotifywait entr

  # Act
  tool doctor

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" =~ watcher\ +warn\ +polling ]]
}

@test "commands - an unknown option is a usage error even without a value" {
  # Arrange
  local option=--nope

  # Act
  tool "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "autoreload-revamped: unknown option '--nope'. run 'autoreload-revamped help' for usage." ]]
}

@test "commands - an unknown option with a value is a usage error" {
  # Arrange
  local option=--nope=1

  # Act
  tool "${option}" status

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "autoreload-revamped: unknown option '--nope'. run 'autoreload-revamped help' for usage." ]]
}

@test "commands - a setting option without its value is a usage error" {
  # Arrange
  local option=--interval

  # Act
  tool "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "autoreload-revamped: option '--interval' needs a value. run 'autoreload-revamped help' for usage." ]]
}

@test "commands - a single-dash option is a usage error" {
  # Arrange
  local option=-x

  # Act
  tool "${option}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "autoreload-revamped: unknown option '-x'. run 'autoreload-revamped help' for usage." ]]
}

@test "commands - --json with any command but status is a usage error" {
  # Arrange
  local command=reload

  # Act
  tool --json "${command}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "autoreload-revamped: option '--json' works only with status. run 'autoreload-revamped help' for usage." ]]
}

@test "commands - an unknown command is a usage error" {
  # Arrange
  local command=frobnicate

  # Act
  tool "${command}"

  # Assert
  [[ "${status}" -eq 1 ]]
  [[ "${output}" == "autoreload-revamped: unknown command 'frobnicate'. run 'autoreload-revamped help' for usage." ]]
}

@test "commands - -- ends the options, and a theme may come first" {
  # Arrange
  harness_hide fswatch inotifywait entr

  # Act
  tool --theme nord -- status

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == "autoreload-revamped: active; watcher pid none; backend poll" ]]
}

@test "commands - a theme in its other form and an accent are taken" {
  # Arrange
  export AUTORELOAD_REVAMPED_ACCENT='#CBA6F7'

  # Act
  tool --theme=mono version

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" =~ ^autoreload-revamped\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
  [[ "${lines[1]}" == tmux:\ * ]]
}

@test "commands - an inherited guard variable of the plugin is ignored" {
  # Arrange
  export AUTORELOAD_REVAMPED_AUTORELOAD_LOADED=1 AUTORELOAD_REVAMPED_CORE_LOADED=1

  # Act
  tool version

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ "${lines[0]}" =~ ^autoreload-revamped\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}
