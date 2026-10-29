#!/usr/bin/env bash
# 빌드된 Zed 설치: 종료 → 보관 스레드 해제 → 교체 → 산출물 정리 → 재실행
set -euo pipefail

SRC_DIR="${ZED_SRC:-$HOME/Tools/zed-src}"
APP_DST="${ZED_APP:-/Applications/Zed.app}"
REL="$SRC_DIR/target/aarch64-apple-darwin/release"
BUILT="$REL/dmg/Zed.app"
DB="$HOME/Library/Application Support/Zed/db/0-stable/db.sqlite"

[ -d "$BUILT" ] || { echo "❌ 빌드 산출물 없음: $BUILT (먼저 ./script/bundle-mac -l)"; exit 1; }

echo "==> Zed 종료"
osascript -e 'quit app "Zed"' 2>/dev/null || true
sleep 2; pkill -x zed 2>/dev/null || true; sleep 1

if [ "${KEEP_ARCHIVED:-0}" != "1" ] && [ -f "$DB" ]; then
  echo "==> 보관 스레드 해제 (백업 후)"
  cp "$DB" "$DB.bak-$(date +%y%m%d_%H%M%S)"
  sqlite3 "$DB" "UPDATE sidebar_threads SET archived=0 WHERE archived=1;"
fi

echo "==> 설치"
rm -rf "$APP_DST"
cp -R "$BUILT" "$APP_DST"
xattr -cr "$APP_DST" 2>/dev/null || true
rm -rf "$REL/dmg/Zed.app" "$REL/bundle/osx/Zed.app" "$REL"/Zed-*.dmg 2>/dev/null || true

if [ "${NO_OPEN:-0}" != "1" ]; then
  echo "==> 실행"
  open "$APP_DST"
fi
