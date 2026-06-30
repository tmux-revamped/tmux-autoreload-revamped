#!/usr/bin/env bash
#
# autoreload.sh: pure helpers for tmux-autoreload-revamped.
#
# Watcher selection, change detection, source-directive parsing, path
# normalization, and backoff math are pure. The real file watching, mtime reads,
# content hashing, and config sourcing sit behind seams in the dispatcher, so the
# tests touch no real watcher and reload no real config.

[[ -n "${_AUTORELOAD_REVAMPED_LOADED:-}" ]] && return 0
_AUTORELOAD_REVAMPED_LOADED=1

_AR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_AR_LIB_DIR}/../utils/has-command.sh"

# autoreload_select_watcher -> the best available watcher: fswatch (macOS and
# Linux), inotifywait (Linux), entr (cross-platform), or poll as the universal
# fallback.
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

# autoreload_changed OLD NEW -> "1" when the snapshots differ, else "0".
autoreload_changed() {
  if [[ "${1}" != "${2}" ]]; then
    echo "1"
  else
    echo "0"
  fi
}

# autoreload_split LIST -> LIST normalized to one path per line, splitting on
# commas and whitespace, with blanks and duplicates removed.
autoreload_split() {
  printf '%s' "${1}" | tr ',[:space:]' '\n' | awk 'NF && !seen[$0]++'
}

# autoreload_expand_path PATH -> PATH with a leading ~ expanded to $HOME, so a
# watch entry like ~/.tmux.conf resolves to a real file.
# shellcheck disable=SC2088 # the ~ patterns are matched literally, not expanded
autoreload_expand_path() {
  case "${1}" in
    "~") printf '%s' "${HOME}" ;;
    "~/"*) printf '%s/%s' "${HOME}" "${1#\~/}" ;;
    *) printf '%s' "${1}" ;;
  esac
}

# shellcheck disable=SC2088 # the ~ patterns are matched literally, not expanded
# autoreload_resolve PARENT CHILD -> CHILD made absolute. An absolute or ~ path
# is taken as-is; a relative path resolves against PARENT's directory, so a
# `source ./theme.conf` inside ~/.tmux.conf points at ~/theme.conf.
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

# autoreload_parse_sources -> read tmux config text on stdin, print every path
# referenced by a `source` or `source-file` directive, one per line. Leading
# flags such as -q are skipped and surrounding quotes are stripped.
autoreload_parse_sources() {
  awk '{ s=$0; sub(/^[[:space:]]+/,"",s); n=split(s,a," "); if((a[1]=="source"||a[1]=="source-file")&&n>=2){ p=a[n]; gsub(/^[\042\047]/,"",p); gsub(/[\042\047]$/,"",p); if(p!=""&&p!~/^-/) print p } }'
}

# autoreload_watch_dirs -> read a file list on stdin, print the unique parent
# directory of each entry. Watching the directory plus the basename catches the
# rename-on-save dance most editors use.
autoreload_watch_dirs() {
  awk 'NF{ p=$0; sub(/\/[^/]*$/,"",p); if(p=="") p="/"; if(!seen[p]++) print p }'
}

# autoreload_diff_files OLD NEW -> print every file in NEW whose mtime differs
# from OLD or is absent from OLD. Each snapshot is "<file> <mtime>" lines.
autoreload_diff_files() {
  awk 'NR==FNR{m[$1]=$2;seen[$1]=1;next} NF{ if(!seen[$1]||m[$1]!=$2) print $1 }' <(printf '%s\n' "${1}") <(printf '%s\n' "${2}")
}

# autoreload_backoff_delay BASE FAILS MAX -> seconds to wait before the next poll
# tick. Zero or one failure returns BASE; each further consecutive failure
# doubles the delay, capped at MAX.
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
