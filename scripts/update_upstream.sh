#!/usr/bin/env bash
# 공식 Zed 새 정식 버전 + 한글 번역 + 하네스 패치 → 빌드 → (Zed 꺼져 있을 때) 설치
# 사용: update_upstream.sh [--force] [--tag vX.Y.Z] [--skip-extract]  (--skip-extract: 충돌을 손으로 정리한 patches/harness.patch 를 그대로 쓴다)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${ZED_SRC:-$HOME/Tools/zed-src}"
PATCH="$REPO_DIR/patches/harness.patch"
BASE_FILE="$REPO_DIR/patches/BASE"
LOG_DIR="$HOME/.harness"
LOG="$LOG_DIR/zed_update.log"
TRIAL="/tmp/zed-trial"
BASE_TREE="/tmp/zed-base"
PY="$HOME/anaconda3/envs/harness-tools/bin/python"
ZEDL10N="$HOME/Tools/zed-globalization/.venv/bin/zedl10n"
MARKERS=("그림판 열기" "줄 더 보기" "↻ 새로고침")
export PATH="$HOME/.cargo/bin:$PATH"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG") 2>&1
echo "==== $(date '+%F %T') Zed 업데이트 확인"

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
  echo "[알림] $1 — $2"
}

translate() {
  (cd "$1" && "$ZEDL10N" replace --input "$REPO_DIR/i18n/ko.json" --source-root "$1" | tail -1)
  git -C "$1" add -A crates
}

FORCE=0
TAG=""
SKIP_EXTRACT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --tag) TAG="$2"; shift ;;
    --skip-extract) SKIP_EXTRACT=1 ;;
  esac
  shift
done

CURRENT="$(cat "$BASE_FILE")"
if [ -z "$TAG" ]; then
  TAG="$(git -C "$SRC_DIR" ls-remote --tags origin 'v*' | awk -F/ '{print $3}' | grep -v '\^{}' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
fi
echo "지금 $CURRENT · 최신 정식 $TAG"
if [ "$TAG" = "$CURRENT" ] && [ "$FORCE" = 0 ]; then
  echo "이미 최신"
  exit 0
fi

if [ "$SKIP_EXTRACT" = 0 ]; then
  echo "==> 1. 지금 소스의 하네스 수정을 패치로 다시 뽑기 (기준 $CURRENT)"
  git -C "$SRC_DIR" worktree remove --force "$BASE_TREE" 2>/dev/null || rm -rf "$BASE_TREE"
  git -C "$SRC_DIR" worktree add --detach "$BASE_TREE" "$CURRENT" >/dev/null
  translate "$BASE_TREE"
  "$PY" -I "$REPO_DIR/scripts/make_patch.py" "$SRC_DIR" "$BASE_TREE" "$PATCH"
else
  echo "==> 1. 건너뜀 — 정리된 패치 그대로 사용"
fi

echo "==> 2. 시험 공간에서 $TAG + 번역 + 패치"
git -C "$SRC_DIR" fetch --quiet origin "refs/tags/$TAG:refs/tags/$TAG"
git -C "$SRC_DIR" worktree remove --force "$TRIAL" 2>/dev/null || rm -rf "$TRIAL"
git -C "$SRC_DIR" worktree add --detach "$TRIAL" "$TAG" >/dev/null
translate "$TRIAL"
if ! (cd "$TRIAL" && git apply --3way --whitespace=nowarn "$PATCH"); then
  CONFLICTS="$(cd "$TRIAL" && git diff --name-only --diff-filter=U | tr '\n' ' ')"
  notify "Zed $TAG 자동 적용 실패" "패치 충돌: ${CONFLICTS:-확인 필요} — 지금 Zed는 그대로"
  echo "충돌 파일: $CONFLICTS  (시험 공간 $TRIAL 에 남겨 둠)"
  exit 1
fi
echo "패치 적용 OK"

echo "==> 3. 소스를 $TAG 로 옮기기 (지금 상태 백업 후)"
BACKUP="$LOG_DIR/zed-src-backup-$CURRENT-$(date +%y%m%d_%H%M%S).patch"
git -C "$SRC_DIR" diff > "$BACKUP"
cp "$PATCH" "$BACKUP.harness"
git -C "$SRC_DIR" fetch --quiet origin "refs/tags/$TAG:refs/tags/$TAG"
git -C "$SRC_DIR" checkout --quiet -f "$TAG"
git -C "$SRC_DIR" clean -fdq crates
translate "$SRC_DIR"
(cd "$SRC_DIR" && git apply --3way --whitespace=nowarn "$PATCH")

echo "==> 4. 빌드 (처음부터라 오래 걸림)"
(cd "$SRC_DIR" && ./script/bundle-mac -l) || true
BUILT="$SRC_DIR/target/aarch64-apple-darwin/release/dmg/Zed.app"
BIN="$BUILT/Contents/MacOS/zed"
if [ ! -x "$BIN" ]; then
  notify "Zed $TAG 빌드 실패" "로그: $LOG — 지금 Zed는 그대로"
  exit 1
fi
for marker in "${MARKERS[@]}"; do
  if ! "$PY" -I -c "import sys; sys.exit(0 if open('$BIN','rb').read().count('$marker'.encode()) else 1)"; then
    notify "Zed $TAG 검사 실패" "패치 문구 '$marker' 없음 — 설치 안 함"
    exit 1
  fi
done
echo "$TAG" > "$BASE_FILE"
echo "빌드 OK · 패치 문구 확인"

echo "==> 5. 설치 (Zed 가 꺼져 있을 때만)"
if pgrep -x zed >/dev/null; then
  notify "Zed $TAG 준비됨" "Zed를 끄면 새 버전으로 바뀝니다"
  nohup bash -c "while pgrep -x zed >/dev/null; do sleep 20; done; KEEP_ARCHIVED=1 NO_OPEN=1 bash '$REPO_DIR/scripts/reinstall.sh'" \
    >> "$LOG" 2>&1 < /dev/null &
  disown
else
  KEEP_ARCHIVED=1 NO_OPEN=1 bash "$REPO_DIR/scripts/reinstall.sh"
  notify "Zed $TAG 설치됨" "한글·하네스 패치 포함"
fi
