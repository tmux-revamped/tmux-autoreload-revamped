# shellcheck shell=bash
# shellcheck disable=SC2207

_autoreload_revamped() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  case "${prev}" in
  --theme)
    COMPREPLY=($(compgen -W "kodougu catppuccin-mocha catppuccin-latte dracula nord gruvbox tokyo-night mono" -- "${cur}"))
    return
    ;;
  --quiet)
    COMPREPLY=($(compgen -W "0 1" -- "${cur}"))
    return
    ;;
  --discover)
    COMPREPLY=($(compgen -W "0 1" -- "${cur}"))
    return
    ;;
  --atomic)
    COMPREPLY=($(compgen -W "0 1" -- "${cur}"))
    return
    ;;
  --validate)
    COMPREPLY=($(compgen -W "0 1" -- "${cur}"))
    return
    ;;
  --defer)
    COMPREPLY=($(compgen -W "0 1" -- "${cur}"))
    return
    ;;
  --selective)
    COMPREPLY=($(compgen -W "0 1" -- "${cur}"))
    return
    ;;
  --flash)
    COMPREPLY=($(compgen -W "0 1" -- "${cur}"))
    return
    ;;
  --notify)
    COMPREPLY=($(compgen -W "0 1" -- "${cur}"))
    return
    ;;
  --files | --entrypoints | --interval | --backup-dir)
    return
    ;;
  *) ;;
  esac

  COMPREPLY=($(compgen -W "apply watch reload pause resume toggle status doctor version help --json --theme --files --entrypoints --interval --quiet --discover --atomic --validate --defer --selective --flash --notify --backup-dir" -- "${cur}"))
}

complete -F _autoreload_revamped autoreload-revamped
