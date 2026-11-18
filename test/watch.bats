#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034

# shellcheck source=test/autoreload_helpers.bash
source "${BATS_TEST_DIRNAME:-.}/autoreload_helpers.bash"

watching() {
  conf main.conf 'set -g @x 1'
  option files "${WORK}/main.conf"
  option entrypoints "${WORK}/main.conf"
}

tool() {
  quiet "$1" "$2"
}

blocking_tool() {
  tool "$1" "printf '%s\n' \"\$\$\" >'${BATS_TEST_TMPDIR}/tool.pid'; while :; do /bin/sleep 0.05; done"
}

slept() {
  paste -sd ' ' "${BATS_TEST_TMPDIR}/sleep.calls" 2>/dev/null || :
}

gone() {
  local pid
  [[ -f "${BATS_TEST_TMPDIR}/tool.pid" ]] || return 0
  pid=$(cat "${BATS_TEST_TMPDIR}/tool.pid")
  ! kill -0 "${pid}" 2>/dev/null
}

pauses() {
  [[ -f "${BATS_TEST_TMPDIR}/sleep.calls" ]] || {
    printf '0\n'
    return 0
  }
  grep -c '^7$' "${BATS_TEST_TMPDIR}/sleep.calls" || :
}

wait_for() {
  local delay
  for delay in 0.01 0.02 0.05 0.1 0.2 0.5 1 1 2; do
    "$@" && return 0
    /bin/sleep "${delay}"
  done
  "$@"
}

@test "watch - a changed file reloads the entry points, says so and takes the new snapshot" {
  # Arrange
  watching
  local script='autoreload_revamped_track; printf "set -g @x 2\n" >"'"${WORK}"'/main.conf"; autoreload_revamped_event; autoreload_revamped_event; printf "[%s]" "${AUTORELOAD_REVAMPED_HELD}"'

  # Act
  loaded "${script}"

  # Assert
  [[ "${output}" == "[0]" ]]
  run sourced "${WORK}/main.conf"
  [[ "${output}" == "1" ]]
  run said
  [[ "${output}" == "display-message tmux config reloaded (main.conf)" ]]
}

@test "watch - a save made while a reload runs is loaded by the next event" {
  # Arrange
  watching
  tmux_saves_once "${WORK}/main.conf" 'set -g @x 3'
  local script='autoreload_revamped_track; printf "set -g @x 2\n" >"'"${WORK}"'/main.conf"; autoreload_revamped_event; autoreload_revamped_event; autoreload_revamped_event'

  # Act
  loaded "${script}"

  # Assert
  run sourced "${WORK}/main.conf"
  [[ "${output}" == "2" ]]
}

@test "watch - a file the config starts to source joins the watch without a second reload" {
  # Arrange
  conf main.conf 'set -g @x 1'
  conf sub.conf 'set -g @y 1'
  tmux_loads "$(printf '\t\t\t\t\t\t\t\t\t\t\t\t42\t\t\t%s' "${WORK}/main.conf")"
  local script='autoreload_revamped_track; printf "source-file %s/sub.conf\n" "'"${WORK}"'" >"'"${WORK}"'/main.conf"; autoreload_revamped_event; autoreload_revamped_event; printf "%s\n" "${AUTORELOAD_REVAMPED_TRACKED}"'

  # Act
  loaded "${script}"

  # Assert
  [[ "${output}" == *"${WORK}/sub.conf" ]]
  run sourced "${WORK}/main.conf"
  [[ "${output}" == "1" ]]
}

@test "watch - while paused, or with nothing changed, an event reloads nothing, and a pause is checked each interval" {
  # Arrange
  watching
  local script='autoreload_revamped_track; autoreload_revamped_event; printf "[%s]" "${AUTORELOAD_REVAMPED_HELD}"; printf "set -g @x 2\n" >"'"${WORK}"'/main.conf"; AUTORELOAD_REVAMPED_S_paused=1; autoreload_revamped_event; printf "[%s]" "${AUTORELOAD_REVAMPED_HELD}"'

  # Act
  loaded "${script}"

  # Assert
  [[ "${output}" == "[0][1]" ]]
  run grep -c '^source-file' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == "0" ]]
}

@test "watch - a change is held while a pane is in a mode, and applied once none is" {
  # Arrange
  watching
  tmux_lists_panes '0 1'
  local script='autoreload_revamped_track; printf "set -g @x 2\n" >"'"${WORK}"'/main.conf"; autoreload_revamped_event; printf "[%s]" "${AUTORELOAD_REVAMPED_HELD}"; grep -c "^source-file" "'"${REVAMPED_TEST_TMUX_LOG}"'"; rm -f "'"${BATS_TEST_TMPDIR}"'/stubs/tmux"; autoreload_revamped_event; printf "[%s]" "${AUTORELOAD_REVAMPED_HELD}"'

  # Act
  loaded "${script}"

  # Assert
  [[ "${output}" == "[1]0"$'\n'"[0]" ]]
  run sourced "${WORK}/main.conf"
  [[ "${output}" == "1" ]]
}

@test "watch - with defer off a change reloads even while a pane is in a mode" {
  # Arrange
  watching
  option defer 0
  tmux_lists_panes '1'
  local script='autoreload_revamped_track; printf "set -g @x 2\n" >"'"${WORK}"'/main.conf"; autoreload_revamped_event'

  # Act
  loaded "${script}"

  # Assert
  run sourced "${WORK}/main.conf"
  [[ "${output}" == "1" ]]
}

@test "watch - a file that goes away is forgotten without a reload" {
  # Arrange
  watching
  conf extra.conf 'set -g @y 1'
  option files "${WORK}/main.conf ${WORK}/extra.conf"
  local script='autoreload_revamped_track; rm -f "'"${WORK}"'/extra.conf"; autoreload_revamped_event; printf "%s" "${AUTORELOAD_REVAMPED_TRACKED}"'

  # Act
  loaded "${script}"

  # Assert
  [[ "${output}" == "${WORK}/main.conf" ]]
  run grep -c '^source-file' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == "0" ]]
}

@test "watch - a reload that fails is tried once, until the file changes again" {
  # Arrange
  watching
  tmux_refuses "${WORK}/main.conf" "main.conf:1: unknown command: bogus"
  local script='autoreload_revamped_track; printf "bogus\n" >"'"${WORK}"'/main.conf"; autoreload_revamped_event; autoreload_revamped_event'

  # Act
  loaded "${script}"

  # Assert
  run sourced "${WORK}/main.conf"
  [[ "${output}" == "1" ]]
  run said
  [[ "${output}" == "display-message tmux config error in main.conf: main.conf:1: unknown command: bogus" ]]
}

@test "watch - a file a config starts to source is watched from the next check on" {
  # Arrange
  watching
  option files ""
  tmux_loads "$(printf '\t%s\t\t\t\t\t\t\t\t\t\t\t42\t\t\t%s' "${WORK}/main.conf" "${WORK}/main.conf")"
  conf new.conf 'set -g @y 1'
  local script='autoreload_revamped_track; printf "source-file %s\n" "'"${WORK}"'/new.conf" >"'"${WORK}"'/main.conf"; autoreload_revamped_event; printf "%s" "${AUTORELOAD_REVAMPED_TRACKED}"'

  # Act
  loaded "${script}"

  # Assert
  [[ "${output}" == "${WORK}/main.conf"$'\n'"${WORK}/new.conf" ]]
}

@test "watch - selective reloads only the entry point that includes the changed file" {
  # Arrange
  conf one.conf "source-file ${WORK}/shared.conf"
  conf two.conf 'set -g @y 1'
  conf shared.conf 'set -g @x 1'
  option files "${WORK}/one.conf ${WORK}/two.conf"
  option entrypoints "${WORK}/one.conf ${WORK}/two.conf"
  option selective 1
  local script='autoreload_revamped_track; printf "set -g @x 2\n" >"'"${WORK}"'/shared.conf"; autoreload_revamped_event'

  # Act
  loaded "${script}"

  # Assert
  run grep '^source-file' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == "source-file ${WORK}/one.conf" ]]
}

@test "watch - polling, a held change or nothing to watch waits one interval" {
  # Arrange
  quiet_command sleep
  local script='AUTORELOAD_REVAMPED_S_interval=7 AUTORELOAD_REVAMPED_TRACKED=/etc/a.conf; autoreload_revamped_wait poll; AUTORELOAD_REVAMPED_HELD=1; autoreload_revamped_wait fswatch; AUTORELOAD_REVAMPED_HELD=0 AUTORELOAD_REVAMPED_TRACKED=""; autoreload_revamped_wait fswatch'

  # Act
  lib_run autoreload "${script}"

  # Assert
  run slept
  [[ "${output}" == "7 7 7" ]]
}

@test "watch - fswatch is given every file and folder, and its return means check now" {
  # Arrange
  quiet_command sleep
  tool fswatch "printf '%s\n' \"\$@\" >'${BATS_TEST_TMPDIR}/tool.args'"
  local script='AUTORELOAD_REVAMPED_SERVER=$$ AUTORELOAD_REVAMPED_S_interval=7 AUTORELOAD_REVAMPED_TRACKED="/etc/a b.conf"; autoreload_revamped_wait fswatch; printf "[%s]" "$?"'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == "[0]" ]]
  run cat "${BATS_TEST_TMPDIR}/tool.args"
  [[ "${output}" == $'-1\n-o\n/etc/a b.conf\n/etc' ]]
  run pauses
  [[ "${output}" == "0" ]]
}

@test "watch - inotifywait watches for writes, moves, creations and deletions" {
  # Arrange
  quiet_command sleep
  tool inotifywait "printf '%s\n' \"\$@\" >'${BATS_TEST_TMPDIR}/tool.args'"
  local script='AUTORELOAD_REVAMPED_SERVER=$$ AUTORELOAD_REVAMPED_S_atomic=0 AUTORELOAD_REVAMPED_TRACKED=/etc/a.conf; autoreload_revamped_wait inotifywait'

  # Act
  lib_run autoreload "${script}"

  # Assert
  run cat "${BATS_TEST_TMPDIR}/tool.args"
  [[ "${output}" == $'-q\n-e\nmodify,move,create,delete,close_write\n/etc/a.conf' ]]
}

@test "watch - entr reads the list on its input, and its folder-changed status means check now" {
  # Arrange
  quiet_command sleep
  tool entr "cat >'${BATS_TEST_TMPDIR}/tool.input'; printf '%s\n' \"\$@\" >'${BATS_TEST_TMPDIR}/tool.args'; exit 2"
  local script='AUTORELOAD_REVAMPED_SERVER=$$ AUTORELOAD_REVAMPED_S_interval=7 AUTORELOAD_REVAMPED_S_atomic=0 AUTORELOAD_REVAMPED_TRACKED="/etc/a b.conf"; autoreload_revamped_wait entr'

  # Act
  lib_run autoreload "${script}"

  # Assert
  run cat "${BATS_TEST_TMPDIR}/tool.input" "${BATS_TEST_TMPDIR}/tool.args"
  [[ "${output}" == $'/etc/a b.conf\n-d\n-n\n-p\n-z\ntrue' ]]
  run pauses
  [[ "${output}" == "0" ]]
}

@test "watch - a tool that fails is followed by one interval, so the loop never spins" {
  # Arrange
  quiet_command sleep
  tool fswatch 'exit 3'
  local script='AUTORELOAD_REVAMPED_SERVER=$$ AUTORELOAD_REVAMPED_S_interval=7 AUTORELOAD_REVAMPED_TRACKED=/etc/a.conf; autoreload_revamped_wait fswatch'

  # Act
  lib_run autoreload "${script}"

  # Assert
  run pauses
  [[ "${output}" == "1" ]]
}

@test "watch - a save made before the tool was armed is caught at once, and the tool is stopped" {
  # Arrange
  watching
  blocking_tool fswatch
  local script='autoreload_revamped_track; AUTORELOAD_REVAMPED_SERVER=$$; printf "set -g @x 2\n" >"'"${WORK}"'/main.conf"; autoreload_revamped_wait fswatch; printf "[%s]" "$?"'

  # Act
  loaded "${script}"

  # Assert
  [[ "${output}" == "[0]" ]]
  wait_for gone
}

@test "watch - a save the tool never reported is caught by the next guard check" {
  # Arrange
  watching
  tool fswatch "printf '%s\n' \"\$\$\" >'${BATS_TEST_TMPDIR}/tool.pid'; printf 'set -g @x 2\n' >'${WORK}/main.conf'; while :; do /bin/sleep 0.05; done"
  quiet_command sleep
  local script='autoreload_revamped_track; AUTORELOAD_REVAMPED_SERVER=$$ AUTORELOAD_REVAMPED_S_interval=7; autoreload_revamped_wait fswatch; printf "[%s]" "$?"'

  # Act
  loaded "${script}"

  # Assert
  [[ "${output}" == *"[0]" ]]
  wait_for gone
  run pauses
  [[ "${output}" == "0" ]]
}

@test "watch - the guard stops the tool at its first check when the files no longer match the copy it holds" {
  # Arrange
  watching
  quiet_command sleep
  local script='AUTORELOAD_REVAMPED_TRACKED="'"${WORK}"'/main.conf" AUTORELOAD_REVAMPED_SNAPSHOT=stale; /bin/sleep 30 & tool=$!; autoreload_revamped_guard "$$" "${tool}" 3; code=0; wait "${tool}" 2>/dev/null || code=$?; printf "[%s]" "${code}"'

  # Act
  loaded "${script}"

  # Assert
  [[ "${output}" == *"[143]" ]]
  run slept
  [[ "${output}" == "3" ]]
}

@test "watch - the tool is stopped when the tmux server is gone" {
  # Arrange
  watching
  blocking_tool fswatch
  quiet_command sleep
  /bin/sleep 0 &
  local dead=$!
  wait "${dead}"
  local script='autoreload_revamped_track; AUTORELOAD_REVAMPED_SERVER='"${dead}"'; autoreload_revamped_block fswatch "'"${WORK}"'/main.conf"; printf "[%s]" "$?"'

  # Act
  loaded "${script}"

  # Assert
  [[ "${output}" == *"[143]" ]]
  wait_for gone
}

@test "watch - a step ends the watcher when another server answers" {
  # Arrange
  quiet_command sleep
  tmux_loads "$(printf '\t\t\t\t\t\t\t\t\t\t\t\t77\t\t\t')"
  local script='AUTORELOAD_REVAMPED_SERVER=42; autoreload_revamped_step poll || printf ended'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == "ended" ]]
}

@test "watch - with no server to ask, the watcher ends before watching anything" {
  # Arrange
  quiet_command sleep
  tmux_loads ""

  # Act
  lib_run autoreload 'autoreload_revamped_watch; printf "[%s]" "${AUTORELOAD_REVAMPED_TRACKED}"'

  # Assert
  [[ "${output}" == "[]" ]]
  [[ ! -e "${BATS_TEST_TMPDIR}/sleep.calls" ]]
}

@test "watch - the watcher keeps a first copy, reloads a change on its next check and ends with its server" {
  # Arrange
  local copy
  conf main.conf 'set -g @x 1'
  copy=$(copy_of "${WORK}/main.conf")
  harness_hide fswatch inotifywait entr
  tmux_loads "$(printf '%s\t%s\t\t\t\t\t\t\t\t\t\t\t42\t\t\t' "${WORK}/main.conf" "${WORK}/main.conf")"
  tool sleep "count=\$(cat '${BATS_TEST_TMPDIR}/ticks' 2>/dev/null || printf 0); count=\$((count + 1)); printf '%s' \"\${count}\" >'${BATS_TEST_TMPDIR}/ticks'; [ \"\${count}\" -ne 1 ] || printf 'set -g @x 2\n' >'${WORK}/main.conf'; [ \"\${count}\" -lt 3 ] || printf '\t\t\t\t\t\t\t\t\t\t\t\t77\t\t\t\n' >'${BATS_TEST_TMPDIR}/loaded'"

  # Act
  lib_run autoreload 'autoreload_revamped_watch'

  # Assert
  [[ "${status}" -eq 0 ]]
  run cat "${BATS_TEST_TMPDIR}/ticks"
  [[ "${output}" == "3" ]]
  run sourced "${WORK}/main.conf"
  [[ "${output}" == "1" ]]
  run cat "${copy}"
  [[ "${output}" == "set -g @x 2" ]]
}

@test "watch - with validate off the watcher keeps no copy" {
  # Arrange
  conf main.conf 'set -g @x 1'
  harness_hide fswatch inotifywait entr
  tmux_loads "$(printf '%s\t%s\t\t\t\t\t0\t\t\t\t\t\t42\t\t\t' "${WORK}/main.conf" "${WORK}/main.conf")"
  tool sleep "printf '\t\t\t\t\t\t\t\t\t\t\t\t77\t\t\t\n' >'${BATS_TEST_TMPDIR}/loaded'"

  # Act
  lib_run autoreload 'autoreload_revamped_watch'

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ ! -d "${HOME}/.tmux" ]]
}

@test "watch - apply starts a watcher and records its process id" {
  # Arrange
  tmux_loads ""

  # Act
  lib_run autoreload 'autoreload_revamped_apply; printf "%s" "$!"'

  # Assert
  [[ "${status}" -eq 0 ]]
  run grep '^set-option' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" =~ ^set-option\ -gq\ @autoreload_revamped_pid\ [0-9]+$ ]]
}

@test "watch - apply leaves a living watcher alone" {
  # Arrange
  tmux_loads "$(printf '\t\t\t\t\t\t\t\t\t\t\t\t42\t\t%s\t' "$$")"

  # Act
  lib_run autoreload 'autoreload_revamped_apply'

  # Assert
  [[ "${status}" -eq 0 ]]
  run grep -c '^set-option' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == "0" ]]
}

@test "watch - toggle pauses an active watcher and resumes a paused one" {
  # Arrange
  local script='autoreload_revamped_toggle; autoreload_revamped_toggle'

  # Act
  lib_run autoreload "${script}"

  # Assert
  run grep -e '^set-option' -e '^display-message [a-z]' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == $'set-option -gq @autoreload_revamped_paused 1\ndisplay-message autoreload paused\nset-option -gq @autoreload_revamped_paused 0\ndisplay-message autoreload resumed' ]]
}

@test "watch - the state names the pause, the living watcher and the backend" {
  # Arrange
  harness_hide fswatch inotifywait entr
  tmux_loads "$(printf '\t\t\t\t\t\t\t\t\t\t\t\t42\t1\t%s\t' "$$")"

  # Act
  lib_run autoreload 'autoreload_revamped_state'

  # Assert
  [[ "${output}" == "paused"$'\t'"$$"$'\t'"poll" ]]
}

@test "watch - the state of a fresh server is active with no watcher" {
  # Arrange
  harness_hide fswatch inotifywait entr
  tmux_loads "$(printf '\t\t\t\t\t\t\t\t\t\t\t\t42\t\t999999999\t')"

  # Act
  lib_run autoreload 'autoreload_revamped_state'

  # Assert
  [[ "${output}" == $'active\tnone\tpoll' ]]
}
