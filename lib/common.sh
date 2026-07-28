# loomo — shared helpers (colors, banner/note/ok/warn, abspath)
# sourced by bin/tell (not standalone). shell: bash

# Terminal width for CLI chrome — matches the dashboard's full-width rules so a
# banner never stops short mid-screen. Falls back to 52 off a TTY (pipes/logs).
_term_cols() {
  local c=""
  [ -t 1 ] && c=$(tput cols 2>/dev/null)
  case "$c" in ''|*[!0-9]*) c=52 ;; esac
  [ "$c" -lt 20 ] && c=20
  printf '%s' "$c"
}
_rule() { # $1=width $2=glyph(default ═) → a horizontal rule that fills the width
  local n="$1" ch="${2:-═}" out=""
  while [ "$n" -gt 0 ]; do out="$out$ch"; n=$((n-1)); done
  printf '%s' "$out"
}
banner() {
  local w; w=$(_term_cols)
  echo ""
  echo "${C_C}${C_B}$(_rule "$w")${C_X}"
  echo "${C_C}${C_B}   🔗 $BRAND — $1${C_X}"
  echo "${C_C}${C_B}$(_rule "$w")${C_X}"
}

step() { echo ""; echo "${C_Y}${C_B}▶ $1${C_X}"; }
note() { echo "${C_D}  $1${C_X}"; }
ok()   { echo "${C_G}  ✔ $1${C_X}"; }
skip() { echo "${C_D}  ⤼ $1${C_X}"; }
warn() { echo "${C_R}  ⚠ $1${C_X}"; }
ask()  { printf "%s" "${C_B}$1${C_X}"; }
abspath() { # ~ 확장 + 상대경로 → 절대경로 (실행 위치가 달라도 설정이 항상 유효하도록)
  local d="$1"; d=${d/#\~/$HOME}
  case "$d" in ""|/*) ;; *) d="$PWD/$d" ;; esac
  printf '%s' "$d"
}

# Should delegated claude panes skip the approval classifier (bypassPermissions)?
# The LOOMO_CLAUDE_BYPASS env var wins; otherwise the value persisted by the
# dashboard Settings toggle ($CONFIG_DIR/claude-bypass); default off.
_claude_bypass_on() {
  case "${LOOMO_CLAUDE_BYPASS:-_}" in
    1|true|yes|on) return 0 ;;
    0|false|no|off) return 1 ;;
  esac
  local v=""; [ -f "$CONFIG_DIR/claude-bypass" ] && read -r v < "$CONFIG_DIR/claude-bypass" 2>/dev/null
  [ "$v" = 1 ]
}

# loomo window theme: auto (follow the terminal), dark, or light. LOOMO_THEME env
# wins; otherwise the dashboard-persisted value ($CONFIG_DIR/theme); default auto.
# auto renders on the terminal's own colors; dark/light force loomo's own windows
# (dashboard + spawned session terminals) so it works on any terminal, no terminal
# config needed.
_loomo_theme() {
  local t="${LOOMO_THEME:-}"
  case "$t" in dark|light|auto) printf '%s' "$t"; return ;; esac
  [ -f "$CONFIG_DIR/theme" ] && read -r t < "$CONFIG_DIR/theme" 2>/dev/null
  case "$t" in dark|light) printf '%s' "$t" ;; *) printf 'auto' ;; esac
}
# Model every pane of an agent should launch with; empty = let the CLI decide.
# Env (LOOMO_CLAUDE_MODEL / LOOMO_CODEX_MODEL) wins over the dashboard setting.
_loomo_model() { # $1=claude|codex
  local m=""
  case "${1:-}" in
    claude) m="${LOOMO_CLAUDE_MODEL:-}" ;;
    codex)  m="${LOOMO_CODEX_MODEL:-}" ;;
    *) return ;;
  esac
  [ -n "$m" ] || { [ -f "$CONFIG_DIR/model-$1" ] && read -r m < "$CONFIG_DIR/model-$1" 2>/dev/null; }
  # Only a bare model name/alias — it is interpolated into launch commands.
  case "$m" in auto|"") return ;; *[!A-Za-z0-9._-]*) return ;; esac
  printf '%s' "$m"
}
# Concrete model the newest claude conversation actually ran on. Aliases like
# 'opus' only say "the latest one", so this shows which version that resolved to.
_loomo_recent_model() {
  node -e '
    const fs=require("fs"), os=require("os"), path=require("path");
    const root=path.join(os.homedir(),".claude","projects");
    let newest=null, newestAt=0;
    let dirs=[]; try { dirs=fs.readdirSync(root); } catch { process.exit(0); }
    for (const d of dirs) {
      let files=[]; try { files=fs.readdirSync(path.join(root,d)); } catch { continue; }
      for (const f of files) {
        if (!f.endsWith(".jsonl")) continue;
        const p=path.join(root,d,f);
        try { const s=fs.statSync(p); if (s.mtimeMs>newestAt) { newestAt=s.mtimeMs; newest=p; } } catch {}
      }
    }
    if (!newest) process.exit(0);
    // Read only the tail — these transcripts grow to many MB.
    let buf="";
    try {
      const fd=fs.openSync(newest,"r"); const size=fs.statSync(newest).size;
      const len=Math.min(size, 256*1024); const b=Buffer.alloc(len);
      fs.readSync(fd, b, 0, len, size-len); fs.closeSync(fd); buf=b.toString("utf8");
    } catch { process.exit(0); }
    const lines=buf.split("\n").reverse();
    for (const line of lines) {
      try { const o=JSON.parse(line); const m=o.message&&o.message.model; if (m) { process.stdout.write(m); break; } } catch {}
    }
  ' 2>/dev/null
}
# OSC 10/11 that forces a window's fg/bg for the chosen theme; empty for auto.
_theme_osc() {
  case "$(_loomo_theme)" in
    dark)  printf '\033]10;#f2f2f2\007\033]11;#000000\007' ;;
    light) printf '\033]10;#1a1a1a\007\033]11;#f2f2f2\007' ;;
  esac
}

# Persistent diagnostics for background/UI actions whose stderr is otherwise
# hidden by AppleScript or the dashboard's alternate screen.
LOOMO_LOG_FILE="${LOOMO_LOG_FILE:-$CONFIG_DIR/loomo.log}"
loomo_log() { # $1=level $2=event, remaining args are key=value details
  local level="${1:-INFO}" event="${2:-event}" arg line size=0
  shift 2 2>/dev/null || true
  mkdir -p "$CONFIG_DIR" 2>/dev/null || return 0
  [ -f "$LOOMO_LOG_FILE" ] && size=$(wc -c <"$LOOMO_LOG_FILE" 2>/dev/null || printf 0)
  if [ "${size:-0}" -ge 1048576 ]; then
    mv -f "$LOOMO_LOG_FILE" "$LOOMO_LOG_FILE.1" 2>/dev/null || true
  fi
  line="$(date '+%Y-%m-%dT%H:%M:%S%z') level=$level event=$event pid=$$"
  for arg in "$@"; do
    arg=${arg//$'\n'/\\n}; arg=${arg//$'\r'/\\r}
    line="$line $arg"
  done
  printf '%s\n' "$line" >>"$LOOMO_LOG_FILE" 2>/dev/null || true
}

set_pane_role() { # stable title for the private loomo tmux border
  local pane="$1" role="$2"
  tmux select-pane -t "$pane" -T "$role" 2>/dev/null || return 1
  tmux set-option -p -t "$pane" @loomo_role "$role" 2>/dev/null || true
}
