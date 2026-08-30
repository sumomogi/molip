#!/bin/bash
# 테스트. tools/tests의 파일 하나가 스위트 하나다.
# 각 스위트는 main.swift를 뺀 앱 소스 전부와 함께 컴파일된다.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

SRC=$(ls Sources/*.swift | grep -v '/main\.swift$')

fail=0
for t in tools/tests/*.swift; do
    name=$(basename "$t" .swift)
    echo "── $name"
    # -wmo(전체 모듈 컴파일): 그렇지 않으면 파일별 임시 오브젝트 이름이 대소문자
    # 구분 없는 파일시스템(APFS)에서 Sources/Stepping.swift와 tools/tests/stepping.swift처럼
    # 대소문자만 다른 이름끼리 충돌해 링크 단계에서 심볼이 사라진다.
    swiftc -parse-as-library -wmo -o "$OUT/$name" $SRC tools/testsupport/*.swift "$t"
    "$OUT/$name" || fail=1
    echo
done

if [ "$fail" -eq 0 ]; then
    echo "모두 통과"
else
    echo "실패한 스위트가 있다"
    exit 1
fi
