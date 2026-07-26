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
} else {
  process.exit(2);
}
NODE
}

account_export_env() { # provider — apply selected account to this process
  local provider root
  provider=$(_account_provider "${1:-}") || return 1
  # Claude stores its OAuth token in the macOS Keychain (a single per-user entry),
  # not in $CLAUDE_CONFIG_DIR/.credentials.json — so an isolated config dir carries
  # no token and forces a login prompt. Panels must always use the real logged-in
  # account (the Keychain). Switching accounts swaps the Keychain (see cmd_account).
  # Only Codex (file-based ~/.codex/auth.json) can be isolated per profile.
  [ "$provider" = claude ] && return 0
  root=$(_account_mutate active-root "$provider" 2>/dev/null) || return 1
  [ -n "$root" ] || return 0
  export CODEX_HOME="$root"
}

account_launch_prefix() { # provider — shell-safe prefix for commands sent to tmux
  local provider root
  provider=$(_account_provider "${1:-}") || return 1
  [ "$provider" = claude ] && return 0   # Claude always uses the real Keychain login (see account_export_env)
  root=$(_account_mutate active-root "$provider" 2>/dev/null) || return 1
  [ -n "$root" ] || return 0
  printf 'env CODEX_HOME=%q ' "$root"
}

_account_resolve() { _account_mutate resolve "$1" "${2:-active}"; }

_account_connected() { # provider id root
  local provider="$1" id="$2" root="$3"
  if [ "$provider" = claude ]; then
    if [ "$id" = default ]; then claude auth status --json 2>/dev/null
    else CLAUDE_CONFIG_DIR="$root" claude auth status --json 2>/dev/null; fi \
      | grep -Eq '"loggedIn"[[:space:]]*:[[:space:]]*true'
  else
    if [ "$id" = default ]; then codex login status >/dev/null 2>&1
    else CODEX_HOME="$root" codex login status >/dev/null 2>&1; fi
  fi
}

_account_identity() { # provider id root — identity<TAB>plan
  local provider="$1" id="$2" root="$3"
  if [ "$provider" = claude ]; then
    if [ "$id" = default ]; then claude auth status --json 2>/dev/null
    else CLAUDE_CONFIG_DIR="$root" claude auth status --json 2>/dev/null; fi | node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{try{const x=JSON.parse(s); process.stdout.write(`${x.email||"Connected"}\t${x.subscriptionType||""}`)}catch{}})'
  else
    node - "$root/auth.json" <<'NODE'
const fs=require('fs'); const file=process.argv[2];
try { const x=JSON.parse(fs.readFileSync(file,'utf8')); const p=JSON.parse(Buffer.from((x.tokens?.id_token||'').split('.')[1]||'', 'base64url')); const a=p['https://api.openai.com/auth']||{}; process.stdout.write(`${p.email||p.name||'Connected'}\t${a.chatgpt_plan_type||''}`); } catch {}
NODE
  fi
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
  # Claude — Keychain/bundle based (no per-profile config isolation on macOS).
  echo ""; printf '  Claude\n'
  while IFS=$'\t' read -r id label active email plan hasTok; do
    mark=" "; [ "$active" = 1 ] && mark="*"
    if ! command -v claude >/dev/null 2>&1; then identity="$label"; plan=""; status="CLI not installed"
    elif [ "$hasTok" = 1 ]; then identity="${email:-$label}"; status="connected"
    else identity="$label"; plan=""; status="login required"; fi
    printf '  %s %-12s  %-30s  %s%s\n' "$mark" "$id" "$identity" "$status" "${plan:+ · $plan}"
  done < <(_account_mutate kc-rows claude)
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
        _account_mutate kc-capture claude >/dev/null 2>&1 || true   # snapshot the current login before it's replaced
        result=$(_account_mutate add claude) || return 1
        IFS=$'\t' read -r id root <<< "$result"
        ok "created claude profile · $id"
        note "log in as the NEW Claude account in the browser…"
        claude auth login || { warn "login did not complete · loomo account use claude $id"; return 1; }
        if result=$(_account_mutate kc-select claude "$id" 2>/dev/null); then ok "claude active account · $id · ${result#*$'\t'}"
        else warn "could not adopt the new login · loomo account use claude $id"; fi
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
        if [ "$action" = login ]; then
          claude auth login || { warn "login did not complete"; return 1; }
          _account_mutate kc-select claude "${target:-active}" >/dev/null 2>&1 || true
          ok "claude login complete"
        else
          claude auth logout
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
        result=$(_account_mutate kc-select claude "$target"); rc=$?
        case "$rc" in
          0) ok "claude active account · $target · ${result#*$'\t'}"
             note "new panes and restarted sessions use this account; existing panes keep their current login" ;;
          4) warn "this account has no saved login yet · loomo account login claude $target"; return 1 ;;
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
    *)
      echo "usage: loomo account [list|add|use|login|logout]"
      return 2
      ;;
  esac
}
