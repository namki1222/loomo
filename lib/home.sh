# loomo — home dashboard TUI (loomo with no args). 초보자용: 모든 것을 메인 패널 안에서, 채팅창 입력으로.
# sourced by bin/tell (not standalone). shell: bash
#
# row1 = loomo+경로 · row2 = 메뉴(탭) · row3 = 구분선 · 왼쪽 = 탭 콘텐츠 + 하단 채팅 · 오른쪽 = 2:1:1:1 패널
# 전부 절대좌표. Sessions는 프로젝트/미배정 패널과 세션별 Layout, Settings는 Hub와 AI 계정 설정.

cmd_home() {
  local needs_setup=0
  [ "$(uname)" = Darwin ] && ! command -v brew >/dev/null 2>&1 && needs_setup=1
  type -P tmux >/dev/null 2>&1 || needs_setup=1
  # claude는 '명령 존재'만이 아니라 '실제 동작'까지 본다 — 네이티브 바이너리가
  # 빠진 반쪽 설치도 첫 설정(cmd_init)이 감지·복구하도록 needs_setup을 켠다.
  { command -v claude >/dev/null 2>&1 && claude --version >/dev/null 2>&1; } || needs_setup=1
  command -v codex >/dev/null 2>&1 || needs_setup=1

  if [ "$needs_setup" = 1 ] && [ -t 0 ] && [ -t 1 ]; then
    banner "welcome · first-time setup"
    echo ""
    note "loomo will prepare tmux and an AI CLI before opening the dashboard."
    echo ""
    cmd_init || true
  fi

  if [ "$(uname)" = Darwin ] && ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew is required before the dashboard can open"
    note "fix the issue above, then run loomo again"
    return 1
  fi
  if ! type -P tmux >/dev/null 2>&1; then
    warn "tmux is required to open the loomo dashboard"
    note "fix the issue above, then run loomo again"
    return 1
  fi
  if ! command -v claude >/dev/null 2>&1; then
    warn "Claude Code installation is not complete"
    note "fix the issue above, then run loomo again"
    return 1
  fi
  if ! command -v codex >/dev/null 2>&1; then
    warn "Codex installation is not complete"
    note "fix the issue above, then run loomo again"
    return 1
  fi
  if [ -t 0 ] && [ -t 1 ] && { : </dev/tty; } 2>/dev/null; then
    _dash_autosync
    # Run the dashboard as a pane of loomo's own tmux server. That is what lets
    # the Hub tab pull the hub's pane in beside it as a real pane instead of a
    # redrawn copy — a pane can only live inside a tmux window.
    if [ "${LOOMO_DASH_PANE:-0}" != 1 ] && ! inside_loomo_tmux; then
      _dash_in_tmux; return $?
    fi
    _dashboard; return $?
  fi
  cmd_help
}

DASH_SESSION="${LOOMO_DASH_SESSION:-__loomo_dash}"

# Host the dashboard in its own tmux session, then attach to it. Re-running loomo
# reattaches instead of stacking a second dashboard.
_dash_in_tmux() {
  local sz rows cols
  sz=$(stty size </dev/tty 2>/dev/null); rows=${sz%% *}; cols=${sz##* }
  [ -n "$rows" ] || rows=40; [ -n "$cols" ] || cols=120
  if ! tmux has-session -t "=$DASH_SESSION" 2>/dev/null; then
    tmux new-session -d -s "$DASH_SESSION" -x "$cols" -y "$rows" \
      "LOOMO_DASH_PANE=1 $(printf '%q' "$0")" 2>/dev/null || {
        warn "could not start the dashboard session"; return 1; }
    tmux set-option -t "=$DASH_SESSION" status off 2>/dev/null
    # The dashboard owns this window; keep tmux from renaming or killing it early.
    tmux set-option -t "=$DASH_SESSION" destroy-unattached off 2>/dev/null
  fi
  tmux attach -t "=$DASH_SESSION"
}

# Refresh every project's convention once when the templates or hub changed since
# the last dashboard launch (e.g. after 'loomo update'), so panes get the current
# convention without anyone remembering to run 'loomo sync'. Silent, and guarded
# by a stamp so unchanged launches stay instant. Disable with LOOMO_AUTOSYNC=0.
_conventions_stamp() {
  local f out=""
  for f in "$TEMPLATE_DIR"/CLAUDE-section-*.md "$HUB_FILE"; do
    [ -e "$f" ] || continue
    out="$out$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null):"
  done
  printf '%s' "$out"
}
_dash_autosync() {
  [ "${LOOMO_AUTOSYNC:-1}" != 0 ] || return 0
  [ -f "$WS_CONF" ] || return 0
  local stamp_file="$CONFIG_DIR/sync-stamp" cur prev=""
  cur=$(_conventions_stamp)
  [ -f "$stamp_file" ] && read -r prev < "$stamp_file" 2>/dev/null
  [ "$cur" = "$prev" ] && return 0
  cmd_sync >/dev/null 2>&1 || true
  mkdir -p "$CONFIG_DIR" 2>/dev/null && printf '%s\n' "$cur" > "$stamp_file" 2>/dev/null || true
}

_usage_dir() {
  local root="$1"; [ -d "$root" ] || { printf '—|—|0|0'; return; }
  local out; out=$(python3 - "$root" <<'PY'
import sys,os,json,glob,datetime,signal
signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError()))
signal.alarm(3)
root=sys.argv[1]; today=datetime.date.today(); tin=tout=0; is_codex=root.endswith('/sessions')
for f in glob.glob(os.path.join(root,'**','*.jsonl'),recursive=True):
    try:
        if datetime.date.fromtimestamp(os.path.getmtime(f))!=today: continue
    except OSError: continue
    try:
        last_total=None
        for line in open(f,encoding='utf-8',errors='ignore'):
            if 'token' not in line and '"usage"' not in line: continue
            try: o=json.loads(line)
            except Exception: continue
            if is_codex:
                info=(o.get('payload') or {}).get('info') or {}
                if isinstance(info,dict) and isinstance(info.get('total_token_usage'),dict): last_total=info['total_token_usage']
                continue
            u=(o.get('message') or {}).get('usage') or o.get('usage') or o.get('token_usage') or {}
            if isinstance(u,dict) and u:
                tin+=u.get('input_tokens',0)+u.get('cache_read_input_tokens',0)+u.get('cache_creation_input_tokens',0)+u.get('prompt_tokens',0)
                tout+=u.get('output_tokens',0)+u.get('completion_tokens',0)
        if is_codex and last_total:
            tin+=last_total.get('input_tokens',0); tout+=last_total.get('output_tokens',0)
    except OSError: continue
h=lambda n: f"{n/1e6:.1f}M" if n>=1e6 else (f"{n/1e3:.0f}k" if n>=1e3 else str(n))
total=tin+tout
print(f"{h(tin)}|{h(tout)}|{round(tin*100/total) if total else 0}|{round(tout*100/total) if total else 0}")
PY
  2>/dev/null)
  printf '%s' "${out:-—|—|0|0}"
}
_codex_limits() {
  python3 - "$HOME/.codex/sessions" <<'PY' 2>/dev/null
import sys,os,json,glob,datetime,signal
signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError())); signal.alarm(3)
files=sorted(glob.glob(os.path.join(sys.argv[1],'**','*.jsonl'),recursive=True),key=lambda f: os.path.getmtime(f),reverse=True)
for f in files[:20]:
    try: lines=open(f,encoding='utf-8',errors='ignore').read().splitlines()
    except OSError: continue
    for line in reversed(lines):
        if '"rate_limits"' not in line: continue
        try: rl=(json.loads(line).get('payload') or {}).get('rate_limits') or {}
        except Exception: continue
        if not rl: continue
        def one(k):
            v=rl.get(k) or {}; pct=int(round(float(v.get('used_percent') or 0))); ts=v.get('resets_at')
            reset=datetime.datetime.fromtimestamp(ts).strftime('%m/%d %H:%M') if ts else '—'
            return pct,reset
        p,pr=one('primary'); s,sr=one('secondary'); print(f'{p}|{pr}|{s}|{sr}'); raise SystemExit
print('0|—|0|—')
PY
}
_claude_limits() {
  python3 - <<'PY' 2>/dev/null
import os,sys,json,datetime,signal,subprocess,urllib.request
signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError())); signal.alarm(5)
try:
    token=os.environ.get('CLAUDE_CODE_OAUTH_TOKEN','')
    if not token and sys.platform=='darwin':
        raw=subprocess.check_output(['security','find-generic-password','-s','Claude Code-credentials','-w'],stderr=subprocess.DEVNULL)
        token=(json.loads(raw).get('claudeAiOauth') or {}).get('accessToken','')
    if not token:
        f=os.path.expanduser('~/.claude/.credentials.json')
        if os.path.isfile(f): token=(json.load(open(f)).get('claudeAiOauth') or {}).get('accessToken','')
    if not token: raise RuntimeError()
    req=urllib.request.Request('https://api.anthropic.com/api/oauth/usage',headers={
        'Authorization':'Bearer '+token,'Accept':'application/json','anthropic-beta':'oauth-2025-04-20'})
    data=json.load(urllib.request.urlopen(req,timeout=4))
    limits=data.get('limits') or []
    def fmt(ts):
        if not ts: return '—'
        return datetime.datetime.fromisoformat(ts.replace('Z','+00:00')).astimezone().strftime('%m/%d %H:%M')
    def find(kind):
        x=next((v for v in limits if v.get('kind')==kind),{})
        return int(round(float(x.get('percent') or 0))),fmt(x.get('resets_at')),x
    sp,sr,_=find('session'); wp,wr,_=find('weekly_all'); mp,mr,m=find('weekly_scoped')
    scope=m.get('scope') or {}; model=(scope.get('model') or {}).get('display_name') or 'model'
    print(f'{sp}|{sr}|{wp}|{wr}|{model}|{mp}|{mr}')
except Exception:
    print('0|—|0|—|model|0|—')
PY
}
_dash_usage() {
  IFS='|' read -r CLAUDE_IN CLAUDE_OUT CLAUDE_IN_PCT CLAUDE_OUT_PCT <<EOF
$(_usage_dir "$HOME/.claude/projects")
EOF
  IFS='|' read -r CODEX_IN CODEX_OUT CODEX_IN_PCT CODEX_OUT_PCT <<EOF
$(_usage_dir "$HOME/.codex/sessions")
EOF
  IFS='|' read -r CODEX_5H CODEX_5H_RESET CODEX_WEEK CODEX_WEEK_RESET <<EOF
$(_codex_limits)
EOF
  IFS='|' read -r CLAUDE_SESSION CLAUDE_SESSION_RESET CLAUDE_WEEK CLAUDE_WEEK_RESET CLAUDE_MODEL CLAUDE_MODEL_WEEK CLAUDE_MODEL_RESET <<EOF
$(_claude_limits)
EOF
}
_dash_size()  { local sz; sz=$(stty size </dev/tty 2>/dev/null); ROWS=${sz%% *}; COLS=${sz##* }; [ -n "$ROWS" ] || ROWS=24; [ -n "$COLS" ] || COLS=80; }
_hrn() { local n=$1 o=""; while [ "$n" -gt 0 ]; do o="${o}─"; n=$((n-1)); done; printf '%s' "$o"; }
_usage_bar() { # $1=percent $2=width; plain glyphs so sidebar clipping stays exact
  local pct="${1:-0}" w="${2:-10}" fill empty out=""
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0; [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  fill=$(( (pct * w + 50) / 100 )); empty=$(( w - fill ))
  while [ "$fill" -gt 0 ]; do out="${out}█"; fill=$((fill-1)); done
  while [ "$empty" -gt 0 ]; do out="${out}░"; empty=$((empty-1)); done
  printf '%s' "$out"
}
_quota_line() { # compact colored sidebar row marker + label + bar + percentage
  local label="$1" pct="${2:-0}" tone=G
  [ "$pct" -ge 90 ] 2>/dev/null && tone=R || { [ "$pct" -ge 70 ] 2>/dev/null && tone=Y; }
  printf '@%s@  %-5s %s %3d%%' "$tone" "$label" "$(_usage_bar "$pct" 9)" "$pct"
}
_dash_team() {
  local reg s now pf="${PENDING_FILE:-$CONFIG_DIR/pending.tsv}"
  TEAM_TOTAL=0; TEAM_RUNNING=0; TEAM_PANES=0; TEAM_OFFLINE=0; TEAM_MISSING=0; TEAM_WAITING=0; TEAM_STALE=0
  reg=$(_reg_sessions); now=$(date +%s)
  while IFS= read -r s; do
    [ -n "$s" ] || continue; TEAM_TOTAL=$((TEAM_TOTAL+1))
    if tmux has-session -t "=$s" 2>/dev/null; then
      TEAM_RUNNING=$((TEAM_RUNNING+1))
      local pc; pc=$(tmux list-panes -t "=$s" 2>/dev/null | wc -l | tr -d ' '); TEAM_PANES=$((TEAM_PANES + ${pc:-0}))
    else TEAM_OFFLINE=$((TEAM_OFFLINE+1)); fi
  done <<EOF
$reg
EOF
  if [ -f "$WS_CONF" ]; then
    while IFS='|' read -r _ _ d _ _; do [ -n "$d" ] && [ ! -d "${d/#\~/$HOME}" ] && TEAM_MISSING=$((TEAM_MISSING+1)); done < "$WS_CONF"
  fi
  if [ -f "$pf" ]; then
    while IFS=$'\t' read -r ts _; do
      case "$ts" in ''|*[!0-9]*) continue ;; esac
      TEAM_WAITING=$((TEAM_WAITING+1)); [ $((now-ts)) -ge 900 ] && TEAM_STALE=$((TEAM_STALE+1))
    done < "$pf"
  fi
}
_dash_tasks() {
  local now ts key state target_s target_r sender_s sender_r summary age
  TASK_RUNNING=0; TASK_ATTENTION=0; TASK_DONE=0; TASK_LATEST_TARGET=""; TASK_LATEST_SUMMARY=""; TASK_LATEST_STATE=""
  now=$(date +%s)
  while IFS=$'\t' read -r ts key state target_s target_r sender_s sender_r summary; do
    [ -n "$key" ] || continue
    age=$((now-ts))
    case "$state" in
      delivered|working|acknowledged)
        if [ "$age" -ge 900 ]; then state=stale; TASK_ATTENTION=$((TASK_ATTENTION+1))
        else TASK_RUNNING=$((TASK_RUNNING+1)); fi ;;
      needs_approval|failed|stale) TASK_ATTENTION=$((TASK_ATTENTION+1)) ;;
      completed) TASK_DONE=$((TASK_DONE+1)) ;;
    esac
    if [ -z "$TASK_LATEST_STATE" ] && [ "$state" != completed ] && [ "$state" != cancelled ]; then
      TASK_LATEST_STATE="$state"; TASK_LATEST_TARGET="${target_r:-$target_s}"; TASK_LATEST_SUMMARY="$summary"
    fi
  done < <(task_latest)
}
_task_file_stamp() {
  [ -f "$TASK_FILE" ] || { printf 'none'; return; }
  stat -f '%m:%z' "$TASK_FILE" 2>/dev/null || stat -c '%Y:%s' "$TASK_FILE" 2>/dev/null || printf 'unknown'
}
_scan_ai_conversations() { # TSV: id, agent, cwd, last user prompt, mtime, user turns, recent conversation
  python3 - <<'PY' 2>/dev/null
import os,glob,json,signal,datetime
signal.signal(signal.SIGALRM, lambda *_: (_ for _ in ()).throw(TimeoutError())); signal.alarm(5)
home=os.path.expanduser('~'); rows=[]
def text_of(content):
    if isinstance(content,str): return content
    if isinstance(content,list):
        return ' '.join(x.get('text','') for x in content if isinstance(x,dict) and x.get('type')=='text')
    return ''
def clean(s): return ' '.join(str(s or '').replace('\t',' ').replace('\r',' ').replace('\n',' ').split())[:160]
def timestamp_of(o):
    value=o.get('timestamp')
    if isinstance(value,(int,float)): return float(value)
    try: return datetime.datetime.fromisoformat(str(value).replace('Z','+00:00')).timestamp()
    except Exception: return 0
def push(preview,role,text):
    value=clean(text)
    if not value: return False
    tagged=role+':'+value
    # Assistants often emit several progress/tool-boundary events during one
    # logical turn. Keep only the latest event so the preview reads like chat.
    if role=='A' and preview and preview[-1].startswith('A:'): preview[-1]=tagged
    else: preview.append(tagged)
    return True
for f in glob.glob(os.path.join(home,'.claude/projects/*/*.jsonl')):
    sid=os.path.basename(f)[:-6]; cwd=''; title=''; preview=[]; last_time=0
    try:
        for line in open(f,encoding='utf-8',errors='ignore'):
            try:o=json.loads(line)
            except Exception:continue
            cwd=cwd or o.get('cwd','')
            if o.get('type')=='user':
                t=text_of((o.get('message') or {}).get('content'))
                stripped=t.lstrip()
                if t and not stripped.startswith(('<local-command-','<command-name>','<system-reminder>')):
                    title=t
                    if push(preview,'U',t): last_time=max(last_time,timestamp_of(o))
            elif o.get('type')=='assistant':
                t=text_of((o.get('message') or {}).get('content'))
                if push(preview,'A',t): last_time=max(last_time,timestamp_of(o))
        turns=sum(x.startswith('U:') for x in preview)
        rows.append((last_time or os.path.getmtime(f),sid,'claude',cwd,clean(title),turns,'\x1e'.join(preview[-4:])))
    except OSError: pass
for f in glob.glob(os.path.join(home,'.codex/sessions/*/*/*/*.jsonl')):
    sid=''; cwd=''; title=''; preview=[]; last_time=0
    try:
        for line in open(f,encoding='utf-8',errors='ignore'):
            try:o=json.loads(line)
            except Exception:continue
            p=o.get('payload') or {}
            if o.get('type')=='session_meta': sid=p.get('id') or p.get('session_id',''); cwd=p.get('cwd','')
            elif o.get('type')=='event_msg' and p.get('type')=='user_message' and p.get('message'):
                title=p.get('message')
                if push(preview,'U',title): last_time=max(last_time,timestamp_of(o))
            elif o.get('type')=='event_msg' and p.get('type')=='agent_message' and p.get('message'):
                if push(preview,'A',p.get('message')): last_time=max(last_time,timestamp_of(o))
        if sid:
            turns=sum(x.startswith('U:') for x in preview)
            rows.append((last_time or os.path.getmtime(f),sid,'codex',cwd,clean(title),turns,'\x1e'.join(preview[-4:])))
    except OSError: pass
kept={'claude':0,'codex':0}
for m,sid,agent,cwd,title,turns,preview in sorted(rows,reverse=True):
    if kept[agent]>=100: continue
    kept[agent]+=1; print(f'{sid}\t{agent}\t{clean(cwd)}\t{title}\t{int(m)}\t{turns}\t{preview}')
PY
}

_dashboard() {
  local TABS=(Sessions Hub Adopt Settings) tab=0 mtop=0 INPUT="" key rest mc mseq csi legacy_mouse
  local LAST_MOUSE_DOWN="" MOUSE_FINAL=""
  local FLOW="" FSTEP=0 FNAME="" FROLE="" FAGENT=""; local -a LOG=() MLC=() ULC=() LSEL=()
  local -a SACT=() SARG=() SGROUP=() UACT=() UARG=() UGROUP=() UP_ID=() UP_AG=() UP_DIR=() UP_NAME=()
  local -a AD_ID=() AD_AGENT=() AD_DIR=() AD_TITLE=() AD_TIME=() AD_USED=() AD_TURNS=() AD_PREVIEW=() WRAPPED=()
  local PANEL_CONF="$CONFIG_DIR/unassigned-panels.conf"
  local PANEL_ID="" PANEL_AGENT="" PANEL_DIR="" PANEL_NAME=""
  local PANEL_SELECTED=0 PANEL_SOURCE_SESSION="" PANEL_SOURCE_ROLE=""
  local PENDING_TARGET="" PENDING_ROLE=""
  local BROWSE_DIR="$PWD" ADD_BROWSE=0
  local ARRANGE_MODE=0 ARRANGE_MSG=""
  local SETTINGS_PAGE=main SETTINGS_MSG="" SKILL_DELETE="" ACCT_SWITCH="" CLAUDE_AUTH=unknown CODEX_AUTH=unknown
  local CLAUDE_ACCT=() CODEX_ACCT=()   # cached account rows for the Settings render (id\tlabel\tactive\tident\tplan\thasToken)
  local RECENT_MODEL=""                # concrete model the newest claude conversation ran on
  local CLAUDE_LIVE_IDENT="" CODEX_IDENT="" ACCT_SEEN_AT=-99   # cached identities + last account re-read
  # Hub chat: the dashboard is the chat window; the hub's own pane is the engine.
  local -a HUBC_ROLE=() HUBC_TEXT=()   # rendered turns (role + body, newlines as \x01)
  local HUBC_FILE="" HUBC_STAMP="" HUBC_SEEN_AT=-99 HUBC_MSG="" HUBC_WAITING=0
  local -a HUBC_VIEW=(); local HUBC_SIZE=""   # live mirror of the hub pane + the size it is held at
  local HUBC_JOINED=0 HUBC_PANE="" HUBC_ORIGIN="" HUBC_KEEP=""   # the hub's real pane, borrowed into this window
  local DETAIL_SESSION="" DETAIL_ADD=0 DETAIL_EDIT=0 DETAIL_DELETE=0 DETAIL_PRESET="" DETAIL_MSG="" EDIT_SESSION="" EDIT_ROLE=""
  local HOVER_AREA="" HOVER_INDEX=-1 HOVER_GROUP="" LAST_CLICK_SESSION="" LAST_CLICK_TIME=0
  local ADOPT_FILTER=claude ADOPT_LOADED=0 ADOPT_MSG="" ADOPT_SELECTED=""
  # Highlight/mute with bold vs dim on the terminal's DEFAULT foreground, not a
  # hardcoded white — so rows stay readable on both dark and light themes.
  local C_ACTIVE="" C_MUTED=""; [ -n "$C_X" ] && { C_ACTIVE=$'\033[1m'; C_MUTED=$'\033[2m'; }
  local ROWS COLS MMAX=0 LW=0 SESSION_LEFT_W=0 LISTBODY=1 HUB_ROWS=0 STAR_X0=0 STAR_X1=0 STAR_Y=0 TASK_RESET_X0=0 TASK_RESET_X1=0 TASK_RESET_Y=0; _dash_size
  local -a TX0 TX1
  local VER; VER=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SELF_DIR/../package.json" 2>/dev/null | head -1)
  local CWD="${PWD/#$HOME/~}"
  get_hub >/dev/null 2>&1 || true
  CLAUDE_IN="…"; CLAUDE_OUT="…"; CLAUDE_IN_PCT=0; CLAUDE_OUT_PCT=0
  CLAUDE_SESSION=0; CLAUDE_SESSION_RESET="—"; CLAUDE_WEEK=0; CLAUDE_WEEK_RESET="—"
  CLAUDE_MODEL="model"; CLAUDE_MODEL_WEEK=0; CLAUDE_MODEL_RESET="—"
  CODEX_IN="…"; CODEX_OUT="…"; CODEX_IN_PCT=0; CODEX_OUT_PCT=0
  CODEX_5H=0; CODEX_5H_RESET="—"; CODEX_WEEK=0; CODEX_WEEK_RESET="—"; _dash_usage
  TEAM_TOTAL=0; TEAM_RUNNING=0; TEAM_PANES=0; TEAM_OFFLINE=0; TEAM_MISSING=0; TEAM_WAITING=0; TEAM_STALE=0
  TASK_RUNNING=0; TASK_ATTENTION=0; TASK_DONE=0; TASK_LATEST_TARGET=""; TASK_LATEST_SUMMARY=""; TASK_LATEST_STATE=""
  local TASK_STAMP; TASK_STAMP=$(_task_file_stamp)

  # ── 흐름(대화) 엔진 ──────────────────────────────────────────────
  _say() { LOG+=("$1"); }
  _you() { LOG+=("  ${C_C}› $1${C_X}"); }
  _flow_ensure() { local t="${TABS[$tab]}"; case "$t" in
    Adopt) [ "$ADOPT_LOADED" = 1 ] || _adopt_scan ;;
    Sessions) case "$FLOW" in Add|SessionAssign|SessionRoleEdit|DetailNewPanel) : ;; *) FLOW="" ;; esac ;;
    Settings) case "$FLOW" in Hub|SettingsNotice|SkillAdd) : ;; *) FLOW="" ;; esac ;;
    *) FLOW="" ;;
  esac; }
  _flow_start() {
    FLOW="$1"; FSTEP=1; LOG=(); FNAME=""; FROLE=""; FAGENT=""; LSEL=()
    case "$1" in
      Add) ADD_BROWSE=0; _say "${C_B}➕ 프로젝트 추가${C_X}"; _say ""; _say "먼저 사용할 에이전트를 선택하세요." ;;
      Hub) if [ -n "${HUB:-}" ]; then _say "${C_B}🧑 비서(허브)${C_X}"; _say ""; _say "이미 허브가 있어요: ${C_C}$HUB${C_X}"; _say "${C_D}바꾸려면 먼저 rm 후 다시.${C_X}"; FSTEP=0
           else _say "${C_B}🧑 비서(허브) 만들기${C_X}"; _say ""; _say "비서 세션 이름을 입력하세요 (그냥 Enter = hub)."; fi ;;
    esac
  }
  _flow_answer() { local a="$1"; case "$FLOW" in
    Add) _flow_add "$a" ;; Hub) _flow_hub "$a" ;; SettingsNotice) FLOW="" ;; SkillAdd) _flow_skill_add "$a" ;;
    SessionAdopt) _flow_session_adopt "$a" ;; SessionAssign) _flow_session_assign "$a" ;;
    SessionRoleEdit) _flow_role_edit "$a" ;; DetailNewPanel) _flow_detail_new_panel "$a" ;;
  esac; }

  _conversation_used() { # $1=id; assigned or already imported
    local id="$1"
    { [ -f "$WS_CONF" ] && LC_ALL=C awk -F'|' -v id="$id" '$4==id{f=1} END{exit !f}' "$WS_CONF"; } && return 0
    { [ -f "$PANEL_CONF" ] && LC_ALL=C awk -F'|' -v id="$id" '$1==id{f=1} END{exit !f}' "$PANEL_CONF"; }
  }
  _conversation_find() { # $1=id → PANEL_AGENT/PANEL_DIR
    local id="$1" f=""
    PANEL_AGENT=""; PANEL_DIR=""
    case "$id" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
    f=$(find "$HOME/.codex/sessions" -type f -name "*$id*.jsonl" 2>/dev/null | head -1)
    if [ -n "$f" ]; then PANEL_AGENT=codex
    else f=$(find "$HOME/.claude/projects" -type f -name "$id.jsonl" 2>/dev/null | head -1); [ -n "$f" ] && PANEL_AGENT=claude; fi
    [ -n "$f" ] || return 1
    PANEL_DIR=$(grep -o '"cwd":"[^"]*"' "$f" 2>/dev/null | head -1 | sed 's/^"cwd":"//; s/"$//')
    [ -n "$PANEL_DIR" ] || PANEL_DIR="$PWD"
    return 0
  }
  _adopt_scan() {
    AD_ID=(); AD_AGENT=(); AD_DIR=(); AD_TITLE=(); AD_TIME=(); AD_USED=(); AD_TURNS=(); AD_PREVIEW=(); ADOPT_MSG=""
    local id ag dir title mt turns preview used
    while IFS=$'\t' read -r id ag dir title mt turns preview; do
      [ -n "$id" ] || continue; used=0; _conversation_used "$id" && used=1
      AD_ID+=("$id"); AD_AGENT+=("$ag"); AD_DIR+=("${dir:-$PWD}"); AD_TITLE+=("${title:-대화 내용 없음}"); AD_TIME+=("${mt:-0}"); AD_USED+=("$used"); AD_TURNS+=("${turns:-0}"); AD_PREVIEW+=("$preview")
    done < <(_scan_ai_conversations)
    # Fresh panels have no resume ID in workspaces.conf. Match the newest unused
    # conversation with the same agent + directory so it is not offered again.
    if [ -f "$WS_CONF" ]; then
      local _s _r _d _rid _ag i want
      while IFS='|' read -r _s _r _d _rid _ag; do
        [ -n "$_d" ] || continue; [ -n "$_rid" ] && continue
        want="${_d/#\~/$HOME}"; _ag="${_ag:-$TELL_AGENT}"
        for ((i=0;i<${#AD_ID[@]};i++)); do
          [ "${AD_USED[$i]}" = 0 ] && [ "${AD_AGENT[$i]}" = "$_ag" ] && [ "${AD_DIR[$i]}" = "$want" ] || continue
          AD_USED[$i]=1; break
        done
      done < "$WS_CONF"
    fi
    ADOPT_LOADED=1
    [ "${#AD_ID[@]}" -eq 0 ] && ADOPT_MSG="세션 기록을 찾지 못했습니다"
  }
  _adopt_age() {
    local ts="${1:-0}" now d; now=$(date +%s); d=$((now-ts))
    if [ "$d" -lt 60 ]; then printf '방금 전'
    elif [ "$d" -lt 3600 ]; then printf '%d분 전' $((d/60))
    elif [ "$d" -lt 86400 ]; then printf '%d시간 전' $((d/3600))
    else printf '%d일 전' $((d/86400)); fi
  }
  _adopt_select() { # $1=session id from cached list → jump to naming step
    local id="$1" i
    for ((i=0;i<${#AD_ID[@]};i++)); do
      [ "${AD_ID[$i]}" = "$id" ] || continue
      [ "${AD_USED[$i]}" = 1 ] && return 1
      PANEL_ID="$id"; PANEL_AGENT="${AD_AGENT[$i]}"; PANEL_DIR="${AD_DIR[$i]}"; PANEL_NAME="${PANEL_AGENT}-${id:0:8}"
      FLOW=SessionAdopt; FSTEP=2; LOG=(); _say "${C_G}✔ $PANEL_AGENT 대화 선택${C_X}"; _say "  ${C_D}$PANEL_DIR${C_X}"; _say "패널 이름을 입력하세요. ${C_D}(Enter = $PANEL_NAME)${C_X}"
      return 0
    done
    return 1
  }
  _panel_recent_prompt() { # $1=agent $2=dir $3=resume id; sets RP_TEXT/RP_APPROX
    local agent="${1:-$TELL_AGENT}" dir="${2/#\~/$HOME}" rid="${3:-}" i
    RP_TEXT=""; RP_APPROX=0
    if [ -n "$rid" ]; then
      for ((i=0;i<${#AD_ID[@]};i++)); do
        [ "${AD_ID[$i]}" = "$rid" ] || continue; RP_TEXT="${AD_TITLE[$i]}"; return 0
      done
      RP_TEXT=$(_conversation_title_by_id "$agent" "$rid") && return 0
      RP_TEXT="대화 기록을 찾을 수 없음"; return 0
    fi
    RP_TEXT="새 대화 · 아직 연결되지 않음"; return 0
  }
  _conversation_title_by_id() { # agent id — exact transcript lookup, no cwd fallback
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import glob,json,os,sys
agent,sid=sys.argv[1:3]; title=''; path=''
if agent=='claude':
    hits=glob.glob(os.path.expanduser('~/.claude/projects/*/'+sid+'.jsonl'))
else:
    hits=glob.glob(os.path.expanduser('~/.codex/sessions/*/*/*/*.jsonl'))
for f in hits:
    try:
        current=''
        with open(f,encoding='utf-8',errors='ignore') as h:
            for line in h:
                try:o=json.loads(line)
                except Exception:continue
                p=o.get('payload') or {}
                if agent=='codex' and o.get('type')=='session_meta': current=p.get('id') or p.get('session_id','')
                if agent=='claude' and o.get('type')=='user':
                    c=(o.get('message') or {}).get('content','')
                    if isinstance(c,list): c=' '.join(x.get('text','') for x in c if isinstance(x,dict) and x.get('type')=='text')
                    if c and not str(c).lstrip().startswith(('<local-command-','<command-name>','<system-reminder>')): title=str(c)
                elif agent=='codex' and o.get('type')=='event_msg' and p.get('type')=='user_message' and p.get('message'): title=str(p['message'])
        if agent=='claude' or current==sid: path=f; break
    except OSError: pass
if path and title: print(' '.join(title.replace('\t',' ').replace('\n',' ').split())[:160])
elif path: print('대화 내용 없음')
else: raise SystemExit(1)
PY
  }
  _panel_remove() { # $1=id
    [ -f "$PANEL_CONF" ] || return 0
    local tmp; tmp=$(mktemp)
    LC_ALL=C awk -F'|' -v id="$1" '$1!=id' "$PANEL_CONF" > "$tmp" && mv "$tmp" "$PANEL_CONF"
  }
  _start_assigned_panel() { # running project gets the adopted conversation immediately
    local session="$1" role="$2" dir="$3" rid="$4" agent="$5"
    tmux has-session -t "=$session" 2>/dev/null || return 0
    ws_add_configured_panel "$session" "$role" "$dir" "$rid" "$agent"
  }
  _move_assigned_pane() { # $1=target session $2=new role; move a live pane when one exists
    local target="$1" role="$2" pane="" dummy=""
    pane=$(tmux list-panes -t "=$PANEL_SOURCE_SESSION" -F '#{pane_id}|#{pane_title}' 2>/dev/null | LC_ALL=C awk -F'|' -v r="$PANEL_SOURCE_ROLE" '$2==r{print $1;exit}')
    [ -n "$pane" ] || return 2
    if [ "$PANEL_SOURCE_SESSION" = "$target" ]; then
      set_pane_role "$pane" "$role" 2>/dev/null
      return $?
    fi
    if ! tmux has-session -t "=$target" 2>/dev/null; then
      dummy=$(tmux new-session -d -P -F '#{pane_id}' -s "$target" -c "$PANEL_DIR" 2>/dev/null) || return 1
    fi
    if tmux join-pane -s "$pane" -t "=$target:" 2>/dev/null; then
      set_pane_role "$pane" "$role" 2>/dev/null
      [ -n "$dummy" ] && tmux kill-pane -t "$dummy" 2>/dev/null
      tmux select-layout -t "=$target:" tiled 2>/dev/null
      tmux set-option -w -t "=$target:" @loomo_layout tiled 2>/dev/null
      return 0
    fi
    [ -n "$dummy" ] && tmux kill-session -t "=$target" 2>/dev/null
    return 1
  }
  _sessions_adopt_start() {
    FLOW=SessionAdopt; FSTEP=1; LOG=(); PANEL_ID=""; PANEL_AGENT=""; PANEL_DIR=""; PANEL_NAME=""
    PANEL_SELECTED=0; PANEL_SOURCE_SESSION=""; PANEL_SOURCE_ROLE=""
    _say "${C_B}＋ AI 대화 가져오기${C_X}"; _say ""; _say "Claude 또는 Codex의 session ID를 입력하세요."
  }
  _flow_session_adopt() { local a="$1"
    [ "$FSTEP" = 0 ] && { FLOW=""; return; }
    case "$FSTEP" in
      1) [ -n "$a" ] || { _say "session ID가 필요해요:"; return; }
         _conversation_used "$a" && { _say "${C_R}이미 loomo에 등록된 conversation입니다.${C_X}"; return; }
         _conversation_find "$a" || { _say "${C_R}Claude/Codex 기록에서 ID를 찾지 못했습니다. 다시 확인하세요:${C_X}"; return; }
         PANEL_ID="$a"; PANEL_NAME="${PANEL_AGENT}-${a:0:8}"; _you "$a"
         _say "${C_G}✔ $PANEL_AGENT 대화 발견${C_X}"; _say "  ${C_D}$PANEL_DIR${C_X}"; FSTEP=2
         _say "패널 이름을 입력하세요. ${C_D}(Enter = $PANEL_NAME)${C_X}" ;;
      2) PANEL_NAME="${a:-$PANEL_NAME}"; case "$PANEL_NAME" in *'|'*|*$'\n'*) _say "이름에 | 또는 줄바꿈은 쓸 수 없어요:"; return ;; esac
         mkdir -p "$CONFIG_DIR"; printf '%s|%s|%s|%s\n' "$PANEL_ID" "$PANEL_AGENT" "$PANEL_DIR" "$PANEL_NAME" >> "$PANEL_CONF"
         ADOPT_LOADED=0; _say "${C_G}✅ '$PANEL_NAME'을 미배정 패널로 가져왔습니다.${C_X}"; _say "Sessions의 Edit arrangement에서 프로젝트에 배정하세요."; _say "${C_D}Enter를 누르면 목록으로 돌아갑니다.${C_X}"; FSTEP=0 ;;
    esac
  }
  _sessions_select_panel() { # arrangement mode: select one unassigned panel
    local id="$1"
    IFS='|' read -r PANEL_ID PANEL_AGENT PANEL_DIR PANEL_NAME < <(LC_ALL=C awk -F'|' -v id="$id" '$1==id{print;exit}' "$PANEL_CONF")
    PANEL_SELECTED=1; PANEL_SOURCE_SESSION=""; PANEL_SOURCE_ROLE=""; PENDING_TARGET=""; PENDING_ROLE=""; ARRANGE_MSG=""
  }
  _sessions_select_assigned() { # $1=session $2=role
    local s="$1" r="$2"
    IFS='|' read -r PANEL_SOURCE_SESSION PANEL_SOURCE_ROLE PANEL_DIR PANEL_ID PANEL_AGENT < <(LC_ALL=C awk -F'|' -v s="$s" -v r="$r" '$1==s&&$2==r{print;exit}' "$WS_CONF")
    PANEL_AGENT="${PANEL_AGENT:-$TELL_AGENT}"; PANEL_NAME="$PANEL_SOURCE_ROLE"; PANEL_SELECTED=1; PENDING_TARGET=""; PENDING_ROLE=""; ARRANGE_MSG=""
  }
  _detail_add_panel() { # $1=unassigned id -> selected detail session immediately
    local id="$1" role base n=2
    _sessions_select_panel "$id" || return 1
    role=${PANEL_NAME// /-}; role=${role//|/-}; [ -n "$role" ] || role="${PANEL_AGENT}-panel"
    base="$role"
    while LC_ALL=C awk -F'|' -v s="$DETAIL_SESSION" -v r="$role" '$1==s&&$2==r{f=1} END{exit !f}' "$WS_CONF"; do role="$base-$n"; n=$((n+1)); done
    PENDING_TARGET="$DETAIL_SESSION"; PENDING_ROLE="$role"
    _commit_pending_assignment
    DETAIL_ADD=0
  }
  _detail_new_panel_start() {
    [ -n "$DETAIL_SESSION" ] || return 1
    FLOW=DetailNewPanel; FSTEP=1; FNAME="$DETAIL_SESSION"; FROLE=""; PANEL_DIR=""; PANEL_AGENT=""
    BROWSE_DIR=$(LC_ALL=C awk -F'|' -v s="$DETAIL_SESSION" '$1==s && $3!="" {print $3; exit}' "$WS_CONF" 2>/dev/null)
    [ -d "$BROWSE_DIR" ] || BROWSE_DIR="$PWD"
    INPUT=""; LOG=("${C_B}＋ New panel → $DETAIL_SESSION${C_X}" "" "먼저 사용할 에이전트를 선택하세요.")
  }
  _flow_detail_new_panel() { local a="$1" d pane=""
    case "$FSTEP" in
      1) PANEL_AGENT=$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')
         case "$PANEL_AGENT" in claude|codex) ;; *) _say "claude 또는 codex를 선택하세요:"; return ;; esac
         _you "$PANEL_AGENT"; FSTEP=2; _say "역할 이름을 입력하세요. ${C_D}예: server, web, app${C_X}" ;;
      2) [ -n "$a" ] || { _say "역할 이름이 필요해요:"; return; }
         case "$a" in *'|'*|*' '*) _say "공백과 | 없이 역할 이름을 입력하세요:"; return ;; esac
         if LC_ALL=C awk -F'|' -v s="$FNAME" -v r="$a" '$1==s&&$2==r{f=1} END{exit !f}' "$WS_CONF"; then
           _say "${C_R}이미 같은 역할이 있습니다. 다른 이름:${C_X}"; return
         fi
         FROLE="$a"; _you "$a"; FSTEP=3
         _say "'$FROLE' 패널의 폴더 경로를 입력하거나 아래 버튼을 누르세요."
         _say "${C_C}${C_B}[📁 Browse folders]${C_X}" ;;
      3) d=$(abspath "$a"); [ -n "$d" ] || { _say "경로가 필요해요:"; return; }
         if [ ! -d "$d" ]; then
           mkdir -p "$d" 2>/dev/null || { _say "${C_R}폴더를 만들 수 없습니다: $d${C_X}"; return; }
         fi
         PANEL_DIR="$d"; _you "$a"
         printf '%s|%s|%s||%s\n' "$FNAME" "$FROLE" "$PANEL_DIR" "$PANEL_AGENT" >> "$WS_CONF"
         load_agent_profile "$PANEL_AGENT"
         append_role_template "$PANEL_DIR" "$FNAME" "$FROLE" "${HUB:-}" "${HUBR:-}"
         load_agent_profile "$TELL_AGENT"
         if tmux has-session -t "=$FNAME" 2>/dev/null; then
           if _start_assigned_panel "$FNAME" "$FROLE" "$PANEL_DIR" "" "$PANEL_AGENT" >/dev/null 2>&1; then
             DETAIL_MSG="패널 '$FROLE' 추가 및 시작 완료"
           else DETAIL_MSG="패널 설정은 저장했지만 시작하지 못함"
           fi
         else DETAIL_MSG="패널 '$FROLE' 추가 완료 · 세션 시작 시 함께 실행"; fi
         FLOW=""; FSTEP=0; INPUT=""; DETAIL_ADD=0; DETAIL_EDIT=0
         FNAME=""; FROLE=""; PANEL_DIR=""; PANEL_AGENT=""; mtop=0 ;;
    esac
  }
  _detail_delete_panel() { # $1=session|role; resumed panels return to unassigned
    local session role dir rid agent pane
    IFS='|' read -r session role <<< "$1"
    IFS='|' read -r _ role dir rid agent < <(LC_ALL=C awk -F'|' -v s="$session" -v r="$role" '$1==s&&$2==r{print;exit}' "$WS_CONF")
    [ -n "$role" ] || return 1
    pane=$(tmux list-panes -t "=$session" -F '#{pane_id}|#{pane_title}' 2>/dev/null | LC_ALL=C awk -F'|' -v r="$role" '$2==r{print $1;exit}')
    [ -n "$pane" ] && tmux kill-pane -t "$pane" 2>/dev/null || true
    _register_session "$session"
    _conf_del "$session" "$role" "$dir"
    if [ -n "$rid" ]; then
      mkdir -p "$CONFIG_DIR"
      _conversation_used "$rid" || printf '%s|%s|%s|%s\n' "$rid" "${agent:-$TELL_AGENT}" "$dir" "$role" >> "$PANEL_CONF"
    fi
    PANEL_SELECTED=0; PANEL_ID=""; PANEL_SOURCE_SESSION=""; PANEL_SOURCE_ROLE=""
  }
  _detail_delete_session() { # confirmed destructive action from the session detail header
    local session="$DETAIL_SESSION" rows d ag tmp
    [ -n "$session" ] || return 1
    rows=$(grep -vE '^[[:space:]]*(#|$)' "$WS_CONF" 2>/dev/null | LC_ALL=C awk -F'|' -v s="$session" '$1==s{print $3 "|" $5}')
    tmux has-session -t "=$session" 2>/dev/null && tmux kill-session -t "=$session" 2>/dev/null
    if [ -f "$WS_CONF" ]; then
      cp "$WS_CONF" "$WS_CONF.bak"
      tmp=$(mktemp); LC_ALL=C awk -F'|' -v s="$session" '$1!=s' "$WS_CONF" > "$tmp" && mv "$tmp" "$WS_CONF"
    fi
    while IFS='|' read -r d ag; do
      [ -n "$d" ] || continue
      if ! grep -vE '^[[:space:]]*(#|$)' "$WS_CONF" 2>/dev/null | LC_ALL=C awk -F'|' -v d="$d" '$3==d{f=1} END{exit !f}'; then
        load_agent_profile "${ag:-$TELL_AGENT}"; remove_bridge_section "$d" >/dev/null 2>&1 || true
      fi
    done <<EOF
$rows
EOF
    load_agent_profile "$TELL_AGENT"
    if get_hub && [ "$HUB" = "$session" ]; then rm -f "$HUB_FILE"; HUB=""; HUBR=""; fi
    _unregister_session "$session"
    DETAIL_SESSION=""; DETAIL_ADD=0; DETAIL_EDIT=0; DETAIL_DELETE=0; DETAIL_PRESET=""; DETAIL_MSG=""
  }
  _detail_edit_panel() { # $1=session|role
    IFS='|' read -r EDIT_SESSION EDIT_ROLE <<< "$1"
    [ -n "$EDIT_SESSION" ] && [ -n "$EDIT_ROLE" ] || return 1
    FLOW=SessionRoleEdit; FSTEP=1; INPUT=""; LOG=("${C_B}✎ Edit panel role${C_X}" "" "현재 역할: ${C_C}$EDIT_ROLE${C_X}" "새 역할 이름을 입력하세요.")
  }
  _flow_role_edit() {
    local new="$1" tmp pane
    [ -n "$new" ] || { _say "역할 이름이 필요해요:"; return; }
    case "$new" in *'|'*|*' '*) _say "공백과 | 없이 역할 이름을 입력하세요:"; return ;; esac
    if LC_ALL=C awk -F'|' -v s="$EDIT_SESSION" -v r="$new" -v old="$EDIT_ROLE" '$1==s&&$2==r&&$2!=old{f=1} END{exit !f}' "$WS_CONF"; then
      _say "${C_R}이미 같은 역할이 있습니다.${C_X}"; return
    fi
    tmp=$(mktemp)
    LC_ALL=C awk -F'|' -v OFS='|' -v s="$EDIT_SESSION" -v old="$EDIT_ROLE" -v new="$new" '$1==s&&$2==old{$2=new} {print}' "$WS_CONF" > "$tmp" && mv "$tmp" "$WS_CONF"
    pane=$(tmux list-panes -t "=$EDIT_SESSION" -F '#{pane_id}|#{pane_title}' 2>/dev/null | LC_ALL=C awk -F'|' -v r="$EDIT_ROLE" '$2==r{print $1;exit}')
    [ -n "$pane" ] && set_pane_role "$pane" "$new" 2>/dev/null || true
    EDIT_ROLE=""; EDIT_SESSION=""; FLOW=""; FSTEP=0; INPUT=""
  }
  _sessions_assign_target() { # $1=project selected on the left
    [ "$PANEL_SELECTED" = 1 ] || return 1
    FNAME="$1"
    if [ -n "$PANEL_SOURCE_SESSION" ]; then
      if LC_ALL=C awk -F'|' -v s="$FNAME" -v r="$PANEL_SOURCE_ROLE" -v os="$PANEL_SOURCE_SESSION" -v or="$PANEL_SOURCE_ROLE" \
        '$1==s&&$2==r&&!($1==os&&$2==or){f=1} END{exit !f}' "$WS_CONF"; then ARRANGE_MSG="이미 '$FNAME/$PANEL_SOURCE_ROLE' 역할이 있습니다"; return 1; fi
      PENDING_TARGET="$FNAME"; PENDING_ROLE="$PANEL_SOURCE_ROLE"; ARRANGE_MSG=""; mtop=0
    else FLOW=SessionAssign; FSTEP=2; LOG=("${C_B}↳ '$PANEL_NAME' → $FNAME${C_X}" ""); _say "역할 이름을 입력하세요. ${C_D}(Enter = $PANEL_NAME)${C_X}"; fi
  }
  _flow_session_assign() { local a="$1"
    [ "$FSTEP" = 0 ] && { FLOW=""; return; }
    case "$FSTEP" in
      2) FROLE="${a:-$PANEL_NAME}"; case "$FROLE" in ''|*'|'*|*' '*) _say "공백과 | 없이 역할 이름을 입력하세요:"; return ;; esac
         if LC_ALL=C awk -F'|' -v s="$FNAME" -v r="$FROLE" -v os="$PANEL_SOURCE_SESSION" -v or="$PANEL_SOURCE_ROLE" \
           '$1==s&&$2==r&&!($1==os&&$2==or){f=1} END{exit !f}' "$WS_CONF"; then _say "${C_R}이미 같은 역할이 있습니다. 다른 이름:${C_X}"; return; fi
         PENDING_TARGET="$FNAME"; PENDING_ROLE="$FROLE"; FLOW=""; FSTEP=0; mtop=0 ;;
    esac
  }
  _commit_pending_assignment() {
    [ -n "$PENDING_TARGET" ] || return 0
    FNAME="$PENDING_TARGET"; FROLE="$PENDING_ROLE"
    if [ -n "$PANEL_SOURCE_SESSION" ]; then _conf_del "$PANEL_SOURCE_SESSION" "$PANEL_SOURCE_ROLE" "$PANEL_DIR"
    else _panel_remove "$PANEL_ID"; fi
    printf '%s|%s|%s|%s|%s\n' "$FNAME" "$FROLE" "$PANEL_DIR" "$PANEL_ID" "$PANEL_AGENT" >> "$WS_CONF"
    load_agent_profile "$PANEL_AGENT"; append_role_template "$PANEL_DIR" "$FNAME" "$FROLE" "${HUB:-}" "${HUBR:-}"; load_agent_profile "$TELL_AGENT"
    if [ -n "$PANEL_SOURCE_SESSION" ]; then
           local move_rc=0
           _move_assigned_pane "$FNAME" "$FROLE" || move_rc=$?
           if [ "$move_rc" = 2 ] && tmux has-session -t "=$FNAME" 2>/dev/null; then _start_assigned_panel "$FNAME" "$FROLE" "$PANEL_DIR" "$PANEL_ID" "$PANEL_AGENT" >/dev/null 2>&1 || true; fi
    elif tmux has-session -t "=$FNAME" 2>/dev/null; then
      _start_assigned_panel "$FNAME" "$FROLE" "$PANEL_DIR" "$PANEL_ID" "$PANEL_AGENT" >/dev/null 2>&1 || true
    fi
    PANEL_ID=""; PANEL_AGENT=""; PANEL_DIR=""; PANEL_NAME=""; PANEL_SELECTED=0
    PANEL_SOURCE_SESSION=""; PANEL_SOURCE_ROLE=""; PENDING_TARGET=""; PENDING_ROLE=""
  }
  _flow_add() { local a="$1"
    [ "$FSTEP" = 0 ] && { FLOW=""; return; }
    case "$FSTEP" in
      1) FAGENT=$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]'); case "$FAGENT" in claude|codex) ;; *) _say "claude 또는 codex를 선택하세요:"; return ;; esac
         _you "$FAGENT"; FSTEP=2; _say "프로젝트(작업 묶음) 이름을 입력하세요."; _say "${C_D}예: myapp${C_X}" ;;
      2) case "$a" in ""|*" "*|*[=:.]*) _say "${C_R}공백·특수문자 없이 다시:${C_X}"; return ;; esac
         if tmux has-session -t "=$a" 2>/dev/null || { [ -f "$WS_CONF" ] && grep -qE "^$a\|" "$WS_CONF" 2>/dev/null; }; then _say "${C_R}이미 있는 이름. 다른 이름:${C_X}"; return; fi
         FNAME="$a"; _register_session "$FNAME"; _you "$a"; FSTEP=3; _say "역할 이름을 입력하세요. ${C_D}예: server${C_X}" ;;
      3) [ -z "$a" ] && { _say "역할 이름이 필요해요:"; return; }; FROLE="$a"; _you "$a"; FSTEP=4; _say "'$a'의 폴더 경로를 입력하거나 아래 버튼을 누르세요."; _say "${C_C}${C_B}[📁 Browse folders]${C_X}" ;;
      4) ADD_BROWSE=0; local d; d=$(abspath "$a"); [ -z "$d" ] && { _say "경로가 필요해요:"; return; }
         [ -d "$d" ] || mkdir -p "$d" 2>/dev/null
         printf '%s|%s|%s||%s\n' "$FNAME" "$FROLE" "$d" "$FAGENT" >> "$WS_CONF"
         load_agent_profile "$FAGENT"
         append_role_template "$d" "$FNAME" "$FROLE" "${HUB:-}" "${HUBR:-}"
         load_agent_profile "$TELL_AGENT"
         BROWSE_DIR=$(dirname "$d"); _you "$a"; _say "${C_G}✔ 역할 '$FROLE' 추가됨${C_X}"; FSTEP=5; _say "역할을 더 추가하려면 이름 입력, 끝내려면 그냥 Enter." ;;
      5) if [ -z "$a" ]; then _say "${C_G}✅ '$FNAME' 완료! Sessions 탭에서 확인하거나 'loomo up $FNAME'로 시작하세요.${C_X}"; FSTEP=0
         else FROLE="$a"; _you "$a"; FSTEP=4; _say "'$a'의 폴더 경로를 입력하거나 아래 버튼을 누르세요."; _say "${C_C}${C_B}[📁 Browse folders]${C_X}"; fi ;;
    esac
  }
  _flow_add_browse() {
    { [ "$FLOW" = Add ] && [ "$FSTEP" = 4 ]; } || { [ "$FLOW" = DetailNewPanel ] && [ "$FSTEP" = 3 ]; } || return 1
    BROWSE_DIR=$(cd "$BROWSE_DIR" 2>/dev/null && pwd) || BROWSE_DIR="$PWD"
    ADD_BROWSE=1; mtop=0
  }
  _flow_add_browse_action() { # $1=select|parent|open|cancel $2=path
    case "$1" in
      select) ADD_BROWSE=0
              if [ "$FLOW" = DetailNewPanel ]; then _flow_detail_new_panel "$BROWSE_DIR"
              else _flow_add "$BROWSE_DIR"; fi ;;
      parent) BROWSE_DIR=$(dirname "$BROWSE_DIR"); mtop=0 ;;
      open) BROWSE_DIR="$2"; mtop=0 ;;
      cancel) ADD_BROWSE=0; mtop=9999 ;;
    esac
  }
  _flow_hub() { local a="$1"; [ "$FSTEP" = 0 ] && { FLOW=""; return; }
    case "$FSTEP" in
      1) local h="${a:-hub}"; case "$h" in *" "*|*[=:.]*) _say "${C_R}공백·특수문자 X. 다시:${C_X}"; return ;; esac
         FNAME="$h"; _you "$h"; FSTEP=2; _say "비서 작업 폴더 경로 (그냥 Enter = ~/loomo-hub):" ;;
      2) local d; d=$(abspath "${a:-$HOME/loomo-hub}"); mkdir -p "$d" 2>/dev/null
         printf '%s|%s|%s|\n' "$FNAME" "$FNAME" "$d" >> "$WS_CONF"; printf '%s|%s\n' "$FNAME" "$FNAME" > "$HUB_FILE"
         append_role_template "$d" "$FNAME" "$FNAME" "$FNAME" "$FNAME"; get_hub >/dev/null 2>&1 || true
         _you "${a:-~/loomo-hub}"; _say "${C_G}✅ 비서 '$FNAME' 생성! 자동으로 active 상태를 유지합니다.${C_X}"; FSTEP=0 ;;
    esac
  }
  _settings_hub_target() { # registered project session -> secretary session
    local session="$1" role sync_ok=1
    role=$(LC_ALL=C awk -F'|' -v s="$session" '$1==s && $2!="" {print $2; exit}' "$WS_CONF" 2>/dev/null)
    role=${role:-$session}
    mkdir -p "$CONFIG_DIR"
    printf '%s|%s\n' "$session" "$role" > "$HUB_FILE"
    get_hub >/dev/null 2>&1
    cmd_sync >/dev/null 2>&1 || sync_ok=0
    if tmux has-session -t "=$HUB" 2>/dev/null || ws_boot "$HUB" >/dev/null 2>&1; then
      if [ "$sync_ok" = 1 ]; then SETTINGS_MSG="Hub session → $session · active · 전체 패널 동기화 완료"
      else SETTINGS_MSG="Hub session → $session · active · 일부 패널 동기화 실패"; fi
    else
      SETTINGS_MSG="Hub session → $session · 시작 실패"
    fi
  }
  _ensure_hub_active() { # dashboard lifetime: configured hub stays running
    [ -n "${HUB:-}" ] || return 0
    tmux has-session -t "=$HUB" 2>/dev/null || ws_boot "$HUB" >/dev/null 2>&1 || return 1
  }
  _detail_layout() { # $1=tmux preset; detail session is the implicit target
    local preset="$1"
    if ! tmux has-session -t "=$DETAIL_SESSION" 2>/dev/null; then DETAIL_MSG="$DETAIL_SESSION is offline — 먼저 시작하세요"
    elif tmux select-layout -t "=$DETAIL_SESSION:" "$preset" >/dev/null 2>&1; then
      tmux set-option -w -t "=$DETAIL_SESSION:" @loomo_layout "$preset" 2>/dev/null
      DETAIL_PRESET="$preset"; DETAIL_MSG="Applied $preset"
    else DETAIL_MSG="레이아웃 적용 실패"; fi
  }
  _settings_auth_refresh() {
    CLAUDE_AUTH=unavailable; CODEX_AUTH=unavailable
    command -v claude >/dev/null 2>&1 && { if claude auth status >/dev/null 2>&1; then CLAUDE_AUTH=connected; else CLAUDE_AUTH=signed-out; fi; }
    command -v codex >/dev/null 2>&1 && { if codex login status >/dev/null 2>&1; then CODEX_AUTH=connected; else CODEX_AUTH=signed-out; fi; }
    CLAUDE_LIVE_IDENT=""; CODEX_IDENT=""   # explicit refresh re-resolves the live logins too
    _settings_accounts_refresh
  }
  _split6() { # split tab-separated fields keeping empty ones (bash read collapses IFS whitespace)
    local s="$1"
    F1=${s%%$'\t'*}; s=${s#*$'\t'}; F2=${s%%$'\t'*}; s=${s#*$'\t'}
    F3=${s%%$'\t'*}; s=${s#*$'\t'}; F4=${s%%$'\t'*}; s=${s#*$'\t'}
    F5=${s%%$'\t'*}; s=${s#*$'\t'}; F6=${s%%$'\t'*}
  }
  _settings_accounts_refresh() { # populate CLAUDE_ACCT / CODEX_ACCT caches (id\tlabel\tactive\tident\tplan\thasToken)
    local ln id label active root ident plan
    CLAUDE_ACCT=(); CODEX_ACCT=()
    RECENT_MODEL=$(_loomo_recent_model)
    ACCT_SEEN_AT=$SECONDS
    # The live CLI identity costs a `claude auth status` round-trip, so resolve it
    # once and reuse it — accounts are re-read often to catch logins done elsewhere.
    if [ -z "$CLAUDE_LIVE_IDENT" ] && command -v claude >/dev/null 2>&1; then
      CLAUDE_LIVE_IDENT=$(_account_identity claude default '')
    fi
    # Claude rows come from the long-lived token store; 'default' shows the live CLI login.
    while IFS= read -r ln; do
      [ -n "$ln" ] || continue
      _split6 "$ln"
      if [ "$F6" != 1 ] && [ "$F1" = default ] && [ -n "$CLAUDE_LIVE_IDENT" ]; then
        IFS=$'\t' read -r ident plan <<< "$CLAUDE_LIVE_IDENT"
        [ -n "$ident" ] && ln="$F1"$'\t'"$F2"$'\t'"$F3"$'\t'"$ident"$'\t'"$plan"$'\t'2   # 2 = live login, no stored token
      fi
      CLAUDE_ACCT+=("$ln")
    done < <(_account_mutate tok-rows claude 2>/dev/null)
    while IFS=$'\t' read -r id label active root; do
      [ -n "$id" ] || continue
      if [ -n "$CODEX_IDENT" ] && [ "$id" = default ]; then
        IFS=$'\t' read -r ident plan <<< "$CODEX_IDENT"
        CODEX_ACCT+=("$id"$'\t'"$label"$'\t'"$active"$'\t'"${ident:-$label}"$'\t'"$plan"$'\t'1)
      elif command -v codex >/dev/null 2>&1 && _account_connected codex "$id" "$root"; then
        IFS=$'\t' read -r ident plan <<< "$(_account_identity codex "$id" "$root")"
        [ "$id" = default ] && CODEX_IDENT="$ident"$'\t'"$plan"
        CODEX_ACCT+=("$id"$'\t'"$label"$'\t'"$active"$'\t'"${ident:-$label}"$'\t'"$plan"$'\t'1)
      else
        CODEX_ACCT+=("$id"$'\t'"$label"$'\t'"$active"$'\t'"$label"$'\t'""$'\t'0)
      fi
    done < <(_account_mutate rows codex 2>/dev/null)
  }
  _settings_auth_login() { # $1=claude|codex
    mkdir -p "$CONFIG_DIR"
    case "$1" in
      claude) nohup claude auth login </dev/null >"$CONFIG_DIR/claude-auth.log" 2>&1 & CLAUDE_AUTH=connecting ;;
      codex)  nohup codex login </dev/null >"$CONFIG_DIR/codex-auth.log" 2>&1 & CODEX_AUTH=connecting ;;
      *) return 1 ;;
    esac
    SETTINGS_MSG="$1 login started in background · 브라우저 승인 후 Refresh status"
  }
  _settings_auth_logout() { # non-interactive; run without opening another terminal
    mkdir -p "$CONFIG_DIR"
    case "$1" in
      claude) nohup claude auth logout </dev/null >"$CONFIG_DIR/claude-auth.log" 2>&1 & CLAUDE_AUTH=signed-out ;;
      codex)  nohup codex logout </dev/null >"$CONFIG_DIR/codex-auth.log" 2>&1 & CODEX_AUTH=signed-out ;;
      *) return 1 ;;
    esac
    SETTINGS_MSG="$1 logout started in background"
  }
  _settings_account_add() { # provider — create a profile slot + browser login
    local provider="$1" result id root log
    result=$(_account_mutate add "$provider" 2>/dev/null) || { SETTINGS_MSG="Account profile creation failed"; return 1; }
    IFS=$'\t' read -r id root <<< "$result"
    log="$CONFIG_DIR/${provider}-${id}-auth.log"
    if [ "$provider" = claude ]; then
      # setup-token is interactive, so run it in its own terminal window; the dashboard owns the alt-screen.
      if open_terminal_command "$(printf '%q account login claude %q' "$0" "$id")" 2>/dev/null; then
        SETTINGS_MSG="Claude 계정 추가 · 새 터미널에서 로그인하면 토큰이 저장돼요 · 끝나면 [Refresh status]"
      else
        SETTINGS_MSG="Claude 계정 추가됨 · 터미널에서 'loomo account login claude $id' 를 실행하세요"
      fi
    else
      nohup env CODEX_HOME="$root" codex login </dev/null >"$log" 2>&1 &
      SETTINGS_MSG="Codex 계정 추가 · 브라우저 승인 후 해당 계정을 클릭해 선택하세요"
    fi
    _settings_accounts_refresh
    mtop=0
  }
  _settings_account_profile() { # provider|id — switch a connected profile or start its login
    local provider id resolved root log
    IFS='|' read -r provider id <<< "$1"
    resolved=$(_account_resolve "$provider" "$id" 2>/dev/null) || { SETTINGS_MSG="Account profile not found"; return 1; }
    IFS=$'\t' read -r id root <<< "$resolved"
    if [ "$provider" = claude ]; then
      # A stored token (or 'default' = the live login) can be switched to right away.
      if [ "$id" = default ] || _account_mutate tok-rows claude 2>/dev/null | LC_ALL=C awk -F'\t' -v id="$id" '$1==id && $6==1{found=1} END{exit !found}'; then
        ACCT_SWITCH="$provider|$id"
        SETTINGS_MSG=""
      else
        _settings_account_login "$provider|$id"
      fi
    elif _account_connected "$provider" "$id" "$root"; then
      ACCT_SWITCH="$provider|$id"
      SETTINGS_MSG=""
    else
      log="$CONFIG_DIR/${provider}-${id}-auth.log"
      if [ "$id" = default ]; then nohup codex login </dev/null >"$log" 2>&1 &
      else nohup env CODEX_HOME="$root" codex login </dev/null >"$log" 2>&1 & fi
      SETTINGS_MSG="$provider login started · 브라우저 승인 후 다시 클릭해 선택하세요"
    fi
    mtop=0
  }
  _settings_account_switch() { # provider|id — apply after the dashboard confirmation
    local provider id result rc resolved root
    IFS='|' read -r provider id <<< "$1"
    ACCT_SWITCH=""
    if [ "$provider" = claude ]; then
      result=$(_account_mutate tok-use claude "$id" 2>/dev/null); rc=$?
      case "$rc" in
        0) SETTINGS_MSG="Claude 계정 전환 완료 → $result · 새 패널·재시작 세션부터 적용" ;;
        4) SETTINGS_MSG="이 계정은 저장된 토큰이 없어요 · 먼저 Login 하세요" ;;
        3) SETTINGS_MSG="계정 프로필을 찾지 못했어요" ;;
        *) SETTINGS_MSG="계정 전환에 실패했어요" ;;
      esac
    else
      resolved=$(_account_resolve codex "$id" 2>/dev/null) || { SETTINGS_MSG="계정 프로필을 찾지 못했어요"; return 1; }
      IFS=$'\t' read -r id root <<< "$resolved"
      if ! _account_connected codex "$id" "$root"; then
        SETTINGS_MSG="이 계정은 로그인되지 않았어요 · 먼저 Login 하세요"
      elif _account_mutate use codex "$id" >/dev/null 2>&1; then
        SETTINGS_MSG="Codex 계정 전환 완료 → $id · 새 패널·재시작 세션부터 적용"
      else
        SETTINGS_MSG="계정 전환에 실패했어요"
      fi
    fi
    _settings_accounts_refresh
    mtop=0
  }
  _settings_account_logout() { # provider|id — drop this account's stored login
    local provider id resolved root
    IFS='|' read -r provider id <<< "$1"
    ACCT_SWITCH=""
    if [ "$provider" = claude ]; then
      if [ "$id" = default ]; then
        # 'default' is the CLI's own login, not a stored one — sign it out for real.
        nohup claude auth logout </dev/null >"$CONFIG_DIR/claude-auth.log" 2>&1 &
        CLAUDE_AUTH=signed-out; CLAUDE_LIVE_IDENT=""
        SETTINGS_MSG="Claude CLI 로그아웃 · 저장된 다른 계정은 그대로예요"
      elif _account_mutate remove claude "$id" >/dev/null 2>&1; then
        # Drop the token and the profile itself: a profile with no login has no use.
        SETTINGS_MSG="Claude 계정 로그아웃 · 목록에서 제거했어요"
      else
        SETTINGS_MSG="계정 로그아웃에 실패했어요"
      fi
    else
      resolved=$(_account_resolve codex "$id" 2>/dev/null) || { SETTINGS_MSG="계정 프로필을 찾지 못했어요"; return 1; }
      IFS=$'\t' read -r id root <<< "$resolved"
      if [ "$id" = default ]; then
        nohup codex logout </dev/null >"$CONFIG_DIR/codex-auth.log" 2>&1 &
        CODEX_AUTH=signed-out; CODEX_IDENT=""
        SETTINGS_MSG="Codex CLI 로그아웃 · 저장된 다른 계정은 그대로예요"
      else
        # Sign the isolated profile out, then drop it from the list.
        nohup env CODEX_HOME="$root" codex logout </dev/null >"$CONFIG_DIR/codex-${id}-auth.log" 2>&1 &
        _account_mutate remove codex "$id" >/dev/null 2>&1
        SETTINGS_MSG="Codex 계정 로그아웃 · 목록에서 제거했어요"
      fi
    fi
    _settings_accounts_refresh
    mtop=0
  }
  _settings_account_login() { # provider|id — login, or adopt a completed Claude browser login
    local provider id owner_id live_email resolved root log
    IFS='|' read -r provider id <<< "$1"
    ACCT_SWITCH=""
    if [ "$provider" = claude ]; then
      # Issuing a long-lived token needs an interactive terminal — hand it its own window.
      if open_terminal_command "$(printf '%q account login claude %q' "$0" "$id")" 2>/dev/null; then
        SETTINGS_MSG="새 터미널에서 이 계정으로 로그인하세요 · 끝나면 [Refresh status]"
      else
        SETTINGS_MSG="터미널에서 'loomo account login claude $id' 를 실행하세요"
      fi
    else
      resolved=$(_account_resolve codex "$id" 2>/dev/null) || { SETTINGS_MSG="계정 프로필을 찾지 못했어요"; return 1; }
      IFS=$'\t' read -r id root <<< "$resolved"
      log="$CONFIG_DIR/codex-${id}-auth.log"
      if [ "$id" = default ]; then nohup codex login </dev/null >"$log" 2>&1 &
      else nohup env CODEX_HOME="$root" codex login </dev/null >"$log" 2>&1 & fi
      SETTINGS_MSG="Codex 로그인 시작 · 브라우저 승인 후 Refresh status를 눌러주세요"
    fi
    _settings_accounts_refresh
    mtop=0
  }
  # ── Hub chat ────────────────────────────────────────────────────────────────
  # The hub keeps running in its own pane; the dashboard just shows that pane's
  # conversation and types into it, so this chat IS the hub (same history, same
  # ability to delegate with tell) instead of a second, disconnected agent.
  _hubc_file() { # resolve the hub pane's transcript, '' when it has none yet
    local rid=""
    get_hub 2>/dev/null || return 1
    [ -n "${HUB:-}" ] && [ -n "${HUBR:-}" ] || return 1
    rid=$(grep -vE '^[[:space:]]*(#|$)' "$WS_CONF" 2>/dev/null \
      | LC_ALL=C awk -F'|' -v s="$HUB" -v r="$HUBR" '$1==s && $2==r {print $4; exit}')
    [ -n "$rid" ] || return 1
    node -e '
      const fs=require("fs"), os=require("os"), path=require("path");
      const root=path.join(os.homedir(),".claude","projects");
      let dirs=[]; try { dirs=fs.readdirSync(root); } catch { process.exit(0); }
      for (const d of dirs) {
        const p=path.join(root,d,process.argv[1]+".jsonl");
        if (fs.existsSync(p)) { process.stdout.write(p); break; }
      }
    ' "$rid" 2>/dev/null
  }
  _hubc_load() { # re-read the transcript into HUBC_ROLE/HUBC_TEXT (cheap: tail only)
    local out line role text
    HUBC_SEEN_AT=$SECONDS
    [ -n "$HUBC_FILE" ] || HUBC_FILE=$(_hubc_file)
    [ -n "$HUBC_FILE" ] && [ -f "$HUBC_FILE" ] || return 1
    HUBC_ROLE=(); HUBC_TEXT=()
    while IFS=$'\t' read -r role text; do
      [ -n "$role" ] || continue
      HUBC_ROLE+=("$role"); HUBC_TEXT+=("$text")
    done < <(node -e '
      const fs=require("fs");
      const file=process.argv[1];
      let buf="";
      try {
        const size=fs.statSync(file).size, len=Math.min(size, 512*1024);
        const fd=fs.openSync(file,"r"), b=Buffer.alloc(len);
        fs.readSync(fd,b,0,len,size-len); fs.closeSync(fd); buf=b.toString("utf8");
      } catch { process.exit(0); }
      const turns=[];
      for (const line of buf.split("\n")) {
        let o; try { o=JSON.parse(line); } catch { continue; }
        if (o.type!=="user" && o.type!=="assistant") continue;
        const c=o.message && o.message.content;
        let t="";
        if (typeof c==="string") t=c;
        else if (Array.isArray(c)) t=c.filter(b=>b&&b.type==="text").map(b=>b.text).join("");
        t=t.trim();
        if (!t) continue;
        if (o.type==="user" && /^<(command-name|local-command|system-reminder)/.test(t)) continue;
        turns.push(o.type+"\t"+t.replace(/\t/g," ").replace(/\n/g,""));
      }
      process.stdout.write(turns.slice(-40).join("\n"));
    ' "$HUBC_FILE" 2>/dev/null)
    HUBC_STAMP=$(stat -f %m "$HUBC_FILE" 2>/dev/null || stat -c %Y "$HUBC_FILE" 2>/dev/null)
    return 0
  }
  _hubc_poll() { # refresh when the transcript changed (the hub answers in its own pane)
    local now
    [ $(( SECONDS - HUBC_SEEN_AT )) -ge 2 ] || return
    HUBC_SEEN_AT=$SECONDS
    [ -n "$HUBC_FILE" ] || { _hubc_load; return; }
    now=$(stat -f %m "$HUBC_FILE" 2>/dev/null || stat -c %Y "$HUBC_FILE" 2>/dev/null)
    [ "$now" = "$HUBC_STAMP" ] && return
    _hubc_load && HUBC_WAITING=0
  }
  _hubc_pane() { # hub pane id, booting the session when it isn't up yet
    if ! get_hub 2>/dev/null || [ -z "${HUB:-}" ]; then
      HUBC_MSG="허브 세션이 지정되지 않았어요 · Settings → Hub session"; return 1
    fi
    if ! tmux has-session -t "=$HUB" 2>/dev/null; then
      ws_boot "$HUB" >/dev/null 2>&1 || { HUBC_MSG="허브 세션을 시작하지 못했어요"; return 1; }
    fi
    local pane
    pane=$(tmux list-panes -t "=$HUB" -F "#{pane_id}	#{pane_title}" 2>/dev/null \
      | LC_ALL=C awk -F'\t' -v r="$HUBR" '$2==r{print $1; exit}')
    [ -n "$pane" ] || { HUBC_MSG="허브 패널을 찾지 못했어요: $HUB:$HUBR"; return 1; }
    printf '%s' "$pane"
  }
  _hubc_attach_pane() { # pull the hub's real pane in beside the dashboard
    local pane origin
    if [ "$HUBC_JOINED" = 1 ]; then
      # Claude may have exited under us; notice it instead of holding a corpse.
      [ "$(tmux display-message -p -t "$HUBC_PANE" '#{pane_dead}' 2>/dev/null)" = 0 ] && return 0
      _hubc_detach_pane
      return 1
    fi
    [ -n "${LOOMO_DASH_PANE:-}" ] || return 1        # only possible when we are a pane
    pane=$(_hubc_pane) || return 1
    origin=$(tmux display-message -p -t "$pane" '#{session_name}:#{window_index}' 2>/dev/null)
    [ -n "$origin" ] || return 1
    # Moving a window's last pane destroys its session, so leave a placeholder
    # behind — otherwise borrowing the hub's pane would kill the hub itself.
    if [ "$(tmux list-panes -t "$origin" 2>/dev/null | grep -c .)" -le 1 ]; then
      tmux split-window -d -t "$pane" 'sleep 2147483647' 2>/dev/null
      HUBC_KEEP=$(tmux list-panes -t "$origin" -F '#{pane_id}' 2>/dev/null | grep -v "^${pane}$" | head -1)
    else
      HUBC_KEEP=""
    fi
    # Two rows are enough for the tab strip (see the compact branch in _draw);
    # the divider takes one more, so Claude gets everything below that.
    if tmux join-pane -v -l "$(( ROWS - 3 ))" -s "$pane" -t "$TMUX_PANE" 2>/dev/null; then
      HUBC_JOINED=1; HUBC_ORIGIN="$origin"; HUBC_PANE="$pane"
      tmux select-pane -t "$pane" 2>/dev/null      # type into Claude right away
      return 0
    fi
    [ -n "$HUBC_KEEP" ] && tmux kill-pane -t "$HUBC_KEEP" 2>/dev/null
    HUBC_KEEP=""
    return 1
  }
  _hubc_detach_pane() { # send the hub's pane home again
    [ "$HUBC_JOINED" = 1 ] || return 0
    local alive=""
    [ -n "$HUBC_PANE" ] && alive=$(tmux display-message -p -t "$HUBC_PANE" '#{pane_dead}' 2>/dev/null)
    if [ "$alive" = 0 ] && [ -n "$HUBC_ORIGIN" ]; then
      tmux join-pane -s "$HUBC_PANE" -t "$HUBC_ORIGIN" 2>/dev/null
      [ -n "$HUBC_KEEP" ] && tmux kill-pane -t "$HUBC_KEEP" 2>/dev/null
    else
      # Claude exited while we had its pane. Drop the corpse and leave the
      # placeholder holding the hub's window, so the session survives for a restart.
      [ -n "$HUBC_PANE" ] && tmux kill-pane -t "$HUBC_PANE" 2>/dev/null
      HUBC_MSG="비서 세션이 종료됐어요 · Sessions 탭에서 다시 시작하세요"
    fi
    HUBC_JOINED=0; HUBC_PANE=""; HUBC_ORIGIN=""; HUBC_KEEP=""
    tmux select-pane -t "$TMUX_PANE" 2>/dev/null
    printf '\033[2J'
  }
  _hubc_mirror() { # mirror the hub pane's live screen into the content area
    local pane w h
    pane=$(_hubc_pane) || return 1
    w=$LW; h=$LISTBODY
    [ "$w" -gt 20 ] && [ "$h" -gt 3 ] || return 1
    # Match the pane to the area we paint into so nothing wraps or gets clipped.
    # Only safe while nobody is attached — a client would fight us for the size.
    if [ "$(tmux display-message -p -t "$pane" '#{session_attached}' 2>/dev/null)" = 0 ]; then
      if [ "$HUBC_SIZE" != "${w}x${h}" ]; then
        tmux set-option -w -t "$pane" window-size manual 2>/dev/null
        tmux resize-window -t "$pane" -x "$w" -y "$h" 2>/dev/null && HUBC_SIZE="${w}x${h}"
      fi
    fi
    HUBC_VIEW=()
    while IFS= read -r line; do HUBC_VIEW+=("$line"); done < <(tmux capture-pane -e -p -t "$pane" 2>/dev/null)
    [ "${#HUBC_VIEW[@]}" -gt 0 ]
  }
  _hubc_open() { # hand the terminal to the hub's own Claude UI, then come back
    local pane
    pane=$(_hubc_pane) || return 1
    # Rebuilding the chat in bash can never stream or look like Claude's own UI —
    # so show the real pane instead. Detaching returns to the dashboard.
    _dash_cleanup
    printf '\033[?1049l\033[2J\033[H'
    if inside_loomo_tmux; then
      # Already a client of this server — attaching again would nest.
      tmux switch-client -t "=$HUB" 2>/dev/null
      tmux select-pane -t "$pane" 2>/dev/null
      tmux resize-pane -Z -t "$pane" 2>/dev/null
    else
      tmux attach -t "=$HUB" \; select-pane -t "$pane" \; resize-pane -Z -t "$pane" 2>/dev/null
    fi
    # Re-enter the TUI exactly as the dashboard first set it up.
    stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null
    printf '%s\033[?1049h\033[2J\033[?1000h\033[?1002h\033[?1003h\033[?1006h\033[?25l\033[?7l' "$(_theme_osc)"
    HUBC_MSG=""; HUBC_SEEN_AT=-99
    return 0
  }
  _hubc_key() { # forward one keypress to the hub pane; non-zero = not ours to send
    local k="$1" pane byte
    pane=$(_hubc_pane) || return 1
    case "$k" in
      UP)    tmux send-keys -t "$pane" Up 2>/dev/null; return 0 ;;
      DOWN)  tmux send-keys -t "$pane" Down 2>/dev/null; return 0 ;;
      LEFT)  tmux send-keys -t "$pane" Left 2>/dev/null; return 0 ;;
      RIGHT) tmux send-keys -t "$pane" Right 2>/dev/null; return 0 ;;
      BTAB)  tmux send-keys -t "$pane" BTab 2>/dev/null; return 0 ;;
      "")    tmux send-keys -t "$pane" Enter 2>/dev/null; return 0 ;;
      $'\x7f'|$'\b') tmux send-keys -t "$pane" BSpace 2>/dev/null; return 0 ;;
      $'\t')  tmux send-keys -t "$pane" Tab 2>/dev/null; return 0 ;;
      ESCAPE|$'\x1b') tmux send-keys -t "$pane" Escape 2>/dev/null; return 0 ;;
    esac
    # Control characters keep their meaning (C-c interrupts, C-u clears, …).
    byte=$(LC_ALL=C printf '%d' "'$k" 2>/dev/null); [ "${byte:-0}" -lt 0 ] 2>/dev/null && byte=$((byte+256))
    if [ "${byte:-0}" -ge 1 ] 2>/dev/null && [ "${byte:-0}" -le 26 ]; then
      tmux send-keys -t "$pane" "C-$(printf "\\$(printf '%03o' $((byte+96)))")" 2>/dev/null
      return 0
    fi
    # Anything printable (including multi-byte UTF-8) goes through literally.
    [ -n "$k" ] || return 1
    tmux send-keys -t "$pane" -l "$k" 2>/dev/null
    return 0
  }
  _hubc_send() { # deliver one message to the hub pane without leaving the dashboard
    local msg="$1" pane
    [ -n "$msg" ] || return
    pane=$(_hubc_pane) || return 1
    # Same delivery tell uses: type the text, then submit.
    tmux send-keys -t "$pane" -l "$msg" 2>/dev/null
    sleep 0.4
    tmux send-keys -t "$pane" Enter 2>/dev/null
    HUBC_ROLE+=("user"); HUBC_TEXT+=("${msg//$'\n'/$'\001'}")
    HUBC_WAITING=1; HUBC_MSG=""
    return 0
  }
  _settings_skill_start() {
    FLOW=SkillAdd; FSTEP=1; INPUT=""; LOG=("${C_B}＋ Add Markdown skill${C_X}" "" "이 화면에 .md 파일을 드래그앤드롭하세요." "${C_D}직접 경로를 입력해도 됩니다.${C_X}")
  }
  _flow_skill_add() { local raw="$1" output
    [ -n "$raw" ] || { _say "Markdown 파일 경로가 필요해요:"; return; }
    output=$(LOOMO_SKILL_NO_PAUSE=1 cmd_skill_add "$raw" 2>&1) || { _say "${C_R}${output:-스킬 추가 실패}${C_X}"; return; }
    SETTINGS_MSG=$(printf '%s' "$output" | LC_ALL=C awk '/Added skill:/{sub(/^.*Added skill: /,""); print; exit}')
    SETTINGS_MSG="Skill added · ${SETTINGS_MSG:-ready}"
    FLOW=""; FSTEP=0; INPUT=""; mtop=0
  }
  _settings_skill_delete_confirm() { local slug="$1" output
    output=$(cmd_skill_delete "$slug" 2>&1) || { SETTINGS_MSG="${output:-Skill delete failed}"; SKILL_DELETE=""; return 1; }
    SETTINGS_MSG="Skill deleted · $slug"; SKILL_DELETE=""; mtop=0
  }
  _settings_sync() { # refresh every project's CLAUDE.md/AGENTS.md convention block (quiet; output stays off the alt-screen)
    local output rc count
    output=$(cmd_sync 2>&1); rc=$?
    load_agent_profile "$TELL_AGENT"   # cmd_sync switches profiles per panel; restore the dashboard default
    if [ "$rc" -eq 0 ]; then
      count=$(printf '%s' "$output" | LC_ALL=C awk '/convention file\(s\) refreshed/{print $1; exit}')
      SETTINGS_MSG="Conventions synced · ${count:-0} file(s) refreshed"
    elif printf '%s' "$output" | grep -q 'no registered panels'; then
      SETTINGS_MSG="Sync skipped · 등록된 패널이 없습니다"
    else
      SETTINGS_MSG="Sync failed · 일부 규약을 갱신하지 못했습니다"
    fi
    mtop=0
  }
  _settings_bypass_toggle() { # persist the claude approval-bypass setting the launch code reads
    local f="$CONFIG_DIR/claude-bypass" cur=0 v=""
    [ -f "$f" ] && { read -r v < "$f" 2>/dev/null; [ "$v" = 1 ] && cur=1; }
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    if [ "$cur" = 1 ]; then printf '0\n' > "$f"; SETTINGS_MSG="Claude bypass off · 위임 패널의 승인 분류기 복원 (새 패널부터)"
    else printf '1\n' > "$f"; SETTINGS_MSG="Claude bypass on · 위임 패널이 승인에서 안 멈춤 (새 패널부터)"; fi
    mtop=0
  }
  _settings_model_cycle() { # $1=claude|codex — cycle the model every new pane launches with
    local agent="$1" f="$CONFIG_DIR/model-$1" cur next
    cur=$(_loomo_model "$agent"); [ -n "$cur" ] || cur=auto
    if [ "$agent" = claude ]; then
      case "$cur" in auto) next=opus ;; opus) next=sonnet ;; sonnet) next=haiku ;; *) next=auto ;; esac
    else
      case "$cur" in auto) next=gpt-5-codex ;; gpt-5-codex) next=gpt-5 ;; *) next=auto ;; esac
    fi
    mkdir -p "$CONFIG_DIR" 2>/dev/null; printf '%s\n' "$next" > "$f" 2>/dev/null
    SETTINGS_MSG="$agent model → $next · 새 패널·재시작 세션부터 적용"
    mtop=0
  }
  _settings_theme_cycle() { # cycle loomo window theme auto → dark → light and apply live
    local f="$CONFIG_DIR/theme" next
    case "$(_loomo_theme)" in auto) next=dark ;; dark) next=light ;; *) next=auto ;; esac
    mkdir -p "$CONFIG_DIR" 2>/dev/null; printf '%s\n' "$next" > "$f" 2>/dev/null
    # Apply to this dashboard window immediately: reset any forced colors, then
    # re-force for the new theme (empty for auto → back to the terminal's own).
    printf '\033]110\007\033]111\007%s' "$(_theme_osc)"
    SETTINGS_MSG="Window theme → $next · 새 세션 창부터 반영"
    mtop=0
  }
  _open_session() { # double click: start if needed, then open in a new terminal window
    local session="$1" output rc
    loomo_log INFO dashboard.session.open "session=$session"
    if tmux has-session -t "=$session" 2>/dev/null; then
      loomo_log INFO dashboard.session.exists "session=$session"
    else
      output=$(ws_boot "$session" 2>&1); rc=$?
      if [ "$rc" -ne 0 ]; then
        loomo_log ERROR dashboard.session.boot_failed "session=$session" "rc=$rc" "error=${output:-unknown}"
        DETAIL_MSG="세션 시작 실패 · $LOOMO_LOG_FILE"
        return "$rc"
      fi
      loomo_log INFO dashboard.session.booted "session=$session"
    fi
    if ! open_terminal_window "$session"; then
      DETAIL_MSG="터미널 열기 실패 · $LOOMO_LOG_FILE"
      return 1
    fi
  }
  _session_click() {
    local session="$1" now
    now=$(perl -MTime::HiRes=time -e 'print int(time()*1000)' 2>/dev/null) || now=$(( $(date +%s) * 1000 ))
    DETAIL_SESSION="$session"; DETAIL_ADD=0; DETAIL_EDIT=0; DETAIL_DELETE=0; DETAIL_MSG=""
    DETAIL_PRESET=$(tmux show-option -wqv -t "=$session:" @loomo_layout 2>/dev/null)
    if [ "$LAST_CLICK_SESSION" = "$session" ] && [ $(( now - LAST_CLICK_TIME )) -le 450 ]; then
      loomo_log INFO dashboard.session.double_click "session=$session" "interval_ms=$(( now - LAST_CLICK_TIME ))"
      LAST_CLICK_SESSION=""; LAST_CLICK_TIME=0; _open_session "$session"
    else LAST_CLICK_SESSION="$session"; LAST_CLICK_TIME=$now; fi
  }

  # ── 렌더 ─────────────────────────────────────────────────────────
  _fit_cols() { # $1=text $2=terminal columns → FITTED/FIT_WIDTH (non-ASCII conservatively counts as 2)
    local src="$1" max="$2" out="" used=0 i ch w
    for ((i=0;i<${#src};i++)); do
      ch="${src:i:1}"; case "$ch" in [[:ascii:]]) w=1 ;; *) w=2 ;; esac
      [ $((used+w)) -gt "$max" ] && break
      out="$out$ch"; used=$((used+w))
    done
    FITTED="$out"; FIT_WIDTH=$used
  }
  _wrap_cols() { # $1=text $2=fixed line width $3=max lines → WRAPPED
    local src="$1" max="$2" limit="${3:-3}" line="" used=0 i ch w truncated=0
    WRAPPED=()
    for ((i=0;i<${#src};i++)); do
      ch="${src:i:1}"; case "$ch" in [[:ascii:]]) w=1 ;; *) w=2 ;; esac
      if [ $((used+w)) -gt "$max" ]; then
        WRAPPED+=("$line"); line=""; used=0
        if [ "${#WRAPPED[@]}" -ge "$limit" ]; then truncated=1; break; fi
      fi
      line="$line$ch"; used=$((used+w))
    done
    [ -n "$line" ] && [ "${#WRAPPED[@]}" -lt "$limit" ] && WRAPPED+=("$line")
    if [ "$truncated" = 1 ] && [ "${#WRAPPED[@]}" -gt 0 ]; then
      i=$(( ${#WRAPPED[@]} - 1 )); WRAPPED[$i]="${WRAPPED[$i]%?}…"
    fi
    [ "${#WRAPPED[@]}" -gt 0 ] || WRAPPED=("")
  }
  _pad_cols() { # $1=text $2=cell width → PADDED
    local text="$1" width="$2" pad
    _fit_cols "$text" "$width"; PADDED="$FITTED"; pad=$((width-FIT_WIDTH))
    while [ "$pad" -gt 0 ]; do PADDED="$PADDED "; pad=$((pad-1)); done
  }
  _slice_ansi_cols() { # ANSI-aware terminal-column slice → SLICED
    local src="$1" max="$2" out="" used=0 i=0 ch w
    # Most secondary-pane rows are blank or short. Avoid character-by-character
    # parsing on every mouse move when even double-width text is guaranteed to fit.
    if [ $(( ${#src} * 2 )) -le "$max" ]; then
      SLICED="$src"; return
    fi
    while [ "$i" -lt "${#src}" ]; do
      ch="${src:i:1}"
      if [ "$ch" = $'\033' ]; then
        while [ "$i" -lt "${#src}" ]; do
          ch="${src:i:1}"; out="$out$ch"; i=$((i+1)); [ "$ch" = m ] && break
        done
        continue
      fi
      case "$ch" in [[:ascii:]]) w=1 ;; *) w=2 ;; esac
      [ $((used+w)) -gt "$max" ] && break
      out="$out$ch"; used=$((used+w)); i=$((i+1))
    done
    SLICED="$out$C_X"
  }
  _main_row() { MLC+=("$1"); SACT+=("${2:-none}"); SARG+=("${3:-}"); SGROUP+=("${4:-}"); }
  _unassigned_row() { ULC+=("$1"); UACT+=("${2:-none}"); UARG+=("${3:-}"); UGROUP+=("${4:-}"); }
  _build_main() {  # 활성 탭 → MLC
    MLC=(); ULC=(); SACT=(); SARG=(); SGROUP=(); UACT=(); UARG=(); UGROUP=(); local name="${TABS[$tab]}"
    if [ "$name" = "Sessions" ]; then
      _flow_ensure
      [ "$ADOPT_LOADED" = 1 ] || _adopt_scan
      UP_ID=(); UP_AG=(); UP_DIR=(); UP_NAME=()
      if [ -f "$PANEL_CONF" ]; then
        local uid uag udir uname
        while IFS='|' read -r uid uag udir uname; do [ -n "$uid" ] || continue
          UP_ID+=("$uid"); UP_AG+=("$uag"); UP_DIR+=("$udir"); UP_NAME+=("$uname")
        done < "$PANEL_CONF"
      fi
      if [ -n "$DETAIL_SESSION" ] && [ "$ARRANGE_MODE" = 0 ]; then
        local dc dr dd did da drr ui pcount=0
        drr="${C_D}•${C_X}"; tmux has-session -t "=$DETAIL_SESSION" 2>/dev/null && drr="${C_X}${C_G}${C_B}•${C_X}"
        # Keep the session name before ANSI styling: the compact detail column
        # truncates raw strings, and leading escape sequences must not hide it.
        _unassigned_row "  ${C_C}${C_B}[← Back]${C_X}  $DETAIL_SESSION  $drr" detailheader "$DETAIL_SESSION"
        _unassigned_row ""
        if [ "$DETAIL_EDIT" = 1 ]; then _unassigned_row "  ${C_B}Panels${C_X}  ${C_G}${C_B}[Done]${C_X}" detailedit
        else _unassigned_row "  ${C_B}Panels${C_X}  ${C_C}[Edit]${C_X}" detailedit; fi
        while IFS='|' read -r dc dr dd did da; do
          [ -n "$dr" ] || continue
          pcount=$((pcount+1))
          if [ "$DETAIL_EDIT" = 1 ]; then
            _unassigned_row "  ${C_C}${C_B}[Edit]${C_X} ${C_R}${C_B}[Delete]${C_X} $dr" detailactions "$DETAIL_SESSION|$dr"
          else _unassigned_row "  ${C_D}· $dr (${da:-$TELL_AGENT})${C_X}"; fi
        done < <(grep -vE '^[[:space:]]*(#|$)' "$WS_CONF" 2>/dev/null | LC_ALL=C awk -F'|' -v s="$DETAIL_SESSION" '$1==s')
        if [ "$pcount" -ge 2 ]; then
          _unassigned_row ""
          _unassigned_row "  ${C_B}Layout${C_X}  ${C_D}$pcount panels · 클릭하면 즉시 적용${C_X}"
          if [ "$pcount" -eq 2 ]; then
            if [ "$DETAIL_PRESET" = even-horizontal ]; then drr="✓"; else drr=" "; fi
            _unassigned_row "  $drr ┌─────┬─────┐  side-by-side" detailpreset even-horizontal layout:even-horizontal
            _unassigned_row "    │  1  │  2  │" detailpreset even-horizontal layout:even-horizontal
            _unassigned_row "    └─────┴─────┘" detailpreset even-horizontal layout:even-horizontal
            if [ "$DETAIL_PRESET" = even-vertical ]; then drr="✓"; else drr=" "; fi
            _unassigned_row "  $drr ┌───────────┐  stacked" detailpreset even-vertical layout:even-vertical
            _unassigned_row "    │     1     │" detailpreset even-vertical layout:even-vertical
            _unassigned_row "    ├───────────┤" detailpreset even-vertical layout:even-vertical
            _unassigned_row "    │     2     │" detailpreset even-vertical layout:even-vertical
            _unassigned_row "    └───────────┘" detailpreset even-vertical layout:even-vertical
          else
            if [ "$DETAIL_PRESET" = main-vertical ]; then drr="✓"; else drr=" "; fi
            _unassigned_row "  $drr ┌───────┬───┐  main-vertical" detailpreset main-vertical layout:main-vertical
            _unassigned_row "    │   1   │ 2 │" detailpreset main-vertical layout:main-vertical
            _unassigned_row "    │       ├───┤" detailpreset main-vertical layout:main-vertical
            _unassigned_row "    │       │ 3 │" detailpreset main-vertical layout:main-vertical
            if [ "$pcount" -ge 4 ]; then
              _unassigned_row "    │       ├───┤" detailpreset main-vertical layout:main-vertical
              _unassigned_row "    │       │ 4 │" detailpreset main-vertical layout:main-vertical
            fi
            _unassigned_row "    └───────┴───┘" detailpreset main-vertical layout:main-vertical
            if [ "$DETAIL_PRESET" = main-horizontal ]; then drr="✓"; else drr=" "; fi
            _unassigned_row "  $drr ┌───────────┐  main-horizontal" detailpreset main-horizontal layout:main-horizontal
            _unassigned_row "    │     1     │" detailpreset main-horizontal layout:main-horizontal
            if [ "$pcount" -eq 3 ]; then
              _unassigned_row "    ├─────┬─────┤" detailpreset main-horizontal layout:main-horizontal
              _unassigned_row "    │  2  │  3  │" detailpreset main-horizontal layout:main-horizontal
              _unassigned_row "    └─────┴─────┘" detailpreset main-horizontal layout:main-horizontal
            else
              _unassigned_row "    ├───┬───┬───┤" detailpreset main-horizontal layout:main-horizontal
              _unassigned_row "    │ 2 │ 3 │ 4 │" detailpreset main-horizontal layout:main-horizontal
              _unassigned_row "    └───┴───┴───┘" detailpreset main-horizontal layout:main-horizontal
            fi
            if [ "$DETAIL_PRESET" = even-horizontal ]; then drr="✓"; else drr=" "; fi
            if [ "$pcount" -eq 3 ]; then
              _unassigned_row "  $drr ┌───┬───┬───┐  even-horizontal" detailpreset even-horizontal layout:even-horizontal
              _unassigned_row "    │ 1 │ 2 │ 3 │" detailpreset even-horizontal layout:even-horizontal
              _unassigned_row "    └───┴───┴───┘" detailpreset even-horizontal layout:even-horizontal
            else
              _unassigned_row "  $drr ┌──┬──┬──┬──┐  even-horizontal" detailpreset even-horizontal layout:even-horizontal
              _unassigned_row "    │1 │2 │3 │4 │" detailpreset even-horizontal layout:even-horizontal
              _unassigned_row "    └──┴──┴──┴──┘" detailpreset even-horizontal layout:even-horizontal
            fi
            if [ "$DETAIL_PRESET" = even-vertical ]; then drr="✓"; else drr=" "; fi
            _unassigned_row "  $drr ┌───────────┐  even-vertical" detailpreset even-vertical layout:even-vertical
            for ((ui=1;ui<=pcount && ui<=4;ui++)); do
              _unassigned_row "    │     $ui     │" detailpreset even-vertical layout:even-vertical
              [ "$ui" -lt "$pcount" ] && [ "$ui" -lt 4 ] && _unassigned_row "    ├───────────┤" detailpreset even-vertical layout:even-vertical
            done
            _unassigned_row "    └───────────┘" detailpreset even-vertical layout:even-vertical
            if [ "$DETAIL_PRESET" = tiled ]; then drr="✓"; else drr=" "; fi
            if [ "$pcount" -eq 3 ]; then
              _unassigned_row "  $drr ┌─────┬─────┐  tiled" detailpreset tiled layout:tiled
              _unassigned_row "    │  1  │  2  │" detailpreset tiled layout:tiled
              _unassigned_row "    ├─────┴─────┤" detailpreset tiled layout:tiled
              _unassigned_row "    │     3     │" detailpreset tiled layout:tiled
              _unassigned_row "    └───────────┘" detailpreset tiled layout:tiled
            else
              _unassigned_row "  $drr ┌─────┬─────┐  tiled" detailpreset tiled layout:tiled
              _unassigned_row "    │  1  │  2  │" detailpreset tiled layout:tiled
              _unassigned_row "    ├─────┼─────┤" detailpreset tiled layout:tiled
              _unassigned_row "    │  3  │  4  │" detailpreset tiled layout:tiled
              _unassigned_row "    └─────┴─────┘" detailpreset tiled layout:tiled
            fi
          fi
          [ "$pcount" -gt 4 ] && _unassigned_row "  ${C_D}미리보기는 첫 4개 패널 기준${C_X}"
        fi
        _unassigned_row ""
        if [ "$DETAIL_ADD" = 0 ]; then
          _unassigned_row "  ${C_C}${C_B}[＋ Add unassigned panel]${C_X}" detailadd
        else
          _unassigned_row "  ${C_B}Add panel${C_X}  ${C_D}선택하면 바로 추가${C_X}"
          _unassigned_row "  ${C_C}${C_B}[＋ New panel]${C_X}" detailnew
          if [ "${#UP_ID[@]}" -eq 0 ]; then _unassigned_row "  ${C_D}미배정 패널 없음${C_X}"
          else for ((ui=0;ui<${#UP_ID[@]};ui++)); do
            _unassigned_row "  ○ ${UP_NAME[$ui]} ${C_D}(${UP_AG[$ui]})${C_X}" detailpick "${UP_ID[$ui]}"
          done; fi
          _unassigned_row "  ${C_D}[Cancel]${C_X}" detailcancel
        fi
        _unassigned_row ""
        _unassigned_row "  ${C_D}────────────────────────────${C_X}"
        if [ "$DETAIL_DELETE" = 1 ]; then
          _unassigned_row "  ${C_R}Delete session '$DETAIL_SESSION'?${C_X}"
          _unassigned_row "  [Cancel] [Confirm delete]" detaildeleteconfirm "$DETAIL_SESSION"
        else
          _unassigned_row "  ${C_R}[Delete Session]${C_X}" detaildelete "$DETAIL_SESSION"
        fi
      else
        _unassigned_row "  ${C_Y}${C_B}Unassigned panels${C_X}"
        if [ "$ARRANGE_MODE" = 1 ]; then _unassigned_row "  ${C_D}배정할 패널을 선택하세요${C_X}"
        else _unassigned_row "  ${C_D}Edit arrangement로 배정${C_X}"; fi
        _unassigned_row ""
        if [ "${#UP_ID[@]}" -eq 0 ]; then _unassigned_row "  ${C_D}미배정 패널 없음${C_X}"
        else
          local ui mark
          for ((ui=0;ui<${#UP_ID[@]};ui++)); do
            mark="○"; [ "$PANEL_SELECTED" = 1 ] && [ -z "$PANEL_SOURCE_SESSION" ] && [ "${UP_ID[$ui]}" = "$PANEL_ID" ] && mark="${C_G}●${C_X}"
            if [ "$ARRANGE_MODE" = 1 ] && [ -z "$FLOW" ]; then
              _unassigned_row "  $mark ${UP_NAME[$ui]} ${C_D}(${UP_AG[$ui]})${C_X}" select "${UP_ID[$ui]}" "unassigned:${UP_ID[$ui]}"
              _unassigned_row "    ${C_D}${UP_DIR[$ui]/#$HOME/~}${C_X}" select "${UP_ID[$ui]}" "unassigned:${UP_ID[$ui]}"
            else
              _unassigned_row "  $mark ${UP_NAME[$ui]} (${UP_AG[$ui]})" panelview "${UP_ID[$ui]}" "unassigned:${UP_ID[$ui]}"
              _unassigned_row "    ${UP_DIR[$ui]/#$HOME/~}" panelview "${UP_ID[$ui]}" "unassigned:${UP_ID[$ui]}"
            fi
          done
        fi
      fi
      if [ -n "$FLOW" ]; then
        if { [ "$FLOW" = Add ] || [ "$FLOW" = DetailNewPanel ]; } && [ "$ADD_BROWSE" = 1 ]; then
          local browse_title="Add project"; [ "$FLOW" = DetailNewPanel ] && browse_title="New panel → $FNAME"
          _main_row "  ${C_C}${C_B}[← Back]${C_X}  ${C_C}${C_B}$browse_title${C_X}" addback
          _main_row ""
          _main_row "  ${C_B}📁 폴더 선택${C_X}"
          _main_row "  ${C_D}현재: ${BROWSE_DIR/#$HOME/~}${C_X}"
          _main_row ""
          _main_row "  ${C_G}${C_B}[✓ 이 폴더 선택]${C_X}" dirselect
          _main_row "  ${C_C}[↑ 상위 폴더]${C_X}" dirparent
          _main_row "  ${C_D}[취소]${C_X}" dircancel
          _main_row ""
          local bd bn
          for bd in "$BROWSE_DIR"/*/; do
            [ -d "$bd" ] || continue; bd=${bd%/}; bn=${bd##*/}
            _main_row "  📁 $bn/" diropen "$bd"
          done
        else
          if [ "$FLOW" = Add ] || [ "$FLOW" = DetailNewPanel ]; then
            local flow_title="Add project"; [ "$FLOW" = DetailNewPanel ] && flow_title="New panel → $FNAME"
            _main_row "  ${C_C}${C_B}[← Back]${C_X}  ${C_C}${C_B}$flow_title${C_X}" addback
            _main_row ""
            local li; for ((li=0;li<${#LOG[@]};li++)); do _main_row "${LOG[$li]}"; done
            if [ "$FSTEP" = 1 ]; then
              _main_row "  ${C_C}${C_B}[ Claude ]${C_X}" agentchoice claude "agent:claude"
              _main_row "  ${C_C}${C_B}[ Codex  ]${C_X}" agentchoice codex "agent:codex"
            fi
            [ "$FLOW" = Add ] && [ "$FSTEP" = 4 ] && [ "${#MLC[@]}" -gt 0 ] && SACT[$(( ${#MLC[@]} - 1 ))]=browse
            [ "$FLOW" = DetailNewPanel ] && [ "$FSTEP" = 3 ] && [ "${#MLC[@]}" -gt 0 ] && SACT[$(( ${#MLC[@]} - 1 ))]=browse
          else MLC=(); [ "${#LOG[@]}" -gt 0 ] && MLC=("${LOG[@]}"); fi
        fi
      else
        _main_row "  ${C_C}${C_B}[＋ Add project]${C_X}" addproject
        if [ "$ARRANGE_MODE" = 1 ]; then _main_row "  ${C_G}${C_B}[✓ Done editing]${C_X}" arrange
        else _main_row "  ${C_C}${C_B}[✎ Edit arrangement]${C_X}" arrange; fi
        _main_row ""
        if [ "$ARRANGE_MODE" = 1 ]; then
          _main_row "  ${C_D}패널 선택 → 대상 프로젝트 선택 → Done editing${C_X}"
        fi
        local s reg _c role _d rid _a rr role_label role_line label_width prompt_width; reg=$(_reg_sessions)
        while IFS= read -r s; do [ -n "$s" ] || continue
          rr="__OFF__"
          tmux has-session -t "=$s" 2>/dev/null && rr="__ON__"
          if [ "$ARRANGE_MODE" = 1 ]; then
            if [ "$PENDING_TARGET" = "$s" ]; then _main_row "  $rr ${C_G}${C_B}✓ $s${C_X}  ${C_D}← 변경 예정${C_X}" target "$s"
            else _main_row "  $rr ${C_C}${C_B}$s${C_X}  ${C_D}← 배정${C_X}" target "$s"; fi
            else _main_row "  $rr $s" sessionopen "$s" "$s"; fi
          while IFS='|' read -r _c role _d rid _a; do
            if [ "$ARRANGE_MODE" = 1 ]; then
              local pmark="○"; [ "$PANEL_SOURCE_SESSION" = "$s" ] && [ "$PANEL_SOURCE_ROLE" = "$role" ] && pmark="${C_G}●${C_X}"
              _main_row "     $pmark $role  ${C_D}(${_a:-$TELL_AGENT}${rid:+ · resumed})${C_X}" selectassigned "$s|$role"
            else
              label_width=20
              if [ $(( SESSION_LEFT_W - 7 - label_width - 3 )) -lt 4 ]; then
                label_width=$(( SESSION_LEFT_W - 14 ))
              fi
              [ "$label_width" -lt 6 ] && label_width=6
              role_label="$role (${_a:-$TELL_AGENT})"; _pad_cols "$role_label" "$label_width"
              role_line="       $PADDED"
              if _panel_recent_prompt "${_a:-$TELL_AGENT}" "$_d" "$rid"; then
                prompt_width=$(( SESSION_LEFT_W - 7 - label_width - 3 ))
                if [ "$prompt_width" -ge 4 ]; then
                  _fit_cols "$RP_TEXT" "$prompt_width"; role_line="$role_line   $FITTED"
                fi
              fi
              _main_row "$role_line" panelview "$s" "$s"
            fi
          done < <(grep -vE '^[[:space:]]*(#|$)' "$WS_CONF" 2>/dev/null | LC_ALL=C awk -F'|' -v s="$s" '$1==s')
        done <<EOF
$reg
EOF
        [ -z "$reg" ] && { _main_row ""; _main_row "  아직 프로젝트가 없어요. Add 탭에서 먼저 만들어보세요."; }
      fi
    elif [ "$name" = "Hub" ]; then
      _hubc_poll
      local hb_i hb_w hb_seg hb_line hb_body rr
      if ! get_hub 2>/dev/null || [ -z "${HUB:-}" ]; then
        _main_row "  ${C_B}Hub chat${C_X}"
        _main_row ""
        _main_row "  ${C_D}허브 세션이 지정되지 않았어요.${C_X}"
        _main_row "  ${C_C}${C_B}[Settings → Hub session]${C_X} 에서 먼저 지정하세요." settingshubjump
      else
        # Preferred: borrow the hub's actual pane into this window, so typing goes
        # to Claude natively. Mirroring is the fallback for a dashboard that isn't
        # running as a pane (an older launch, or tmux unavailable).
        if _hubc_attach_pane; then
          _main_row "  ${C_D}비서 패널이 아래에 열렸습니다 · 그 안에서 바로 입력하세요${C_X}"
        elif _hubc_mirror; then
          for hb_line in ${HUBC_VIEW[@]+"${HUBC_VIEW[@]}"}; do _main_row "$hb_line"; done
        else
          _main_row "  ${C_B}Hub${C_X}  ${C_D}$HUB:$HUBR${C_X}"
          _main_row ""
          _main_row "  ${C_D}${HUBC_MSG:-허브 화면을 불러오지 못했어요}${C_X}"
          _main_row "  ${C_C}${C_B}[대화 열기]${C_X}  ${C_D}전체 화면으로 열기 · 나올 때 Ctrl-b d${C_X}" hubopen
        fi
      fi
    elif [ "$name" = "Settings" ]; then
      _flow_ensure
      local ss sc role sd srid sa rr reg ast; reg=$(_reg_sessions)
      if [ "$FLOW" = SkillAdd ]; then
        MLC=()
        _main_row "  ${C_C}${C_B}[← Back]${C_X}  ${C_C}${C_B}Add Markdown skill${C_X}" settingsskillback
        _main_row ""
        local sli; for ((sli=0;sli<${#LOG[@]};sli++)); do _main_row "${LOG[$sli]}"; done
      elif [ "$SETTINGS_PAGE" = main ]; then
        [ "$CLAUDE_AUTH" = unknown ] && _settings_auth_refresh
        _main_row "  ${C_C}${C_B}Settings${C_X}"
        _main_row ""
        _main_row "  ${C_B}Hub session${C_X}"
        rr="__OFF__"; [ -n "${HUB:-}" ] && tmux has-session -t "=$HUB" 2>/dev/null && rr="__ON__"
        if [ -n "${HUB:-}" ]; then _main_row "  $rr ${C_B}$HUB${C_X}  ${C_D}[Change]${C_X}" settingshub
        else _main_row "  ${C_D}Not selected${C_X}  ${C_C}[Configure]${C_X}" settingshub; fi
        _main_row ""
        _main_row "  ${C_B}Conventions${C_X}  ${C_D}협업 규약 동기화${C_X}"
        _main_row "  ${C_C}${C_B}[⟳ Sync now]${C_X}  ${C_D}모든 CLAUDE.md/AGENTS.md 갱신${C_X}" settingssync
        _main_row ""
        local bypass_on=0; [ "$(cat "$CONFIG_DIR/claude-bypass" 2>/dev/null)" = 1 ] && bypass_on=1
        _main_row "  ${C_B}Delegated claude panes${C_X}  ${C_D}승인 프롬프트에서 안 멈춤${C_X}"
        if [ "$bypass_on" = 1 ]; then _main_row "  ${C_G}${C_B}● Bypass on${C_X}   ${C_D}[Turn off]${C_X}" settingsbypass
        else _main_row "  ${C_D}○ Bypass off${C_X}  ${C_C}[Turn on]${C_X}" settingsbypass; fi
        _main_row ""
        local theme_now; theme_now=$(_loomo_theme)
        _main_row "  ${C_B}Window theme${C_X}  ${C_D}loomo 창 색 · 터미널 설정 불필요${C_X}"
        _main_row "  ${C_C}${C_B}[${theme_now}]${C_X}  ${C_D}클릭 = auto → dark → light${C_X}" settingstheme
        _main_row ""
        _main_row "  ${C_B}AI models${C_X}  ${C_D}[Refresh status]${C_X}" authrefresh
        _main_row "  ${C_D}새 패널과 재시작 세션은 선택된 계정으로 열립니다${C_X}"
        _main_row ""
        # Logins finish in a separate terminal, so re-read the (file-backed) account
        # rows every few seconds — otherwise a new account sits invisible until
        # someone presses [Refresh status]. Live identities stay cached.
        [ $(( SECONDS - ACCT_SEEN_AT )) -ge 3 ] && _settings_accounts_refresh
        local ap_provider ap_id ap_label ap_active ap_identity ap_plan ap_token ap_mark ap_detail ap_action ap_row ap_plain ap_logout_x ap_model ap_model_note
        local ap_rows=()
        for ap_provider in claude codex; do
          if [ "$ap_provider" = claude ]; then _main_row "  ${C_B}Claude${C_X}"
          else _main_row ""; _main_row "  ${C_B}Codex${C_X}"; fi
          ap_model=$(_loomo_model "$ap_provider"); [ -n "$ap_model" ] || ap_model="auto"
          # Aliases ('opus') and 'auto' only say which family — show the concrete
          # model the newest conversation actually ran on so the version is visible.
          ap_model_note=""
          if [ "$ap_provider" = claude ] && [ -n "$RECENT_MODEL" ]; then
            case "$ap_model" in
              *-*[0-9]*) : ;;   # already a full model name
              *) ap_model_note="  ${C_D}최근 실행: ${RECENT_MODEL}${C_X}" ;;
            esac
          fi
          _main_row "    ${C_D}Model${C_X}  ${C_C}${C_B}[$ap_model]${C_X}${ap_model_note}  ${C_D}클릭해서 변경${C_X}" acctmodel "$ap_provider"
          if [ "$ap_provider" = claude ]; then ap_rows=(${CLAUDE_ACCT[@]+"${CLAUDE_ACCT[@]}"})
          else ap_rows=(${CODEX_ACCT[@]+"${CODEX_ACCT[@]}"}); fi
          for ap_row in ${ap_rows[@]+"${ap_rows[@]}"}; do
            _split6 "$ap_row"
            ap_id=$F1; ap_label=$F2; ap_active=$F3; ap_identity=$F4; ap_plan=$F5; ap_token=$F6
            # ap_token: 1 = stored login, 2 = the live CLI login (default profile), 0 = none
            ap_mark="${C_D}○${C_X}"; ap_action="${C_G}[Login]${C_X}"
            [ "$ap_active" = 1 ] && ap_mark="${C_G}${C_B}●${C_X}"
            if [ "$ap_active" = 1 ]; then ap_action="${C_D}사용 중${C_X}"
            elif [ "$ap_token" != 0 ]; then ap_action="${C_C}[전환]${C_X}"; fi
            ap_detail="${ap_identity:-$ap_label}"; [ -n "$ap_plan" ] && ap_detail="$ap_detail · $ap_plan"
            # Every account can be removed, so each row carries [Logout]. Two hit
            # zones: left of it switches (or finishes a login), the rest signs out.
            if [ "$ap_active" = 1 ]; then ap_plain="    ● $ap_detail  $ap_id  사용 중  "
            elif [ "$ap_token" != 0 ]; then ap_plain="    ○ $ap_detail  $ap_id  [전환]  "
            else ap_plain="    ○ $ap_detail  $ap_id  [Login]  "; fi
            _fit_cols "$ap_plain" 10000; ap_logout_x=$((FIT_WIDTH+1))
            _main_row "    $ap_mark $ap_detail  ${C_D}$ap_id${C_X}  $ap_action  ${C_R}[Logout]${C_X}" \
              acctrow "$ap_provider|$ap_id|$ap_active|$ap_token|$ap_logout_x"
            if [ "$ACCT_SWITCH" = "$ap_provider|$ap_id" ]; then
              _main_row "      ${C_Y}이 계정으로 전환할까요?${C_X}  ${C_D}모든 새 패널이 이 계정으로 열립니다${C_X}"
              _main_row "      ${C_D}[취소]${C_X}" acctswitchcancel
              _main_row "      ${C_C}${C_B}[전환]${C_X}" acctswitchconfirm "$ap_provider|$ap_id"
            fi
          done
          _main_row "    ${C_C}[＋ Add $ap_provider account]${C_X}" accountadd "$ap_provider"
        done
        _main_row "  ${C_D}CLI: loomo account list · use <provider> <id>${C_X}"
        _main_row ""
        local skill_count=0 skill_path skill_dir skill_slug skill_name
        [ -d "$SKILL_DIR" ] && skill_count=$(find "$SKILL_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
        _main_row "  ${C_B}Skills${C_X}  ${C_D}$skill_count installed${C_X}"
        _main_row "  ${C_C}${C_B}[＋ Add Markdown skill]${C_X}" settingsskill
        if [ "$skill_count" -gt 0 ]; then
          for skill_path in "$SKILL_DIR"/*/SKILL.md; do
            [ -f "$skill_path" ] || continue
            skill_dir=$(dirname "$skill_path"); skill_slug=$(basename "$skill_dir")
            skill_name=$(cat "$skill_dir/name" 2>/dev/null || printf '%s' "$skill_slug")
            _main_row "  · $skill_name  ${C_R}[Delete]${C_X}" settingsskilldelete "$skill_slug"
            if [ "$SKILL_DELETE" = "$skill_slug" ]; then
              _main_row "    ${C_R}Delete this skill?${C_X}"
              _main_row "    ${C_D}[Cancel]${C_X}" settingsskillcancel
              _main_row "    ${C_R}${C_B}[Confirm delete]${C_X}" settingsskillconfirm "$skill_slug"
            fi
          done
        fi
      elif [ "$SETTINGS_PAGE" = hub ]; then
        _main_row "  ${C_C}${C_B}[← Back]${C_X}  ${C_C}${C_B}Hub session${C_X}" settingsback
        _main_row "  ${C_D}비서로 사용할 세션을 선택하세요${C_X}"
        _main_row ""
        while IFS= read -r ss; do [ -n "$ss" ] || continue
          rr="__OFF__"; tmux has-session -t "=$ss" 2>/dev/null && rr="__ON__"
          if [ "$ss" = "${HUB:-}" ]; then _main_row "  $rr ${C_G}${C_B}✓ $ss${C_X}  ${C_D}Current${C_X}" sethub "$ss" "hub:$ss"
          else _main_row "  $rr $ss" sethub "$ss" "hub:$ss"; fi
          while IFS='|' read -r sc role sd srid sa; do
            _main_row "       · $role  (${sa:-$TELL_AGENT}${srid:+ · resumed})" sethub "$ss" "hub:$ss"
          done < <(grep -vE '^[[:space:]]*(#|$)' "$WS_CONF" 2>/dev/null | LC_ALL=C awk -F'|' -v s="$ss" '$1==s')
        done <<EOF
$reg
EOF
        [ -n "$reg" ] || _main_row "  ${C_D}선택할 프로젝트 세션이 없습니다.${C_X}"
      fi
    elif [ "$name" = "Adopt" ]; then
      _flow_ensure
      if [ "$FLOW" = SessionAdopt ]; then
        MLC=(); [ "${#LOG[@]}" -gt 0 ] && MLC=("${LOG[@]}")
      else
        local ai ac=0 cc=0 age mark group shown=0 cf kf sid_short title_width title line sid_cell age_cell preview_blob msg body chat_width list_width pad spaces ui wi bubble_width button_gap button_target
        for ((ai=0;ai<${#AD_ID[@]};ai++)); do
          [ "${AD_USED[$ai]}" = 0 ] || continue
          case "${AD_AGENT[$ai]}" in claude) ac=$((ac+1)) ;; codex) cc=$((cc+1)) ;; esac
        done
        if [ "$ADOPT_FILTER" = claude ]; then cf="${C_C}${C_B}"; kf="${C_D}"; else cf="${C_D}"; kf="${C_C}${C_B}"; fi
        _main_row "  ${C_C}${C_B}Adopt AI conversation${C_X}"
        _main_row "  ${cf}[Claude $ac]${C_X}  ${kf}[Codex $cc]${C_X}  ${C_D}[Refresh]${C_X}" adoptfilters
        _main_row ""
        for ((ai=0;ai<${#AD_ID[@]};ai++)); do
          [ "${AD_AGENT[$ai]}" = "$ADOPT_FILTER" ] && [ "${AD_USED[$ai]}" = 0 ] || continue
          shown=$((shown+1)); group="adopt:${AD_ID[$ai]}"; age=$(_adopt_age "${AD_TIME[$ai]}"); sid_short="${AD_ID[$ai]:0:11}…"
          _pad_cols "$sid_short" 13; sid_cell="$PADDED"
          _pad_cols "$age" 10; age_cell="$PADDED"
          list_width=$LW; [ "$SESSION_LEFT_W" -gt 0 ] && list_width=$SESSION_LEFT_W
          title_width=$(( list_width - 31 )); [ "$title_width" -lt 4 ] && title_width=4
          _fit_cols "${AD_TITLE[$ai]}" "$title_width"; title="$FITTED"
          line="  $sid_cell  $age_cell  $title"
          _main_row "$line" adoptsession "${AD_ID[$ai]}" "$group"
          if [ "$ADOPT_SELECTED" = "${AD_ID[$ai]}" ]; then
            # The Adopt preview uses viewport-relative rows, independent of the
            # scrolling conversation list on the left.
            chat_width=$(( LW - SESSION_LEFT_W - 1 )); [ "$chat_width" -lt 16 ] && chat_width=16
            _unassigned_row "  ${C_C}${C_B}Context preview${C_X}  ${C_D}latest 4${C_X}"
            _unassigned_row "  ${C_D}${AD_AGENT[$ai]} · ${AD_TURNS[$ai]} total turns · ${AD_ID[$ai]:0:12}…${C_X}"
            _fit_cols "${AD_DIR[$ai]/#$HOME/~}" $((chat_width-4))
            _unassigned_row "  ${C_D}$FITTED${C_X}"
            _unassigned_row ""
            bubble_width=28
            [ $((chat_width-10)) -lt "$bubble_width" ] && bubble_width=$((chat_width-10))
            [ "$bubble_width" -lt 12 ] && bubble_width=12
            preview_blob="${AD_PREVIEW[$ai]}"
            if [ -n "$preview_blob" ]; then
              while IFS= read -r msg; do
                case "$msg" in
                  U:*)
                    body="${msg#U:}"; _wrap_cols "$body" "$bubble_width" 3
                    pad=$((chat_width-2)); [ "$pad" -lt 0 ] && pad=0; spaces=""
                    while [ "$pad" -gt 0 ]; do spaces="$spaces "; pad=$((pad-1)); done
                    _unassigned_row "$spaces${C_C}${C_B}나${C_X}"
                    for ((wi=0;wi<${#WRAPPED[@]};wi++)); do
                      _fit_cols "${WRAPPED[$wi]}" "$bubble_width"
                      pad=$((chat_width-FIT_WIDTH)); [ "$pad" -lt 0 ] && pad=0; spaces=""
                      while [ "$pad" -gt 0 ]; do spaces="$spaces "; pad=$((pad-1)); done
                      _unassigned_row "$spaces${WRAPPED[$wi]}"
                    done
                    _unassigned_row "" ;;
                  A:*)
                    body="${msg#A:}"; _wrap_cols "$body" "$bubble_width" 3
                    _unassigned_row "${C_G}${C_B}AI${C_X}"
                    for ((wi=0;wi<${#WRAPPED[@]};wi++)); do
                      _unassigned_row "${WRAPPED[$wi]}"
                    done
                    _unassigned_row "" ;;
                  *) continue ;;
                esac
              done <<< "${preview_blob//$'\x1e'/$'\n'}"
            else
              _unassigned_row "  ${C_D}미리볼 대화가 없습니다${C_X}"
            fi
            button_target=$((LISTBODY-2))
            while [ "${#ULC[@]}" -lt "$button_target" ]; do _unassigned_row ""; done
            _unassigned_row "  ${C_D}────────────────────────────────────────${C_X}"
            button_gap=$((chat_width-29)); [ "$button_gap" -lt 2 ] && button_gap=2; spaces=""
            while [ "$button_gap" -gt 0 ]; do spaces="$spaces "; button_gap=$((button_gap-1)); done
            _unassigned_row "  ${C_G}${C_B}[Adopt conversation]${C_X}$spaces${C_C}${C_B}[Close]${C_X}" adoptpreviewactions "${AD_ID[$ai]}"
          fi
        done
        [ "$shown" -eq 0 ] && _main_row "  ${C_D}${ADOPT_MSG:-표시할 $ADOPT_FILTER 세션이 없습니다}${C_X}"
        _main_row ""
        _main_row "  ${C_D}[Enter session ID manually]${C_X}" adoptmanual
      fi
    else _flow_ensure; MLC=(); [ "${#LOG[@]}" -gt 0 ] && MLC=("${LOG[@]}"); fi
    local content_rows=${#MLC[@]}
    [ "$name" = Sessions ] && [ "${#ULC[@]}" -gt "$content_rows" ] && content_rows=${#ULC[@]}
    MMAX=$(( content_rows - LISTBODY )); [ "$MMAX" -lt 0 ] && MMAX=0
    [ "$mtop" -gt "$MMAX" ] && mtop=$MMAX; [ "$mtop" -lt 0 ] && mtop=0
  }
  _style_item() { # $1=result variable $2=text $3=active(0/1); status dot keeps its own color
    local __out="$1" v="$2" active="$3" code tone
    for code in "$C_B" "$C_D" "$C_C" "$C_G" "$C_Y" "$C_R" "$C_X"; do [ -n "$code" ] && v=${v//"$code"/}; done
    if [ "$active" = 1 ]; then tone="$C_ACTIVE"; else tone="$C_MUTED"; fi
    v=${v//__ON__/"${C_X}${C_G}${C_B}•${C_X}${tone}"}
    v=${v//__OFF__/"${C_D}•${C_X}${tone}"}
    printf -v "$__out" '%s%s%s' "$tone" "$v" "$C_X"
  }
  _draw_main() { local r s us idx uidx sact uact group ugroup active uw shown
    for ((r=0;r<LISTBODY;r++)); do
      idx=$((mtop+r)); s="${MLC[$idx]:-}"; sact="${SACT[$idx]:-none}"; group="${SGROUP[$idx]:-}"; active=0
      if [ -n "$group" ] && [ "$HOVER_GROUP" = "$group" ]; then active=1
      elif [ "$HOVER_AREA" = main ] && [ "$HOVER_INDEX" -eq "$idx" ]; then active=1; fi
      case "$sact" in sessionopen|target|selectassigned|panelview|sethub|settingshub|agentchoice|browse|diropen|dirselect|dirparent|dircancel|adoptsession|adoptconfirm|adoptclose|adoptmanual) _style_item s "$s" "$active" ;; *) [ "$active" = 1 ] && s="${C_C}${C_B}›${C_X}${s:1}" ;; esac
      if [ "$SESSION_LEFT_W" -gt 0 ] && { [ "${TABS[$tab]}" = Sessions ] || [ "${TABS[$tab]}" = Adopt ]; }; then
        uidx=$idx; [ "${TABS[$tab]}" = Adopt ] && uidx=$r
        us="${ULC[$uidx]:-}"; uact="${UACT[$uidx]:-none}"; active=0
        ugroup="${UGROUP[$uidx]:-}"
        if [ -n "$ugroup" ] && [ "$HOVER_GROUP" = "$ugroup" ]; then active=1
        elif [ "$HOVER_AREA" = unassigned ] && [ "$HOVER_INDEX" -eq "$idx" ]; then active=1; fi
        [ "$uact" = detailpreset ] && [ "${UARG[$uidx]:-}" = "$DETAIL_PRESET" ] && active=1
        case "$uact" in
          select|panelview|detailpick|detailremove|detailnew|adoptconfirm|adoptclose) _style_item us "$us" "$active" ;;
          detailpreset) : ;;
          detailedit|detailactions|adoptpreviewactions) : ;; # embedded buttons keep their own styling
          *) [ "$active" = 1 ] && us="${C_C}${C_B}›${C_X}${us:1}" ;;
        esac
        printf '\033[%d;1H%*s' "$((r+4))" "$LW" ""
        printf '\033[%d;1H%s' "$((r+4))" "${s:0:$SESSION_LEFT_W}"
        if [ "${TABS[$tab]}" = Adopt ]; then uw=$(( LW - SESSION_LEFT_W - 1 ))
        else uw=$(( LW - SESSION_LEFT_W - 2 )); fi
        _slice_ansi_cols "$us" "$uw"; shown="$SLICED"
        if [ "$uact" = detailpreset ]; then
          if [ "$active" = 1 ]; then shown="${C_ACTIVE}${shown}${C_X}"; else shown="${C_MUTED}${shown}${C_X}"; fi
        fi
        if [ "${TABS[$tab]}" = Adopt ]; then
          printf '\033[%d;%dH%s│%s%s' "$((r+4))" "$((SESSION_LEFT_W+1))" "${C_D}" "${C_X}" "$shown"
        else
          printf '\033[%d;%dH%s│%s %s' "$((r+4))" "$((SESSION_LEFT_W+1))" "${C_D}" "${C_X}" "$shown"
        fi
      elif [ "${TABS[$tab]}" = Hub ]; then
        # Mirrored pane rows carry their own colors: slice by columns, not bytes,
        # or an escape sequence gets cut in half and the styling bleeds.
        _slice_ansi_cols "$s" "$LW"
        printf '\033[%d;1H%*s' "$((r+4))" "$LW" ""
        printf '\033[%d;1H%s\033[0m' "$((r+4))" "$SLICED"
      else
        printf '\033[%d;1H%*s' "$((r+4))" "$LW" ""
        printf '\033[%d;1H%s' "$((r+4))" "${s:0:$LW}"
      fi
    done
  }
  _draw_scroll() { # Adopt preview stays untouched while only its left list scrolls
    if [ "${TABS[$tab]}" = Adopt ] && [ -n "$ADOPT_SELECTED" ] && [ "$SESSION_LEFT_W" -gt 0 ]; then
      local r idx s sact group active
      for ((r=0;r<LISTBODY;r++)); do
        idx=$((mtop+r)); s="${MLC[$idx]:-}"; sact="${SACT[$idx]:-none}"; group="${SGROUP[$idx]:-}"; active=0
        if [ -n "$group" ] && [ "$HOVER_GROUP" = "$group" ]; then active=1
        elif [ "$HOVER_AREA" = main ] && [ "$HOVER_INDEX" -eq "$idx" ]; then active=1; fi
        case "$sact" in
          sessionopen|target|selectassigned|panelview|sethub|settingshub|agentchoice|browse|diropen|dirselect|dirparent|dircancel|adoptsession|adoptconfirm|adoptclose|adoptmanual) _style_item s "$s" "$active" ;;
          *) [ "$active" = 1 ] && s="${C_C}${C_B}›${C_X}${s:1}" ;;
        esac
        printf '\033[%d;1H%*s' "$((r+4))" "$SESSION_LEFT_W" ""
        printf '\033[%d;1H%s' "$((r+4))" "${s:0:$SESSION_LEFT_W}"
      done
    else
      _draw_main
    fi
  }

  _draw_tabs() { local col=2 i lbl
    printf '\033[2;1H '
    for ((i=0;i<${#TABS[@]};i++)); do
      if [ "$i" -eq "$tab" ]; then lbl="[${TABS[$i]}]"; else lbl=" ${TABS[$i]} "; fi
      TX0[$i]=$col; TX1[$i]=$(( col + ${#lbl} - 1 )); col=$(( col + ${#lbl} + 1 ))
      if [ "$i" -eq "$tab" ] || { [ "$HOVER_AREA" = tab ] && [ "$HOVER_INDEX" -eq "$i" ]; }; then printf '%s%s%s ' "${C_C}${C_B}" "$lbl" "${C_X}"; else printf '%s%s%s ' "${C_D}" "$lbl" "${C_X}"; fi
    done
    printf '\033[K'
  }

  _draw_input() { # fast path: typing must not rebuild sessions, usage, or sidebar
    printf '\033[%d;1H %s❯%s %s\033[K' "$(( ROWS - 1 ))" "${C_C}${C_B}" "${C_X}" "$INPUT"
    printf '\033[s%s▏%s\033[u' "${C_D}" "${C_X}"
  }

  _open_github_star() {
    local slug="namki1222/loomo" url="https://github.com/namki1222/loomo"
    # gh CLI가 로그인돼 있으면 실제로 별을 찍는다(원클릭). 아니면 repo 페이지로 폴백.
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      if gh api --method PUT "/user/starred/$slug" >/dev/null 2>&1; then
        DETAIL_MSG="★ Starred! GitHub에 별을 찍었습니다 — 고마워요"; return 0
      fi
    fi
    if command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1 &
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
    else DETAIL_MSG="GitHub: $url"; return 1; fi
    DETAIL_MSG="GitHub repo를 열었습니다 · ★ 눌러 별을 남겨주세요"
  }

  _read_tui_char() { # macOS Bash 3.2 read -n1 returns UTF-8 bytes, not characters
    local out="$1" timeout="${2:-1}" ch="" more="" byte=0 need=0 i
    IFS= read -rsn1 -t "$timeout" ch </dev/tty || return 1
    byte=$(LC_ALL=C printf '%d' "'$ch" 2>/dev/null)
    [ "$byte" -lt 0 ] 2>/dev/null && byte=$((byte + 256))
    if [ "$byte" -ge 194 ] 2>/dev/null && [ "$byte" -le 223 ]; then need=1
    elif [ "$byte" -ge 224 ] 2>/dev/null && [ "$byte" -le 239 ]; then need=2
    elif [ "$byte" -ge 240 ] 2>/dev/null && [ "$byte" -le 244 ]; then need=3
    fi
    for ((i=0;i<need;i++)); do
      IFS= read -rsn1 -t 1 more </dev/tty || return 1
      ch="$ch$more"
    done
    printf -v "$out" '%s' "$ch"
  }

  _draw() {
    local rw=26 session_wrap_w=32
    # Compact strip: while the Hub tab lends most of the window to Claude's pane
    # there is only room for the tabs. Everything else is drawn by absolute row
    # and would land on top of them. Tabs stay on row 2 so click targets hold.
    if [ "$ROWS" -le 6 ]; then
      printf '\033[1;1H %s비서 패널에서 바로 입력하세요 · Esc 중단 · 다른 탭을 누르면 패널을 돌려줍니다%s\033[K' "${C_D}" "${C_X}"
      _draw_tabs
      local _r; for ((_r=3;_r<=ROWS;_r++)); do printf '\033[%d;1H\033[K' "$_r"; done
      return
    fi
    _ensure_hub_active || true
    _dash_team
    _dash_tasks
    [ "$COLS" -lt 64 ] && rw=0
    LW=$COLS; [ "$rw" -gt 0 ] && LW=$(( COLS - rw - 1 ))
    SESSION_LEFT_W=0
    if [ "${TABS[$tab]}" = Sessions ] && [ "$LW" -ge 40 ]; then
      # Session list expands into all remaining space; the secondary panel wraps
      # to a compact content width (details need a little more for diagrams).
      [ -n "$DETAIL_SESSION" ] && session_wrap_w=40
      if [ "$LW" -ge $((session_wrap_w + 34)) ]; then
        SESSION_LEFT_W=$(( LW - session_wrap_w - 2 ))
      else
        SESSION_LEFT_W=$(( LW * 54 / 100 ))
      fi
    elif [ "${TABS[$tab]}" = Adopt ] && [ -n "$ADOPT_SELECTED" ] && [ "$LW" -ge 50 ]; then
      session_wrap_w=48
      if [ "$LW" -ge $((session_wrap_w + 40)) ]; then
        SESSION_LEFT_W=$(( LW - session_wrap_w - 2 ))
      else
        SESSION_LEFT_W=$(( LW * 54 / 100 ))
      fi
    fi
    LISTBODY=$(( ROWS - 4 - 3 )); [ "$LISTBODY" -lt 1 ] && LISTBODY=1
    _build_main
    # 오른쪽 상태 사이드바는 모든 탭에서 유지
    local nsess hubrun; nsess=$(_reg_sessions | grep -c .)
    hubrun="○ stopped"; [ -n "${HUB:-}" ] && { tmux has-session -t "=$HUB" 2>/dev/null && hubrun="● running"; }
    local rr_total=$(( ROWS - 3 )) u=$(( (ROWS - 3) / 6 )); [ "$u" -lt 1 ] && u=1
    local h_task=$u h_hub=$u h_cla=$u h_cod=$u h_team=$u h_loo=$(( rr_total - u*5 )); [ "$h_loo" -lt 1 ] && h_loo=1; HUB_ROWS=$h_hub
    local R=()
    _right_row() { R+=("$1"); }
    _region() { local h=$1 div=$2 t=$3; shift 3; local b=$h c; [ "$div" = 1 ] && { _right_row "---"; b=$((b-1)); }; _right_row "@T@$t"; b=$((b-1)); for c in "$@"; do [ "$b" -gt 0 ] && { _right_row "$c"; b=$((b-1)); }; done; while [ "$b" -gt 0 ]; do _right_row ""; b=$((b-1)); done; }
    _region_bottom() { # title stays at top; content sits at the bottom of its region
      local h=$1 div=$2 t=$3; shift 3
      local b=$h n=$# pad i
      [ "$div" = 1 ] && { _right_row "---"; b=$((b-1)); }
      _right_row "@T@$t"; b=$((b-1))
      [ "$n" -gt "$b" ] && n=$b
      pad=$(( b - n )); while [ "$pad" -gt 0 ]; do _right_row ""; pad=$((pad-1)); done
      for ((i=1;i<=n;i++)); do _right_row "${!i}"; done
    }
    local task_tone=G task_status="@D@  대기 중 작업 없음"
    if [ "$TASK_ATTENTION" -gt 0 ]; then task_tone=R; task_status="@$task_tone@  ! 확인 필요 $TASK_ATTENTION"
    elif [ "$TASK_RUNNING" -gt 0 ]; then task_status="@G@  ● 진행 중 $TASK_RUNNING"
    elif [ "$TASK_DONE" -gt 0 ]; then task_status="@D@  ✓ 최근 완료 $TASK_DONE"; fi
    local task_state_kr=""; case "$TASK_LATEST_STATE" in
      working|delivered|acknowledged) task_state_kr="진행 중" ;;
      needs_approval) task_state_kr="승인 대기" ;;
      failed) task_state_kr="실패" ;;
      stale) task_state_kr="응답 지연" ;;
      completed) task_state_kr="완료" ;;
      cancelled) task_state_kr="취소" ;;
      *) task_state_kr="$TASK_LATEST_STATE" ;;
    esac
    # tasks = 세션끼리 tell로 주고받는 위임 작업(KEY 추적)의 현재 상태. ⟳ 아이콘으로 비움.
    _region "$h_task" 0 "tasks" \
      "$task_status" \
      "@D@  세션끼리 맡긴 위임 작업" \
      "@D@  진행 $TASK_RUNNING · 완료 $TASK_DONE · 확인 $TASK_ATTENTION" \
      "${TASK_LATEST_TARGET:+@$task_tone@  최근 ${TASK_LATEST_TARGET} — ${task_state_kr}}" \
      "${TASK_LATEST_SUMMARY:+@D@  ${TASK_LATEST_SUMMARY}}"
    if [ -n "${HUB:-}" ]; then _region "$h_hub" 1 "비서(hub)" "  $HUB" "  $hubrun"; else _region "$h_hub" 1 "비서(hub)" "  ${C_D}없음 (Settings)${C_X}"; fi
    _region_bottom "$h_cla" 1 "claude usage" \
      "$(_quota_line session "$CLAUDE_SESSION")" \
      "$(_quota_line week "$CLAUDE_WEEK")" \
      "$(_quota_line "$CLAUDE_MODEL" "$CLAUDE_MODEL_WEEK")"
    _region_bottom "$h_cod" 1 "codex usage" \
      "$(_quota_line 5h "$CODEX_5H")" \
      "$(_quota_line week "$CODEX_WEEK")" \
      "@D@  reset $CODEX_5H_RESET"
    local team_tone=G
    if [ "$TEAM_STALE" -gt 0 ] || [ "$TEAM_MISSING" -gt 0 ]; then team_tone=R
    elif [ "$TEAM_OFFLINE" -gt 0 ]; then team_tone=Y; fi
    _region_bottom "$h_team" 1 "team" \
      "@$team_tone@  $TEAM_RUNNING/$TEAM_TOTAL sessions · $TEAM_PANES panes" \
      "@D@  waiting $TEAM_WAITING · stale $TEAM_STALE" \
      "@D@  offline $TEAM_OFFLINE · paths $TEAM_MISSING"
    _region "$h_loo" 1 "loomo v$VER" "  프로젝트  $nsess"

    printf '\033[1;1H  %s🔗 loomo%s   %s%s%s\033[K' "${C_C}${C_B}" "${C_X}" "${C_D}" "${CWD:0:$(( COLS - 14 ))}" "${C_X}"
    _draw_tabs; printf '\033[3;1H%s\033[K' "$(_hrn "$COLS")"
    _draw_main
    local notice="" notice_tone="$C_G" notice_icon="✓"
    if [ -n "$DETAIL_MSG" ]; then notice="$DETAIL_MSG"
    elif [ -n "$SETTINGS_MSG" ]; then notice="$SETTINGS_MSG"
    elif [ -n "$ARRANGE_MSG" ]; then notice="$ARRANGE_MSG"; fi
    case "$notice" in
      *실패*|*오류*|*못함*|*failed*|*Failed*|*missing*|*not\ found*) notice_tone="$C_R"; notice_icon="!" ;;
      *started*|*active*|*완료*|*added*|*deleted*|*Applied*|*refreshed*) notice_tone="$C_G"; notice_icon="✓" ;;
      *) notice_tone="$C_Y"; notice_icon="•" ;;
    esac
    if [ -n "$notice" ]; then
      _fit_cols "$notice" $((LW-8))
      printf '\033[%d;1H%s%s %s %s%s\033[K' "$(( ROWS - 2 ))" "${C_D}" "$(_hrn 2)" "$notice_tone" "$notice_icon $FITTED" "$C_X"
    elif [ "${TABS[$tab]}" = Hub ]; then
      printf '\033[%d;1H\033[K' "$(( ROWS - 2 ))"   # no chat rule here — clear whatever the last tab left
    else
      printf '\033[%d;1H%s%s 채팅%s\033[K' "$(( ROWS - 2 ))" "${C_D}" "$(_hrn 3)" "$(_hrn $(( LW - 8 )))"
    fi
    if [ "${TABS[$tab]}" = Hub ]; then
      # Keys go to the mirrored pane, so the dashboard's own input line would
      # only be a second place to type into. Claude already has one.
      printf '\033[%d;1H\033[K' "$(( ROWS - 1 ))"
      printf '\033[%d;1H %s타이핑이 비서에게 바로 전달됩니다 · Esc 중단 · 탭 전환은 위 탭 클릭 · Ctrl-C 대시보드 종료%s\033[0m\033[K' "$ROWS" "${C_D}" "${C_X}"
    else
      printf '\033[%d;1H %s❯%s %s\033[K' "$(( ROWS - 1 ))" "${C_C}${C_B}" "${C_X}" "${INPUT:0:$(( LW - 4 ))}"
      printf '\033[s%s▏%s' "${C_D}" "${C_X}"
      printf '\033[%d;1H %s←→ 탭 · 채팅 입력 후 Enter · ↑↓ 스크롤 · Ctrl-C 종료%s\033[0m\033[K' "$ROWS" "${C_D}" "${C_X}"
    fi
    STAR_X0=0; STAR_X1=0; STAR_Y=0; TASK_RESET_X0=0; TASK_RESET_X1=0; TASK_RESET_Y=0
    if [ "$rw" -gt 0 ]; then local r rc
      for ((r=4; r<=ROWS; r++)); do rc="${R[$((r-4))]:-}"
        if [ "$rc" = "---" ]; then printf '\033[%d;%dH%s├%s%s' "$r" "$(( LW+1 ))" "${C_D}" "$(_hrn "$rw")" "${C_X}"
        elif [ "${rc:0:3}" = "@T@" ]; then printf '\033[%d;%dH%s│%s %s%s%s\033[K' "$r" "$(( LW+1 ))" "${C_D}" "${C_X}" "${C_C}${C_B}" "${rc:3:$(( rw-2 ))}" "${C_X}"
        elif [ "${rc:0:3}" = "@G@" ]; then printf '\033[%d;%dH%s│%s %s%s%s\033[K' "$r" "$(( LW+1 ))" "${C_D}" "${C_X}" "${C_G}" "${rc:3:$(( rw-1 ))}" "${C_X}"
        elif [ "${rc:0:3}" = "@Y@" ]; then printf '\033[%d;%dH%s│%s %s%s%s\033[K' "$r" "$(( LW+1 ))" "${C_D}" "${C_X}" "${C_Y}" "${rc:3:$(( rw-1 ))}" "${C_X}"
        elif [ "${rc:0:3}" = "@R@" ]; then printf '\033[%d;%dH%s│%s %s%s%s\033[K' "$r" "$(( LW+1 ))" "${C_D}" "${C_X}" "${C_R}${C_B}" "${rc:3:$(( rw-1 ))}" "${C_X}"
        elif [ "${rc:0:3}" = "@D@" ]; then printf '\033[%d;%dH%s│%s %s%s%s\033[K' "$r" "$(( LW+1 ))" "${C_D}" "${C_X}" "${C_D}" "${rc:3:$(( rw-1 ))}" "${C_X}"
        else printf '\033[%d;%dH%s│%s %s\033[K' "$r" "$(( LW+1 ))" "${C_D}" "${C_X}" "${rc:0:$(( rw-1 ))}"; fi
      done
      # ★ Star on GitHub — loomo 버전 섹션(우측 패널 맨 아래 행)에 배치. R-loop 이후 덮어써 안 지워지게.
      local star_label="★ Star on GitHub"
      if [ "$rw" -ge $(( ${#star_label} + 2 )) ]; then
        STAR_Y=$ROWS; STAR_X0=$(( LW + 3 )); STAR_X1=$(( STAR_X0 + ${#star_label} - 1 ))
        printf '\033[%d;%dH%s%s%s\033[K' "$STAR_Y" "$STAR_X0" "${C_C}${C_B}" "$star_label" "${C_X}"
      fi
      # ⟳ 비우기 버튼 — tasks 타이틀 행 오른쪽. 기록이 있을 때만, 눈에 띄게(청록 굵게).
      if [ -s "$TASK_FILE" ] && [ "$rw" -ge 12 ]; then
        TASK_RESET_Y=4; TASK_RESET_X1=$(( COLS - 1 )); TASK_RESET_X0=$(( COLS - 9 ))
        printf '\033[%d;%dH%s⟳ 비우기%s' "$TASK_RESET_Y" "$TASK_RESET_X0" "${C_C}${C_B}" "${C_X}"
      fi
    fi
    printf '\033[u'
  }

  _hover_update() { # $1=x $2=y; return 0 only when hover target changed
    local hx="$1" hy="$2" old="$HOVER_AREA:$HOVER_INDEX:$HOVER_GROUP" idx act t
    HOVER_AREA=""; HOVER_INDEX=-1; HOVER_GROUP=""
    if [ "$hy" -eq 2 ]; then
      for ((t=0;t<${#TABS[@]};t++)); do
        if [ "$hx" -ge "${TX0[$t]}" ] && [ "$hx" -le "${TX1[$t]}" ]; then HOVER_AREA=tab; HOVER_INDEX=$t; break; fi
      done
    elif [ "$hy" -ge 4 ] && [ "$hy" -le $(( 3 + LISTBODY )) ] && [ "$hx" -le "$LW" ]; then
      idx=$(( mtop + hy - 4 ))
      if [ "$SESSION_LEFT_W" -gt 0 ] && { [ "${TABS[$tab]}" = Sessions ] || [ "${TABS[$tab]}" = Adopt ]; } && [ "$hx" -gt "$SESSION_LEFT_W" ]; then
        [ "${TABS[$tab]}" = Adopt ] && idx=$(( hy - 4 ))
        act="${UACT[$idx]:-none}"; [ "$act" != none ] && { HOVER_AREA=unassigned; HOVER_INDEX=$idx; HOVER_GROUP="${UGROUP[$idx]:-}"; }
      else act="${SACT[$idx]:-none}"; [ "$act" != none ] && { HOVER_AREA=main; HOVER_INDEX=$idx; HOVER_GROUP="${SGROUP[$idx]:-}"; }; fi
    fi
    [ "$old" != "$HOVER_AREA:$HOVER_INDEX:$HOVER_GROUP" ]
  }
  _draw_hover() {
    _draw_tabs; _draw_scroll
    _draw_input
  }

  # read 호출 사이(특히 redraw 중)에도 mouse bytes가 canonical 버퍼에 쌓이거나
  # 화면에 echo되지 않도록 TUI 수명 전체에서 입력 모드를 고정한다.
  local TTY_STATE; TTY_STATE=$(stty -g </dev/tty 2>/dev/null)
  stty -echo -icanon min 1 time 0 </dev/tty 2>/dev/null
  printf '%s\033[?1049h\033[2J\033[?1000h\033[?1002h\033[?1003h\033[?1006h\033[?25l\033[?7l' "$(_theme_osc)"
  _dash_cleanup() {
    # A borrowed hub pane must go home, or it stays stranded in this window.
    declare -f _hubc_detach_pane >/dev/null && _hubc_detach_pane 2>/dev/null
    # OSC 110/111 restore the terminal's default fg/bg — the dashboard changed
    # them via OSC 10/11 above, and leaving them set would recolor other panes.
    printf '\033[0m\033]110\007\033]111\007\033[?1006l\033[?1003l\033[?1002l\033[?1000l\033[?7h\033[?25h\033[?1049l'
    [ -n "$TTY_STATE" ] && stty "$TTY_STATE" </dev/tty 2>/dev/null || stty sane </dev/tty 2>/dev/null
  }
  trap '_dash_cleanup' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap '_dash_size; declare -f _draw >/dev/null && { printf "\033[2J"; _draw; }' WINCH
  printf '\033[2J'; _draw

  while :; do
    if ! _read_tui_char key 1; then
      key=IGNORE
      # The Hub tab mirrors a live pane, so it repaints on every idle tick
      # instead of only when something the dashboard owns changed.
      # (Bash 3.2's `read -t` takes whole seconds, so one second is the floor.)
      if [ "${TABS[$tab]}" = Hub ]; then _draw; else
        local new_task_stamp; new_task_stamp=$(_task_file_stamp)
        if [ "$new_task_stamp" != "$TASK_STAMP" ]; then TASK_STAMP="$new_task_stamp"; _draw; fi
      fi
    fi
    if [ "$key" = $'\x1b' ]; then
      # CSI는 길이가 고정되어 있지 않다. 종결 문자까지 전부 소비해야
      # 트랙패드/수정키 마우스 패킷의 나머지가 채팅 입력으로 새지 않는다.
      IFS= read -rsn1 -t 1 rest </dev/tty || rest=""
      if [ "$rest" = '[' ]; then
        csi=""
        while [ "${#csi}" -lt 64 ] && IFS= read -rsn1 -t 1 mc </dev/tty; do
          csi="$csi$mc"
          case "$mc" in [A-Za-z~]) break ;; esac
        done
        case "$csi" in
          '<'*[Mm]) mseq="${csi#<}"; key=MOUSE ;;
          M) IFS= read -rsn3 -t 1 legacy_mouse </dev/tty || true; key=IGNORE ;;
          *A) key=UP ;; *B) key=DOWN ;; *C) key=RIGHT ;; *D) key=LEFT ;;
          5~) key=UP ;; 6~) key=DOWN ;;
          Z) key=BTAB ;;   # shift+tab — Claude cycles its modes with it
          *) key=IGNORE ;;
        esac
      elif [ "$rest" = 'O' ]; then
        IFS= read -rsn1 -t 1 mc </dev/tty || mc=""
        case "$mc" in A) key=UP ;; B) key=DOWN ;; C) key=RIGHT ;; D) key=LEFT ;; *) key=IGNORE ;; esac
      elif [ -z "$rest" ]; then key=ESCAPE   # bare Esc — Claude interrupts on it
      else key=IGNORE
      fi
    fi
    # On the Hub tab the keyboard belongs to the mirrored Claude pane: forward
    # each key straight through and repaint, so typing feels like being in it.
    # The mouse stays with the dashboard, which is how you leave the tab.
    if [ "${TABS[$tab]}" = Hub ] && [ "$key" != MOUSE ] && [ "$key" != IGNORE ]; then
      if _hubc_key "$key"; then _draw; continue; fi
    fi
    case "$key" in
      RIGHT) [ "${TABS[$tab]}" = Hub ] && _hubc_detach_pane
             tab=$(( (tab+1) % ${#TABS[@]} )); mtop=0; HOVER_AREA=""; HOVER_INDEX=-1; HOVER_GROUP="" ;;
      LEFT)  [ "${TABS[$tab]}" = Hub ] && _hubc_detach_pane
             tab=$(( (tab-1+${#TABS[@]}) % ${#TABS[@]} )); mtop=0; HOVER_AREA=""; HOVER_INDEX=-1; HOVER_GROUP="" ;;
      UP)    if [ "$mtop" -gt 0 ]; then mtop=$((mtop-1)); _draw_scroll; fi; continue ;;
      DOWN)  if [ "$mtop" -lt "$MMAX" ]; then mtop=$((mtop+1)); _draw_scroll; fi; continue ;;
      MOUSE) case "$mseq" in *[Mm]) MOUSE_FINAL="${mseq: -1}" ;; *) continue ;; esac
        local mb mx my mb_base mb_motion mb_wheel click_at
        IFS=';' read -r mb mx my <<< "${mseq%[Mm]}"
        case "$mb;$mx;$my" in *[!0-9\;]*) continue ;; esac
        mb_base=$(( mb & 3 )); mb_motion=$(( mb & 32 )); mb_wheel=$(( mb & 64 ))

        # 휠은 수정키 비트가 붙어도 항상 스크롤로만 처리한다.
        if [ "$mb_wheel" -ne 0 ]; then
          if [ "$mb_base" -eq 0 ]; then [ "$mtop" -gt 0 ] && { mtop=$((mtop-1)); _draw_scroll; }
          elif [ "$mb_base" -eq 1 ]; then [ "$mtop" -lt "$MMAX" ] && { mtop=$((mtop+1)); _draw_scroll; }; fi
          continue
        fi

        # 버튼 없는 이동은 호버. 왼쪽 버튼 이동(32)은 일부 터미널의 클릭 방식이라
        # 한 번의 클릭으로도 허용하되 같은 좌표의 release와 중복 실행하지 않는다.
        if [ "$mb_motion" -ne 0 ] && [ "$mb_base" -ne 0 ]; then
          _hover_update "${mx:-0}" "${my:-0}" || continue; _draw_hover; continue
        fi
        [ "$mb_base" -eq 0 ] || continue
        click_at="$mx;$my"
        if [ "$MOUSE_FINAL" = m ]; then
          if [ "$LAST_MOUSE_DOWN" = "$click_at" ]; then LAST_MOUSE_DOWN=""; continue; fi
        else LAST_MOUSE_DOWN="$click_at"
        fi
        mb=0
        case "$mb" in
          0) if [ "$STAR_Y" -gt 0 ] && [ "${my:-0}" = "$STAR_Y" ] && [ "$STAR_X0" -gt 0 ] && [ "${mx:-0}" -ge "$STAR_X0" ] && [ "${mx:-0}" -le "$STAR_X1" ]; then
                _open_github_star || true; _draw; continue
             elif [ "$TASK_RESET_X0" -gt 0 ] && [ "${my:-0}" = "$TASK_RESET_Y" ] && [ "${mx:-0}" -ge "$TASK_RESET_X0" ] && [ "${mx:-0}" -le "$TASK_RESET_X1" ]; then
                : > "$TASK_FILE" 2>/dev/null; TASK_STAMP=$(_task_file_stamp); DETAIL_MSG="작업 기록을 초기화했습니다"; _draw; continue
             elif [ "${my:-0}" = 2 ]; then local t hit=-1; for ((t=0;t<${#TABS[@]};t++)); do [ "${mx:-0}" -ge "${TX0[$t]}" ] && [ "${mx:-0}" -le "${TX1[$t]}" ] && { hit=$t; break; }; done
                [ "$hit" -lt 0 ] && continue
                [ "${TABS[$tab]}" = Hub ] && [ "$hit" -ne "$tab" ] && _hubc_detach_pane
                tab=$hit; mtop=0; HOVER_AREA=tab; HOVER_INDEX=$hit; HOVER_GROUP=""
             elif [ "${mx:-0}" -gt "$LW" ]; then    # 우측 패널 클릭
                continue
             elif [ "${my:-0}" -ge 4 ] && [ "${my:-0}" -le $(( 3 + LISTBODY )) ]; then    # 좌측 메인 패널 클릭
                if [ "$SESSION_LEFT_W" -gt 0 ] && { [ "${TABS[$tab]}" = Sessions ] || [ "${TABS[$tab]}" = Adopt ]; } && [ "${mx:-0}" -gt "$SESSION_LEFT_W" ]; then
                  [ -n "$FLOW" ] && continue
                  local ui uact uarg
                  if [ "${TABS[$tab]}" = Adopt ]; then ui=$(( ${my:-0} - 4 ))
                  else ui=$(( mtop + ${my:-0} - 4 )); fi
                  uact="${UACT[$ui]:-none}"; uarg="${UARG[$ui]:-}"
                  if [ "${TABS[$tab]}" = Adopt ]; then
                    case "$uact" in
                      adoptconfirm) _adopt_select "$uarg" || continue; ADOPT_SELECTED=""; mtop=0 ;;
                      adoptclose) ADOPT_SELECTED=""; mtop=0 ;;
                      adoptpreviewactions) local preview_x=$(( ${mx:-0} - SESSION_LEFT_W )) preview_w=$(( LW - SESSION_LEFT_W - 1 ))
                                           if [ "$preview_x" -le 24 ]; then _adopt_select "$uarg" || continue; ADOPT_SELECTED=""; mtop=0
                                           elif [ "$preview_x" -ge $((preview_w-4)) ]; then ADOPT_SELECTED=""; mtop=0
                                           else continue; fi ;;
                      *) continue ;;
                    esac
                  else case "$uact" in
                    select) _sessions_select_panel "$uarg" ;;
                    detailheader) local detail_x=$(( ${mx:-0} - SESSION_LEFT_W ))
                                  if [ "$detail_x" -le 12 ]; then DETAIL_SESSION=""; DETAIL_ADD=0; DETAIL_EDIT=0; DETAIL_DELETE=0; DETAIL_MSG=""
                                  else continue; fi ;;
                    detaildelete) DETAIL_DELETE=1; DETAIL_ADD=0; DETAIL_EDIT=0 ;;
                    detaildeleteconfirm) local detail_x=$(( ${mx:-0} - SESSION_LEFT_W ))
                                         if [ "$detail_x" -le 12 ]; then DETAIL_DELETE=0
                                         else _detail_delete_session; fi ;;
                    detailedit) DETAIL_EDIT=$((1-DETAIL_EDIT)); DETAIL_ADD=0 ;;
                    detailpreset) _detail_layout "$uarg" ;;
                    detailadd) DETAIL_ADD=1 ;;
                    detailnew) _detail_new_panel_start ;;
                    detailcancel) DETAIL_ADD=0 ;;
                    detailpick) _detail_add_panel "$uarg" ;;
                    detailremove) _detail_delete_panel "$uarg" ;;
                    detailactions) local detail_x=$(( ${mx:-0} - SESSION_LEFT_W ))
                                   if [ "$detail_x" -ge 5 ] && [ "$detail_x" -le 10 ]; then _detail_edit_panel "$uarg"
                                   elif [ "$detail_x" -ge 12 ] && [ "$detail_x" -le 19 ]; then _detail_delete_panel "$uarg"
                                   else continue; fi ;;
                    *) continue ;;
                  esac; fi
                else case "${TABS[$tab]}" in
                  Sessions) case "$FLOW" in ""|Add|DetailNewPanel) : ;; *) continue ;; esac
                            local si act arg
                            si=$(( mtop + ${my:-0} - 4 ))
                            act="${SACT[$si]:-none}"; arg="${SARG[$si]:-}"
                            case "$act" in
                              addproject) _flow_start Add ;;
                              addback) FLOW=""; FSTEP=0; ADD_BROWSE=0; INPUT=""; mtop=0 ;;
                              agentchoice) INPUT=""; _flow_answer "$arg"; mtop=9999 ;;
                              browse) _flow_add_browse ;;
                              dirselect) _flow_add_browse_action select ;;
                              dirparent) _flow_add_browse_action parent ;;
                              diropen) _flow_add_browse_action open "$arg" ;;
                              dircancel) _flow_add_browse_action cancel ;;
                              arrange) if [ "$ARRANGE_MODE" = 0 ]; then ARRANGE_MODE=1
                                       else _commit_pending_assignment; ARRANGE_MODE=0; ARRANGE_MSG=""; PANEL_ID=""; PANEL_SELECTED=0; PANEL_SOURCE_SESSION=""; PANEL_SOURCE_ROLE=""; PENDING_TARGET=""; PENDING_ROLE=""; fi ;;
                              selectassigned) local ps pr; IFS='|' read -r ps pr <<< "$arg"; _sessions_select_assigned "$ps" "$pr" ;;
                              target) _sessions_assign_target "$arg" || continue ;;
                              sessionopen) _session_click "$arg" ;;
                              panelview) _session_click "$arg" ;;
                              *) continue ;;
                            esac ;;
                  Hub) local hi hact
                       hi=$(( mtop + ${my:-0} - 4 )); hact="${SACT[$hi]:-none}"
                       case "$hact" in
                         hubopen) _hubc_open; _draw; continue ;;
                         settingshubjump) for ((i=0;i<${#TABS[@]};i++)); do [ "${TABS[$i]}" = Settings ] && tab=$i; done
                                          SETTINGS_PAGE=hub; mtop=0 ;;
                         *) continue ;;
                       esac ;;
                  Settings) local xi xact xarg
                            xi=$(( mtop + ${my:-0} - 4 )); xact="${SACT[$xi]:-none}"; xarg="${SARG[$xi]:-}"
                            [ -n "$FLOW" ] && [ "$xact" != settingsskillback ] && continue
                            case "$xact" in
                              settingsskillback) FLOW=""; FSTEP=0; INPUT=""; SETTINGS_MSG=""; mtop=0 ;;
                              settingshub) SETTINGS_PAGE=hub; SETTINGS_MSG=""; mtop=0 ;;
                              settingsback) SETTINGS_PAGE=main; SETTINGS_MSG=""; mtop=0 ;;
                              sethub) _settings_hub_target "$xarg" ;;
                              authrefresh) _settings_auth_refresh; SETTINGS_MSG="Status refreshed" ;;
                              settingssync) _settings_sync ;;
                              settingsbypass) _settings_bypass_toggle ;;
                              settingstheme) _settings_theme_cycle ;;
                              acctmodel) _settings_model_cycle "$xarg" ;;
                              authlogin) _settings_auth_login "$xarg" ;;
                              authlogout) _settings_auth_logout "$xarg" ;;
                              accountadd) _settings_account_add "$xarg" ;;
                              accountprofile) _settings_account_profile "$xarg" ;;
                              acctswitch) ACCT_SWITCH="$xarg"; SETTINGS_MSG=""; mtop=0 ;;
                              acctswitchconfirm) _settings_account_switch "$xarg" ;;
                              acctswitchcancel) ACCT_SWITCH=""; SETTINGS_MSG=""; mtop=0 ;;
                              acctlogin) _settings_account_login "$xarg" ;;
                              acctrow) local ar_provider ar_id ar_active ar_token ar_logout_x
                                       IFS='|' read -r ar_provider ar_id ar_active ar_token ar_logout_x <<< "$xarg"
                                       if [ "${mx:-0}" -ge "${ar_logout_x:-9999}" ]; then
                                         _settings_account_logout "$ar_provider|$ar_id"
                                       elif [ "$ar_token" = 0 ]; then
                                         _settings_account_login "$ar_provider|$ar_id"
                                       elif [ "$ar_active" != 1 ]; then
                                         ACCT_SWITCH="$ar_provider|$ar_id"; SETTINGS_MSG=""; mtop=0
                                       fi ;;
                              settingsskill) _settings_skill_start; mtop=0 ;;
                              settingsskilldelete) SKILL_DELETE="$xarg"; SETTINGS_MSG=""; mtop=0 ;;
                              settingsskillcancel) SKILL_DELETE=""; mtop=0 ;;
                              settingsskillconfirm) _settings_skill_delete_confirm "$xarg" ;;
                              *) continue ;;
                            esac ;;
                  Adopt) local xi xact xarg
                         xi=$(( mtop + ${my:-0} - 4 )); xact="${SACT[$xi]:-none}"; xarg="${SARG[$xi]:-}"
                         case "$xact" in
                           adoptfilters) if [ "${mx:-0}" -le 14 ]; then ADOPT_FILTER=claude
                                         elif [ "${mx:-0}" -le 27 ]; then ADOPT_FILTER=codex
                                         else ADOPT_LOADED=0; _adopt_scan; fi; ADOPT_SELECTED=""; mtop=0 ;;
                           adoptsession) ADOPT_SELECTED="$xarg"
                                         if [ $((xi-mtop)) -gt $((LISTBODY-7)) ]; then
                                           mtop=$((xi-LISTBODY+7)); [ "$mtop" -lt 0 ] && mtop=0
                                         fi ;;
                           adoptconfirm) _adopt_select "$xarg" || continue; ADOPT_SELECTED=""; mtop=0 ;;
                           adoptclose) ADOPT_SELECTED="" ;;
                           adoptmanual) _sessions_adopt_start; mtop=0 ;;
                           *) continue ;;
                         esac ;;
                  *) continue ;;
                esac; fi
             else continue; fi ;;
          64) if [ "$mtop" -gt 0 ]; then mtop=$((mtop-1)); _draw_scroll; fi; continue ;;
          65) if [ "$mtop" -lt "$MMAX" ]; then mtop=$((mtop+1)); _draw_scroll; fi; continue ;;
          *) continue ;; esac ;;
      "")  case "${TABS[$tab]}" in
             Sessions) [ -n "$FLOW" ] || continue; [ "$ADD_BROWSE" = 1 ] && [ -z "$INPUT" ] && continue
                       local a="$INPUT"; INPUT=""; _flow_answer "$a"; mtop=9999 ;;
             Hub) [ -n "$INPUT" ] || continue; local hm="$INPUT"; INPUT=""; _hubc_send "$hm"; mtop=9999 ;;
             Adopt) [ -n "$FLOW" ] || continue; local a="$INPUT"; INPUT=""; _flow_answer "$a"; mtop=9999 ;;
             Settings) [ -n "$FLOW" ] || continue; local a="$INPUT"; INPUT=""; _flow_answer "$a"; mtop=9999 ;;
             *) continue ;;
           esac ;;
      $'\x7f'|$'\b') INPUT="${INPUT%?}"; _draw_input; continue ;;
      IGNORE) continue ;;
      *)     local key_byte; key_byte=$(LC_ALL=C printf '%d' "'$key" 2>/dev/null)
             [ "${key_byte:-0}" -lt 0 ] 2>/dev/null && key_byte=$((key_byte + 256))
             case "$key" in [[:print:]]) INPUT="$INPUT$key"; _draw_input; continue ;; esac
             if [ "${key_byte:-0}" -ge 128 ] 2>/dev/null; then INPUT="$INPUT$key"; _draw_input; continue; fi
             continue ;;
    esac
    _draw
  done
}
