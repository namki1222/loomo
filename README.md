<div align="center">

<br>

# loomo

### Weave your Claude Code & Codex sessions into a team that talks to each other.

<br>

[![npm](https://img.shields.io/npm/v/@namki1222/loomo?style=flat-square)](https://www.npmjs.com/package/@namki1222/loomo)
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

loomo has two goals:

1. **Session-to-session communication** — projects and models can differ; Claude ↔ Claude, Codex ↔ Codex, and Claude ↔ Codex can request work and reply directly.
2. **Easy for anyone** — you do not need to understand tmux, session IDs, or messaging commands. Build projects and panes in the dashboard, then delegate in plain language.

New users only need to run `loomo`. It guides dependency setup, project and pane creation, conversation adoption, and conversation restoration after restart.

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

Each session is **long-lived** — a resident teammate that keeps its own project's history, not a throwaway agent that forgets everything between tasks. loomo stores and restores session IDs so users never have to manage them manually.

<br>

---

<br>

## Requirements

<br>

**Running `loomo` installs these for you on first launch** and opens the dashboard when ready. It skips anything already present.

| Need | Check | Notes |
|---|---|---|
| **tmux** | `tmux -V` | 3.x recommended · first `loomo` run installs it |
| **Claude Code and/or Codex** | `claude --version` / `codex --version` | first `loomo` run installs both |
| **Node.js / npm** | `npm -v` | install channel only (runtime is pure shell) |
| macOS or Linux | — | Windows expected under WSL (untested) |

<br>

---

<br>

## Install

<br>

```bash
npm install -g @namki1222/loomo

loomo               # check/install Homebrew → tmux → Claude Code → Codex, then open dashboard
```

<sub>First launch is idempotent: existing dependencies are skipped. On macOS, missing Homebrew is installed through its official interactive installer.</sub>

<sub>Upgrading from a Korean-header setup (pre-1.1)? `export LOOMO_LANG=ko` keeps your existing protocol headers.</sub>

<br>

---

<br>

## Dashboard guide for beginners

<br>

Run `loomo` to open the dashboard. Nearly everything can be managed here with the mouse.

<br>

### Sessions

- Select `[＋ Add project]`, then choose Claude/Codex → project name → first pane role → folder.
- Click a project once to open details for panes and layouts.
- In details, use `Add unassigned panel` → `[＋ New panel]` to create and assign a pane immediately.
- Double-click a project to open all its panes in a dedicated terminal.
- Use `Edit arrangement` to assign unassigned panes or move existing panes between projects.

### Adopt

- Preview conversations previously used in Claude or Codex.
- Choose a conversation and pane name to place it in **Unassigned panels**.
- Conversations already managed by loomo are excluded from Adopt.

### Settings

- Choose the Hub session that routes requests across projects.
- Under **AI models**, each model lists its accounts by email. Click one to make every pane run as that account, add another with **[＋ Add account]**, or sign one out.
- View environment status and usage.
- Refresh every project's collaboration convention with **[⟳ Sync now]** — no CLI needed.

### Pane right-click skills

- In the dashboard, choose **Settings → Skills → Add Markdown skill**.
- Drag a `.md` file into the input area and press Enter.
- The skill appears as `Use: filename` the next time you right-click.
- Selecting it makes that pane's AI read and activate the Markdown instructions.
- Remove a skill from Settings with `[Delete]` → `[Confirm delete]`.
- Skills are stored under loomo's `skills/<name>/SKILL.md` configuration directory.

A project is one tmux session; each role is one resident AI pane. Claude and Codex panes can live in the same project.

<br>

This also inserts the collaboration convention into each directory (`CLAUDE.md` or `AGENTS.md`) — that's what tells the receiving AI to reply over the bridge. A project pane only messages within its own project; reaching another project is routed through the hub.

### Conversation persistence

loomo stores the Claude/Codex session ID for every pane. Conversation previews and resume use that same ID, so `loomo restart` reopens the same conversations. If a configured pane is missing from a running tmux session, opening the session or running `loomo up` restores it automatically.

Adopt shows only external conversations that loomo does not already own or have assigned.

<br>

---

<br>

## Terminal command guide

Use the CLI when you want a faster terminal workflow or scripting. Beginners do not need to memorize these commands.

### Start and attach

```bash
loomo up <project>      # start one project
loomo up --all          # start every registered project
loomo ws <project>      # start and attach in the current terminal
loomo down <project>    # stop a project, keep its configuration
loomo down --all        # stop every project
```

### Configure and manage

```bash
loomo add                         # register a project with the terminal wizard
loomo adopt                       # import an existing Claude/Codex conversation
loomo hub                         # register a Hub session
loomo layout <project> tiled      # change the pane layout
loomo list                        # show sessions, roles, and run state
loomo rm <project>                # remove project configuration
```

### Switch accounts

Run several subscription accounts and choose which one your panes use.

```bash
loomo account list                     # show accounts and which one is active
loomo account add claude               # add an account (one browser login)
loomo account use claude <id>          # switch — instant, no browser
loomo account logout claude <id>       # drop a stored account
loomo account remove claude <id>       # delete the profile entirely
```

Adding an account logs in once and stores its credentials, so switching afterwards is instant — the dashboard's **Settings → AI models** list does the same thing with a click. The chosen account applies to newly opened and restarted panes; panes already running keep the account they started with. The `default` profile means "whatever the CLI is logged in as".

### Restore and diagnose

```bash
loomo restart          # restart private tmux and restore saved panes/conversations
loomo doctor           # inspect the environment and configuration
loomo doctor --fix     # repair issues that are safe to fix automatically
loomo sync             # refresh collaboration blocks in CLAUDE.md/AGENTS.md
loomo tmux status      # inspect loomo's private tmux server
loomo update           # update to the latest npm release
```

> **After updating loomo, run `loomo sync` first.** It refreshes the collaboration convention in every registered project's `CLAUDE.md`/`AGENTS.md`. Then restart those sessions so they reload it — a session reads its convention only at startup.

### Cross-session request state

```bash
loomo task list
loomo task ack <KEY>
loomo task status <KEY> <state> "summary"
loomo skill add <file.md>
loomo skill list
```

Sessions can message with `tell <session> <role> "request"`. Most users should simply ask their AI in plain language instead of typing this directly.

<br>

---

<br>

## Let sessions talk

<br>

Double-click a project in the dashboard, then ask any pane's AI in plain language:

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

## Useful behavior

<br>

- **Single-click** a project for details; **double-click** it to open the session terminal.
- A pane name and path behave as one selectable item, and folders can be chosen in the browser.
- Configured panes missing from a live tmux session are restored when the session opens.
- Conversation previews and launches use the same session ID.
- Stopping a project or restarting loomo preserves configuration and conversation identity.
- Cross-session requests are tracked by KEY; a Hub can route work and aggregate replies.

<br>

---

<br>

## Mixing Claude & Codex

<br>

The bridge is agent-agnostic, so a **hub running Claude can command a project running Codex** — and vice versa.

Choose Claude or Codex first when creating a project or pane in the dashboard. Different panes in one project can use different models:

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
