#!/bin/bash
# --print 출력이 계산 규칙(docs/PRD.md 6장)과 맞는지 확인한다.
# 기대값은 모두 손으로 계산했다. 실행: ./tests/run.sh (먼저 ./build.sh --no-install)

set -uo pipefail
cd "$(dirname "$0")/.."

BIN="build/WorkClock.app/Contents/MacOS/WorkClock"
[ -x "$BIN" ] || { echo "먼저 ./build.sh --no-install 로 빌드하세요" >&2; exit 1; }

PASS=0
FAIL=0

run() { WORKCLOCK_CONFIG="tests/fixtures/$1.json" WORKCLOCK_NOW="$2" "$BIN" --print; }

expect() {
  local name="$1" fixture="$2" now="$3" line="$4"
  if run "$fixture" "$now" | grep -qxF -- "$line"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL [$name] $fixture @ $now"
    echo "  기대: $line"
    run "$fixture" "$now" | sed 's/^/  실제: /'
  fi
}

NOW="2026-11-16 14:00"

# 계약직, 월급 (9/1~12/31, 11/20 휴가, 12/25 공휴일, 날짜 미정 휴가 1일)
expect "메뉴 막대" contract "$NOW" "메뉴 막대: 계약 62% · 오늘 55.555% · 오늘 번 돈 ₩83,333"
expect "계약 진행" contract "$NOW" "계약 진행 62.7% (남은 46일)"
expect "남은 날" contract "$NOW" "남은 날 = 평일 31일 + 주말 12일 + 공휴일 1일 + 휴가 2일 (오늘 포함)"
expect "출근 일수" contract "$NOW" "지금까지 55일 출근 · 이만큼을 0.5번 더 하면 끝 (남은 근무 30일)"
expect "휴가 시간" contract "$NOW" "남은 휴가 12시간 (총 16시간 중 4시간 사용)"
expect "오늘" contract "$NOW" "오늘 55.5% 지남 / 44.5% 남음"
expect "이번 달" contract "$NOW" "이번 달 번 돈 ₩1,583,333"
expect "통상시급" contract "$NOW" "통상시급 ₩14,354"
expect "월급일" contract "$NOW" "다음 월급일 11/25(수) · D-9"
expect "월급일 당일" contract "2026-11-25 09:00" "오늘 월급일 11/25(수) · D-Day"
expect "주말" contract "2026-11-21 12:00" "오늘은 주말"
expect "공휴일" contract "2026-12-25 12:00" "오늘은 공휴일"
expect "휴가" contract "2026-11-20 12:00" "오늘은 휴가"
expect "휴일 막대" contract "2026-11-21 12:00" "메뉴 막대: 계약 66% · 오늘 휴일 · 오늘 번 돈 ₩0"

# 정규직, 연봉 (입사 3/3, 연봉 4,800만 원, 월급일 21일 = 토요일)
expect "올해" permanent "2026-11-16 20:00" "올해 87.6% 지남"
expect "입사" permanent "$NOW" "입사 259일째"
expect "연차 발생" permanent "$NOW" "다음 연차 발생 12/3(목) · D-17"
expect "퇴근 후" permanent "2026-11-16 20:00" "오늘 번 돈 ₩190,476"
expect "연봉 이번 달" permanent "2026-11-16 20:00" "이번 달 번 돈 ₩2,095,238"
expect "연봉 통상시급" permanent "$NOW" "통상시급 ₩19,138"
expect "주말 월급일" permanent "$NOW" "다음 월급일 11/20(금) · D-4"

# 시급 (점심 60분 빼고 하루 8시간)
expect "시급 오늘" hourly "$NOW" "오늘 번 돈 ₩44,444"
expect "시급 이번 달" hourly "$NOW" "이번 달 번 돈 ₩844,444"
expect "시급 X번" hourly "$NOW" "지금까지 11일 출근 · 이만큼을 0.8번 더 하면 끝 (남은 근무 9일)"

# 설정 오류는 경고만 띄우고 종료 코드 0
expect "깨진 JSON" broken "$NOW" "⚠︎ 설정 파일 오류: JSON 형식이 올바르지 않습니다"
expect "잘못된 시각" bad-value "$NOW" "⚠︎ 설정 파일 오류: workStart의 시각 형식은 HH:mm입니다 (9시)"

# 설정 파일이 없으면 600 권한으로 만든다
TMP="$(mktemp -d)"
if WORKCLOCK_CONFIG="$TMP/new/config.json" "$BIN" --print >/dev/null \
  && [ "$(stat -f %Lp "$TMP/new/config.json")" = "600" ]; then
  PASS=$((PASS + 1))
else
  FAIL=$((FAIL + 1))
  echo "FAIL [양식 생성] 파일이 없거나 권한이 600이 아님"
fi
rm -rf "$TMP"

echo "통과 $PASS · 실패 $FAIL"
[ "$FAIL" -eq 0 ]
