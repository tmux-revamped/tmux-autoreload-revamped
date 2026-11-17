#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# shellcheck source=test/server_helpers.bash
source "${BATS_TEST_DIRNAME:-.}/server_helpers.bash"

bats_require_minimum_version 1.5.0

needs() {
  command -v "$1" >/dev/null 2>&1 || skip "$1 is not installed on this machine"
}

no_tool() {
  local running
  running=$(pgrep -f "$1 .*${CONF}" 2>/dev/null) || running=""
  [[ -z "${running}" ]]
}

@test "watcher - it ends when its tmux server does" {
  # Arrange
  local pid
  armed
  pid=$(watcher)

  # Act
  tmux kill-server

  # Assert
  wait_for ended "${pid}"
}

@test "fswatch - a save reloads at once, long before the next poll" {
  # Arrange
  needs fswatch
  tmux set-option -g @autoreload_revamped_interval 30
  backend fswatch
  armed

  # Act
  printf 'set -g @y saved\n' >"${CONF}/sub.conf"

  # Assert
  wait_for shows '#{@y}' saved
}

@test "fswatch - a save made right after a reload is not missed" {
  # Arrange
  needs fswatch
  tmux set-option -g @autoreload_revamped_interval 30
  backend fswatch
  armed
  printf 'set -g @y first\n' >"${CONF}/sub.conf"
  wait_for shows '#{@y}' first

  # Act
  printf 'set -g @y second\n' >"${CONF}/sub.conf"

  # Assert
  wait_long shows '#{@y}' second
}

@test "fswatch - the watcher and the tool end when the tmux server does" {
  # Arrange
  local pid
  needs fswatch
  backend fswatch
  armed
  pid=$(watcher)

  # Act
  tmux kill-server

  # Assert
  wait_for ended "${pid}"
  wait_for no_tool fswatch
}

@test "inotifywait - a save reloads at once, long before the next poll" {
  # Arrange
  needs inotifywait
  tmux set-option -g @autoreload_revamped_interval 30
  backend inotifywait
  armed

  # Act
  printf 'set -g @y saved\n' >"${CONF}/sub.conf"

  # Assert
  wait_for shows '#{@y}' saved
}

@test "inotifywait - a save made right after a reload is not missed" {
  # Arrange
  needs inotifywait
  tmux set-option -g @autoreload_revamped_interval 30
  backend inotifywait
  armed
  printf 'set -g @y first\n' >"${CONF}/sub.conf"
  wait_for shows '#{@y}' first

  # Act
  printf 'set -g @y second\n' >"${CONF}/sub.conf"

  # Assert
  wait_long shows '#{@y}' second
}

@test "inotifywait - the watcher and the tool end when the tmux server does" {
  # Arrange
  local pid
  needs inotifywait
  backend inotifywait
  armed
  pid=$(watcher)

  # Act
  tmux kill-server

  # Assert
  wait_for ended "${pid}"
  wait_for no_tool inotifywait
}

@test "entr - a save reloads at once, long before the next poll" {
  # Arrange
  needs entr
  tmux set-option -g @autoreload_revamped_interval 30
  backend entr
  armed

  # Act
  printf 'set -g @y saved\n' >"${CONF}/sub.conf"

  # Assert
  wait_for shows '#{@y}' saved
}

@test "entr - a save made right after a reload is not missed" {
  # Arrange
  needs entr
  tmux set-option -g @autoreload_revamped_interval 30
  backend entr
  armed
  printf 'set -g @y first\n' >"${CONF}/sub.conf"
  wait_for shows '#{@y}' first

  # Act
  printf 'set -g @y second\n' >"${CONF}/sub.conf"

  # Assert
  wait_long shows '#{@y}' second
}

@test "entr - the watcher and the tool end when the tmux server does" {
  # Arrange
  local pid
  needs entr
  backend entr
  armed
  pid=$(watcher)

  # Act
  tmux kill-server

  # Assert
  wait_for ended "${pid}"
  wait_for no_tool entr
}
