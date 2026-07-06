<div align="center">

<br>

# loomo

### 把你的 Claude Code 和 Codex 会话编织成一支互相对话的团队。

<br>

[![npm](https://img.shields.io/npm/v/loomo?style=flat-square)](https://www.npmjs.com/package/loomo)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-555?style=flat-square)](#环境要求)

<br>

[English](README.md) · [한국어](README.ko.md) · 中文

<sub>无守护进程 · 无数据库 · 无 MCP —— 一个脚本加一套约定。</sub>

<br>

</div>

---

<br>

用一个会话跑后端、另一个跑前端，你很快会撞上一堵墙：**这两个会话看不到彼此。**

后端一改 API，就得*你亲手*把结果复制粘贴到前端会话。每一次交接都是手动中转。

<br>

**loomo 拆掉了这堵墙。** 你的会话变成会互相发消息的队友——后端改完后自己去告诉前端，前端做完再把结果回传。

你只用自然语言说话，协调交给会话自己完成。而且它不在乎会话跑的是 **Claude Code 还是 Codex** —— 它们都在同一座桥上对话。

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

每个会话都是**长期存活**的——一个持有该项目历史的常驻队友，而不是每次任务间就忘光的一次性 agent。

<br>

---

<br>

## 环境要求

<br>

| 需要 | 检查 | 说明 |
|---|---|---|
| **tmux** | `tmux -V` | 建议 3.x · `brew install tmux` |
| **Claude Code 和/或 Codex** | `claude --version` / `codex --version` | 每个窗格里的 AI —— 可自由混用 |
| **Node.js / npm** | `npm -v` | 仅作安装渠道（运行时是纯 shell） |
| macOS 或 Linux | — | Windows 预期可在 WSL 下运行（未验证） |

<br>

---

<br>

## 安装

<br>

```bash
npm install -g loomo

loomo doctor        # 环境检查
```

<br>

---

<br>

## 组建你的团队

<br>

```bash
loomo init
```

<br>

向导按顺序询问：

<br>

- **1 · 默认 AI 模型** —— `claude` 或 `codex`。之后可按会话覆盖，所以 Claude 和 Codex 能共享一块屏幕。

- **2 · 要中枢（管理）会话吗？** —— 替你指挥项目的"秘书"。回车跳过，之后用 `loomo hub` 添加。

- **3 · 项目** —— 每个：**项目名（= 会话）** → **角色（= 窗格）** → **目录** → **模型**（回车 = 默认）。每个项目可多个角色。

<br>

此时会把协作约定插入每个目录的约定文件（`CLAUDE.md` 或 `AGENTS.md`）——这正是接收方 AI 通过桥回复的依据。

<br>

---

<br>

## 运行与对话

<br>

```bash
loomo up --all      # 启动全部会话（分割窗格 + 启动 AI），接入中枢

loomo up <项目>     # 或只启动一个

loomo list          # 现在你能对话的对象
```

<br>

然后用自然语言对任意窗格的 AI 说：

<br>

```
告诉 web 订单数据结构改了，让它更新 UI
```

<br>

你从不输入消息命令——约定会让 AI 自己中转，对方会话自己回复。

**Claude → Codex、Codex → Claude，任意方向。**

<br>

---

<br>

## 命令

<br>

你运行的全是管理命令——就那么几个。会话之间的消息由约定驱动 AI 自动执行，你从不亲手输入。

<br>

| 命令 | 作用 |
|---|---|
| `loomo up --all` \| `up <会话>` | 启动全部（→接入中枢）/ 一个 · 不带参数的 `up` 列出已注册项 |
| `loomo down <会话>` \| `--all` | 停止 —— 仅终止会话，保留配置 |
| `loomo ws <会话>` | 启动一个并接入 |
| `loomo layout [<会话>] <预设>` | 重排窗格（`tiled` / `main-vertical` / …），无需 `tmux.conf` |
| `loomo init` | 设置向导 —— 模型·中枢·项目/角色/目录 + 约定 |
| `loomo adopt` | 接入已在运行的 AI —— 无需重启 |
| `loomo hub` | 注册管理（中枢）会话 —— 只允许一个 |
| `loomo list` | 通讯录 —— 可对话对象 + 状态 |
| `loomo rm <会话>` | 删除工作区 —— 移除配置+约定，项目文件不受影响 |
| `loomo doctor` · `completion` · `help` | 环境检查 · Shell 补全 · 完整帮助 |

<br>

可选 Tab 补全：

```bash
echo 'eval "$(loomo completion)"' >> ~/.zshrc
```

<br>

---

<br>

## 混用 Claude 与 Codex

<br>

桥与具体 agent 无关，所以**跑 Claude 的中枢可以指挥跑 Codex 的项目**——反之亦然。

在 `loomo init`（或 `~/.config/loomo/workspaces.conf` 的第 5 字段）里按会话指定模型：

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

一个 **Claude 中枢会话**掌控全局 —— 把请求路由到对应会话，追踪回复并汇报。配合 Claude Code 的 **远程控制（Remote Control）**，不带电脑时也能用**手机**指挥整支队伍。

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
