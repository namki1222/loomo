<div align="center">

<br>

# loomo

### Claude Code & Codex 세션을 엮어, 서로 대화하는 하나의 팀으로.

<br>

[![npm](https://img.shields.io/npm/v/loomo?style=flat-square)](https://www.npmjs.com/package/loomo)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-555?style=flat-square)](#환경-요구사항)

<br>

[English](README.md) · 한국어 · [中文](README.zh-CN.md)

<sub>데몬 없음 · DB 없음 · MCP 없음 — 스크립트 하나와 규약이 전부.</sub>

<br>

</div>

---

<br>

백엔드용 세션 하나, 프론트엔드용 하나를 띄워보면 금방 벽에 부딪힌다: **둘은 서로를 못 본다.**

백엔드가 API를 바꾸면 그 결과를 *사람이 복사해서* 프론트 세션에 붙여넣어야 한다. 매번 손으로 중계하는 거다.

<br>

**loomo는 그 벽을 허문다.** 세션들이 서로 직접 메시지를 주고받는 동료가 된다 — 백엔드가 변경을 마치면 스스로 프론트에게 알리고, 프론트는 자기 일을 한 뒤 결과를 돌려준다.

너는 자연어로 말하면 되고, 조율은 세션들이 알아서 한다. 그리고 그 세션이 **Claude Code든 Codex든 상관없다** — 같은 브릿지 위에서 다 대화한다.

<br>

```
브릿지 없이 — 네가 중계자:              브릿지와 함께 — 세션들이 알아서 순환:


  [백엔드]  "완료, API 바뀜"                 ┌──"API 바뀜, UI 반영해줘"──►┐

      │                                 [백엔드]                      [프론트]

      │  ✋ 복사 & 붙여넣기                     └◄──────"완료 ✅"──────────┘

      ▼

  [프론트]  "...여기 붙여넣기"            너: 한 문장, 나머지는 세션들이 처리
```

<br>

각 세션은 **장수명**이다 — 그 프로젝트의 이력을 계속 들고 있는 상주 동료지, 작업마다 다 잊는 일회용 에이전트가 아니다.

<br>

---

<br>

## 환경 요구사항

<br>

| 필요한 것 | 확인 | 비고 |
|---|---|---|
| **tmux** | `tmux -V` | 3.x 권장 · `brew install tmux` |
| **Claude Code 및/또는 Codex** | `claude --version` / `codex --version` | 각 패널의 AI — 섞어 써도 됨 |
| **Node.js / npm** | `npm -v` | 설치 채널로만 (런타임은 순수 셸) |
| macOS 또는 Linux | — | Windows는 WSL에서 동작 예상 (미검증) |

<br>

---

<br>

## 설치

<br>

```bash
npm install -g loomo

loomo doctor        # 환경 점검
```

<br>

---

<br>

## 팀 구성

<br>

```bash
loomo init
```

<br>

마법사가 순서대로 묻는다:

<br>

- **1 · 기본 AI 모델** — `claude` 또는 `codex`. 세션마다 다르게도 지정할 수 있어서, Claude와 Codex가 한 화면을 공유한다.

- **2 · 허브(관리자) 세션?** — 프로젝트를 대신 지휘하는 '비서'. 엔터로 건너뛰고 나중에 `loomo hub`로 추가.

- **3 · 프로젝트** — 각각: **프로젝트 이름(=세션)** → **역할(=패널)** → **디렉터리** → **모델**(엔터=기본). 역할은 여러 개.

<br>

이때 각 디렉터리의 규약 파일(`CLAUDE.md` 또는 `AGENTS.md`)에 협업 규약이 삽입된다 — 받는 쪽 AI가 브릿지로 응답하는 근거다.

<br>

---

<br>

## 실행 & 대화

<br>

```bash
loomo up --all      # 전체 세션 켜기(패널 분할 + AI 실행), 허브로 접속

loomo up <프로젝트>  # 또는 하나만

loomo list          # 지금 말 걸 수 있는 상대
```

<br>

그다음 아무 패널의 AI에게 자연어로 부탁한다:

<br>

```
web한테 주문 스키마 바뀐 거 알려주고 UI 반영시켜줘
```

<br>

메시징 명령을 직접 칠 필요 없다 — 규약이 AI가 알아서 중계하게 하고, 상대 세션이 스스로 응답한다.

**Claude → Codex, Codex → Claude, 어느 방향이든.**

<br>

---

<br>

## 명령어

<br>

네가 쓰는 건 관리 명령이 전부다 — 몇 개 안 된다. 세션끼리의 메시징은 규약대로 AI가 알아서 실행하니 사람이 칠 일이 없다.

<br>

| 명령 | 설명 |
|---|---|
| `loomo up --all` \| `up <세션>` | 전체 켜기(→허브 접속) / 하나 · 인자 없는 `up`은 목록 안내 |
| `loomo down <세션>` \| `--all` | 끄기 — 세션 종료만, 설정 유지 |
| `loomo ws <세션>` | 하나 켜고 접속 |
| `loomo layout [<세션>] <프리셋>` | 패널 배치(`tiled` / `main-vertical` / …), `tmux.conf` 불필요 |
| `loomo init` | 셋업 마법사 — 모델·허브·프로젝트/역할/디렉터리 + 규약 |
| `loomo adopt` | 이미 쓰던 AI 편입 — 재시작 없이 |
| `loomo hub` | 관리자(허브) 세션 등록 — 하나만 |
| `loomo list` | 주소록 — 말 걸 수 있는 상대 + 상태 |
| `loomo rm <세션>` | 워크스페이스 삭제 — 설정+규약 제거, 프로젝트 파일 무손상 |
| `loomo doctor` · `completion` · `help` | 환경 점검 · 셸 자동완성 · 전체 도움말 |

<br>

탭 자동완성(선택):

```bash
echo 'eval "$(loomo completion)"' >> ~/.zshrc
```

<br>

---

<br>

## Claude & Codex 혼합

<br>

브릿지는 에이전트 무관이라, **Claude로 도는 허브가 Codex로 도는 프로젝트를 지휘**할 수 있다 — 반대도 된다.

모델은 `loomo init`에서(또는 `~/.config/loomo/workspaces.conf`의 5번째 필드로) 세션별로 지정한다:

<br>

```
howlpot|서버|~/work/howlpot|      claude

labs|dev|~/work/labs|            codex
```

<br>

한 화면을 공유하며 똑같은 방식으로 서로 대화한다 — Claude 세션이 Codex 세션에 일을 넘기고 결과를 받는다. 접착 코드 없이.

<br>

---

<br>

## 실전 — 저자는 이렇게 씁니다

<br>

프로젝트 **6개**를 등록해두고, 각각 1~4개 패널(서버 / 앱 / 대시보드 …)로 구성합니다.

<br>

**Claude 비서 세션 하나**가 전부를 파악합니다 — 요청을 맞는 세션으로 라우팅하고, 응답을 추적해 보고합니다. Claude Code의 **Remote Control**과 함께 쓰면, 노트북 없이 **폰에서도** 전 프로젝트를 지휘합니다.

<br>

한 프로젝트에 집중할 땐 비서를 거치지 않고 그 **프로젝트 세션에서 직접** 대화합니다 — 그러면 하루 종일 컨텍스트가 이어져서 매번 새로 시작할 필요가 없습니다.

<br>

---

<br>

## 보안

<br>

- **신뢰된 로컬 환경 전용.** 같은 tmux 서버에 접근 가능한 누구나 어떤 패널에든 메시지를 주입할 수 있다. 상관키는 라우팅용이지 인증이 아니다.

- **비밀번호·토큰·시크릿을 절대 이걸로 보내지 마라** — 상대 패널 스크롤백에 평문으로 남는다. 자격증명은 권한 있는 채널(scp 등)로.

<br>

---

<br>

<div align="center">

MIT © [namki1222](https://github.com/namki1222)

<br>

</div>
