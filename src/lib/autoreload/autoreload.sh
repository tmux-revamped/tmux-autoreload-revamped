#!/usr/bin/env bash

[[ -n "${_AUTORELOAD_REVAMPED_LOADED:-}" ]] && return 0
_AUTORELOAD_REVAMPED_LOADED=1

_AR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_AR_LIB_DIR}/../utils/has-command.sh"

autoreload_select_watcher() {
  if has_command fswatch; then
    echo "fswatch"
  elif has_command inotifywait; then
    echo "inotifywait"
  elif has_command entr; then
    echo "entr"
  else
    echo "poll"
  fi
}

autoreload_changed() {
  if [[ "${1}" != "${2}" ]]; then
    echo "1"
  else
    echo "0"
  fi
}

autoreload_split() {
  printf '%s' "${1}" | tr ',[:space:]' '\n' | awk 'NF && !seen[$0]++'
}

# shellcheck disable=SC2088 # the ~ patterns are matched literally, not expanded
autoreload_expand_path() {
  case "${1}" in
    "~") printf '%s' "${HOME}" ;;
    "~/"*) printf '%s/%s' "${HOME}" "${1#\~/}" ;;
    *) printf '%s' "${1}" ;;
  esac
}

# shellcheck disable=SC2088 # the ~ patterns are matched literally, not expanded
autoreload_resolve() {
  local parent="${1}" child="${2}" dir
  case "${child}" in
    "~"|"~/"*) autoreload_expand_path "${child}" ;;
    /*) printf '%s' "${child}" ;;
    *)
      dir="${parent%/*}"
      [[ "${dir}" == "${parent}" ]] && dir="."
      printf '%s/%s' "${dir}" "${child}"
      ;;
  esac
}

autoreload_parse_sources() {
  awk '{ s=$0; sub(/^[[:space:]]+/,"",s); n=split(s,a," "); if((a[1]=="source"||a[1]=="source-file")&&n>=2){ p=a[n]; gsub(/^[\042\047]/,"",p); gsub(/[\042\047]$/,"",p); if(p!=""&&p!~/^-/) print p } }'
}

autoreload_watch_dirs() {
  local line parent seen=""
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    parent="${line%/*}"
    [[ "${parent}" == "${line}" ]] || [[ -n "${parent}" ]] || parent="/"
    case " ${seen} " in *" ${parent} "*) continue ;; esac
    seen="${seen} ${parent}"
    printf '%s\n' "${parent}"
  done
}

autoreload_diff_files() {
  awk 'NR==FNR{m[$1]=$2;seen[$1]=1;next} NF{ if(!seen[$1]||m[$1]!=$2) print $1 }' <(printf '%s\n' "${1}") <(printf '%s\n' "${2}")
}

autoreload_backoff_delay() {
  local base="${1}" fails="${2}" max="${3}" d i
  [[ "${base}" =~ ^[0-9]+$ ]] || base=2
  [[ "${fails}" =~ ^[0-9]+$ ]] || fails=0
  [[ "${max}" =~ ^[0-9]+$ ]] || max=30
  d="${base}"
  i=1
  while (( i < fails )); do
    d=$(( d * 2 ))
    if (( d >= max )); then d="${max}"; break; fi
    i=$(( i + 1 ))
  done
  echo "${d}"
}

export -f autoreload_select_watcher
export -f autoreload_changed
export -f autoreload_split
export -f autoreload_expand_path
export -f autoreload_resolve
export -f autoreload_parse_sources
export -f autoreload_watch_dirs
export -f autoreload_diff_files
export -f autoreload_backoff_delay
