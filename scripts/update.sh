#!/usr/bin/env bash
# 번역 추가/수정 후 재빌드·재설치를 한 번에. (증분 빌드라 처음보다 빠름)
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${ZED_SRC:-$HOME/Tools/zed-src}"
APP_DST="${ZED_APP:-/Applications/Zed.app}"
export PATH="$HOME/.cargo/bin:$PATH"

# zedl10n 은 보통 전용 venv 에 설치돼 있다. PATH 에 없으면 venv 를 찾아 쓴다.
ZEDL10N="zedl10n"
if ! command -v zedl10n >/dev/null 2>&1; then
  if [ -x "$HOME/Tools/zed-globalization/.venv/bin/zedl10n" ]; then
    ZEDL10N="$HOME/Tools/zed-globalization/.venv/bin/zedl10n"
  else
    echo "   ❌ zedl10n 없음: pip install git+https://github.com/x6nux/zed-globalization.git" >&2
    exit 1
  fi
fi

echo "==> 1. 번역 적용 (i18n/ko.json → 소스)"
"$ZEDL10N" replace --input "$REPO_DIR/i18n/ko.json" --source-root "$SRC_DIR"

echo "==> 2. 증분 빌드"
cd "$SRC_DIR"
./script/bundle-mac -l

echo "==> 3. 재설치 (실행 중이면 종료)"
pkill -x zed 2>/dev/null || true
sleep 1
BUILT="$SRC_DIR/target/aarch64-apple-darwin/release/dmg/Zed.app"
rm -rf "$APP_DST"
cp -R "$BUILT" "$APP_DST"
xattr -cr "$APP_DST" 2>/dev/null || true

echo "==> 완료. 한글 수 확인:"
grep -a -c "스레드" "$APP_DST/Contents/MacOS/zed" | xargs echo "  '스레드' 건수:"
echo "   open $APP_DST 로 실행"
