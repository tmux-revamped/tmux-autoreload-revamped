#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2030,SC2031,SC2034,SC2154

# shellcheck source=test/tmux_helpers.bash
source "${BATS_TEST_DIRNAME:-.}/tmux_helpers.bash"

setup() {
  ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  CONF="${BATS_TEST_TMPDIR}/conf"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${CONF}" "${HOME}"
  printf 'set -g @x 1\nsource-file %s/sub.conf\n' "${CONF}" >"${CONF}/main.conf"
  printf 'set -g @y 1\n' >"${CONF}/sub.conf"
  command tmux -S "${TMUX_SOCKET}" -f "${CONF}/main.conf" new-session -d -s test -x 100 -y 30 "env PS1='$ ' sh"
  wait_for shows '#{@y}' 1
  tmux set-option -g @autoreload_revamped_interval 1
  backend "${BACKEND:-poll}"
  HOST="${TMUX_SOCKET}-host"
  command tmux -S "${HOST}" -f /dev/null new-session -d -s host -x 100 -y 31 "env -u TMUX TERM=xterm-256color tmux -S '${TMUX_SOCKET}' attach-session -t test"
  wait_for attached
}

teardown() {
  local pid
  pid=$(tmux show-option -gqv @autoreload_revamped_pid 2>/dev/null) || pid=""
  command tmux -S "${HOST}" kill-server 2>/dev/null || :
  rm -f "${HOST}"
  teardown_tmux_server
  [[ -z "${pid}" ]] || kill "${pid}" 2>/dev/null || :
}

backend() {
  local farm="${BATS_TEST_TMPDIR}/farm-$1" dir name
  FARM="${farm}"
  mkdir -p "${farm}"
  local IFS=:
  for dir in ${PATH}; do
    [[ -d "${dir}" ]] || continue
    ln -s "${dir}"/* "${farm}/" 2>/dev/null || :
  done
  unset IFS
  for name in fswatch inotifywait entr; do
    [[ "${name}" == "$1" ]] || rm -f "${farm:?}/${name}"
  done
  tmux set-environment -g PATH "${farm}"
}

load_plugin() {
  local quoted
  quoted=$(printf '%s' "$1" | sed -e "s/'/'\\\\''/g" -e 's/#/##/g')
  tmux run-shell "'${quoted}/autoreload-revamped.tmux'"
}

wait_for() {
  local delay
  for delay in 0.01 0.02 0.05 0.1 0.2 0.5 0.5 1 1 1 2 2 2; do
    "$@" && return 0
    sleep "${delay}"
  done
  "$@"
}

wait_long() {
  local delay
  for delay in 0.01 0.02 0.05 0.1 0.2 0.5 0.5 1 1 1 2 2 2 2 2 2 2 2 2 2; do
    "$@" && return 0
    sleep "${delay}"
  done
  "$@"
}

attached() {
  local clients
  clients=$(tmux list-clients -F x 2>/dev/null)
  [[ -n "${clients}" ]]
}

shows() {
  local now
  now=$(tmux display-message -p "$1" 2>/dev/null)
  [[ "${now}" == "$2" ]]
}

watcher() {
  tmux show-option -gqv @autoreload_revamped_pid
}

alive() {
  local pid
  pid=$(watcher)
  [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null
}

ended() {
  ! kill -0 "$1" 2>/dev/null
}

messages() {
  local log
  log=$(tmux show-messages)
  grep -c " message: $1" <<<"${log}" || :
}

message_count() {
  local count
  count=$(messages "$1")
  [[ "${count}" == "$2" ]]
}

armed() {
  load_plugin "${ROOT}"
  wait_for alive
  wait_for [ -d "${HOME}/.tmux/autoreload-revamped/backup" ]
}

tool() {
  # shellcheck disable=SC2086
  TMUX="${TMUX_SOCKET},1,0" PATH="${FARM}" run ${REVAMPED_TEST_SHELL:-sh} "${ROOT}/bin/autoreload-revamped" "$@"
}
