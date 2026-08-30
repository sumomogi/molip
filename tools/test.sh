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
    # 컴파일이 실패하면 set -e로 스크립트가 여기서 바로 멈춘다 — 이후 스위트는 돌지 않고
    # "실패한 스위트가 있다" 요약도 안 찍힌다. 원인은 위에 뜬 컴파일러 출력에서 확인한다.
    swiftc -parse-as-library -wmo -o "$OUT/$name" $SRC tools/testsupport/*.swift "$t"

    log="$OUT/$name.log"
    if ! "$OUT/$name" | tee "$log"; then fail=1; fi
    # T.finish()를 빠뜨린 스위트는 FAIL을 찍고도 0으로 끝난다. 출력도 함께 본다.
    if grep -q '^FAIL' "$log"; then fail=1; fi
    echo
done

if [ "$fail" -eq 0 ]; then
    echo "모두 통과"
else
    echo "실패한 스위트가 있다"
    exit 1
fi
