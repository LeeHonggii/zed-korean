# zed-korean — 한글 Zed + AI 작업 관측 IDE

[Zed](https://github.com/zed-industries/zed)(오픈소스 Rust 에디터)를 **한국어화**하고, **Claude Code를 구독으로 붙여 AI가 작업하는 과정을 그대로 지켜보는** 개인용 IDE 세팅. Zed 본가를 포크/패치해서 내 작업 환경에 맞게 다시 빌드한다.

> 이 저장소는 "다 만들어진 앱"이 아니라 **"Zed 소스에 내 수정을 얹어 다시 빌드하는 레시피"**다. 빌드 시 upstream Zed를 받아 아래 패치를 적용한다.

## 왜 만들었나 (문제)

- Zed는 **공식 한국어 UI가 없다** (i18n 미지원, 문자열이 Rust 바이너리에 하드코딩).
- JetBrains Air 등은 Claude를 **API 과금**으로만 붙일 수 있어 구독 활용이 막힌다.
- 여러 프로젝트에 흩어진 **Claude 세션을 한 곳에서** 이어가고, 저장 규칙·환경을 **내 방식대로** 통일하고 싶었다.

## 무엇을 했나 (결과)

| 영역 | 내용 |
|---|---|
| **한국어화** | UI 문자열 **4,728개 번역 → 소스 6,873곳 치환**. v1.25.3 기준 427개 UI 크레이트 파일 대상 |
| **세션 통합** | ACP 어댑터 패치로 **전 프로젝트 Claude 세션을 한 picker에서** 선택·이어가기. 자동화(블로그·논문·로그) 세션은 숨김 |
| **애플풍 테마** | One Dark의 파란빛 회색 제거, **중성 검정(#000~#1c)** 오버라이드 |
| **저장 규칙** | CLI와 동일한 설정 소스(`user·project·local`) 로드 → 파일명 `YYMMDD_`·`output/` 규칙·대화기록 위치가 그대로 적용 |
| **환경 자동화** | 프로젝트별 전용 Python(conda) env를 언어서버에 자동 연결 |

## 어떻게 했나 (엔지니어링)

### 1. 한국어 번역 — Claude 에이전트 병렬 파이프라인
Zed 문자열은 바이너리에 박혀 있어 **소스를 고쳐 재컴파일**해야 한다. 기계 번역 품질이 아쉬워, **번역을 Claude 에이전트 8개로 분산**했다.

```
Zed 소스(v1.25.3) → UI 크레이트 427파일 문자열 추출(zedl10n extract)
   → zh 커뮤니티 패치와 교집합으로 "실제 번역 대상"만 선별 (34,504 → 10,585 유니크)
   → 8개 청크로 분할 → Claude 에이전트 8개 병렬 번역 (용어집·플레이스홀더 규칙 통일)
   → 병합 → 파일별 ko.json (4,728 유니크 / 6,873 치환)
   → zedl10n replace 로 소스에 반영 → cargo build
```
- 에이전트가 **UI 문자열만 번역**하고 테스트·로그·텔레메트리 문자열은 영문 유지하도록 규칙화.
- 플레이스홀더(`{}`, `{:?}`, `%s`, `\n`)는 위치까지 보존.

### 2. 세션 통합 — ACP 어댑터 패치
[claude-agent-acp](https://github.com/agentclientprotocol/claude-agent-acp)의 `listSessions` 경로를 패치해 모든 프로젝트 세션을 노출하고, 자동화 세션을 패턴으로 필터링.

### 3. 저장 규칙 — 설정 소스 상속
ACP 어댑터가 `settingSources: ["user","project","local"]`로 세션을 열어, 터미널 CLI와 **같은 훅·CLAUDE.md·세션 기록 위치**를 공유. 즉 어디서 띄우든 동일한 작업 규칙.

## 빌드

> **요구:** 전체 Xcode.app(Metal 컴파일러), Rust(rustup), Python 3.

```bash
./scripts/build.sh
```
upstream Zed(v1.25.3)를 받아 → `i18n/ko.json` 적용 → `config/`의 테마·세팅을 반영 → `cargo build`로 한글 Zed.app 생성. 서명이 없으므로 첫 실행 시:
```bash
sudo xattr -rd com.apple.quarantine /Applications/<이름>.app
```

## 라이선스

Zed는 **GPL-3.0**. 이 저장소의 수정분도 동일 라이선스를 따른다. 원저작권·출처는 [NOTICE](./NOTICE) 참고. "Zed" 이름·로고는 Zed Industries의 상표이며, 재배포 시 **다른 이름·아이콘**을 사용한다.

## 유지보수

Zed 본가가 업데이트되면 새 버전으로 `scripts/build.sh`를 다시 돌려 번역을 재적용·재빌드한다. 신규 문자열은 `scripts/extract.sh`로 다시 뽑아 번역을 보강한다.
