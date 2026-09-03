# 몰입 (Molip)

메뉴바 집중 타이머. Xcode 없이 Command Line Tools만으로 빌드한다.

> A quiet menu bar focus timer for macOS, in Korean, English, and Japanese.
> The menu bar shows a 10-segment bar that drains as the session runs — no digits,
> so it does not invite clock-watching. Grayscale only; all colors come from system
> semantic colors, so light/dark and increased-contrast are handled automatically.
>
> Built with `swiftc` alone — no Xcode, no asset catalog, no package manager.
> Run `./build.sh && ./install.sh`. Notes below are in Korean.

```
./build.sh       # 컴파일 → 번들 조립 → 애드혹 서명
./install.sh     # /Applications에 설치하고 실행
./tools/test.sh  # 순수 함수 테스트
```

## 설계

무채색만 쓴다. 색은 전부 시스템 시맨틱 컬러(`labelColor`, `secondaryLabelColor`,
`tertiaryLabelColor`)에서 가져오므로 라이트/다크와 대비 설정을 자동으로 따라간다.
하드코딩한 회색값은 없다.

### 구성

| 파일 | 역할 |
|---|---|
| `TimerEngine.swift` | 상태 머신 + 카운트다운. UI를 모른다. |
| `GaugeRenderer.swift` | (진행률, 상태) → 그림. 메뉴바와 팝오버가 공유. |
| `PopoverView.swift` | SwiftUI 뷰. 엔진 상태를 읽기만 한다. |
| `Notifier.swift` | 알림 + 시스템 사운드 |
| `SessionLog.swift` | 세션 기록 파일 읽고 쓰기 |
| `Insight.swift` | 기록 → 히트맵·최적 구간. 순수 함수 |
| `HistoryView.swift` | 기록 화면 |
| `Workday.swift` | 근무·몰입 계산. 순수 함수 |
| `ShareCard.swift` | 공유용 정사각 PNG |
| `CheckoutView.swift` | 마감 화면 |
| `Hotkey.swift` | 전역 단축키 (Carbon) |
| `Strings.swift` | 3개 언어 문자열 테이블 |
| `Prefs.swift` | UserDefaults |
| `main.swift` | NSStatusItem + NSPopover 조립 |

전이 규칙은 `TimerEngine.nextStep(after:completedInSet:setSize:)` 순수 함수에 모여 있다.
타이머 없이 단독으로 검증할 수 있다.

### 게이지

10칸. 세그먼트 3pt + 간격 1pt = 39pt 폭이라 1x/2x 어느 화면에서도 픽셀에 맞아떨어진다.
50분 기준 한 칸이 정확히 5분. 초 단위로 움직이지 않아 곁눈에 걸리지 않는다.

템플릿 이미지로 그리므로 색은 macOS가 칠한다. 강약은 알파값으로만 준다.

```
작업  채움 1.00 / 빈칸 0.20
휴식  채움 0.40 / 빈칸 0.10
대기  전부 0.20
```

### 동작

| 시점 | 처리 |
|---|---|
| 작업 종료 | 알림 + Submarine / 휴식 자동 시작 |
| 휴식 종료 | 알림 + Tink / 대기로 정지 |
| N세트 완료 | 짧은 휴식 대신 긴 휴식 |

휴식 후 자동으로 다음 작업을 시작하지 않는다. 자리를 비운 사이 타이머만 혼자 돌아
실제 집중 시간과 기록이 어긋나는 것을 막기 위해서다.

### 기록

작업 세션만 `~/Library/Application Support/Molip/sessions.jsonl`에 한 줄씩 쌓는다.
휴식은 남기지 않는다. 60초 미만도 버린다 — 눌렀다 바로 끈 것까지 세면 그림이 흐려진다.

```
{"start":"2026-08-30T15:44:04+09:00","seconds":3000,"completed":true}
```

`start`에 로컬 오프셋을 붙여 적고, 요일과 시간대는 그 오프셋으로 센다.
다른 시간대로 옮겨가도 과거 기록이 다시 쓰이지 않는다.
`JSONEncoder`의 `.iso8601` 전략은 UTC로 적어 이 정보를 잃으므로 쓰지 않는다.

인사이트는 최근 8주만 본다. 습관이 바뀌면 화면도 따라 바뀐다.

히트맵 농도는 가장 큰 칸이 아니라 상위 25% 지점(0이 아닌 칸만 정렬)을 기준으로
잰다. 최댓값을 기준 삼으면 어쩌다 한 번 길게 돌린 세션 하나가 나머지 칸을 전부
최저 단계로 눌러버려, 정작 보여줘야 할 반복 습관이 지워진다.

문장은 두 문턱을 넘어야 나온다 — 창 안에 10세션 이상, 그리고 3세션 이상 쌓인
칸이 하나 이상. 그 후보들 중에서 합계가 가장 큰 칸을 고른다. 합계부터 고르고
그 칸에만 문턱을 검사하면, 어쩌다 한 번 길게 집중한 칸이 먼저 뽑혔다가 문턱에서
떨어져 침묵으로 끝난다 — 꾸준히 쌓아온 칸이 있어도 앱이 아무 말도 못 하게 된다.

작업 중에 앱을 끄면 그때까지 한 만큼이 `completed: false`로 남는다.

`completed`는 인사이트 계산에 쓰지 않는다. 파일을 직접 열어 보는 사람을 위해
남기는 값이다 — 끝까지 간 세션과 중간에 끊은 세션을 눈으로 구분할 수 있어야 한다.

### 체크인

하루의 시작과 끝은 사용자가 직접 찍는다. 자동으로 잡지 않는다 — 커피 내리고
메일 보는 시간도 근무이고, 그 경계는 앱이 알 수 없다.

열려 있는 체크인 시각 하나만 `UserDefaults`에 둔다. 근무 이력 파일은 만들지 않는다.
몰입 시간은 `sessions.jsonl`에서 그 구간에 시작한 세션을 걸러 더한다.

체크아웃 버튼을 누르는 순간이 아니라 마감 화면을 닫을 때 체크인 값을 지운다 —
화면이 떠 있는 동안엔 값이 살아 있어야 `이미지 복사`를 다시 눌러도 같은 카드가
그려진다.

몰입/근무 비율은 1.0에서 자른다. 체크인을 늦게 찍었거나 세션 집계가 어긋나
몰입이 근무보다 길게 잡혀도 카드에는 101%가 뜨지 않는다.

체크아웃을 잊고 앱을 다시 켜면, 어제 이전에 찍힌 체크인은 조용히 버린다.
"근무 31시간"이라 적힌 카드를 올리는 것보다 그날 숫자를 잃는 편이 낫다.

마감 화면에서 `이미지 복사`를 누르면 1080×1080 PNG가 클립보드에 올라간다.
공유 시트를 쓰지 않는다 — 요즘 macOS 공유 시트에는 SNS가 거의 없고, 클립보드는
어디에든 붙일 수 있으며 올리기 전에 내용을 한 번 더 보게 된다.

네트워크 코드도 API 키도 없다.

### 언어

한국어·영어·일본어. 설정의 선택 행에서 바꾸며 즉시 반영된다.
저장된 값이 없으면 시스템 언어를 따르고, 셋 중 없으면 영어로 떨어진다.

화면에 나가는 문자열은 전부 `Strings.swift`의 테이블에 있다. 다른 파일에
문자열을 직접 쓰지 말 것 — 한 언어에서만 번역이 빠지는 사고가 난다.

`L10n.Key`는 `CaseIterable`이라 키 × 언어 전수 검사를 코드로 돌릴 수 있다.

설정 행 이름은 단계 이름과 같아야 한다. 같은 대상을 두 이름으로 부르면
(단계는 `집중`인데 설정은 `작업`) 쓰는 사람이 다른 기능으로 오해한다.

번역은 직역이 아니라 각 언어에서 자연스럽게 읽히는 쪽을 택했다.
영어 대기 상태가 `Idle`이 아니라 `Ready`인 것, 세트 표기가 `2 / 4`가 아니라
`2 of 4`인 것이 그 예다. 한국어·일본어와 단어가 일대일로 대응하지 않는 것이 정상이다.

## 알아둘 것

**팝오버 크기.** `NSHostingController.sizingOptions = [.preferredContentSize]`가 없으면
팝오버가 기본값 320x320으로 자리를 먼저 잡고, SwiftUI가 실제 크기를 알린 뒤 아래쪽을
고정한 채 축소된다. 그만큼 메뉴바에서 떨어져 보인다(측정값 115pt). 이 줄을 지우지 말 것.

**유니버설 바이너리다.** `build.sh`가 arm64와 x86_64를 각각 컴파일해 `lipo`로 합친다.
한쪽만 만들면 그 아키텍처에서만 돌아간다 — arm64 전용 바이너리는 인텔 맥에서 아예
실행되지 않고, Rosetta도 도움이 안 된다(x86_64를 ARM에서 돌리는 것이라 방향이 반대다).
SDK가 두 아키텍처를 모두 갖고 있어서 어느 맥에서 빌드해도 양쪽이 나온다.

**애드혹 서명.** Apple 공증을 받지 않았지만 `curl`로 받은 것이 아니라 로컬에서 빌드하므로
격리 속성이 붙지 않아 Gatekeeper 경고 없이 실행된다. `SMAppService`(로그인 시 실행)도
애드혹 서명으로 정상 동작하는 것을 확인했다.

**언어 반영.** `RootView`가 `@AppStorage`로 언어 키를 관찰한다. 이게 있어야 값이
바뀔 때 트리 전체가 다시 그려진다. 메뉴바 툴팁은 SwiftUI 밖이라 별도로
`onLanguageChange` 콜백을 받아 갱신한다.

**팝오버 닫기.** `NSPopover.behavior = .transient`만으로는 부족하다. transient는
앱이 활성 상태를 잃을 때 닫아주는데, 이 앱은 `LSUIElement`(accessory)라 활성 앱이
되는 일이 없어서 그 신호가 오지 않는다. 다른 앱을 눌러도 팝오버가 남는다.

그래서 `NSEvent.addGlobalMonitorForEvents`로 바깥 클릭을 직접 본다. 그런데 활성 앱이
아니면 이 감시자가 **우리 앱으로 가는 클릭까지 받는다**(활성 앱이면 AppKit이 걸러준다).
좌표로 직접 판별해야 한다 — `closeIfClickedOutside()` 참고. 이 판별을 빼면 팝오버
안쪽을 눌러도 닫혀서 설정을 만질 수가 없다.

메뉴바 아이콘도 예외로 둬야 한다. 감시자가 먼저 닫으면 이어서 버튼 동작이 다시 열어버려
아이콘 클릭으로 닫는 게 불가능해진다.

**알림 대리자.** `UNUserNotificationCenter`에 대리자를 걸지 않으면, 앱이 활성일 때
시스템이 "이 알림을 어떻게 보여줄까" 물어보는 자리에서 기본값인 "보여주지 마라"로
답해버린다. 메뉴바 앱이라 평소엔 활성이 될 일이 없어서 대부분은 잘 뜨는데,
**팝오버를 열어둔 채로 세션이 끝나면 그때만 알림이 조용히 사라진다.**
타이머를 보고 있을 때만 안 뜨는 셈이라 원인을 짚기 어렵다.

`Notifier`가 `UNUserNotificationCenterDelegate`를 구현하고 `willPresent`에서
`[.banner, .list]`를 돌려준다. 소리는 `announce`가 `NSSound`로 이미 내므로
여기에 `.sound`를 넣으면 두 번 울린다.

**단축키.** `⌃⌥F` 고정. 바꾸려면 `Hotkey.swift`의 `kVK_ANSI_F`와 수식키를 수정한다.

**`load()`가 파일 전체를 String으로 먼저 디코드하면 안 된다.** 깨진 바이트 하나나
CRLF 줄바꿈 하나로 디코드가 통째로 실패해 몇 년치 기록이 한꺼번에 사라진다.
`SessionLog.load()`는 바이트로 먼저 줄을 가르고 줄마다 따로 디코드한다 —
손실이 그 한 줄에서 멈춘다.

**`append()`는 `O_APPEND`로 연다.** `seekToEnd` 후 `write`는 시스템 콜 두 번이라
그 사이에 다른 프로세스의 쓰기가 끼면 한 줄이 통째로 덮인다. `O_APPEND`는
커널이 파일 끝에 붙여주므로 자리를 다투지 않는다.

**테스트 실행기의 `-wmo`.** 대소문자를 구분하지 않는 파일시스템(APFS)에서는
`Sources/Stepping.swift`와 `tools/tests/stepping.swift`처럼 이름이 대소문자만
다른 파일끼리 임시 오브젝트 이름이 충돌해 링크가 깨진다. `tools/test.sh`가
전체 모듈 컴파일(`-wmo`)로 돌리는 이유다.

**문자열 전수 검사에는 `L10n.raw`를 써야 한다.** `L10n.s(_:lang:)`는 그 언어
표에 값이 없으면 영어로 폴백하므로, 한국어·일본어 번역이 빠져도 검사를
통과해버린다. `L10n.raw(_:lang:)`는 폴백 없이 그 언어 표에 실제로 등록됐는지만
본다.

**카드 색은 고정값이다.** 앱 안에서는 시스템 시맨틱 컬러만 쓰지만, 내보낸 이미지에는
따라갈 라이트/다크가 없다. 받는 쪽 화면이 어떻든 같게 보여야 하므로 `ShareCard`에서만
흑백을 직접 지정한다.

**스크래치 바이너리의 `UserDefaults`.** 앱 번들 밖에서 `swiftc`로 즉석 컴파일해 돌리는
미리보기 바이너리는 번들 ID가 없어 `UserDefaults.standard`가 프로세스 이름으로 된
도메인에 떨어진다. `ShareCard` 렌더링을 헤드리스로 확인하려고 그런 스크래치 바이너리를
만들었다가 `Prefs.language`가 엉뚱한 도메인에서 읽혀 언어가 안 바뀐 것처럼 보였고,
이름이 같은 스크래치 바이너리 두 개를 오갔더니 이전 실행 값이 다음 실행에 새어
들어온 적도 있다. 실제 앱 번들(`Molip.app`)로 확인하거나, 스크래치 바이너리마다
다른 이름을 쓸 것.
