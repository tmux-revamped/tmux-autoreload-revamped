#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# shellcheck source=test/server_helpers.bash
source "${BATS_TEST_DIRNAME:-.}/server_helpers.bash"

bats_require_minimum_version 1.5.0

@test "entrypoint - loading returns at once, with one watcher left running" {
  # Arrange
  local pid

  # Act
  load_plugin "${ROOT}"

  # Assert
  wait_for alive
  pid=$(watcher)
  [[ "${pid}" =~ ^[0-9]+$ ]]
}

@test "entrypoint - loading again keeps the living watcher" {
  # Arrange
  local first
  armed
  first=$(watcher)

  # Act
  load_plugin "${ROOT}"

  # Assert
  run watcher
  [[ "${output}" == "${first}" ]]
}

@test "entrypoint - loading replaces a watcher that died" {
  # Arrange
  local first
  armed
  first=$(watcher)
  kill "${first}"
  wait_for ended "${first}"

  # Act
  load_plugin "${ROOT}"

  # Assert
  wait_for alive
  run watcher
  [[ "${output}" != "${first}" ]]
}

@test "entrypoint - git tracks the entry point and the tool as executable" {
  # Arrange
  local modes

  # Act
  modes=$(git -C "${ROOT}" ls-files --stage -- autoreload-revamped.tmux bin/autoreload-revamped)

  # Assert
  run awk '$1 != "100755" { bad++ } END { print NR ":" bad + 0 }' <<<"${modes}"
  [[ "${output}" == "2:0" ]]
}

@test "entrypoint - a checkout path with a space, a quote and a hash still starts the watcher" {
  # Arrange
  local copy="${BATS_TEST_TMPDIR}/it's #1 dir"
  mkdir -p "${copy}"
  cp -Rf "${ROOT}/bin" "${ROOT}/lib" "${ROOT}/autoreload-revamped.tmux" "${copy}/"

  # Act
  load_plugin "${copy}"

  # Assert
  wait_for alive
}

@test "reload - saving the config sources it again and says so" {
  # Arrange
  armed

  # Act
  printf 'set -g @x 2\nsource-file %s/sub.conf\n' "${CONF}" >"${CONF}/main.conf"

  # Assert
  wait_for shows '#{@x}' 2
  wait_for message_count 'tmux config reloaded (main.conf)' 1
}

@test "reload - saving a file the config sources reloads too" {
  # Arrange
  armed

  # Act
  printf 'set -g @y 2\n' >"${CONF}/sub.conf"

  # Assert
  wait_for shows '#{@y}' 2
  wait_for message_count 'tmux config reloaded (sub.conf)' 1
}

@test "reload - a save that changes no byte reloads nothing" {
  # Arrange
  armed
  printf 'set -g @y 2\n' >"${CONF}/sub.conf"
  wait_for message_count 'tmux config reloaded (sub.conf)' 1

  # Act
  printf 'set -g @y 2\n' >"${CONF}/sub.conf"

  # Assert
  printf 'set -g @x 3\nsource-file %s/sub.conf\n' "${CONF}" >"${CONF}/main.conf"
  wait_for message_count 'tmux config reloaded (main.conf)' 1
  message_count 'tmux config reloaded (sub.conf)' 1
}

@test "reload - a broken save shows the error once and puts the last good copy back" {
  # Arrange
  armed
  tmux set-option -g @x drifted

  # Act
  printf 'bogus-command\n' >"${CONF}/main.conf"

  # Assert
  wait_long shows '#{@x}' 1
  wait_for message_count 'tmux config error in main.conf' 1
  printf 'set -g @x 5\n' >"${CONF}/main.conf"
  wait_for shows '#{@x}' 5
  message_count 'tmux config error in main.conf' 1
}

@test "reload - a change waits while a pane is in copy-mode and lands when it leaves" {
  # Arrange
  armed
  tmux copy-mode -t test
  wait_for shows '#{pane_in_mode}' 1
  printf 'set -g @y held\n' >"${CONF}/sub.conf"
  printf 'set -g @x 7\nsource-file %s/sub.conf\n' "${CONF}" >"${CONF}/main.conf"
  tool status
  shows '#{@y}' 1

  # Act
  tmux send-keys -t test -X cancel

  # Assert
  wait_for shows '#{@y}' held
}

@test "reload - a paused watcher ignores a save until it is resumed" {
  # Arrange
  armed
  tool pause
  printf 'set -g @y later\n' >"${CONF}/sub.conf"
  tool status
  shows '#{@y}' 1

  # Act
  tool resume

  # Assert
  wait_for shows '#{@y}' later
}

@test "reload - the reload command sources the config on demand" {
  # Arrange
  tmux set-option -g @x drifted

  # Act
  tool reload

  # Assert
  [[ "${status}" -eq 0 ]]
  shows '#{@x}' 1
}

@test "status - the command reports the living watcher and its backend" {
  # Arrange
  local pid
  armed
  pid=$(watcher)

  # Act
  tool status

  # Assert
  [[ "${output}" == "autoreload-revamped: active; watcher pid ${pid}; backend poll" ]]
}
