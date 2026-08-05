<div align="center">

<br>

# loomo

### Claude Code & Codex 세션을 엮어, 서로 대화하는 하나의 팀으로.

<br>

[![npm](https://img.shields.io/npm/v/@namki1222/loomo?style=flat-square)](https://www.npmjs.com/package/@namki1222/loomo)
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

loomo의 목표는 두 가지다:

1. **세션 간 대화** — 프로젝트와 AI 모델이 달라도 Claude ↔ Claude, Codex ↔ Codex, Claude ↔ Codex가 직접 요청하고 응답한다.
2. **누구나 쉽게** — tmux, session ID, 메시징 명령을 몰라도 대시보드에서 프로젝트와 패널을 만들고 자연어로 일을 맡길 수 있다.

처음 쓰는 사람은 `loomo`만 실행하면 된다. 설치 확인부터 프로젝트·패널 구성, 기존 대화 가져오기, 재시작 후 대화 복원까지 화면에서 안내한다.

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

각 세션은 **장수명**이다 — 그 프로젝트의 이력을 계속 들고 있는 상주 동료지, 작업마다 다 잊는 일회용 에이전트가 아니다. session ID 저장과 복원은 loomo가 처리하므로 사용자가 직접 관리할 필요가 없다.

<br>

---

<br>

## 환경 요구사항

<br>

**첫 `loomo` 실행이 이걸 전부 설치합니다.** 이미 있는 항목은 건너뜁니다.

| 필요한 것 | 확인 | 비고 |
|---|---|---|
| **tmux** | `tmux -V` | 3.x 권장 · 첫 `loomo` 실행이 설치 |
| **Claude Code 및/또는 Codex** | `claude --version` / `codex --version` | 첫 `loomo` 실행이 둘 다 설치 |
| **Node.js / npm** | `npm -v` | 설치 채널로만 (런타임은 순수 셸) |
| macOS 또는 Linux | — | Windows는 WSL에서 동작 예상 (미검증) |

<br>

---

<br>

## 설치

<br>

```bash
npm install -g @namki1222/loomo

loomo               # Homebrew → tmux → Claude Code → Codex 확인/설치 후 대시보드 실행
```

<sub>첫 `loomo` 실행은 이미 설치된 항목을 건너뜁니다. macOS에서 Homebrew가 없으면 공식 대화형 설치 프로그램부터 실행합니다.</sub>

<sub>1.1 이전의 한국어 헤더 세팅을 쓰고 있다면 `export LOOMO_LANG=ko` 한 줄로 기존 프로토콜이 그대로 유지됩니다.</sub>

<br>

---

<br>

## 초보자를 위한 대시보드 사용법

<br>

터미널에서 `loomo`를 실행하면 대시보드가 열린다. 대부분의 작업은 여기서 마우스로 처리할 수 있다.

<br>

### Sessions

- `[＋ Add project]`를 누르고 Claude/Codex → 프로젝트 이름 → 첫 패널 역할 → 폴더를 선택한다.
- 프로젝트를 한 번 클릭하면 패널과 레이아웃을 관리하는 상세 화면이 열린다.
- 상세 화면의 `Add unassigned panel` → `[＋ New panel]`에서 새 패널을 현재 프로젝트에 바로 추가한다.
- 프로젝트를 더블클릭하면 전용 터미널에서 모든 패널이 열린다.
- `Edit arrangement`에서는 미배정 패널을 프로젝트에 넣거나 기존 패널을 다른 프로젝트로 옮긴다.

### Hub

- 비서의 최근 대화를 보고, **[대화 열기]** 로 비서의 Claude 화면을 그대로 연다. 복사본이 아니라 그 세션이라서 스트리밍과 Claude 고유의 서식이 전부 살아 있다. `Ctrl-b d` 로 대시보드에 돌아온다.
- 한 마디만 시킬 거면 아래 입력창에 바로 써도 된다. 비서에게 그대로 전달된다.
- 비서 세션이 꺼져 있으면 자동으로 시작한다.

### Adopt

- 기존에 사용하던 Claude/Codex 대화를 내용 미리보기로 확인한다.
- 가져올 대화를 선택하고 패널 이름을 정하면 **Unassigned panels**에 들어간다.
- 이미 loomo가 관리하는 대화는 Adopt 목록에 다시 나타나지 않는다.

### Settings

- 전체 요청을 라우팅할 Hub session을 지정한다.
- **AI models** 아래에 모델별 계정이 이메일로 나열된다. 계정을 클릭하면 모든 패널이 그 계정으로 실행되고, **[＋ Add account]** 로 계정을 추가하거나 로그아웃할 수 있다.
- 각 에이전트의 **Model** 토글로 패널이 사용할 모델을 정한다(`auto`는 CLI 기본값). 새로 열거나 재시작하는 패널부터 적용된다.
- 환경 상태와 사용량을 확인한다.
- **[⟳ Sync now]** 로 모든 프로젝트의 협업 규약(CLAUDE.md/AGENTS.md)을 최신 템플릿으로 갱신한다.

### 패널 우클릭과 스킬

- 대시보드 **Settings → Skills → Add Markdown skill**을 선택한다.
- 입력 영역에 `.md` 파일을 드래그앤드롭한 뒤 Enter를 누른다.
- 추가된 스킬은 다음 우클릭 메뉴부터 `Use: 파일명`으로 표시된다.
- 스킬을 클릭하면 해당 패널의 AI가 Markdown 지침을 읽고 활성화한다.
- Settings의 스킬 목록에서 `[Delete]` → `[Confirm delete]`로 제거할 수 있다.
- 스킬은 loomo 설정의 `skills/<이름>/SKILL.md`에 보관된다.

한 프로젝트는 하나의 tmux 세션이고, 역할 하나는 그 안의 AI 패널 하나다. 프로젝트 하나에 Claude와 Codex 패널을 함께 둘 수 있다.

<br>

이때 각 디렉터리의 규약 파일(`CLAUDE.md` 또는 `AGENTS.md`)에 협업 규약이 삽입된다 — 받는 쪽 AI가 브릿지로 응답하는 근거다. 패널은 다른 프로젝트의 역할에게도 직접 요청을 보낼 수 있고, 여러 프로젝트가 걸린 일은 허브에 맡기면 된다.

### 대화 복원

loomo는 각 패널의 Claude/Codex session ID를 저장한다. 목록의 대화 미리보기와 실제 재개가 같은 ID를 사용하므로 `loomo restart` 후에도 같은 대화가 열린다. 실행 중 설정에는 있지만 tmux에서 빠진 패널은 세션을 열거나 `loomo up`을 실행할 때 자동 복구된다.

Adopt에는 loomo가 이미 소유하거나 배정한 대화가 아니라, 아직 연결되지 않은 외부 대화만 표시된다.

<br>

---

<br>

## 터미널 명령어 사용법

대시보드 없이 빠르게 실행하거나 스크립트에서 자동화할 때 사용한다. 처음 쓰는 사람은 이 명령들을 외울 필요가 없다.

### 시작과 접속

```bash
loomo up <프로젝트>    # 프로젝트 시작
loomo up --all         # 등록된 프로젝트 모두 시작
loomo ws <프로젝트>    # 프로젝트 시작 후 현재 터미널에서 접속
loomo down <프로젝트>  # 프로젝트 종료, 설정은 유지
loomo down --all       # 모든 프로젝트 종료
```

### 구성과 관리

```bash
loomo add                         # 터미널 마법사로 프로젝트 등록
loomo adopt                       # 기존 Claude/Codex 대화 가져오기
loomo hub                         # Hub session 등록
loomo layout <프로젝트> tiled      # 패널 레이아웃 변경
loomo list                        # 세션·역할·실행 상태 확인
loomo rm <프로젝트>               # 프로젝트 설정 제거
```

### 계정 전환

구독 계정을 여러 개 등록해두고, 패널이 어떤 계정으로 돌지 고른다.

```bash
loomo account list                     # 계정 목록과 현재 활성 계정 확인
loomo account add claude               # 계정 추가 (브라우저 로그인 1회)
loomo account use claude <id>          # 전환 — 브라우저 없이 즉시
loomo account logout claude <id>       # 저장된 계정 연결 해제
loomo account remove claude <id>       # 프로필 자체를 삭제
```

계정을 추가할 때 한 번 로그인해 인증 정보를 저장하므로, 이후 전환은 즉시 이뤄진다. 대시보드 **Settings → AI models** 목록에서 클릭으로도 같은 전환이 된다. 선택한 계정은 **새로 열거나 재시작하는 패널**부터 적용되고, 이미 떠 있는 패널은 시작할 때의 계정을 유지한다. `default` 프로필은 "현재 CLI에 로그인된 계정 그대로"를 뜻한다.

### 복구와 진단

```bash
loomo restart          # 전용 tmux 재시작 후 저장된 패널·대화 복원
loomo doctor           # 환경과 설정 점검
loomo doctor --fix     # 안전하게 자동 복구 가능한 문제 수정
loomo sync             # CLAUDE.md/AGENTS.md 협업 규약 갱신
loomo tmux status      # loomo 전용 tmux 상태 확인
loomo update           # 최신 npm 버전으로 업데이트
```

> **loomo를 업데이트했다면 `loomo sync`를 맨 먼저 실행하세요.** 등록된 모든 프로젝트의 `CLAUDE.md`/`AGENTS.md` 협업 규약을 최신으로 갱신합니다. 그다음 해당 세션들을 재시작해야 새 규약을 읽습니다 — 세션은 시작 시점에만 규약을 읽습니다.

### 세션 간 요청 상태

```bash
loomo task list
loomo task ack <KEY>
loomo task status <KEY> <상태> "요약"
loomo skill add <파일.md>
loomo skill list
```

세션끼리 메시지를 보낼 때는 `tell <세션> <역할> "요청"`을 사용한다. 하지만 일반 사용자는 직접 입력하지 않고 AI에게 자연어로 부탁하면 된다.

<br>

---

<br>

## 세션끼리 대화하기

<br>

대시보드에서 프로젝트를 더블클릭해 연 다음, 아무 패널의 AI에게 자연어로 부탁한다:

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

## 알아두면 좋은 동작

<br>

- 목록에서 프로젝트를 **한 번 클릭**하면 상세 화면, **더블클릭**하면 세션 터미널이 열린다.
- 패널명과 경로는 한 묶음으로 선택되며, 폴더는 브라우저에서 이동해 고를 수 있다.
- 설정에 등록됐지만 실행 중 빠진 패널은 세션을 열 때 자동 복구된다.
- 대화 미리보기와 실제 실행은 같은 session ID를 사용한다.
- 프로젝트를 멈추거나 loomo를 재시작해도 설정과 대화 연결은 유지된다.
- 세션 간 요청은 KEY로 추적되며, Hub가 있으면 적절한 프로젝트로 라우팅하고 결과를 모아준다.

<br>

---

<br>

## Claude & Codex 혼합

<br>

브릿지는 에이전트 무관이라, **Claude로 도는 허브가 Codex로 도는 프로젝트를 지휘**할 수 있다 — 반대도 된다.

프로젝트나 패널을 만들 때 대시보드에서 Claude 또는 Codex를 먼저 선택한다. 한 프로젝트 안에서도 패널마다 다른 모델을 사용할 수 있다:

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
