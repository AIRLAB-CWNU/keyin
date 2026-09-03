// ╔══════════════════════════════════════════════════════════════╗
// ║  Log.swift — 통합 로깅                                        ║
// ╚══════════════════════════════════════════════════════════════╝
//
// 이 앱은 메뉴바 상주 에이전트라 stdout이 어디에도 보이지 않는다.
// (launchd로 실행되면 더더욱) 그래서 print는 진단에 쓸모가 없고,
// 특히 다른 맥에 배포했을 때 "왜 안 되는지"를 확인할 방법이 없어진다.
//
// os.Logger는 시스템 로그로 나가므로 어느 머신에서든 아래로 확인할 수 있다:
//
//   log show --last 10m --predicate 'subsystem == "com.keyin.ShiftSpaceMac"'
//   log stream --predicate 'subsystem == "com.keyin.ShiftSpaceMac"'
//
// 레벨 기준:
//   .notice — 상태 변화 (시작, 권한, 이벤트 탭 생성/복구). 디스크에 보존됨
//   .debug  — 키 입력마다 발생하는 고빈도 이벤트. 기본적으로 수집되지 않음
//   .error  — 실패

import os

enum Log {
    private static let subsystem = "com.keyin.ShiftSpaceMac"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let input = Logger(subsystem: subsystem, category: "input")
    static let switching = Logger(subsystem: subsystem, category: "switching")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
}
