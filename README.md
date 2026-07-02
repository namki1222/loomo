<div align="center">

# claude-tell-bridge

**여러 Claude Code 세션을 한 화면에 띄우고, 세션끼리 대화하게 하라.**

[![npm](https://img.shields.io/npm/v/claude-tell-bridge?style=flat-square)](https://www.npmjs.com/package/claude-tell-bridge)
[![license](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-555?style=flat-square)](#환경-요구사항)

데몬 없음 · DB 없음 · MCP 없음 — **bash 스크립트 1개 + CLAUDE.md 규약**이 전부.

</div>

---

백엔드용 Claude Code 세션 하나, 프론트엔드용 세션 하나를 띄워놓고 일해본 적 있다면 알 것이다 — 백엔드가 API를 바꾸면 그 결과를 **사람이 복사해서** 프론트 세션에 붙여넣어야 한다. 이 도구는 그 복붙을 없앤다. 한 세션이 `tell`로 **보내면**, 상대 세션이 **자기 입력창으로 직접 받는다.** 받은 세션은 작업을 마치고 `tell -r`로 **스스로 응답한다.**

```
┌─ 한 화면 = 한 팀 ───────────────────────────────────────────────┐
│ [proj-a:server]                     [proj-a:web]               │
│  FastAPI 담당 Claude                 React 담당 Claude          │
│     │ tell proj-a web "응답에 pagination 메타 추가했어.          │
│     │  GET /orders 스키마 바뀜 — 프론트 반영해줘" ──► KEY=a1b2c3 │
│     ◄── tell -r a1b2c3 proj-a server "반영 완료: ..." ──────────│
└────────────────────────────────────────────────────────────────┘
```

> 처음이라면 위에서부터 순서대로 읽으면 된다. 모든 명령이 포함되어 있고, 내부 원리를 몰라도 쓸 수 있다.

## 목차

- [어떻게 상상하면 되나](#어떻게-상상하면-되나)
- [왜 이 방식인가](#왜-이-방식인가)
- [환경 요구사항](#환경-요구사항)
- [설치](#설치)
- [빠른 시작 A — 처음부터 (`tell init`)](#빠른-시작-a--처음부터-tell-init)
- [빠른 시작 B — 이미 쓰던 세션 편입 (`tell adopt`)](#빠른-시작-b--이미-쓰던-세션-편입-tell-adopt)
- [메시지 주고받기 — 자세히](#메시지-주고받기--자세히)
- [규약(CLAUDE.md) — 브릿지의 나머지 절반](#규약claudemd--브릿지의-나머지-절반)
- [권장 패턴: 허브(비서) 세션 + 폰 원격](#권장-패턴-허브비서-세션--폰-원격)
- [여러 프로젝트 동시 운용](#여러-프로젝트-동시-운용)
- [명령어 레퍼런스](#명령어-레퍼런스)
- [설정 파일](#설정-파일)
- [트러블슈팅](#트러블슈팅)
- [FAQ](#faq)
- [보안](#보안)
- [알려진 제약 · 로드맵](#알려진-제약--로드맵)

---

## 어떻게 상상하면 되나

개념은 세 가지뿐이다:

- **세션 = 프로젝트 팀.** 세션 하나가 프로젝트 하나다 (`proj-a`, `blog`, …).
- **패널 = 그 팀에 상주하는 AI 동료.** 패널 이름이 곧 역할이자 주소다 (`server`, `web`, `infra`). 각 패널에서 Claude Code가 **장수명으로** 돌아간다 — 스폰됐다 사라지는 서브에이전트가 아니라, 그 코드베이스의 이력과 맥락을 계속 들고 있는 담당자다.
- **`tell` = 그 동료에게 말 걸기.** `tell <세션> <역할> "<메시지>"` 하면 상대 패널의 입력창에 메시지가 직접 타이핑된다. 6자리 상관키(KEY)가 붙어서, 나중에 어떤 요청에 대한 응답인지 매칭된다.

```
세션 "proj-a"  패널 "server"  ┐
세션 "proj-a"  패널 "web"     ├── 같은 팀 — tell로 서로 대화
세션 "proj-a"  패널 "infra"   ┘

세션 "blog"    패널 "server"  ─── 다른 팀 — 주소가 다르니 섞이지 않음
```

"연결" 버튼 같은 건 없다. **세션이 떠 있다는 것 자체가 연결이다.**

## 왜 이 방식인가

- **컨텍스트 주인에게 물어본다** — 신선한 에이전트가 추측하는 게 아니라, 그 프로젝트에 *상주*하는 세션이 자기 코드·환경을 직접 확인하고 답한다. ("너네 nginx 어떻게 세팅했어?" → 상대가 자기 서버의 실제 conf를 열어보고 답한다.)
- **장수명 컨텍스트** — 각 패널은 프로젝트 이력·메모리·CLAUDE.md를 계속 유지한다. 매번 재설명(온보딩) 비용이 없다.
- **화면 분할 = 팀 관제탑** — `tell ws` 한 번으로 역할별 패널 배치가 재현된다. 모든 AI 동료가 일하는 걸 한 화면에서 보면서, 아무 패널이나 클릭해 **직접** 지시할 수도 있다.
- **비동기 논블로킹** — 상관키로 여러 요청을 동시에 추적한다. 보낸 쪽은 기다리지 않고 다음 일을 한다. 응답은 나중에 새 메시지로 들어온다.
- **유리箱 오케스트레이션** — 모든 대화가 화면에 그대로 보인다. 블랙박스 없음. 언제든 사람이 끼어들 수 있다.
- **인프라 제로** — 상대 입력창에 직접 타이핑하는 게 전부다. 데몬·큐·MCP 서버·훅 설정이 없다. 전체 코드가 bash 한 파일이라 5분이면 다 읽힌다.

## 환경 요구사항

| 필요한 것 | 확인 명령 | 비고 |
|---|---|---|
| **tmux** | `tmux -V` | 3.x 권장. `brew install tmux` |
| **Claude Code** | `claude --version` | 받는 쪽에서 응답을 만들 AI |
| **Node.js / npm** | `npm -v` | 설치 채널로만 사용 (런타임은 순수 bash) |
| macOS 또는 Linux | — | Windows는 WSL에서 동작 예상 (미검증) |

## 설치

```bash
npm install -g claude-tell-bridge
tell doctor        # 환경 점검
```

`tell doctor` 출력 예:

```
── tell doctor ──
✅ tmux 3.6b
✅ claude 2.1.198
✅ tmux 세션 안에서 실행 중 (발신자 헤더 자동)
ℹ️  워크스페이스 설정 없음 — 'tell init' 또는 'tell adopt'로 생성
✅ 템플릿: …/claude-tell-bridge/templates
```

---

## 빠른 시작 A — 처음부터 (`tell init`)

Claude Code를 이 구조로 처음 세팅한다면 이 경로다. **5분 안에 두 Claude가 서로 핑퐁하는 것까지 간다.**

> 🐣 **tmux가 처음이라면** — 준비물 설치부터 tmux 기본 조작, 핑퐁 확인까지 복붙으로 따라가는 [초보자용 상세 가이드](docs/getting-started.md)를 보세요. 아래는 그 압축판입니다.

**1. 마법사 실행**

```bash
tell init
```

질문 순서 (각 질문에 설명이 함께 출력된다):

1. **[1/2] 총괄 관리(허브) 세션이 필요한가?** — "여러 프로젝트를 대신 지휘해주는 비서 세션"인데, **몰라도 되고 없어도 된다.** 처음엔 엔터(건너뜀)로 시작하자 — 나중에 `tell hub` 한 번으로 추가된다.
2. **[2/2] 프로젝트 등록** — 순서대로: **프로젝트 이름(=세션 이름)** → **이 Claude의 역할(=패널 이름)** → **담당 디렉터리**. 역할은 여러 개 등록 가능. 예:
   - 프로젝트 `demo` → 역할 `api` → `~/work/demo/api` → 역할 `web` → `~/work/demo/web` → 엔터 → 엔터
3. 이때 **각 디렉터리의 CLAUDE.md에 협업 규약이 자동 삽입**된다 — 받는 쪽 Claude가 "어떻게 응답해야 하는지"를 아는 근거다.

**2. 세션 띄우기**

```bash
tell ws demo       # 패널 2개(api·web)로 분할 + 각각 Claude 자동 실행 + 접속
tell list          # 주소록 — 지금 말 걸 수 있는 세션:역할과 규약 여부 확인
```

**3. 첫 핑퐁 (P2P)** — `api` 패널의 Claude에게 그냥 말로 부탁한다:

```
web한테 핑퐁 테스트 보내고 응답 오는지 확인해줘
```

`tell` 명령을 직접 칠 필요 없다 — 자동 삽입된 규약 덕에 `api`의 Claude가 스스로 `tell demo web "..."`을 실행한다. 몇 초 뒤 `api` 패널 입력창에 이렇게 돌아오면 성공이다:

```
[세션 응답 - 3f9a1c from demo/web] 퐁 정상
```

이 순간부터 두 세션은 서로에게 일을 시킬 수 있다 — 이게 이 도구의 코어다.

## 빠른 시작 B — 이미 쓰던 세션 편입 (`tell adopt`)

**이미 쓰던 Claude Code 세션이 있다면** — 재시작 없이, 대화 컨텍스트를 유지한 채 그대로 편입된다.

```bash
tell adopt
```

`adopt`가 하는 일:

1. 떠 있는 패널을 전부 스캔해서 하나씩 보여준다
2. 각 패널의 **역할 이름**을 정한다 (엔터 = 현재 패널 제목 유지 / 새 이름 입력 / `s` = 건너뜀)
3. 그 패널의 프로젝트 디렉터리 CLAUDE.md에 **협업 규약을 삽입**한다 (이미 있으면 자동 건너뜀)
4. 원하면 그 자리에서 떠 있는 Claude에게 **"규약 읽어 + 핑퐁" 메시지를 자동 전송**한다 — 재시작 없이 규약이 로드되고, 곧바로 검증까지 끝난다

> 일반 터미널 탭(tmux 밖)에서 쓰던 Claude는? adopt는 떠 있는 tmux 패널만 스캔하므로, 먼저 `tmux new -s <프로젝트> -c <디렉터리>` 로 세션을 하나 만들고 그 안에서 `claude --resume` 으로 기존 대화를 이어받는다. 그 다음 `adopt`.

---

## 메시지 주고받기 — 자세히

### 요청

```bash
tell proj-a server "결제 API에 환불 엔드포인트 추가해줘. 끝나면 받은 키로 응답해줘"
```

```
[tell] 요청 전송 완료 → proj-a:server (%12)
[tell] 요청 KEY=a1b2c3  ← 이 KEY의 [세션 응답 - a1b2c3] 를 기다리세요
```

상대 패널 입력창에는 이렇게 찍힌다:

```
[세션 요청 - a1b2c3 from hub/hub] 결제 API에 환불 엔드포인트 추가해줘. 끝나면 받은 키로 응답해줘
```

헤더를 해부하면:

| 부분 | 의미 |
|---|---|
| `세션 요청` | 이것은 다른 세션이 보낸 **요청**이다 (사람 입력과 구분) |
| `a1b2c3` | 상관키(KEY) — 응답이 돌아올 때 어느 요청인지 매칭하는 열쇠 |
| `from hub/hub` | 발신자 — **자동 감지**된다. 받는 쪽은 이 주소로 `tell -r` 하면 된다 |

### 응답

받은 세션의 Claude가 작업을 마치면 (CLAUDE.md 규약에 따라) **스스로 Bash에서 실행한다**:

```bash
tell -r a1b2c3 hub hub "완료: POST /refunds 추가, 테스트 12건 통과"
```

### 알아두면 좋은 동작

- **큐잉**: 상대가 작업 중이어도 그냥 보내라. Claude Code가 입력을 큐에 쌓았다가 현재 작업이 끝나면 처리한다.
- **덮어쓰기 방지**: 상대 입력창에 사람이 타이핑 중인 텍스트가 있으면 10초 대기 후 재시도한다 (최대 3회).
- **자기완결 메시지**: 받는 쪽은 이 메시지 하나만 보고 일한다. 무엇을·어디를·어떻게 + "끝나면 받은 키로 응답"을 한 통에 담아라.
- **사람 메시지 우선**: 헤더 없는 입력 = 사람이 직접 친 것. 규약상 즉시 처리된다 (세션 요청은 현재 작업 후 처리).

## 규약(CLAUDE.md) — 브릿지의 나머지 절반

`tell`은 전화선이고, **CLAUDE.md 규약은 통화 예절**이다. 이게 없으면 메시지는 도착해도 응답이 돌아오지 않는다 — 받은 Claude가 채팅에 텍스트로만 "완료!"라고 쓰고 끝내기 때문이다 (각 세션은 독립이라 그 텍스트를 상대는 영영 못 본다).

`init`/`adopt`가 자동 삽입하는 규약의 핵심 4줄:

1. **응답 = `tell -r`을 Bash로 실제 실행하는 것.** 채팅 텍스트는 응답이 아니다.
2. 회신 주소는 받은 헤더의 `from`에서 읽는다. **자기 자신에게 보내면 루프다.**
3. `[세션 요청]`이 작업 중에 오면 **현재 작업을 끝낸 뒤** 처리한다.
4. 헤더 없는 메시지 = 사람 → 즉시 처리.

템플릿 원문: [`templates/CLAUDE-section-role.md`](templates/CLAUDE-section-role.md) (역할 패널용) · [`templates/CLAUDE-section-hub.md`](templates/CLAUDE-section-hub.md) (허브용). 수동으로 붙여넣어도 된다 — `{{SESSION}}` 등 플레이스홀더만 채우면 됨.

> **이미 떠 있는 세션에 규약을 로드하려면?** 재시작(CLAUDE.md는 시작 시 로드됨) 또는 더 간단히 — 그 세션에 이렇게 보내면 된다: `tell <세션> <역할> "CLAUDE.md를 Read로 읽고 tell 규약 숙지해. 받은 키로 tell -r 응답해줘"` — 이 한 통이 로드+검증을 겸한다. (`adopt`가 자동으로 해주는 것)

## 권장 패턴: 허브(비서) 세션 + 폰 원격

**허브 세션이란?** 여러 프로젝트를 **대신 지휘해주는 '비서' Claude 세션**이다. 코드를 직접 짜지 않고 — 사용자의 요청을 적절한 세션:역할로 나눠 시키고(위임), 응답(KEY)을 추적해 모아서 보고한다.

> 예: 허브에게 *"서버에 환불 API 추가하고 웹에 버튼 달아줘"* 한 마디
> → 허브가 `tell proj-a server "..."` 와 `tell proj-a web "..."` 를 보내고,
> → 각 응답이 돌아오면 **"✅ 서버: 완료 / ✅ 웹: 완료"** 로 취합해 알려준다.

P2P 대화가 코어지만, 프로젝트가 여럿이면 **허브 세션 하나**를 두는 걸 권장한다 (`tell init`에서 만들거나, 나중에 `tell hub`로 추가):

```
        사용자 (로컬 키보드 or 폰 Remote Control)
                    │
                [hub:hub]  ← 라우팅·위임·취합·보고만. 코드는 안 짬
              ┌─────┼─────────┐
        [proj-a:*]  [proj-b:*]  [proj-c:*]
```

- 허브는 요청을 적절한 세션:역할로 **위임**하고, KEY별로 추적해서 **취합 보고**한다. 여러 건을 동시에 굴린다.
- 사용자는 여전히 아무 패널이나 클릭해서 **직접** 지시할 수 있다 — 허브는 편의지 관문이 아니다.
- **폰 원격(Remote Control)**: Claude Code의 원격 기능으로 허브 세션 하나만 잡으면, 밖에서도 전 프로젝트에 일을 시킬 수 있다. "급한데 노트북이 없다" 상황의 해법.
- `tell init`이 허브용 CLAUDE.md(위임 원칙·논블로킹·보고 포맷 포함)를 자동 생성한다.

## 여러 프로젝트 동시 운용

세션 이름이 곧 네임스페이스다. 설정 파일에 프로젝트를 계속 추가하면 된다:

```
# ~/.config/claude-tell-bridge/workspaces.conf
hub|hub|~/tell-hub
shop|server|~/work/shop/backend
shop|web|~/work/shop/frontend
blog|server|~/work/blog/api
```

`tell ws shop` / `tell ws blog` 로 각각 띄우고, 허브에서 `tell shop server "..."` / `tell blog server "..."` 로 구분해 부른다. 프로젝트끼리는 주소가 달라 섞이지 않고, 필요하면 (드물게) 프로젝트 간 대화도 같은 문법으로 가능하다.

## 명령어 레퍼런스

| 명령 | 설명 |
|---|---|
| `tell <세션> <역할> "<메시지>"` | 요청 전송. KEY 생성·출력, 발신자 헤더 자동 |
| `tell -r <KEY> <세션> <역할> "<메시지>"` | 응답 전송. 받은 요청의 KEY를 그대로 사용 |
| `tell ws` | 실행 중 세션 + 설정된 워크스페이스 목록 |
| `tell ws <세션>` | 워크스페이스 부트스트랩(패널 분할·제목·claude 실행) 후 접속. 이미 떠 있으면 접속만 |
| `tell init` | 셋업 마법사 — 허브(선택) → 프로젝트/역할/디렉터리 등록 + CLAUDE.md 규약 삽입 |
| `tell adopt` | 떠 있는 패널 스캔 → 역할 지정 → 규약 삽입 → (선택) 로드 메시지 전송 |
| `tell hub` | 총괄 관리(허브=비서) 세션을 나중에 추가 |
| `tell list` | **주소록** — 말 걸 수 있는 세션:역할 목록 + 규약/실행 여부 |
| `tell rm <세션>` | 세션 정리 — 세션 종료 + 설정에서 제거 (각각 y/N 확인) |
| `tell doctor` | 환경 점검 (tmux/claude/설정/템플릿) |

종료코드: `0` 전송 성공 · `1` 대상 패널 없음 · `2` 인자 오류

## 설정 파일

`~/.config/claude-tell-bridge/workspaces.conf` — 한 줄에 패널 하나:

```
# 세션|역할|디렉터리          ← #으로 시작하면 주석
shop|server|~/work/shop/backend
shop|web|~/work/shop/frontend
```

- 같은 세션 이름의 줄들이 위에서부터 순서대로 패널이 된다 (첫 줄이 세션 생성, 이후 분할)
- `~` 홈 확장 지원
- 환경변수 `TELL_CONFIG_DIR`로 설정 디렉터리를 바꿀 수 있다 (테스트/멀티 프로필용)

## 트러블슈팅

| 증상 | 원인 · 해법 |
|---|---|
| `[tell] 대상 패널 없음: X:Y` | 세션 이름 또는 패널 제목 불일치. 에러에 함께 출력되는 "(가용)" 목록 확인. 패널 제목 지정: `tmux select-pane -T "역할"` |
| **메시지는 갔는데 응답이 안 옴** | 십중팔구 **규약 미로드**. 그 세션 CLAUDE.md에 규약이 있는지, 세션이 그걸 읽었는지 확인. 빠른 해법: `tell <세션> <역할> "CLAUDE.md 읽고 받은 키로 tell -r 응답해줘"` |
| 응답이 채팅에 텍스트로만 찍히고 안 돌아옴 | 같은 원인 — 규약의 1번("tell -r을 실제 실행")이 로드 안 된 것 |
| `not in a mode` 가 잔뜩 출력 | 대상 패널이 copy-mode(스크롤 중)였음. `tmux send-keys -t <패널> -X cancel` 후 재전송 |
| 전송이 10초씩 지연됨 | 정상 — 상대 입력창에 미제출 텍스트가 있어 덮어쓰기 방지 대기 중 |
| `from`이 없는 요청이 옴 | tmux 밖(일반 셸)에서 보낸 것. 받는 쪽 규약상 회신처를 사람에게 묻게 됨 |
| 한글 세션/역할 이름이 엉뚱한 패널로 감 (macOS) | 알려진 awk 로케일 버그 — 내부에서 `LC_ALL=C`로 회피해두었으니 최신 버전인지 확인 |
| 새 패널에 claude 대신 셸만 뜸 | 그 디렉터리가 없거나 `claude` CLI가 PATH에 없음. `tell doctor` |

## FAQ

**Q. 서브에이전트(Task)랑 뭐가 다른가?**
서브에이전트는 스폰됐다 사라지는 일회용이고, 매번 컨텍스트를 새로 쌓는다. 이 브릿지의 패널은 **상주 담당자**다 — 어제 왜 그렇게 설계했는지 기억하는 세션이 답한다. 서로 배타적이지 않다: 각 패널이 내부적으로 서브에이전트를 쓰면 된다.

**Q. MCP로 만들지 왜 send-keys인가?**
MCP 메시지 버스는 서버·훅 설정이 필요하고 대화가 프로토콜 뒤로 숨는다. send-keys는 **사람이 보는 화면과 AI가 받는 채널이 동일**해서 모든 대화가 눈에 보이고, 설치가 스크립트 한 개다. 트레이드오프는 [알려진 제약](#알려진-제약--로드맵) 참고.

**Q. 응답을 안 하면?**
보낸 쪽 Claude가 KEY를 기억하고 있다가, 한참 없으면 재요청하거나 사용자에게 보고하는 게 규약이다. 전달 영수증(receipt) 자동화는 로드맵에 있다.

**Q. 같은 역할 이름이 두 세션에 있으면?**
문제없다 — 주소는 `세션+역할` 쌍이다. 단 **한 세션 안에서** 역할(패널 제목)은 유일해야 한다 (첫 매칭 패널로 간다).

**Q. 원격 서버의 세션과도 되나?**
같은 tmux 서버 안에서만 동작한다. 원격은 SSH로 그 호스트의 tmux에 들어가 그쪽 브릿지를 쓰는 방식.

## 보안

- **신뢰된 로컬 환경 전용.** `send-keys` 기반이라 같은 tmux 서버에 접근 가능한 누구나 어떤 패널에든 메시지를 주입할 수 있다. 상관키는 라우팅용이지 인증이 아니다.
- **비밀번호·토큰·시크릿을 절대 tell로 보내지 마라.** 상대 패널의 스크롤백과 대화 트랜스크립트에 평문으로 남는다. 자격증명이 필요하면 파일 권한 있는 채널(scp 등)로 옮기고, 규약 템플릿에도 이 금지가 명시돼 있다.
- 받는 쪽 Claude가 메시지를 "지시"로 처리하므로, tmux 서버 접근 권한 = 모든 세션에 대한 지시 권한임을 인지할 것.

## 알려진 제약 · 로드맵

**제약**
- 입력창 감지가 Claude Code의 프롬프트 렌더링(`❯`)을 읽는다 — CLI UI가 크게 바뀌면 점검 필요
- 전달 보장/영수증 없음 (fire-and-forget + 규약 기반 재요청)
- 헤더 프로토콜이 현재 한국어
- 세션 이름에 `=` 사용 불가

**로드맵**
- [ ] 헤더 i18n (영어 프로토콜 + 템플릿)
- [ ] Homebrew tap
- [ ] `tell status` — 대기 중 KEY 목록/추적
- [ ] 전달 영수증(선택적)

기여 환영 — 이슈/PR: https://github.com/namki1222/claude-tell-bridge

## English (TL;DR)

`claude-tell-bridge` lets multiple **long-lived** Claude Code sessions (tmux panes) message each other with correlation keys via `tmux send-keys` — no daemon, no MCP, one bash script + a CLAUDE.md convention. Each pane is a *resident* AI teammate that answers from its own codebase context. `npm i -g claude-tell-bridge`, then `tell init` (fresh) or `tell adopt` (absorb running sessions, no restart). Half the magic is the auto-inserted CLAUDE.md convention telling each Claude to *actually run* `tell -r KEY <session> <role> "..."` to reply. Recommended pattern: one hub session routes/aggregates across projects — pair it with Claude Code Remote Control to command your whole fleet from your phone. Korean-first headers for now; PRs welcome.

## License

MIT © [namki1222](https://github.com/namki1222)
