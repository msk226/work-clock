# WorkClock

> 오늘 근무가 얼마나 지났고, 오늘 얼마를 벌었는지 macOS 메뉴 막대에 보여 주는 작은 앱

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-single%20file-F05138?logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/UI-AppKit-147EFB?logo=apple&logoColor=white)
![ServiceManagement](https://img.shields.io/badge/Login%20Item-ServiceManagement-555555?logo=apple&logoColor=white)
![Homebrew](https://img.shields.io/badge/install-Homebrew-FBB040?logo=homebrew&logoColor=black)
![License](https://img.shields.io/badge/license-MIT-blue)

근무 조건을 설정 파일에 적어 두면 메뉴 막대에 오늘 근무 진행률과 오늘 번 돈이 1초마다 올라갑니다. 계약직이면 계약이 얼마나 지났는지도 보여 줍니다.

- 외부 라이브러리와 네트워크 호출이 없습니다. 급여 정보는 내 Mac의 설정 파일에만 있습니다.
- Xcode 없이 Command Line Tools의 `swiftc`로 빌드합니다.

## 메뉴 막대

| 아이콘 | 값 | 언제 보이나 |
|---|---|---|
| 📅 | 계약 진행률 (`62%`) | 계약직이고 계약 기간이 있을 때 |
| 🕘 | 오늘 근무 진행률 (`55.555%`) | 근무일. 주말·공휴일·휴가면 「휴일」 |
| 💵 | 오늘 번 돈 (`₩83,333`) | 급여 설정이 있을 때. 「금액 숨기기」로 가릴 수 있음 |

## 펼침 메뉴

```text
계약 진행 62.7% (남은 46일)
남은 날 = 평일 31일 + 주말 12일 + 공휴일 1일 + 휴가 2일 (오늘 포함)
지금까지 55일 출근 · 이만큼을 0.5번 더 하면 끝 (남은 근무 30일)
─────────
남은 휴가 12시간 (총 16시간 중 4시간 사용)
─────────
오늘 55.5% 지남 / 44.5% 남음
─────────
오늘 번 돈 ₩83,333
이번 달 번 돈 ₩1,583,333
통상시급 ₩14,354
다음 월급일 11/25(수) · D-9
─────────
금액 숨기기
로그인 시 실행
설정 파일 열기
종료
```

정규직이면 계약 줄 대신 아래 줄이 나옵니다.

```text
올해 87.6% 지남
입사 259일째
다음 연차 발생 12/3(목) · D-17
```

## 설치

### Homebrew

```sh
brew tap msk226/tap
brew trust msk226/tap   # 개인 tap이라 처음 한 번 신뢰 등록이 필요합니다
brew install workclock
```

설치하는 Mac에서 소스를 직접 빌드하므로 Gatekeeper 경고가 뜨지 않습니다. 설치 뒤 앱을 `~/Applications`에 링크하면 Launchpad와 Spotlight에서 찾을 수 있습니다.

```sh
ln -sf "$(brew --prefix workclock)/WorkClock.app" ~/Applications/WorkClock.app
open ~/Applications/WorkClock.app
```

### 소스에서 빌드

```sh
git clone https://github.com/msk226/work-clock.git
cd workclock
./build.sh          # ~/Applications/WorkClock.app에 설치
open ~/Applications/WorkClock.app
```

`./build.sh --no-install`은 `build/WorkClock.app`까지만 만듭니다.

## 설정

설정 파일은 `~/.config/workclock/config.json`입니다. 처음 실행하면 빈 양식을 만들고 권한을 600(나만 읽기·쓰기)으로 둡니다. 메뉴의 「설정 파일 열기」로 열 수 있고, 앱은 10초마다 다시 읽습니다.

### 예시

```json
{
  "employmentType": "contract",
  "contractStart": "2026-01-05",
  "contractEnd": "2026-06-30",
  "workStart": "09:30",
  "workEnd": "18:30",
  "annualSalary": 36000000,
  "payday": 25,
  "holidays": ["2026-03-02", "2026-05-05"],
  "leaveDates": ["2026-04-10"],
  "leaveDays": 1,
  "leaveHoursTotal": 16,
  "leaveHoursUsed": 4
}
```

### 키

| 키 | 형식 | 기본값 | 설명 |
|---|---|---|---|
| `employmentType` | `"contract"` · `"permanent"` · `""` | `""` | 비우면 `contractEnd`가 있을 때 계약직으로 봅니다 |
| `contractStart` | `"YYYY-MM-DD"` | `""` | 계약 시작일 |
| `contractEnd` | `"YYYY-MM-DD"` | `""` | 계약 종료일 (이 날까지 근무) |
| `hireDate` | `"YYYY-MM-DD"` | `""` | 정규직 입사일. 근속 일수와 연차 발생일에 씁니다 |
| `workStart` | `"HH:mm"` | `"09:00"` | 출근 시각 |
| `workEnd` | `"HH:mm"` | `"18:00"` | 퇴근 시각 |
| `lunchMinutes` | 숫자 | `60` | 시급으로 하루 금액을 낼 때만 뺍니다 |
| `annualSalary` | 숫자 | `0` | 연봉 (세전) |
| `annualIncludesSeverance` | true/false | `false` | 연봉에 퇴직금이 들어 있으면 true (÷ 13) |
| `monthlyPay` | 숫자 | `0` | 월급 (세전) |
| `dailyPay` | 숫자 | `0` | 일급 |
| `hourlyPay` | 숫자 | `0` | 시급 |
| `monthlyHours` | 숫자 | `209` | 통상시급 기준 월 소정근로시간 |
| `payday` | 1~31 | `0` | 월급일. 0이면 표시하지 않습니다 |
| `holidays` | 날짜 배열 | `[]` | 공휴일과 회사 휴무일 |
| `leaveDates` | 날짜 배열 | `[]` | 날짜가 정해진 휴가 |
| `leaveDays` | 숫자 | `0` | 날짜가 아직 정해지지 않은 휴가 일수 |
| `leaveHoursTotal` | 숫자 | `0` | 시간 단위 휴가 총량. 0이면 휴가 줄을 숨깁니다 |
| `leaveHoursUsed` | 숫자 | `0` | 사용한 휴가 시간 |
| `currency` | 문자열 | `"₩"` | 금액 앞에 붙는 기호 |

### 계산 방식

- **날짜 분류:** 휴가 > 공휴일 > 주말 > 평일 순서로 하나에만 넣습니다. 평일만 근무일입니다.
- **공휴일:** 네트워크를 쓰지 않아서 자동으로 반영하지 않습니다. `holidays`에 직접 적어 주세요.
- **급여:** 연봉 → 월급 → 일급 → 시급 중 처음 있는 것 하나만 씁니다.
  - 월급(연봉 ÷ 12)은 이번 달 재직 일수 비율로 일할한 뒤, 이번 달 근무일 수로 나눠 하루 금액을 냅니다.
  - 오늘 번 돈 = 하루 금액 × 오늘 근무 진행률. 모든 금액은 세전입니다.
- **월급일:** 주말이나 공휴일이면 직전 근무일로 당깁니다. 개인 휴가는 월급일에 영향을 주지 않습니다.
- **연차 발생일:** 입사 1년 미만은 매달 입사일, 1년 이상은 매년 입사 기념일입니다. 회사별 규칙은 반영하지 않습니다.

자세한 규칙은 [docs/PRD.md](docs/PRD.md) 6장에 있습니다.

## 명령줄

```sh
workclock --print          # 현재 값을 한 번 출력하고 종료
workclock --enable-login   # 로그인 시 실행에 등록
workclock --disable-login  # 로그인 시 실행 해제
workclock --version
```

`build.sh`로 설치했다면 `~/Applications/WorkClock.app/Contents/MacOS/WorkClock --print`로 실행합니다.

## 로그인 시 실행

메뉴의 「로그인 시 실행」을 켜거나 `workclock --enable-login`을 실행합니다. `~/Applications`에 있는 앱으로 켜 두는 것을 권장합니다.

다시 빌드하거나 `brew upgrade`를 하면 서명이 바뀌어 로그인 항목이 꺼질 수 있습니다. 그럴 때는 한 번 더 켜 주세요. 시스템 설정 > 일반 > 로그인 항목에서도 끄고 켤 수 있습니다.

## 개발

```sh
./build.sh --no-install
./tests/run.sh
```

`tests/run.sh`는 가짜 설정(`tests/fixtures`)과 고정 시각으로 `--print` 결과를 손으로 계산한 값과 비교합니다. 테스트용으로 두 환경 변수를 씁니다.

- `WORKCLOCK_CONFIG`: 설정 파일 경로를 바꿉니다
- `WORKCLOCK_NOW`: 현재 시각을 `"YYYY-MM-DD HH:mm"`으로 고정합니다

실제 급여가 든 설정 파일은 저장소에 올리지 마세요. `.gitignore`에 `config.json`이 들어 있습니다.

## 삭제

```sh
workclock --disable-login
brew uninstall workclock
rm -f ~/Applications/WorkClock.app
rm -rf ~/.config/workclock     # 설정까지 지우려면
```

## 라이선스

[MIT](LICENSE)
