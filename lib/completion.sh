# loomo — shell completion
# sourced by bin/tell (not standalone). shell: bash

cmd_completion() { # 셸 자동완성 스크립트 출력 — .zshrc/.bashrc에: eval "$(tell completion)"
  cat <<'EOS'
# loomo completion (bash/zsh) — eval "$(loomo completion)"
if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -U +X compinit bashcompinit
  whence -w compdef >/dev/null 2>&1 || compinit -u 2>/dev/null
  bashcompinit
fi
_tell_conf() {
  local d="${TELL_CONFIG_DIR:-}"
  if [ -z "$d" ]; then
    if [ -d "$HOME/.config/claude-tell-bridge" ] && [ ! -d "$HOME/.config/loomo" ]; then d="$HOME/.config/claude-tell-bridge"; else d="$HOME/.config/loomo"; fi
  fi
  printf '%s' "$d/workspaces.conf"
}
_tell_tmux() {
  local conf mode
  conf=$(_tell_conf); mode=$(dirname "$conf")/tmux-mode
  if { [ -f "$mode" ] && [ "$(cat "$mode" 2>/dev/null)" = dedicated ]; } || { [ ! -f "$mode" ] && [ ! -f "$conf" ]; }; then command tmux -L "${LOOMO_TMUX_SOCKET:-loomo}" "$@"
  else command tmux "$@"; fi
}
_tell_sessions() {
  local conf; conf=$(_tell_conf)
  { _tell_tmux list-sessions -F '#{session_name}' 2>/dev/null
    [ -f "$conf" ] && grep -vE '^[[:space:]]*(#|$)' "$conf" | cut -d'|' -f1
  } | sort -u
}
_tell_roles() { # $1=세션 — 떠 있는 패널 제목 + 설정된 역할
  local conf; conf=$(_tell_conf)
  { _tell_tmux list-panes -t "=$1" -F '#{pane_title}' 2>/dev/null
    [ -f "$conf" ] && LC_ALL=C awk -F'|' -v s="$1" '$1==s{print $2}' "$conf"
  } | sort -u
}
_tell() {
  local cur="${COMP_WORDS[COMP_CWORD]}" idx=1
  [ "${COMP_WORDS[1]:-}" = "-r" ] && idx=3   # -r <KEY> 만큼 위치가 밀림
  local pos=$((COMP_CWORD - idx + 1)) first="${COMP_WORDS[$idx]:-}"
  COMPREPLY=()
  local LAYOUTS="tiled main-vertical main-horizontal even-horizontal even-vertical"
  if [ "$pos" -eq 1 ]; then
    COMPREPLY=($(compgen -W "$(_tell_sessions) add adopt hub up down layout ws list rm task skill account sync tmux doctor completion update restart help -r" -- "$cur"))
  elif [ "$pos" -eq 2 ]; then
    case "$first" in
      ws|rm) COMPREPLY=($(compgen -W "$(_tell_sessions)" -- "$cur")) ;;
      up) COMPREPLY=($(compgen -W "$(_tell_sessions) --all --tabs" -- "$cur")) ;;
      down) COMPREPLY=($(compgen -W "$(_tell_sessions) --all" -- "$cur")) ;;
      layout) COMPREPLY=($(compgen -W "$(_tell_sessions) $LAYOUTS" -- "$cur")) ;;
      task) COMPREPLY=($(compgen -W "list ack status" -- "$cur")) ;;
      skill) COMPREPLY=($(compgen -W "add delete list" -- "$cur")) ;;
      account) COMPREPLY=($(compgen -W "list add use login logout" -- "$cur")) ;;
      tmux) COMPREPLY=($(compgen -W "status dedicated legacy" -- "$cur")) ;;
      doctor) COMPREPLY=($(compgen -W "--fix" -- "$cur")) ;;
      hub) COMPREPLY=($(compgen -W "status" -- "$cur")) ;;
      add|adopt|list|sync|completion|update|restart|help|-r) ;;
      *) COMPREPLY=($(compgen -W "$(_tell_roles "$first")" -- "$cur")) ;;
    esac
  elif [ "$pos" -eq 3 ]; then
    case "$first" in
      layout) COMPREPLY=($(compgen -W "$LAYOUTS" -- "$cur")) ;;
      account) COMPREPLY=($(compgen -W "claude codex" -- "$cur")) ;;
    esac
  fi
}
complete -F _tell tell loomo
EOS
  # show the how-to only when run directly in a terminal (silent when captured by eval)
  [ -t 1 ] && echo "# enable: echo 'eval \"\$(loomo completion)\"' >> ~/.zshrc  (bash: ~/.bashrc)" >&2
  return 0
}
