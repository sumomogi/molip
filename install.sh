#!/bin/bash
# 빌드 결과를 /Applications에 설치하고 실행한다.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Molip.app"
DEST="/Applications/Molip.app"

[ -d "$APP" ] || { echo "먼저 ./build.sh 를 실행하세요."; exit 1; }

echo "==> 실행 중이면 종료"
osascript -e 'tell application id "local.molip.app" to quit' 2>/dev/null || true
pkill -x Molip 2>/dev/null || true
sleep 1

echo "==> 설치"
rm -rf "$DEST"
ditto "$APP" "$DEST"

echo "==> 실행"
open "$DEST"
sleep 2
pgrep -x Molip >/dev/null && echo "실행 중 (PID $(pgrep -x Molip))" || { echo "실행 실패"; exit 1; }
