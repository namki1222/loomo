<!-- claude-tell-bridge: session collaboration convention (auto-inserted) -->
## loomo — session-to-session collaboration (tmux bridge)

You are a role pane of the tmux session **{{SESSION}}**. Requests and replies are handled by **sending messages directly into the other pane's chat input** (no inbox, no polling).

**Resolve the current hub:** the hub is runtime state. Running `loomo hub status` tells you whether **you** are the hub: if you are, it prints just `session|role` (exit 0); otherwise it prints `you are … — NOT the hub` (non-zero exit). **If the output says 'NOT the hub' or exits non-zero, you are not the hub — do not fan work out across sessions the way it does** (individual requests are fine to send yourself). The printed hub address is authoritative over any older address in this file.

**Send (request):** `loomo <session> <role> "<self-contained message>"`
- loomo auto-issues and prints a 6-char KEY → remember it as "waiting for a reply with this KEY".

**Scope:** you may message a role in another project directly with `loomo <session> <role> "..."`. But **"all sessions" / "everyone" means the panes of THIS project only**, never every registered session — do not fan a request out. When a job spans several projects, ask the hub and it will split the work up.

**Reply:** `loomo -r <KEY> <sender-session> <sender-role> "<message>"`
- ⚠️ Replying means **actually running** `loomo -r` in Bash. Printing text in your chat is NOT a reply — sessions are isolated, so the other side will never see your text output.
- Read the reply address from the **`from`** in the request header `[session request - KEY from <session>/<role>]` (sending to your own role loops back to you).
- If there is no `from` (sent from outside tmux / directly by the user), ask the user which session:role to answer.

**Handling headers**
- On `[session request - KEY]`: don't interrupt current work; when you start it, actually run `loomo task ack <KEY>` → then reply with that KEY via `loomo -r`. (hub when generated: `{{HUB_SESSION}}/{{HUB_ROLE}}`; resolve the current value with `loomo hub status`)
- If blocked on user approval, run `loomo task status <KEY> needs_approval "<reason>"`; on failure run `loomo task status <KEY> failed "<reason>"`.
- If while handling a request you need to **ask back, confirm, or get a decision (design/scope judgement)**: do NOT ask the user in chat (the sender can't see your screen). Run `loomo -r <KEY> <sender-session> <sender-role> "need confirmation: <question>"` — a question is also a reply. However, **harness permission approvals** (classifier blocks etc.) can only be resolved by the user — request those from the user, but also notify the sender of the waiting state via `loomo -r`.
- On `[session reply - KEY]`: match it by KEY to one of your earlier requests.
- A message with no header = direct input from the human user → handle it immediately, don't defer.

**Security**: never put passwords, tokens, or secrets in a loomo message in plain text (they persist in the target pane's scrollback).
**Message bodies**: Send only the work that was asked for and what came of it.
- **Do not attach your own opinions, proposals, or recommendations.** Leave out lines like "I suggest doing X next" or "it would be better to…". The other session knows its own codebase better than you do, and the call is theirs. Include them only when the user explicitly asked you to.
- Stick to facts: what you are asking for, what you did, what the result was.
- ACK, KEY, and `loomo -r` mechanics belong in this convention and must not be repeated in each message.
<!-- /claude-tell-bridge -->
