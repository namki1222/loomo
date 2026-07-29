<div align="center">

<br>

# loomo

### 把你的 Claude Code 和 Codex 会话编织成一支互相对话的团队。

<br>

[![npm](https://img.shields.io/npm/v/@namki1222/loomo?style=flat-square)](https://www.npmjs.com/package/@namki1222/loomo)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-555?style=flat-square)](#环境要求)

<br>

[English](README.md) · [한국어](README.ko.md) · 中文

<sub>无守护进程 · 无数据库 · 无 MCP —— 一个脚本加一套约定。</sub>

<br>

</div>

---

<br>

用一个 Claude Code 会话跑后端、另一个跑前端，你很快会撞上一堵墙：**这两个会话看不到彼此。**

后端一改 API，就得*你亲手*把结果复制粘贴到前端会话。每一次交接都是手动中转。

<br>

**loomo 拆掉了这堵墙。** 你的会话变成会互相发消息的队友——后端改完后自己去告诉前端，前端做完再把结果回传。

你只用自然语言说话，协调交给会话自己完成。而且它不在乎会话跑的是 **Claude Code 还是 Codex** —— 它们都在同一座桥上对话。

loomo 有两个目标：

1. **会话间对话** —— 项目和模型可以不同；Claude ↔ Claude、Codex ↔ Codex、Claude ↔ Codex 都能直接请求工作并回复。
2. **人人都能上手** —— 你不需要懂 tmux、session ID 或消息命令。在仪表盘里建好项目和窗格，然后用自然语言委派即可。

新用户只需运行 `loomo`。它会引导你完成依赖安装、项目与窗格创建、对话接入，以及重启后的对话恢复。

<br>

```
没有它 —— 你是中转者：                有了它 —— 会话自己循环：


  [后端]  "完成，API 改了"                 ┌──"API 改了，更新 UI"──►┐

     │                               [后端]                    [前端]

     │  ✋ 复制粘贴                        └◄──────"完成 ✅"────────┘

     ▼

  [前端]  "…粘贴到这里"              你：一句话，剩下的会话自己处理
```

<br>

每个会话都是**长期存活**的——一个持有该项目历史的常驻队友，而不是每次任务间就忘光的一次性 agent。loomo 会保存并恢复 session ID，用户永远不必手动管理它们。

<br>

---

<br>

## 环境要求

<br>

**首次运行 `loomo` 会为你安装以下全部内容**，就绪后打开仪表盘。已安装的项目会自动跳过。

| 需要 | 检查 | 说明 |
|---|---|---|
| **tmux** | `tmux -V` | 建议 3.x · 首次运行 `loomo` 时安装 |
| **Claude Code 和/或 Codex** | `claude --version` / `codex --version` | 首次运行 `loomo` 时安装两者 |
| **Node.js / npm** | `npm -v` | 仅作安装渠道（运行时是纯 shell） |
| macOS 或 Linux | — | Windows 预期可在 WSL 下运行（未验证） |

<br>

---

<br>

## 安装

<br>

```bash
npm install -g @namki1222/loomo

loomo               # 检查/安装 Homebrew → tmux → Claude Code → Codex，然后打开仪表盘
```

<sub>首次运行是幂等的：已安装的依赖会被跳过。在 macOS 上，如果缺少 Homebrew，将先运行其官方交互式安装程序。</sub>

<sub>从 1.1 之前的韩语协议头升级？`export LOOMO_LANG=ko` 可保持原有协议头不变。</sub>

<br>

---

<br>

## 初学者仪表盘指南

<br>

运行 `loomo` 打开仪表盘。几乎所有事情都能在这里用鼠标管理。

<br>

### Sessions

- 选择 `[＋ Add project]`，然后依次选择 Claude/Codex → 项目名 → 首个窗格角色 → 文件夹。
- 单击项目一次即可打开窗格与布局的详情。
- 在详情里，用 `Add unassigned panel` → `[＋ New panel]` 立即创建并分配一个窗格。
- 双击项目会在专用终端里打开它的全部窗格。
- 用 `Edit arrangement` 分配未指派的窗格，或在项目之间移动已有窗格。

### Hub

- 无需离开仪表盘即可与 Hub 会话对话 —— 在输入行里输入，Hub 就在这里回复。
- 它就是 Hub 本身，而不是另一个助手：沿用同一段对话，并且照常把工作分派给各个项目窗格。
- 如果 Hub 会话没有运行，会自动启动。

### Adopt

- 预览此前在 Claude 或 Codex 中用过的对话。
- 选择一个对话并命名窗格，把它放进 **Unassigned panels**。
- 已由 loomo 管理的对话会从 Adopt 中排除。

### Settings

- 选择负责在项目间路由请求的 Hub 会话。
- 在 **AI models** 下，每个模型会按邮箱列出它的账号。点击某个账号即可让所有窗格以该账号运行，也可以用 **[＋ Add account]** 添加账号或退出登录。
- 每个 agent 下的 **Model** 开关用于选择窗格启动时使用的模型（`auto` 表示交给 CLI 决定）。对新打开或重启的窗格生效。
- 查看环境状态与用量。
- 用 **[⟳ Sync now]** 刷新每个项目的协作约定 —— 无需 CLI。

### 窗格右键技能

- 在仪表盘里选择 **Settings → Skills → Add Markdown skill**。
- 把一个 `.md` 文件拖入输入区并按 Enter。
- 该技能会在下次右键时以 `Use: 文件名` 出现。
- 选中它会让该窗格的 AI 读取并激活这段 Markdown 指令。
- 在 Settings 里用 `[Delete]` → `[Confirm delete]` 移除技能。
- 技能保存在 loomo 的 `skills/<名称>/SKILL.md` 配置目录下。

一个项目就是一个 tmux 会话；每个角色就是一个常驻 AI 窗格。Claude 和 Codex 窗格可以共存于同一个项目。

<br>

这同时会把协作约定插入每个目录的约定文件（`CLAUDE.md` 或 `AGENTS.md`）——这正是接收方 AI 通过桥回复的依据。项目窗格只在自己项目内发消息；要触达另一个项目，会经由中枢路由。

### 对话持久化

loomo 会为每个窗格保存 Claude/Codex 的 session ID。对话预览和恢复都使用同一个 ID，所以 `loomo restart` 会重新打开相同的对话。如果某个已配置的窗格在运行中的 tmux 会话里缺失，打开该会话或运行 `loomo up` 会自动恢复它。

Adopt 只显示 loomo 尚未拥有或分配的外部对话。

<br>

---

<br>

## 终端命令指南

想要更快的终端工作流或做脚本化时使用 CLI。初学者不需要记住这些命令。

### 启动与接入

```bash
loomo up <project>      # 启动一个项目
loomo up --all          # 启动每个已注册的项目
loomo ws <project>      # 启动并在当前终端接入
loomo down <project>    # 停止一个项目，保留其配置
loomo down --all        # 停止每个项目
```

### 配置与管理

```bash
loomo add                         # 用终端向导注册一个项目
loomo adopt                       # 导入一个已有的 Claude/Codex 对话
loomo hub                         # 注册一个 Hub 会话
loomo layout <project> tiled      # 更改窗格布局
loomo list                        # 显示会话、角色与运行状态
loomo rm <project>                # 移除项目配置
```

### 切换账号

注册多个订阅账号，并选择窗格使用哪一个。

```bash
loomo account list                     # 查看账号列表与当前生效的账号
loomo account add claude               # 添加账号（浏览器登录一次）
loomo account use claude <id>          # 切换 —— 即时生效，无需浏览器
loomo account logout claude <id>       # 移除已保存的账号凭据
loomo account remove claude <id>       # 彻底删除该配置
```

添加账号时登录一次并保存凭据，因此之后的切换是即时的；在仪表盘 **Settings → AI models** 列表中点击即可完成同样的切换。所选账号对**新打开或重启的窗格**生效，已在运行的窗格仍保持启动时的账号。`default` 配置表示"沿用 CLI 当前登录的账号"。

### 恢复与诊断

```bash
loomo restart          # 重启私有 tmux 并恢复已保存的窗格/对话
loomo doctor           # 检查环境与配置
loomo doctor --fix     # 修复可以安全自动修复的问题
loomo sync             # 刷新 CLAUDE.md/AGENTS.md 里的协作块
loomo tmux status      # 检查 loomo 的私有 tmux 服务器
loomo update           # 更新到最新的 npm 发布版
```

> **更新 loomo 后，请先运行 `loomo sync`。** 它会刷新每个已注册项目 `CLAUDE.md`/`AGENTS.md` 中的协作约定。然后重启这些会话以重新加载新约定 —— 会话只在启动时读取约定。

### 会话间请求状态

```bash
loomo task list
loomo task ack <KEY>
loomo task status <KEY> <state> "summary"
loomo skill add <file.md>
loomo skill list
```

会话之间可以用 `tell <session> <role> "request"` 发消息。大多数用户只需用自然语言让自己的 AI 去做，而不必直接输入这条命令。

<br>

---

<br>

## 让会话对话

<br>

在仪表盘里双击一个项目，然后用自然语言对任意窗格的 AI 说：

<br>

```
tell web the order schema changed and have it update the UI
```

<br>

你从不输入消息命令——约定会让 AI 自己中转，对方会话自己回复。

**Claude → Codex、Codex → Claude，任意方向。**

<br>

---

<br>

## 好用的特性

<br>

- **单击**项目查看详情；**双击**它打开会话终端。
- 窗格名与路径作为一个可选项一起行动，文件夹可在浏览器中选择。
- 在运行中的 tmux 会话里缺失的已配置窗格，会在会话打开时恢复。
- 对话预览与启动使用同一个 session ID。
- 停止项目或重启 loomo 都会保留配置与对话身份。
- 会话间请求按 KEY 追踪；中枢可以路由工作并汇总回复。

<br>

---

<br>

## 混用 Claude 与 Codex

<br>

桥与具体 agent 无关，所以**跑 Claude 的中枢可以指挥跑 Codex 的项目**——反之亦然。

在仪表盘里创建项目或窗格时先选择 Claude 或 Codex。同一个项目里的不同窗格可以使用不同模型：

<br>

```
howlpot|server|~/work/howlpot|      claude

labs|dev|~/work/labs|               codex
```

<br>

它们共享一块屏幕，以完全相同的方式互相对话——Claude 会话把工作交给 Codex 会话并拿回结果，无需胶水代码。

<br>

---

<br>

## 实战 —— 作者这样用

<br>

我注册了 **6 个项目**，每个 1~4 个窗格（服务器 / 应用 / 仪表盘 …）。

<br>

一个 **Claude 中枢会话**掌控全局 —— 把我的请求路由到对应会话，追踪回复并汇报。配合 Claude Code 的 **远程控制（Remote Control）**，不带电脑时也能用**手机**指挥整支队伍。

<br>

专注单个项目时，我跳过中枢，直接和那个**项目会话**对话 —— 这样上下文能贯穿一整天，不必每次重新开始。

<br>

---

<br>

## 安全

<br>

- **仅限可信的本地环境。** 任何能访问同一 tmux 服务器的人都能往任意窗格注入消息。相关 key 用于路由，不是身份认证。

- **绝不要用它发送密码、令牌或密钥** —— 它们会以明文留在目标窗格的回滚缓冲里。凭据请走带权限的通道（scp 等）。

<br>

---

<br>

<div align="center">

MIT © [namki1222](https://github.com/namki1222)

<br>

</div>
