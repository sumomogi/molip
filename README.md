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
./build.sh     # 컴파일 → 번들 조립 → 애드혹 서명
./install.sh   # /Applications에 설치하고 실행
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

**단축키.** `⌃⌥F` 고정. 바꾸려면 `Hotkey.swift`의 `kVK_ANSI_F`와 수식키를 수정한다.
