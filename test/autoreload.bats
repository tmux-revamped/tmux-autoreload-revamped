#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2030,SC2031,SC2034

# shellcheck source=test/autoreload_helpers.bash
source "${BATS_TEST_DIRNAME:-.}/autoreload_helpers.bash"

@test "autoreload - a list splits on commas, spaces and tabs, drops repeats and expands the home folder" {
  # Arrange
  local script='autoreload_revamped_split "/a.conf, ~/b.conf	~ /a.conf"'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == "/a.conf"$'\n'"${HOME}/b.conf"$'\n'"${HOME}" ]]
}

@test "autoreload - the files a config sources are read from source and source-file lines" {
  # Arrange
  conf main.conf 'set -g status on' '  source-file -q "sub/a.conf"' "source 'b.conf'" 'source-file /abs/c.conf' 'source-file ~/d.conf' 'source-file ~' '# source-file skipped.conf' 'source-file' 'bind r source-file -F'

  # Act
  lib_run autoreload "autoreload_revamped_children '${WORK}/main.conf'"

  # Assert
  [[ "${output}" == "${WORK}/sub/a.conf"$'\n'"${WORK}/b.conf"$'\n'"/abs/c.conf"$'\n'"${HOME}/d.conf"$'\n'"${HOME}" ]]
}

@test "autoreload - a file named without a folder sources relative to the current one" {
  # Arrange
  conf main.conf 'source-file sub.conf'

  # Act
  lib_run autoreload "cd '${WORK}' && autoreload_revamped_children main.conf"

  # Assert
  [[ "${output}" == "./sub.conf" ]]
}

@test "autoreload - discovery follows sourced files through every level, once each, and skips missing ones" {
  # Arrange
  conf main.conf "source-file ${WORK}/a.conf" "source-file ${WORK}/gone.conf"
  conf a.conf "source-file ${WORK}/b.conf" "source-file ${WORK}/main.conf"
  conf b.conf 'set -g @x 1'

  # Act
  lib_run autoreload "autoreload_revamped_discover '${WORK}/main.conf'"

  # Assert
  [[ "${output}" == "${WORK}/main.conf"$'\n'"${WORK}/a.conf"$'\n'"${WORK}/b.conf" ]]
}

@test "autoreload - discovery stops eight levels below the first file" {
  # Arrange
  local level
  for level in 0 1 2 3 4 5 6 7 8 9; do
    conf "l${level}.conf" "source-file ${WORK}/l$((level + 1)).conf"
  done

  # Act
  lib_run autoreload "autoreload_revamped_discover '${WORK}/l0.conf' | wc -l | tr -d ' '"

  # Assert
  [[ "${output}" == "9" ]]
}

@test "autoreload - the watched files are the ones tmux loaded and what they source" {
  # Arrange
  conf main.conf "source-file ${WORK}/a.conf"
  conf a.conf 'set -g @x 1'
  tmux_loads "$(printf '\t\t\t\t\t\t\t\t\t\t\t\t42\t\t\t%s' "${WORK}/main.conf,${WORK}/gone.conf")"

  # Act
  loaded 'autoreload_revamped_files; printf "[%s]" "${AUTORELOAD_REVAMPED_S_server}"; autoreload_revamped_entrypoints'

  # Assert
  [[ "${output}" == "${WORK}/main.conf"$'\n'"${WORK}/a.conf"$'\n'"[42]${WORK}/main.conf" ]]
}

@test "autoreload - a loaded config and a backup folder keep the space in their path" {
  # Arrange
  conf "my conf/main.conf" 'set -g @x 1'
  tmux_loads "$(printf '\t\t\t\t\t\t\t\t\t\t\t~/last good\t42\t\t\t%s' "${WORK}/my conf/main.conf")"

  # Act
  loaded 'autoreload_revamped_files; autoreload_revamped_entrypoints; autoreload_revamped_backup_dir'

  # Assert
  [[ "${output}" == "${WORK}/my conf/main.conf"$'\n'"${WORK}/my conf/main.conf"$'\n'"${HOME}/last good" ]]
}

@test "autoreload - the files option replaces the loaded ones, and discover off keeps to them" {
  # Arrange
  conf one.conf "source-file ${WORK}/a.conf"
  conf a.conf 'set -g @x 1'
  option files "${WORK}/one.conf ${WORK}/gone.conf"
  option discover 0

  # Act
  loaded 'autoreload_revamped_files'

  # Assert
  [[ "${output}" == "${WORK}/one.conf" ]]
}

@test "autoreload - the entrypoints option names what a reload sources" {
  # Arrange
  option entrypoints "${WORK}/x.conf,~/y.conf"

  # Act
  loaded 'autoreload_revamped_entrypoints'

  # Assert
  [[ "${output}" == "${WORK}/x.conf"$'\n'"${HOME}/y.conf" ]]
}

@test "autoreload - a snapshot changes with a file's bytes, not with a save that leaves them alone" {
  # Arrange
  conf a.conf 'set -g @x 1'
  conf b.conf 'set -g @y 1'
  local script='files=$(printf "%s\n" "'"${WORK}"'/a.conf" "'"${WORK}"'/b.conf"); one=$(autoreload_revamped_snapshot "${files}"); touch "'"${WORK}"'/a.conf"; two=$(autoreload_revamped_snapshot "${files}"); printf "set -g @y 2\n" >"'"${WORK}"'/b.conf"; three=$(autoreload_revamped_snapshot "${files}"); [ "${one}" = "${two}" ] && printf "same\n"; autoreload_revamped_changed "${one}" "${three}"'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == "same"$'\n'"${WORK}/b.conf" ]]
}

@test "autoreload - a new file counts as changed, a removed one does not, and no file means no snapshot" {
  # Arrange
  conf a.conf 'set -g @x 1'
  conf "b c.conf" 'set -g @y 1'
  local script='one=$(autoreload_revamped_snapshot "'"${WORK}"'/a.conf"); two=$(autoreload_revamped_snapshot "'"${WORK}"'/b c.conf"); autoreload_revamped_changed "${one}" "${two}"; printf "[%s]" "$(autoreload_revamped_snapshot "")" "$(autoreload_revamped_changed "${one}" "")"'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == "${WORK}/b c.conf"$'\n'"[][]" ]]
}

@test "autoreload - the folders of the files are each listed once, the root included" {
  # Arrange
  local script='printf "%s\n" /etc/a.conf /etc/b.conf /c.conf plain | autoreload_revamped_folders'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == $'/etc\n/' ]]
}

@test "autoreload - the watcher's targets are the files and their folders, or the files alone with atomic off" {
  # Arrange
  local script='AUTORELOAD_REVAMPED_FILES=/etc/a.conf; autoreload_revamped_targets; AUTORELOAD_REVAMPED_S_atomic=0; autoreload_revamped_targets'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == $'/etc/a.conf\n/etc\n/etc/a.conf' ]]
}

@test "autoreload - selective picks the entry points whose tree holds the changed file, or all of them" {
  # Arrange
  conf one.conf "source-file ${WORK}/shared.conf"
  conf two.conf 'set -g @y 1'
  conf shared.conf 'set -g @x 1'
  option entrypoints "${WORK}/one.conf ${WORK}/two.conf"

  # Act
  loaded "autoreload_revamped_affected '${WORK}/shared.conf'; printf -- '--\n'; autoreload_revamped_affected '${WORK}/other.conf'"

  # Assert
  [[ "${output}" == "${WORK}/one.conf"$'\n'"--"$'\n'"${WORK}/one.conf"$'\n'"${WORK}/two.conf" ]]
}

@test "autoreload - the last good copies live under the home folder, or where the option says" {
  # Arrange
  local script='autoreload_revamped_backup_dir; AUTORELOAD_REVAMPED_S_backup_dir="~/keep"; autoreload_revamped_backup_dir; autoreload_revamped_backup_of /keep "/etc/tmux conf/a.conf"'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == "${HOME}/.tmux/autoreload-revamped/backup"$'\n'"${HOME}/keep"$'\n'"/keep/_etc_tmux_conf_a.conf" ]]
}

@test "autoreload - a reload that works sources each entry point and keeps a copy of it" {
  # Arrange
  local copy
  conf one.conf 'set -g @x 1'
  conf two.conf 'set -g @y 1'
  option entrypoints "${WORK}/one.conf ${WORK}/two.conf ${WORK}/gone.conf"
  copy=$(copy_of "${WORK}/one.conf")

  # Act
  loaded 'autoreload_revamped_reload'

  # Assert
  [[ "${status}" -eq 0 ]]
  run sourced "${WORK}/one.conf"
  [[ "${output}" == "1" ]]
  run sourced "${WORK}/two.conf"
  [[ "${output}" == "1" ]]
  run cat "${copy}"
  [[ "${output}" == "set -g @x 1" ]]
  run said
  [[ "${output}" == "display-message tmux config reloaded (one.conf +2 more)" ]]
}

@test "autoreload - with validate off no copy is kept" {
  # Arrange
  conf one.conf 'set -g @x 1'
  option entrypoints "${WORK}/one.conf"
  option validate 0

  # Act
  loaded 'autoreload_revamped_reload'

  # Assert
  [[ "${status}" -eq 0 ]]
  [[ ! -d "${HOME}/.tmux" ]]
}

@test "autoreload - a reload that fails shows the first line of the error with its hashes doubled, sources the last good copy and stops" {
  # Arrange
  local copy
  conf one.conf 'bogus'
  conf two.conf 'set -g @y 1'
  option entrypoints "${WORK}/one.conf ${WORK}/two.conf"
  copy=$(copy_of "${WORK}/one.conf")
  mkdir -p "$(dirname "${copy}")"
  printf 'set -g @x 1\n' >"${copy}"
  tmux_refuses "${WORK}/one.conf" "one.conf:1: unknown command: #bogus"$'\n'"second line"

  # Act
  loaded 'autoreload_revamped_reload'

  # Assert
  [[ "${status}" -eq 1 ]]
  run said
  [[ "${output}" == "display-message tmux config error in one.conf: one.conf:1: unknown command: ##bogus" ]]
  run sourced "${copy}"
  [[ "${output}" == "1" ]]
  run sourced "${WORK}/two.conf"
  [[ "${output}" == "0" ]]
}

@test "autoreload - a failure with no copy, or with validate off, sources nothing else" {
  # Arrange
  conf one.conf 'bogus'
  option entrypoints "${WORK}/one.conf"
  option validate 0
  tmux_refuses "${WORK}/one.conf" ""

  # Act
  loaded 'autoreload_revamped_reload; AUTORELOAD_REVAMPED_S_validate=1; autoreload_revamped_fail "'"${WORK}"'/one.conf" ""'

  # Assert
  run said
  [[ "${output}" == "display-message tmux config error in one.conf"$'\n'"display-message tmux config error in one.conf" ]]
  run grep -c '^source-file' "${REVAMPED_TEST_TMUX_LOG}"
  [[ "${output}" == "1" ]]
}

@test "autoreload - the message names the file, can be hidden, flashed or sent as a notification" {
  # Arrange
  stub_command osascript
  stub_command notify-send
  local script='autoreload_revamped_announce /etc/a.conf; AUTORELOAD_REVAMPED_S_quiet=1 AUTORELOAD_REVAMPED_S_flash=1 AUTORELOAD_REVAMPED_S_notify=1; autoreload_revamped_announce /etc/b.conf'

  # Act
  lib_run autoreload "${script}"

  # Assert
  run said
  [[ "${output}" == "display-message tmux config reloaded (a.conf)"$'\n'"display-message #[reverse]tmux config reloaded (b.conf)#[default]" ]]
  run cat "${BATS_TEST_TMPDIR}/osascript.calls" "${BATS_TEST_TMPDIR}/notify-send.calls"
  [[ "${output}" == *"tmux config reloaded (b.conf)"* ]]
}

@test "autoreload - a pane in any mode makes the server busy" {
  # Arrange
  tmux_lists_panes '0 1 0'

  # Act
  lib_run autoreload 'autoreload_revamped_busy && printf busy'

  # Assert
  [[ "${output}" == "busy" ]]
}

@test "autoreload - no pane in a mode leaves it free" {
  # Arrange
  tmux_lists_panes '0 0'

  # Act
  lib_run autoreload 'autoreload_revamped_busy || printf free'

  # Assert
  [[ "${output}" == "free" ]]
}

@test "autoreload - the interval is a whole number above zero, or two seconds" {
  # Arrange
  local script='for value in 5 0 "" x 1.5; do AUTORELOAD_REVAMPED_S_interval="${value}"; autoreload_revamped_interval; done | paste -sd " " -'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == "5 2 2 2 2" ]]
}

@test "autoreload - the backend is fswatch, then inotifywait, then entr, then polling" {
  # Arrange
  harness_hide fswatch inotifywait entr
  stub_command fswatch
  stub_command inotifywait
  stub_command entr
  local script='autoreload_revamped_backend; rm -f "'"${BATS_TEST_TMPDIR}"'/stubs/fswatch"; hash -r; autoreload_revamped_backend; rm -f "'"${BATS_TEST_TMPDIR}"'/stubs/inotifywait"; hash -r; autoreload_revamped_backend'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == $'fswatch\ninotifywait\nentr' ]]
}

@test "autoreload - with no watcher tool it polls" {
  # Arrange
  harness_hide fswatch inotifywait entr

  # Act
  lib_run autoreload 'autoreload_revamped_backend'

  # Assert
  [[ "${output}" == "poll" ]]
}

@test "autoreload - a setting name comes from its long option" {
  # Arrange
  local script='printf "[%s]" "$(autoreload_revamped_setting_name --backup-dir)" "$(autoreload_revamped_setting_name --nope)"'

  # Act
  lib_run autoreload "${script}"

  # Assert
  [[ "${output}" == "[backup_dir][]" ]]
}

@test "autoreload - a setting comes from the environment, then the tmux option, then its default" {
  # Arrange
  option interval 7
  option quiet 1
  export AUTORELOAD_REVAMPED_INTERVAL=9

  # Act
  loaded 'printf "%s %s %s" "${AUTORELOAD_REVAMPED_S_interval}" "${AUTORELOAD_REVAMPED_S_quiet}" "${AUTORELOAD_REVAMPED_S_defer}"'

  # Assert
  [[ "${output}" == "9 1 1" ]]
}
