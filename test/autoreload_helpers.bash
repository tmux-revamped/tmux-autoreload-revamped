#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2030,SC2031,SC2034

# shellcheck source=test/helpers.bash
source "${BATS_TEST_DIRNAME:-.}/helpers.bash"

setup() {
  harness_setup
  for name in $(compgen -v AUTORELOAD_REVAMPED_); do
    unset "${name}"
  done
  WORK="${BATS_TEST_TMPDIR}/conf"
  export HOME="${BATS_TEST_TMPDIR}/home" WORK
  mkdir -p "${WORK}" "${HOME}" "${BATS_TEST_TMPDIR}/stubs"
  UNTRACED='{ set +x; } 2>/dev/null'
  quiet tmux "exec \"${REVAMPED_TESTS_DIR}/bin/tmux\" \"\$@\""
}

quiet() {
  printf '#!/bin/sh\n%s\n%s\n' "${UNTRACED}" "$2" >"${BATS_TEST_TMPDIR}/stubs/$1"
  chmod +x "${BATS_TEST_TMPDIR}/stubs/$1"
}

quiet_command() {
  quiet "$1" "for a in \"\$@\"; do printf '%s\n' \"\$a\"; done >>\"${BATS_TEST_TMPDIR}/$1.calls\""
}

option() {
  printf '%s' "$2" >"${REVAMPED_TEST_TMUX_DIR}/$(printf '%s' "g.-.@autoreload_revamped_$1" | tr -c 'A-Za-z0-9_.-' '_')"
}

conf() {
  local name="$1"
  shift
  mkdir -p "$(dirname "${WORK}/${name}")"
  printf '%s\n' "$@" >"${WORK}/${name}"
}

loaded() {
  lib_run autoreload "autoreload_revamped_load; $1"
}

tmux_refuses() {
  cat >"${BATS_TEST_TMPDIR}/stubs/tmux" <<EOF
#!/bin/sh
${UNTRACED}
if [ "\$1" = source-file ] && [ "\$2" = "$1" ]; then
  printf '%s\n' "\$*" >>"${REVAMPED_TEST_TMUX_LOG}"
  printf '%s\n' "$2" >&2
  exit 1
fi
exec "${REVAMPED_TESTS_DIR}/bin/tmux" "\$@"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/stubs/tmux"
}

copy_of() {
  local name
  name=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')
  printf '%s/.tmux/autoreload-revamped/backup/%s\n' "${HOME}" "${name}"
}

tmux_loads() {
  printf '%s\n' "$1" >"${BATS_TEST_TMPDIR}/loaded"
  cat >"${BATS_TEST_TMPDIR}/stubs/tmux" <<EOF
#!/bin/sh
${UNTRACED}
if [ "\$1" = display-message ] && [ "\$2" = -p ]; then
  cat "${BATS_TEST_TMPDIR}/loaded"
  exit 0
fi
exec "${REVAMPED_TESTS_DIR}/bin/tmux" "\$@"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/stubs/tmux"
}

tmux_saves_once() {
  cat >"${BATS_TEST_TMPDIR}/stubs/tmux" <<EOF
#!/bin/sh
${UNTRACED}
if [ "\$1" = source-file ] && [ ! -f "${BATS_TEST_TMPDIR}/saved" ]; then
  : >"${BATS_TEST_TMPDIR}/saved"
  printf '%s\n' "$2" >"$1"
fi
exec "${REVAMPED_TESTS_DIR}/bin/tmux" "\$@"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/stubs/tmux"
}

tmux_lists_panes() {
  cat >"${BATS_TEST_TMPDIR}/stubs/tmux" <<EOF
#!/bin/sh
${UNTRACED}
if [ "\$1" = list-panes ]; then
  printf '%s\n' $1
  exit 0
fi
exec "${REVAMPED_TESTS_DIR}/bin/tmux" "\$@"
EOF
  chmod +x "${BATS_TEST_TMPDIR}/stubs/tmux"
}

sourced() {
  grep -c "^source-file $1\$" "${REVAMPED_TEST_TMUX_LOG}" || :
}

said() {
  grep '^display-message ' "${REVAMPED_TEST_TMUX_LOG}" | grep -v '^display-message -p' || :
}
