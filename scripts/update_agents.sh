#!/usr/bin/env bash
# Claude 어댑터(우리 패치)+엔진, Codex 어댑터, Codex CLI 를 새 정식 버전으로. 부품마다 시험 통과해야 교체, 실패한 부품만 그대로.
# 사용: update_agents.sh [--skip-extract]  (--skip-extract: 충돌을 손으로 정리한 patches/claude-acp.patch 를 그대로 쓴다)
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACP_DIR="${CLAUDE_ACP_DIR:-$HOME/Tools/claude-agent-acp}"
PATCH="$REPO_DIR/patches/claude-acp.patch"
BASE_FILE="$REPO_DIR/patches/claude-acp.BASE"
TRIAL="/tmp/acp-trial"
SETTINGS="$HOME/.config/zed/settings.json"
CLAUDE_BIN="$HOME/.local/bin/claude"
NPX="/opt/homebrew/bin/npx"
LOG_DIR="$HOME/.harness"
LOG="$LOG_DIR/zed_update.log"
PY="$HOME/anaconda3/envs/harness-tools/bin/python"
SMOKE="$REPO_DIR/scripts/acp_smoke.py"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date '+%F %T') 에이전트 업데이트 확인"

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
  echo "[알림] $1 — $2"
}

smoke_claude() {
  (cd /tmp && CLAUDE_CODE_EXECUTABLE="$CLAUDE_BIN" "$PY" -I "$SMOKE" node "$1/dist/index.js")
}

build_adapter() {
  (cd "$1" && npm ci --silent >/dev/null 2>&1 && npm run build --silent >/dev/null 2>&1)
}

SKIP_EXTRACT=0
[ "${1:-}" = "--skip-extract" ] && SKIP_EXTRACT=1

update_claude_adapter() {
  local current latest
  current="$(cat "$BASE_FILE")"
  latest="$(git -C "$ACP_DIR" ls-remote --tags origin 'v*' | awk -F/ '{print $3}' | grep -v '\^{}' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
  echo "-- Claude 어댑터: 지금 $current · 최신 $latest"
  [ "$latest" = "$current" ] && return 0

  if [ "$SKIP_EXTRACT" = 0 ]; then
    local idx=/tmp/acp_extract_idx
    rm -f "$idx"
    GIT_INDEX_FILE="$idx" git -C "$ACP_DIR" read-tree HEAD
    GIT_INDEX_FILE="$idx" git -C "$ACP_DIR" add -A -- src
    GIT_INDEX_FILE="$idx" git -C "$ACP_DIR" diff --cached "$current" -- src > "$PATCH"
  fi

  git -C "$ACP_DIR" fetch --quiet origin "refs/tags/$latest:refs/tags/$latest"
  git -C "$ACP_DIR" worktree remove --force "$TRIAL" 2>/dev/null || rm -rf "$TRIAL"
  git -C "$ACP_DIR" worktree add --detach "$TRIAL" "$latest" >/dev/null
  if ! (cd "$TRIAL" && git apply --3way --whitespace=nowarn "$PATCH"); then
    notify "Claude 어댑터 $latest 적용 실패" "패치 충돌: $(cd "$TRIAL" && git diff --name-only --diff-filter=U | tr '\n' ' ')— 지금 버전 유지"
    return 1
  fi
  if ! build_adapter "$TRIAL" || ! smoke_claude "$TRIAL"; then
    notify "Claude 어댑터 $latest 시험 실패" "빌드 또는 ACP 응답 실패 — 지금 버전 유지"
    return 1
  fi

  rm -rf "$ACP_DIR/dist.prev" && cp -R "$ACP_DIR/dist" "$ACP_DIR/dist.prev"
  git -C "$ACP_DIR" diff > "$LOG_DIR/claude-acp-backup-$current-$(date +%y%m%d_%H%M%S).patch"
  git -C "$ACP_DIR" checkout --quiet -f "$latest"
  git -C "$ACP_DIR" clean -fdq src
  (cd "$ACP_DIR" && git apply --3way --whitespace=nowarn "$PATCH")
  if build_adapter "$ACP_DIR" && smoke_claude "$ACP_DIR"; then
    echo "$latest" > "$BASE_FILE"
    notify "Claude 어댑터 $latest" "업데이트됨 (새 대화부터)"
  else
    rm -rf "$ACP_DIR/dist" && mv "$ACP_DIR/dist.prev" "$ACP_DIR/dist"
    notify "Claude 어댑터 $latest 교체 실패" "이전 빌드로 되돌림"
    return 1
  fi
}

update_claude_engine() {
  local sdk target now
  sdk="$(sed -n 's/.*"@anthropic-ai\/claude-agent-sdk": "[^0-9]*\([0-9][0-9.]*\)".*/\1/p' "$ACP_DIR/package.json" | head -1)"
  if [ -z "$sdk" ]; then
    notify "Claude 엔진 버전 판단 실패" "package.json 에서 SDK 버전을 못 읽음"
    return 1
  fi
  target="2.1.${sdk##*.}"
  now="$("$CLAUDE_BIN" --version 2>/dev/null | awk '{print $1}')"
  echo "-- Claude 엔진: 지금 $now · 어댑터 짝(SDK $sdk) $target"
  [ "$now" = "$target" ] && return 0
  if ! "$CLAUDE_BIN" install "$target" >/dev/null 2>&1; then
    notify "Claude 엔진 $target 설치 실패" "지금 $now 유지"
    return 1
  fi
  if smoke_claude "$ACP_DIR"; then
    notify "Claude 엔진 $target" "업데이트됨"
  else
    "$CLAUDE_BIN" install "$now" >/dev/null 2>&1
    notify "Claude 엔진 $target 시험 실패" "$now 로 되돌림"
    return 1
  fi
}

update_codex_adapter() {
  local current latest
  current="$(grep -o '@zed-industries/codex-acp@[0-9][0-9.]*' "$SETTINGS" | head -1 | cut -d@ -f3)"
  latest="$(npm view @zed-industries/codex-acp version 2>/dev/null)"
  echo "-- Codex 어댑터: 지금 $current · 최신 $latest"
  [ -z "$latest" ] || [ "$latest" = "$current" ] && return 0
  if (cd /tmp && "$PY" -I "$SMOKE" "$NPX" -y "@zed-industries/codex-acp@$latest"); then
    sed -i '' "s/@zed-industries\/codex-acp@$current/@zed-industries\/codex-acp@$latest/" "$SETTINGS"
    notify "Codex 어댑터 $latest" "업데이트됨 (새 대화부터)"
  else
    notify "Codex 어댑터 $latest 시험 실패" "지금 $current 유지"
    return 1
  fi
}

update_codex_cli() {
  local before after
  before="$(codex --version 2>/dev/null | awk '{print $2}')"
  codex update >/dev/null 2>&1 < /dev/null || true
  after="$(codex --version 2>/dev/null | awk '{print $2}')"
  echo "-- Codex CLI: $before → ${after:-실행 실패}"
  if [ -z "$after" ]; then
    notify "Codex CLI 업데이트 후 실행 실패" "확인 필요"
    return 1
  fi
}

FAILED=0
update_claude_adapter || FAILED=1
update_claude_engine || FAILED=1
update_codex_adapter || FAILED=1
update_codex_cli || FAILED=1
echo "에이전트 업데이트 끝 (실패 있음=$FAILED)"
exit $FAILED
