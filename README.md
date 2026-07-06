<div align="center">

<br>

# loomo

### Weave your Claude Code & Codex sessions into a team that talks to each other.

<br>

[![npm](https://img.shields.io/npm/v/loomo?style=flat-square)](https://www.npmjs.com/package/loomo)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-555?style=flat-square)](#requirements)

<br>

English · [한국어](README.ko.md) · [中文](README.zh-CN.md)

<sub>No daemon · no database · no MCP — just one script and a convention.</sub>

<br>

</div>

---

<br>

Run one Claude Code session for your backend and another for your frontend, and you hit a wall fast: **the two can't see each other.**

When the backend changes an API, *you* copy the result and paste it into the frontend session by hand. Every hand-off is a manual relay.

<br>

**loomo tears down that wall.** Your sessions become teammates that message each other directly — the backend finishes a change and tells the frontend itself, then the frontend does its part and reports back.

You just talk to them in plain language; they coordinate on their own. And it doesn't care whether a session is **Claude Code or Codex** — they all talk over the same bridge.

<br>

```
Without it — you're the relay:         With it — they loop on their own:


  [backend]  "done, API changed"             ┌──"API changed, update the UI"──►┐

      │                                  [backend]                          [frontend]

      │  ✋ copy & paste                       └◄──────────"done ✅"─────────────┘

      ▼

  [frontend]  "...paste it here"         you: one sentence, they handle the rest
```

<br>

Each session is **long-lived** — a resident teammate that keeps its own project's history, not a throwaway agent that forgets everything between tasks.

<br>

---

<br>

## Requirements

<br>

| Need | Check | Notes |
|---|---|---|
| **tmux** | `tmux -V` | 3.x recommended · `brew install tmux` |
| **Claude Code and/or Codex** | `claude --version` / `codex --version` | the AI in each pane — mix freely |
| **Node.js / npm** | `npm -v` | install channel only (runtime is pure shell) |
| macOS or Linux | — | Windows expected under WSL (untested) |

<br>

---

<br>

## Install

<br>

```bash
npm install -g loomo

loomo doctor        # environment check
```

<br>

---

<br>

## Set up your team

<br>

```bash
loomo init
```

<br>

The wizard asks, in order:

<br>

- **1 · Default AI model** — `claude` or `codex`. You can override it per session later, so Claude and Codex can share one screen.

- **2 · A hub (manager) session?** — an optional "secretary" that directs your projects. Skip with Enter; add later with `loomo hub`.

- **3 · Projects** — for each: **project name (= session)** → **role (= pane)** → **directory** → **model** (Enter = default). Multiple roles per project.

<br>

This also inserts the collaboration convention into each directory (`CLAUDE.md` or `AGENTS.md`) — that's what tells the receiving AI to reply over the bridge.

<br>

---

<br>

## Run & talk

<br>

```bash
loomo up --all      # start every session (split panes + launch the AI), attach to the hub

loomo up <project>  # or just one

loomo list          # who you can talk to right now
```

<br>

Then just ask any pane's AI in plain language:

<br>

```
tell web the order schema changed and have it update the UI
```

<br>

You never type a messaging command — the convention makes the AI relay it, and the other session replies on its own.

**Claude → Codex, Codex → Claude, any direction.**

<br>

---

<br>

## Commands

<br>

Everything you run is a management command — a handful of them. Sessions message each other automatically via the convention; you never type that part.

<br>

| Command | What it does |
|---|---|
| `loomo up --all` \| `up <session>` | start all (→ attach hub) / one · bare `up` lists what's registered |
| `loomo down <session>` \| `--all` | stop — kill the session only, config kept |
| `loomo ws <session>` | start one and attach |
| `loomo layout [<session>] <preset>` | rearrange panes (`tiled` / `main-vertical` / …), no `tmux.conf` |
| `loomo init` | setup wizard — model, hub, projects/roles/dirs + convention |
| `loomo adopt` | bring in AIs you're already running — no restart |
| `loomo hub` | register the manager (hub) session — only one |
| `loomo list` | address book — who you can talk to + status |
| `loomo rm <session>` | delete a workspace — config + convention removed, project files untouched |
| `loomo doctor` · `completion` · `help` | environment check · shell completion · full help |

<br>

Optional tab-completion:

```bash
echo 'eval "$(loomo completion)"' >> ~/.zshrc
```

<br>

---

<br>

## Mixing Claude & Codex

<br>

The bridge is agent-agnostic, so a **hub running Claude can command a project running Codex** — and vice versa.

Set the model per session in `loomo init` (or the 5th field of `~/.config/loomo/workspaces.conf`):

<br>

```
howlpot|server|~/work/howlpot|      claude

labs|dev|~/work/labs|               codex
```

<br>

They share one screen and message each other exactly the same way — a Claude session hands work to a Codex session and gets the result back, no glue code.

<br>

---

<br>

## In practice — how the author uses it

<br>

I keep **6 projects** registered, each with 1–4 panes (server / app / dashboard …).

<br>

One **Claude hub session** oversees them all — it routes my request to the right session, tracks the replies, and reports back. Paired with Claude Code's **Remote Control**, I can drive the whole fleet **from my phone** when I'm away from my laptop.

<br>

When I'm heads-down on a single project, I skip the hub and talk to that **project session directly** — so its context carries across the whole day instead of restarting each time.

<br>

---

<br>

## Security

<br>

- **Trusted local environments only.** Anyone with access to the same tmux server can inject a message into any pane. The correlation key routes, it doesn't authenticate.

- **Never send passwords, tokens, or secrets through it** — they'd sit in plain text in the target pane's scrollback. Move credentials over a permissioned channel (scp, etc.).

<br>

---

<br>

<div align="center">

MIT © [namki1222](https://github.com/namki1222)

<br>

</div>
