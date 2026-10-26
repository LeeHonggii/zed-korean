#!/usr/bin/env bash
# 한글 Zed 빌드: upstream Zed 를 받아 번역/설정을 얹어 다시 컴파일한다.
set -euo pipefail

ZED_VERSION="${ZED_VERSION:-v1.25.3}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${ZED_SRC:-$HOME/Tools/zed-src}"

echo "==> 1. Zed 소스 준비 ($ZED_VERSION)"
if [ ! -d "$SRC_DIR/.git" ]; then
  git clone --depth 1 https://github.com/zed-industries/zed.git "$SRC_DIR"
fi
cd "$SRC_DIR"
git fetch --depth 1 origin tag "$ZED_VERSION" 2>/dev/null || true
git checkout "$ZED_VERSION" 2>/dev/null || true

echo "==> 2. 한국어 번역 적용"
if ! command -v zedl10n >/dev/null 2>&1; then
  echo "   zedl10n 필요: pip install git+https://github.com/x6nux/zed-globalization.git" >&2
fi
zedl10n replace --input "$REPO_DIR/i18n/ko.json" --source-root "$SRC_DIR"

echo "==> 3. 빌드 전 점검 (Metal/Rust)"
if ! xcrun -f metal >/dev/null 2>&1; then
  echo "   ❌ Metal 컴파일러 없음 — 전체 Xcode.app 설치 후 'sudo xcode-select -s /Applications/Xcode.app' 필요" >&2
  exit 1
fi
command -v cargo >/dev/null 2>&1 || { echo "   ❌ Rust 필요: https://rustup.rs" >&2; exit 1; }
cargo install cargo-about >/dev/null 2>&1 || true

echo "==> 4. 빌드 (로컬 모드, 서명 없음)"
./script/bundle-mac -l

echo "==> 완료. 서명이 없으니 첫 실행 시: sudo xattr -rd com.apple.quarantine /Applications/<앱>.app"
