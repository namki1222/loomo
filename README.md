<div align="center">

# claude-tell-bridge

**Let your Claude Code sessions talk to each other.**

[![npm](https://img.shields.io/npm/v/claude-tell-bridge?style=flat-square)](https://www.npmjs.com/package/claude-tell-bridge)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-555?style=flat-square)](#requirements)

English · [한국어](README.ko.md) · [中文](README.zh-CN.md)

No daemon · no database · no MCP — just one bash script and a convention.

</div>

---

Run one Claude Code session for your backend and another for your frontend, and you hit a wall fast: the two can't see each other. When the backend changes an API, **you** have to copy the result and paste it into the frontend session by hand. Every hand-off is a manual relay.

**claude-tell-bridge tears down that wall.** Your sessions become teammates that message each other directly — the backend finishes a change and tells the frontend itself, then the frontend does its part and reports back. You just talk to them in plain language; they coordinate on their own.

```
Without it — you're the relay:

  [backend]  "done, API changed"
      │
      │  ✋ copy & paste
      ▼
  [frontend]  "...paste it here"

With it — they loop on their own:

       ┌──"API changed, update the UI"──►┐
  [backend]                          [frontend]
       └◄──────────"done ✅"─────────────┘

  you: one sentence, they handle the rest
```

Each session is **long-lived** — a resident teammate that keeps its own project's history and context, not a throwaway agent that forgets everything between tasks.

## Table of contents

- [What you get](#what-you-get)
- [Requirements](#requirements)
- [Install](#install)
- [Quick start — from scratch](#quick-start--from-scratch)
- [Quick start — adopt sessions you already have](#quick-start--adopt-sessions-you-already-have)
- [The hub: run everything from one seat (and your phone)](#the-hub-run-everything-from-one-seat-and-your-phone)
- [Lifecycle](#lifecycle)
- [Command reference](#command-reference)
- [Config file](#config-file)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Security](#security)
- [How it works (under the hood)](#how-it-works-under-the-hood)
- [Limitations & roadmap](#limitations--roadmap)
- [License](#license)

---

## What you get

Three ideas, that's the whole model:

- **A session is a project team.** One session = one project (`shop`, `blog`, …).
- **A pane is a resident AI teammate.** Its name is its role and its address (`server`, `web`, `infra`). A long-lived Claude Code runs in each pane, holding that codebase's history — not a subagent that spawns and vanishes.
- **They talk to each other.** Ask any pane's Claude in plain language ("tell web the schema changed"), and it relays to the right teammate, who does the work and replies. You never type a messaging command yourself — the sessions handle it.

```
session "shop"  pane "server"  ┐
session "shop"  pane "web"     ├── same team — they talk to each other
session "shop"  pane "infra"   ┘

session "blog"  pane "server"  ─── different team — separate address, never crosses over
```

There's no "connect" button. **A session being up is the connection.**

**Why this way?**

- **Ask the owner, not a guesser.** A resident session answers from its own code and environment ("how's your nginx set up?" → it opens the actual conf and tells you), instead of a fresh agent guessing.
- **No re-onboarding.** Each pane keeps its project history, memory, and context across tasks.
- **One screen = a control tower.** Every teammate works in view; click any pane to steer it directly.
- **Async and non-blocking.** Requests are tracked by key, so the sender moves on and answers arrive later as new messages.
- **Glass-box.** Every exchange is visible on screen. No hidden bus — you can step in anytime.
- **Zero infrastructure.** No daemon, no queue, no MCP server, no hooks. The whole thing is one bash file.

## Requirements

| Need | Check | Notes |
|---|---|---|
| **tmux** | `tmux -V` | 3.x recommended. `brew install tmux` |
| **Claude Code** | `claude --version` | the AI that does the work in each pane |
| **Node.js / npm** | `npm -v` | install channel only (runtime is pure bash) |
| macOS or Linux | — | Windows expected to work under WSL (untested) |

## Install

```bash
npm install -g claude-tell-bridge
tell doctor        # environment check
```

Optional tab-completion for the management commands:

```bash
echo 'eval "$(tell completion)"' >> ~/.zshrc    # use ~/.bashrc for bash
```

## Quick start — from scratch

Setting up Claude Code in this shape for the first time? You'll have two Claudes talking to each other in about 5 minutes.

> 🐣 **New to tmux?** The [beginner's guide](docs/getting-started.md) walks you through prerequisites, basic tmux moves, and the first exchange with copy-paste steps. What's below is the condensed version.

**1. Create — register your workspace**

```bash
tell init
```

> `init` only **registers**. It writes your config and plants the convention in each directory — **nothing runs yet.** Starting sessions is step 2.

The wizard asks, in order:

1. **A hub (manager) session?** — a "secretary" Claude that directs multiple projects for you. Optional and skippable; just press Enter to skip and add one later with `tell hub`.
2. **Register a project** — in order: **project name (= session name)** → **this Claude's role (= pane name)** → **directory**. Multiple roles per project. Example: project `demo` → role `api` → `~/work/demo/api` → role `web` → `~/work/demo/web` → Enter → Enter.

Registering also **inserts the collaboration convention into each directory's CLAUDE.md** — that's what tells the receiving Claude how to reply.

**2. Run — start the sessions**

```bash
tell up            # start every registered session (split panes + launch claude), attach to the hub if you have one
tell list          # address book — who you can talk to right now
```

To start just one: `tell ws demo` (starts it and attaches). Because create and run are separate, one `tell up` restores your whole team after a reboot.

**3. First exchange** — just ask the `api` pane's Claude in plain language:

```
send a ping to web and check that it replies
```

You don't type any messaging command — the convention makes `api`'s Claude do it. A few seconds later a reply lands in the `api` pane. From this moment on, your sessions can hand work to each other — that's the whole point.

## Quick start — adopt sessions you already have

**Already running Claude Code sessions?** Adopt them in place — no restart, conversation context preserved.

```bash
tell adopt
```

`adopt` handles two cases:

**① Adopt live panes** — Claudes already running in your split screen: it scans every pane, lets you name each one's role, inserts the convention into that directory's CLAUDE.md (skips if already there), and can send a "read the convention + ping" message on the spot so it loads and verifies without a restart.

**② Bring in a conversation you were having** — a Claude from a plain terminal tab: give it the conversation's session ID (its directory is auto-detected from the conversation log) — or, if you don't know the ID, give the directory and pick from the recent conversations it lists. Once registered, `tell ws <project>` brings that pane up with `claude --resume` so it **continues the exact conversation** instead of starting fresh.

## The hub: run everything from one seat (and your phone)

A **hub** is a "secretary" Claude session that directs your other projects. It doesn't write code — it takes your request, delegates it to the right session, tracks the replies, and reports back.

> Tell the hub *"add a refund API on the server and a button on the web"*, and it dispatches to both, then reports **"✅ server: done / ✅ web: done"** once each replies.

Peer-to-peer is the core, but with several projects one hub is worth it (create it in `tell init`, or add it later with `tell hub`):

```
        you (local keyboard or phone via Remote Control)
                    │
                [hub]  ← routes, delegates, aggregates, reports. Writes no code.
              ┌─────┼─────────┐
        [proj-a:*]  [proj-b:*]  [proj-c:*]
```

- **Exactly one hub, system-wide** — every project links to the same hub address. Re-running `init`/`adopt` won't ask again if a hub exists; it just adds projects. (To replace: `tell rm <hub>` then `tell hub`.)
- One `tell up` in the morning brings up the hub and all projects and drops you at the hub.
- You can still click any pane to steer it directly — the hub is a convenience, not a gatekeeper.
- **From your phone**: point Claude Code Remote Control at the hub session and you can drive every project from anywhere. The "urgent, but my laptop's at home" fix.

## Lifecycle

A workspace moves through four stages. The key idea is that **create and run are separate**:

```
create (register)      run (start)            stop                 delete
tell init/adopt   ───►  tell up / ws  ◄───►  tell down   ───►   tell rm
config only            starts in tmux         kill (config kept)   config + convention removed
nothing running yet    launches claude                             (your project files untouched)
```

| Stage | Command | What it does |
|---|---|---|
| **Create** | `tell init` · `tell adopt` · `tell hub` | register in `workspaces.conf` + insert the CLAUDE.md convention. **Nothing runs.** |
| **Run** | `tell up` (all) · `tell up <session>` (one) · `tell ws <session>` (one + attach) | split panes + launch claude (`--resume` if a session ID is set) |
| **Stop** | `tell down <session>` · `tell down --all` | kill the session only — config kept, restore with `tell up` |
| **Delete** | `tell rm <session>` | kill + remove from config + strip the convention block — your project files are untouched |

## Command reference

Everything you run is a **management command** — a handful of them. The two messaging lines at the top are what the **agents** use between themselves; you never type those.

| Command | What it does |
|---|---|
| `tell up` | **start every registered session** → attach to the hub (if any). Skips sessions already up |
| `tell up <session>` | start just that session (in the background — attach with `tell ws`) |
| `tell up --tabs` | start all, but open **a terminal tab per session** instead of one attached window (macOS; hub last = focused). iTerm2 = tabs / Terminal.app = tabs (needs Accessibility permission — falls back to new windows with a hint) |
| `tell down <session>` \| `--all` | **stop** — kill the session only, config kept (restore with `tell up`). `--all` only touches registered sessions |
| `tell layout [<session>] <preset>` | rearrange panes — `tiled` / `main-vertical` / `main-horizontal` / `even-horizontal` / `even-vertical`. No `tmux.conf` editing |
| `tell ws` | list running sessions + registered workspaces |
| `tell ws <session>` | bootstrap the workspace (split panes, titles, launch claude; `--resume` if a session ID is set) and attach |
| `tell init` | setup wizard — register hub (optional) + projects/roles/directories + insert the CLAUDE.md convention |
| `tell adopt` | bring in existing Claudes — adopt live panes + resume prior conversations by session ID + insert convention |
| `tell hub` | register the manager (hub) session — **only one allowed**; refuses if one exists |
| `tell list` | **address book** — who you can talk to + convention/running status |
| `tell rm <session>` | **delete a workspace** — kill + remove from config + strip the inserted CLAUDE.md convention block (backup `.bak`). **Your project files/code are untouched.** Shows what it'll remove, confirms once |
| `tell doctor` | environment check (tmux / claude / config / hub / templates) |
| `tell completion` | shell completion script — add `eval "$(tell completion)"` to `.zshrc` |
| `tell help` | full command list with descriptions |

The wizards (`init`/`adopt`/`hub`) also support **tab-completion on directory input**.

Exit codes: `0` sent · `1` no target pane · `2` bad arguments

## Config file

`~/.config/claude-tell-bridge/workspaces.conf` — one pane per line:

```
# session|role|directory|sessionID(optional)   ← # starts a comment
shop|server|~/work/shop/backend
shop|web|~/work/shop/frontend|f3a1b2c4-...
```

- Lines sharing a session name become its panes, top to bottom (first line creates the session, the rest split).
- **4th field (optional) = Claude conversation session ID** — if set, `ws`/`up` bring that pane up with `claude --resume <ID>` to continue the conversation (`adopt` fills this in).
- A `hub` file in the same folder points to the hub (`session|role`) — it's what guarantees a single hub, managed by `tell hub`/`tell rm`, so you rarely touch it.
- `~` home expansion supported.
- `TELL_CONFIG_DIR` overrides the config directory (for tests / multiple profiles).

## Troubleshooting

| Symptom | Cause · fix |
|---|---|
| `[tell] no target pane: X:Y` | session name or pane title mismatch. Check the "(available)" list printed with the error; set a pane title with `tmux select-pane -T "role"` |
| **message arrived but no reply** | almost always the **convention isn't loaded**. Check that the session's CLAUDE.md has it and the session read it. Quick fix: ask that session to "read CLAUDE.md and reply with the key you received" |
| reply only printed as chat text, never came back | same cause — rule #1 of the convention ("actually run the reply command") wasn't loaded |
| lots of `not in a mode` output | the target pane was in copy-mode (scrolling). `tmux send-keys -t <pane> -X cancel`, then resend |
| a send delayed ~10s | normal — the target had unsubmitted text, so it waited to avoid overwriting it |
| a new pane shows a shell, not claude | that directory doesn't exist or `claude` isn't on PATH. Run `tell doctor` |

## FAQ

**How is this different from a subagent (Task)?**
A subagent is a throwaway that rebuilds context every time. A pane here is a **resident teammate** — the session that remembers why it was designed that way yesterday answers you. Not mutually exclusive: each pane can use subagents internally.

**Why send-keys instead of MCP?**
An MCP message bus needs server and hook setup, and hides the conversation behind a protocol. Typing into the pane means **the screen a human watches and the channel the AI receives on are the same** — every exchange is visible, and install is a single script.

**What if a session never replies?**
The sender's Claude remembers the key and, after a while, re-asks or reports to you — that's part of the convention. Delivery receipts are on the roadmap.

**Same role name in two sessions?**
Fine — an address is a `session + role` pair. Within **one** session, though, the role (pane title) must be unique (first match wins).

**Does it reach sessions on a remote server?**
Only within the same tmux server. For remote, SSH into that host's tmux and use the bridge there.

## Security

- **Trusted local environments only.** Because it's built on `send-keys`, anyone with access to the same tmux server can inject a message into any pane. The correlation key is for routing, not authentication.
- **Never send passwords, tokens, or secrets through it.** They'd sit in plain text in the target pane's scrollback and transcript. Move credentials over a permissioned channel (scp, etc.); the convention template says so too.
- The receiving Claude treats messages as instructions, so tmux-server access = the power to instruct every session. Know that.

## How it works (under the hood)

You don't need any of this to use the tool — it's here for the curious and for contributors.

Under the hood, sessions message each other with a command called `tell`, which types straight into the target pane's input box via `tmux send-keys`. A request carries a 6-character correlation key; the reply reuses it so the sender can match answers to requests. The receiving Claude follows the auto-inserted CLAUDE.md convention — its core rule being to **actually run** the reply command rather than just printing "done" as chat text (which no other session would ever see). The convention templates live in [`templates/`](templates/); `init`/`adopt` insert them for you, but you can paste them by hand too.

That's the entire mechanism: type into a pane, tag with a key, follow a convention. The full source is one readable bash file.

## Limitations & roadmap

**Limitations**
- Input detection reads Claude Code's prompt rendering (`❯`) — a big CLI UI change may need a look.
- No delivery guarantee/receipt (fire-and-forget + convention-based re-asking).
- The header protocol is currently Korean.
- Session names can't contain `=`.

**Roadmap**
- [ ] Header i18n (English protocol + templates)
- [ ] Homebrew tap
- [ ] `tell status` — list/track pending keys
- [ ] Optional delivery receipts

Contributions welcome — issues/PRs: https://github.com/namki1222/claude-tell-bridge

## License

MIT © [namki1222](https://github.com/namki1222)
