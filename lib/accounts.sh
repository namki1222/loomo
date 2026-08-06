# loomo — shared Claude/Codex account profiles
# sourced by bin/tell (not standalone). shell: bash

ACCOUNT_PROFILES_FILE="$CONFIG_DIR/studio-account-profiles.json"
ACCOUNT_PROFILES_ROOT="$CONFIG_DIR/accounts"

_account_provider() {
  case "${1:-}" in claude|codex) printf '%s' "$1" ;; *) return 1 ;; esac
}

_account_mutate() { # action provider [value] — prints action result
  node - "$ACCOUNT_PROFILES_FILE" "$ACCOUNT_PROFILES_ROOT" "$HOME" "$@" <<'NODE'
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const [file, accountsRoot, home, action, provider, value = ''] = process.argv.slice(2);
if (!['claude', 'codex'].includes(provider)) throw new Error('provider must be claude or codex');
const fresh = () => ({ version: 1, active: { claude: 'default', codex: 'default' }, profiles: { claude: [], codex: [] } });
let state;
try { state = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { state = fresh(); }
state.version = 1;
state.active ||= { claude: 'default', codex: 'default' };
state.profiles ||= { claude: [], codex: [] };
state.profiles.claude = Array.isArray(state.profiles.claude) ? state.profiles.claude : [];
state.profiles.codex = Array.isArray(state.profiles.codex) ? state.profiles.codex : [];
const profiles = [{ id: 'default', label: 'Default account' }, ...state.profiles[provider]];
const resolve = (raw) => {
  if (!raw || raw === 'active') return state.active[provider] || 'default';
  if (/^[0-9]+$/.test(raw)) return profiles[Number(raw) - 1]?.id || '';
  return profiles.find((profile) => profile.id === raw)?.id || '';
};
// Loomo's "default" profile always means the provider's real default home,
// even when this command is invoked from inside an already isolated pane.
const defaultRoot = provider === 'claude' ? path.join(home, '.claude') : path.join(home, '.codex');
const profileRoot = (id) => id === 'default' ? defaultRoot : path.join(accountsRoot, provider, id);
function link(root, source, name, required = false) {
  if (required) fs.mkdirSync(source, { recursive: true, mode: 0o700 });
  if (!fs.existsSync(source)) return;
  const dest = path.join(root, name);
  try { fs.lstatSync(dest); return; } catch {}
  fs.symlinkSync(source, dest, fs.lstatSync(source).isDirectory() ? 'dir' : 'file');
}
function ensure(id) {
  const root = profileRoot(id);
  if (id === 'default') return root;
  fs.mkdirSync(root, { recursive: true, mode: 0o700 });
  fs.chmodSync(root, 0o700);
  if (provider === 'claude') {
    link(root, path.join(defaultRoot, 'projects'), 'projects', true);
    for (const name of ['skills', 'plugins', 'commands', 'agents']) link(root, path.join(defaultRoot, name), name);
  } else {
    link(root, path.join(defaultRoot, 'sessions'), 'sessions', true);
    for (const name of ['config.toml', 'skills', 'rules', 'plugins', 'prompts']) link(root, path.join(defaultRoot, name), name);
  }
  return root;
}
function save() {
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(tmp, file);
  fs.chmodSync(file, 0o600);
}
// --- Claude Keychain swap ------------------------------------------------
// macOS keeps Claude's OAuth token in a single per-user Keychain entry, so we
// can't isolate accounts by CLAUDE_CONFIG_DIR. Instead we store each account's
// token bundle (Keychain token + ~/.claude.json oauthAccount) and swap the live
// Keychain + ~/.claude.json when the user switches. Claude only.
const { execFileSync } = require('child_process');
const os = require('os');
const KC_SERVICE = 'Claude Code-credentials';
const KC_ACCOUNT = os.userInfo().username;
const claudeJsonPath = path.join(home, '.claude.json');
const backupsDir = path.join(path.dirname(file), 'backups');
function kcRead() {
  try { return execFileSync('security', ['find-generic-password', '-s', KC_SERVICE, '-a', KC_ACCOUNT, '-w'], { encoding: 'utf8' }).replace(/\n$/, ''); }
  catch { return ''; }
}
function kcWrite(token) {
  execFileSync('security', ['add-generic-password', '-U', '-s', KC_SERVICE, '-a', KC_ACCOUNT, '-w', token]);
}
function readClaudeJson() { try { return JSON.parse(fs.readFileSync(claudeJsonPath, 'utf8')); } catch { return {}; } }
function writeClaudeJson(obj) {
  fs.mkdirSync(backupsDir, { recursive: true, mode: 0o700 });
  try { if (fs.existsSync(claudeJsonPath)) fs.copyFileSync(claudeJsonPath, path.join(backupsDir, `claude.json.${Date.now()}`)); } catch {}
  const tmp = `${claudeJsonPath}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2), { mode: 0o600 });
  fs.renameSync(tmp, claudeJsonPath);
}
function subOf(token) { try { return JSON.parse(token).claudeAiOauth?.subscriptionType || ''; } catch { return ''; } }
function bundlePath(id) { return path.join(accountsRoot, provider, id, 'keychain-bundle.json'); }
function readBundle(id) { try { return JSON.parse(fs.readFileSync(bundlePath(id), 'utf8')); } catch { return null; } }
function writeBundle(id, token, oauthAccount) {
  const p = bundlePath(id);
  fs.mkdirSync(path.dirname(p), { recursive: true, mode: 0o700 });
  const tmp = `${p}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify({ token, oauthAccount: oauthAccount || null, email: oauthAccount?.emailAddress || '', plan: subOf(token), capturedAt: Date.now() }, null, 2), { mode: 0o600 });
  fs.renameSync(tmp, p);
}
function captureInto(id) { const token = kcRead(); writeBundle(id, token, readClaudeJson().oauthAccount || null); }
function ownerByEmail(email) { if (!email) return ''; for (const p of profiles) { const b = readBundle(p.id); if (b && b.email && b.email === email) return p.id; } return ''; }
if (action === 'rows') {
  for (const profile of profiles) console.log([profile.id, profile.label || 'Additional account', state.active[provider] === profile.id ? '1' : '0', profileRoot(profile.id)].join('\t'));
} else if (action === 'root') {
  const id = resolve(value);
  if (!id) process.exit(3);
  console.log(ensure(id));
} else if (action === 'add') {
  const id = `profile-${crypto.randomUUID().slice(0, 8)}`;
  const label = `${provider === 'claude' ? 'Claude' : 'Codex'} account ${state.profiles[provider].length + 2}`;
  state.profiles[provider].push({ id, label, createdAt: Date.now() });
  const root = ensure(id);
  save();
  console.log(`${id}\t${root}`);
} else if (action === 'use') {
  const id = resolve(value);
  if (!id) process.exit(3);
  ensure(id);
  state.active[provider] = id;
  save();
  console.log(id);
} else if (action === 'active-root') {
  const id = resolve('active');
  if (id !== 'default') console.log(ensure(id));
} else if (action === 'resolve') {
  const id = resolve(value);
  if (!id) process.exit(3);
  console.log(`${id}\t${ensure(id)}`);
} else if (action === 'kc-rows') { // claude only — id\tlabel\tactive\temail\tplan\thasToken (bundle-based, or live keychain for active)
  if (provider !== 'claude') process.exit(2);
  const activeId = state.active[provider] || 'default';
  const curTok = kcRead();
  const curEmail = readClaudeJson().oauthAccount?.emailAddress || '';
  for (const p of profiles) {
    let email = '', plan = '', hasToken = '0';
    if (p.id === activeId) { email = curEmail; plan = subOf(curTok); hasToken = curTok ? '1' : '0'; }
    else { const b = readBundle(p.id); if (b) { email = b.email || ''; plan = b.plan || ''; hasToken = b.token ? '1' : '0'; } }
    console.log([p.id, p.label || 'Additional account', activeId === p.id ? '1' : '0', email, plan, hasToken].join('\t'));
  }
} else if (action === 'kc-live-owner') { // claude only — ownerProfileId<TAB>liveEmail (owner empty = a fresh, unclaimed login)
  if (provider !== 'claude') process.exit(2);
  const curEmail = readClaudeJson().oauthAccount?.emailAddress || '';
  console.log(`${ownerByEmail(curEmail)}\t${curEmail}`);
} else if (action === 'kc-capture') { // claude only — snapshot the live keychain+identity into <value>'s bundle
  if (provider !== 'claude') process.exit(2);
  const id = resolve(value); if (!id) process.exit(3);
  captureInto(id);
  console.log(id);
} else if (action === 'kc-select') { // claude only — make <value> the live connected account (swap keychain + ~/.claude.json)
  if (provider !== 'claude') process.exit(2);
  const target = resolve(value); if (!target) process.exit(3);
  const activeId = state.active[provider] || 'default';
  const curTok = kcRead();
  const cj = readClaudeJson();
  const curEmail = cj.oauthAccount?.emailAddress || '';
  const tb = readBundle(target);
  if (tb && tb.token && tb.email && tb.email === curEmail) {
    // Target's saved account is already the live one — just activate (and refresh its bundle).
    captureInto(target);
    state.active[provider] = target; save();
    console.log(`active\t${curEmail}`);
  } else if (tb && tb.token) {
    // Restore target from its saved bundle. Save the current login into its owner first so it isn't lost.
    const owner = ownerByEmail(curEmail) || activeId;
    if (curTok) writeBundle(owner, curTok, cj.oauthAccount || null);
    kcWrite(tb.token);
    cj.oauthAccount = tb.oauthAccount || cj.oauthAccount;
    writeClaudeJson(cj);
    state.active[provider] = target; save();
    console.log(`restored\t${tb.email || ''}`);
  } else {
    // Target has no saved token. Only adopt the live login if no other profile owns it
    // (i.e. the user just logged in for this profile). Otherwise it genuinely needs a login.
    const owner = ownerByEmail(curEmail);
    if (owner && owner !== target) { console.log(`needs-login\t${curEmail}`); process.exit(4); }
    captureInto(target);
    state.active[provider] = target; save();
    console.log(`captured\t${curEmail}`);
  }
} else if (action === 'remove') { // drop a profile slot (never the 'default' one) and its stored files
  const id = resolve(value); if (!id) process.exit(3);
  if (id === 'default') process.exit(6);
  state.profiles[provider] = state.profiles[provider].filter((p) => p.id !== id);
  if (state.active[provider] === id) state.active[provider] = 'default';
  try { fs.rmSync(profileRoot(id), { recursive: true, force: true }); } catch {}
  save();
  console.log(id);
} else if (action === 'tok-file') { // claude — path of the profile's long-lived token file
  const id = resolve(value); if (!id) process.exit(3);
  console.log(path.join(ensure(id), 'oauth-token'));
} else if (action === 'tok-rows') { // claude — id\tlabel\tactive\temail\tplan\thasToken (long-lived token store)
  const activeId = state.active[provider] || 'default';
  for (const p of profiles) {
    const root = profileRoot(p.id);
    let email = '', plan = '', hasToken = '0';
    try { if (fs.readFileSync(path.join(root, 'oauth-token'), 'utf8').trim()) hasToken = '1'; } catch {}
    try { const m = JSON.parse(fs.readFileSync(path.join(root, 'oauth-token.meta.json'), 'utf8')); email = m.email || ''; plan = m.plan || ''; } catch {}
    console.log([p.id, p.label || 'Additional account', activeId === p.id ? '1' : '0', email, plan, hasToken].join('\t'));
  }
} else if (action === 'tok-save') { // claude — store token (env LOOMO_TOKEN_IN) + identity for <value>
  const id = resolve(value); if (!id) process.exit(3);
  const token = (process.env.LOOMO_TOKEN_IN || '').trim();
  if (!token) process.exit(5);
  const root = ensure(id);
  fs.writeFileSync(path.join(root, 'oauth-token'), `${token}\n`, { mode: 0o600 });
  fs.writeFileSync(path.join(root, 'oauth-token.meta.json'), JSON.stringify({
    email: process.env.LOOMO_TOKEN_EMAIL || '', plan: process.env.LOOMO_TOKEN_PLAN || '', savedAt: Date.now(),
  }, null, 2), { mode: 0o600 });
  console.log(id);
} else if (action === 'tok-forget') { // claude — drop a stored token (never touches the live login)
  const id = resolve(value); if (!id) process.exit(3);
  const root = profileRoot(id);
  for (const f of ['oauth-token', 'oauth-token.meta.json']) { try { fs.unlinkSync(path.join(root, f)); } catch {} }
  console.log(id);
} else if (action === 'tok-use') { // claude — activate a profile that already has a stored token (instant, no browser)
  const id = resolve(value); if (!id) process.exit(3);
  let has = false;
  try { has = !!fs.readFileSync(path.join(profileRoot(id), 'oauth-token'), 'utf8').trim(); } catch {}
  if (!has && id !== 'default') process.exit(4);   // 'default' means "whatever claude is logged in as"
  state.active[provider] = id; save();
  console.log(id);
} else {
  process.exit(2);
}
NODE
}

# Claude's OAuth token lives in a single per-user macOS Keychain entry, so accounts
# cannot be isolated with CLAUDE_CONFIG_DIR, and rewriting that entry is unsafe:
# any running pane refreshes its token (~8h) and writes back, clobbering the swap.
# Instead every pane is launched with the selected profile's long-lived token in
# CLAUDE_CODE_OAUTH_TOKEN (from `claude setup-token`), which overrides the Keychain
# without touching it. The 'default' profile injects nothing = use the live login.
# Codex stays file-isolated via CODEX_HOME.
_account_token_file() { # claude — prints the active profile's token file, only when non-empty
  local f
  f=$(_account_mutate tok-file claude 2>/dev/null) || return 1
  [ -n "$f" ] && [ -s "$f" ] && printf '%s' "$f"
}

account_export_env() { # provider — apply the selected account to this process
  local provider root file token
  provider=$(_account_provider "${1:-}") || return 1
  if [ "$provider" = claude ]; then
    file=$(_account_token_file) || return 0
    [ -n "$file" ] || return 0
    IFS= read -r token < "$file" 2>/dev/null || return 0
    [ -n "$token" ] && export CLAUDE_CODE_OAUTH_TOKEN="$token"
    return 0
  fi
  root=$(_account_mutate active-root "$provider" 2>/dev/null) || return 1
  [ -n "$root" ] || return 0
  export CODEX_HOME="$root"
}

account_launch_prefix() { # provider — shell-safe prefix for commands sent to tmux
  local provider root file
  provider=$(_account_provider "${1:-}") || return 1
  if [ "$provider" = claude ]; then
    file=$(_account_token_file) || return 0
    # Reference the file, never the token itself — send-keys text lands in scrollback.
    [ -n "$file" ] && printf 'env CLAUDE_CODE_OAUTH_TOKEN="$(cat %q)" ' "$file"
    return 0
  fi
  root=$(_account_mutate active-root "$provider" 2>/dev/null) || return 1
  [ -n "$root" ] || return 0
  printf 'env CODEX_HOME=%q ' "$root"
}

_account_resolve() { _account_mutate resolve "$1" "${2:-active}"; }

_account_connected() { # provider id root
  local provider="$1" id="$2" root="$3"
  if [ "$provider" = claude ]; then
    # 'default' = whatever claude is logged in as; other profiles = a stored token.
    if [ "$id" = default ]; then claude auth status --json 2>/dev/null | grep -Eq '"loggedIn"[[:space:]]*:[[:space:]]*true'
    else [ -s "$root/oauth-token" ]; fi
  else
    if [ "$id" = default ]; then codex login status >/dev/null 2>&1
    else CODEX_HOME="$root" codex login status >/dev/null 2>&1; fi
  fi
}

_account_identity() { # provider id root — identity<TAB>plan
  local provider="$1" id="$2" root="$3"
  if [ "$provider" = claude ]; then
    if [ "$id" = default ]; then
      claude auth status --json 2>/dev/null | node -e '
        let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{try{const x=JSON.parse(s); process.stdout.write(`${x.email||"Connected"}\t${x.subscriptionType||""}`)}catch{}})'
    else
      node -e '
        const fs=require("fs");
        try { const m=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); process.stdout.write(`${m.email||"Connected"}\t${m.plan||""}`); } catch { process.stdout.write("Connected\t"); }
      ' "$root/oauth-token.meta.json"
    fi
  else
    node - "$root/auth.json" <<'NODE'
const fs=require('fs'); const file=process.argv[2];
try { const x=JSON.parse(fs.readFileSync(file,'utf8')); const p=JSON.parse(Buffer.from((x.tokens?.id_token||'').split('.')[1]||'', 'base64url')); const a=p['https://api.openai.com/auth']||{}; process.stdout.write(`${p.email||p.name||'Connected'}\t${a.chatgpt_plan_type||''}`); } catch {}
NODE
  fi
}

_account_token_identity() { # token — email<TAB>plan (ask the API, else fall back to the live identity file)
  local token="$1" out
  out=$(CLAUDE_CODE_OAUTH_TOKEN="$token" claude auth status --json 2>/dev/null | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{try{const x=JSON.parse(s); if(x.email) process.stdout.write(`${x.email}\t${x.subscriptionType||""}`)}catch{}})')
  [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  node -e '
    const fs=require("os"),p=require("path");
    try { const d=JSON.parse(require("fs").readFileSync(p.join(fs.homedir(),".claude.json"),"utf8")); const a=d.oauthAccount||{}; process.stdout.write(`${a.emailAddress||""}\t${a.organizationType==="claude_max"?"max":(a.organizationType||"").replace("claude_","")}`); } catch {}'
}

_account_token_capture() { # id — run `claude setup-token` interactively, store the long-lived token
  local id="$1" tmp token email plan
  command -v claude >/dev/null 2>&1 || { warn "claude CLI is not installed"; return 1; }
  [ -t 0 ] || { warn "this needs an interactive terminal"; return 1; }
  tmp=$(mktemp "${TMPDIR:-/tmp}/loomo-token.XXXXXX") || return 1
  chmod 600 "$tmp" 2>/dev/null
  note "log in as the account you want to add — loomo stores the long-lived token it prints"
  # The browser decides which account authorizes: signed in already, the flow
  # approves that one without offering a chooser. Say so, or every account added
  # from the same browser session is the same account again.
  note "already signed in to claude.ai as someone else? sign out there first, or use a private window"
  # script(1) gives setup-token a pty, so its prompts stay interactive while we capture the output.
  script -q "$tmp" claude setup-token || true
  token=$(LC_ALL=C grep -oE 'sk-ant-oat[0-9]{2}-[A-Za-z0-9_-]+' "$tmp" 2>/dev/null | tail -1)
  rm -f "$tmp"
  [ -n "$token" ] || { warn "no token was issued (login may not have completed)"; return 1; }
  IFS=$'\t' read -r email plan <<< "$(_account_token_identity "$token")"
  owner=$(_account_email_owner "$email" "$id")
  if [ -n "$owner" ]; then
    warn "that is the same account loomo already has ($email)"
    note "the browser approved its current session · sign out of claude.ai (or use a private window) and try again"
    return 2
  fi
  LOOMO_TOKEN_IN="$token" LOOMO_TOKEN_EMAIL="$email" LOOMO_TOKEN_PLAN="$plan" \
    _account_mutate tok-save claude "$id" >/dev/null || { warn "could not store the token"; return 1; }
  ok "token stored · ${email:-connected}${plan:+ · $plan}"
}

_account_email_owner() { # email [except-id] — profile already holding this account
  local email="$1" except="${2:-}" d id
  [ -n "$email" ] || return 0
  for d in "$ACCOUNT_PROFILES_ROOT"/claude/*/; do
    [ -d "$d" ] || continue
    id=$(basename "$d")
    [ "$id" = "$except" ] && continue
    [ -s "$d/oauth-token" ] || continue
    node -e '
      const fs=require("fs");
      try { if (JSON.parse(fs.readFileSync(process.argv[1],"utf8")).email === process.argv[2]) process.exit(0); } catch {}
      process.exit(1);
    ' "$d/oauth-token.meta.json" "$email" 2>/dev/null && { printf '%s' "$id"; return 0; }
  done
  return 0
}

_account_login() { # provider id/index action
  local provider="$1" target="${2:-active}" action="${3:-login}" resolved id root
  command -v "$provider" >/dev/null 2>&1 || { warn "$provider CLI is not installed"; return 1; }
  resolved=$(_account_resolve "$provider" "$target") || { warn "account profile not found: $target"; return 1; }
  IFS=$'\t' read -r id root <<< "$resolved"
  note "$provider · $id"
  if [ "$provider" = claude ]; then
    if [ "$id" = default ]; then claude auth "$action"; else CLAUDE_CONFIG_DIR="$root" claude auth "$action"; fi
  else
    if [ "$id" = default ]; then codex "$action"; else CODEX_HOME="$root" codex "$action"; fi
  fi
}

_account_list() {
  local id label active root identity plan mark status email hasTok
  # Claude — long-lived tokens injected at launch (CLAUDE_CODE_OAUTH_TOKEN).
  echo ""; printf '  Claude\n'
  while IFS=$'\t' read -r id label active email plan hasTok; do
    mark=" "; [ "$active" = 1 ] && mark="*"
    if ! command -v claude >/dev/null 2>&1; then identity="$label"; plan=""; status="CLI not installed"
    elif [ "$hasTok" = 1 ]; then identity="${email:-$label}"; status="ready"
    elif [ "$id" = default ]; then
      IFS=$'\t' read -r identity plan <<< "$(_account_identity claude default '')"
      identity="${identity:-$label}"; status="current login"
    else identity="$label"; plan=""; status="needs setup"; fi
    printf '  %s %-12s  %-30s  %s%s\n' "$mark" "$id" "$identity" "$status" "${plan:+ · $plan}"
  done < <(_account_mutate tok-rows claude)
  # Codex — file-isolation based (~/.codex/auth.json), unchanged.
  echo ""; printf '  Codex\n'
  while IFS=$'\t' read -r id label active root; do
    mark=" "; [ "$active" = 1 ] && mark="*"
    if ! command -v codex >/dev/null 2>&1; then identity="$label"; plan=""; status="CLI not installed"
    elif _account_connected codex "$id" "$root"; then
      IFS=$'\t' read -r identity plan <<< "$(_account_identity codex "$id" "$root")"
      identity="${identity:-$label}"; status="connected"
    else identity="$label"; plan=""; status="login required"; fi
    printf '  %s %-12s  %-30s  %s%s\n' "$mark" "$id" "$identity" "$status" "${plan:+ · $plan}"
  done < <(_account_mutate rows codex)
  echo ""
  note "* is the active account · shared with Loomo Studio"
}

cmd_account() {
  local action="${1:-list}" provider="${2:-}" target="${3:-}" result id root rc
  case "$action" in
    list|status) _account_list ;;
    add)
      provider=$(_account_provider "$provider") || { echo "usage: loomo account add <claude|codex>"; return 2; }
      command -v "$provider" >/dev/null 2>&1 || { warn "$provider CLI is not installed"; return 1; }
      if [ "$provider" = claude ]; then
        result=$(_account_mutate add claude) || return 1
        IFS=$'\t' read -r id root <<< "$result"
        ok "created claude profile · $id"
        _account_token_capture "$id"; rc=$?
        if [ "$rc" = 2 ]; then
          # It authorized an account we already hold, so this slot has no purpose.
          _account_mutate remove claude "$id" >/dev/null 2>&1
          note "no profile was added"
          return 1
        fi
        [ "$rc" = 0 ] || { warn "profile kept · finish it later with: loomo account login claude $id"; return 1; }
        _account_mutate tok-use claude "$id" >/dev/null 2>&1 \
          && { ok "claude active account · $id"; note "new panes and restarted sessions use this account"; }
      else
        result=$(_account_mutate add codex) || return 1
        IFS=$'\t' read -r id root <<< "$result"
        ok "created codex profile · $id"
        note "complete the provider login; then select it with: loomo account use codex $id"
        _account_login codex "$id" login
      fi
      ;;
    login|logout)
      provider=$(_account_provider "$provider") || { echo "usage: loomo account $action <claude|codex> [id|number]"; return 2; }
      if [ "$provider" = claude ]; then
        command -v claude >/dev/null 2>&1 || { warn "claude CLI is not installed"; return 1; }
        result=$(_account_resolve claude "${target:-active}") || { warn "account profile not found: ${target:-active}"; return 1; }
        IFS=$'\t' read -r id root <<< "$result"
        if [ "$action" = login ]; then
          if [ "$id" = default ]; then claude auth login; else _account_token_capture "$id" || return 1; fi
        else
          # Drop this profile's stored token; 'default' means the real CLI login.
          if [ "$id" = default ]; then claude auth logout
          else _account_mutate tok-forget claude "$id" >/dev/null && ok "claude token removed · $id"; fi
        fi
      else
        _account_login codex "${target:-active}" "$action"
      fi
      ;;
    use)
      provider=$(_account_provider "$provider") || { echo "usage: loomo account use <claude|codex> <id|number>"; return 2; }
      [ -n "$target" ] || { echo "usage: loomo account use <claude|codex> <id|number>"; return 2; }
      command -v "$provider" >/dev/null 2>&1 || { warn "$provider CLI is not installed"; return 1; }
      if [ "$provider" = claude ]; then
        result=$(_account_mutate tok-use claude "$target" 2>/dev/null); rc=$?
        case "$rc" in
          0) ok "claude active account · $result"
             note "new panes and restarted sessions use this account; existing panes keep their current login" ;;
          4) warn "this account has no stored token yet · loomo account login claude $target"; return 1 ;;
          3) warn "account profile not found: $target"; return 1 ;;
          *) warn "account switch failed"; return 1 ;;
        esac
      else
        result=$(_account_resolve codex "$target") || { warn "account profile not found: $target"; return 1; }
        IFS=$'\t' read -r id root <<< "$result"
        _account_connected codex "$id" "$root" || { warn "this profile is not logged in · loomo account login codex $id"; return 1; }
        _account_mutate use codex "$id" >/dev/null || return 1
        ok "codex active account · $id"
        note "new panes and restarted sessions use this account; existing panes keep their current login"
      fi
      ;;
    remove|rm)
      provider=$(_account_provider "$provider") || { echo "usage: loomo account remove <claude|codex> <id|number>"; return 2; }
      [ -n "$target" ] || { echo "usage: loomo account remove <claude|codex> <id|number>"; return 2; }
      result=$(_account_mutate remove "$provider" "$target" 2>/dev/null); rc=$?
      case "$rc" in
        0) ok "$provider profile removed · $result" ;;
        6) warn "the default profile cannot be removed"; return 1 ;;
        3) warn "account profile not found: $target"; return 1 ;;
        *) warn "could not remove the profile"; return 1 ;;
      esac
      ;;
    *)
      echo "usage: loomo account [list|add|use|login|logout|remove]"
      return 2
      ;;
  esac
}
