// WorkClock: 근무 진행률과 오늘 번 돈을 macOS 메뉴 막대에 보여 주는 앱
// 빌드: ./build.sh   (Command Line Tools의 swiftc만 사용)

import Cocoa
import ServiceManagement

let appVersion = "1.0.0"

// MARK: - 날짜와 시각

var calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.locale = Locale(identifier: "en_US_POSIX")
    c.timeZone = TimeZone.current
    return c
}()

func makeFormatter(_ format: String, korean: Bool = false) -> DateFormatter {
    let f = DateFormatter()
    f.calendar = calendar
    f.locale = Locale(identifier: korean ? "ko_KR" : "en_US_POSIX")
    f.timeZone = TimeZone.current
    f.dateFormat = format
    f.isLenient = false
    return f
}

let dayFormatter = makeFormatter("yyyy-MM-dd")
let shortDayFormatter = makeFormatter("M/d(E)", korean: true)
let stampFormatter = makeFormatter("yyyy-MM-dd HH:mm")
let headerFormatter = makeFormatter("yyyy-MM-dd(E) HH:mm:ss", korean: true)

func parseDay(_ text: String) -> Date? {
    let t = text.trimmingCharacters(in: .whitespaces)
    guard t.count == 10, let d = dayFormatter.date(from: t) else { return nil }
    return calendar.startOfDay(for: d)
}

/// "HH:mm"을 0시부터의 분으로 바꾼다.
func parseClock(_ text: String) -> Int? {
    let parts = text.split(separator: ":")
    guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
          let h = Int(parts[0]), let m = Int(parts[1]),
          (0...23).contains(h), (0...59).contains(m) else { return nil }
    return h * 60 + m
}

func addDays(_ d: Date, _ n: Int) -> Date {
    calendar.date(byAdding: .day, value: n, to: d)!
}

func daysBetween(_ a: Date, _ b: Date) -> Int {
    calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
}

/// a부터 b까지(둘 다 포함) 하루씩. a가 b보다 늦으면 빈 배열.
func eachDay(from a: Date, through b: Date) -> [Date] {
    guard a <= b else { return [] }
    var result: [Date] = []
    var d = a
    while d <= b {
        result.append(d)
        d = addDays(d, 1)
    }
    return result
}

func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }

// MARK: - 설정

struct ConfigError: Error { let message: String }

enum Pay {
    case monthly(Double)
    case daily(Double)
    case hourly(Double)
}

struct Settings {
    var isContract = false
    var contractStart: Date?
    var contractEnd: Date?
    var hireDate: Date?
    var workStart = 9 * 60
    var workEnd = 18 * 60
    var lunchMinutes = 60.0
    var pay: Pay?
    var monthlyHours = 209.0
    var payday = 0
    var holidays = Set<Date>()
    var leaveDates = Set<Date>()
    var leaveDays = 0
    var leaveHoursTotal = 0.0
    var leaveHoursUsed = 0.0
    var currency = "₩"

    var paidHoursPerDay: Double { max(0, Double(workEnd - workStart) - lunchMinutes) / 60 }
}

let configTemplate = """
{
  "employmentType": "",
  "contractStart": "",
  "contractEnd": "",
  "hireDate": "",
  "workStart": "09:00",
  "workEnd": "18:00",
  "lunchMinutes": 60,
  "annualSalary": 0,
  "annualIncludesSeverance": false,
  "monthlyPay": 0,
  "dailyPay": 0,
  "hourlyPay": 0,
  "monthlyHours": 209,
  "payday": 0,
  "holidays": [],
  "leaveDates": [],
  "leaveDays": 0,
  "leaveHoursTotal": 0,
  "leaveHoursUsed": 0,
  "currency": "₩"
}

"""

func isBoolNumber(_ n: NSNumber) -> Bool { CFGetTypeID(n) == CFBooleanGetTypeID() }

func parseSettings(_ data: Data) throws -> Settings {
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw ConfigError(message: "JSON 형식이 올바르지 않습니다")
    }
    guard let dict = object as? [String: Any] else {
        throw ConfigError(message: "파일 전체가 { } 객체여야 합니다")
    }

    func value(_ key: String) -> Any? {
        guard let v = dict[key], !(v is NSNull) else { return nil }
        return v
    }
    func string(_ key: String) throws -> String {
        guard let v = value(key) else { return "" }
        guard let s = v as? String else { throw ConfigError(message: "\(key)는 문자열이어야 합니다") }
        return s.trimmingCharacters(in: .whitespaces)
    }
    func number(_ key: String) throws -> Double {
        guard let v = value(key) else { return 0 }
        guard let n = v as? NSNumber, !isBoolNumber(n) else { throw ConfigError(message: "\(key)는 숫자여야 합니다") }
        let d = n.doubleValue
        guard d.isFinite, d >= 0 else { throw ConfigError(message: "\(key)는 0 이상이어야 합니다") }
        return d
    }
    func bool(_ key: String) throws -> Bool {
        guard let v = value(key) else { return false }
        guard let n = v as? NSNumber, isBoolNumber(n) else { throw ConfigError(message: "\(key)는 true 또는 false여야 합니다") }
        return n.boolValue
    }
    func day(_ key: String) throws -> Date? {
        let t = try string(key)
        if t.isEmpty { return nil }
        guard let d = parseDay(t) else { throw ConfigError(message: "\(key)의 날짜 형식은 YYYY-MM-DD입니다 (\(t))") }
        return d
    }
    func days(_ key: String) throws -> Set<Date> {
        guard let v = value(key) else { return [] }
        guard let list = v as? [Any] else { throw ConfigError(message: "\(key)는 날짜 배열이어야 합니다") }
        var result = Set<Date>()
        for item in list {
            guard let s = item as? String, let d = parseDay(s) else {
                throw ConfigError(message: "\(key)에 YYYY-MM-DD가 아닌 값이 있습니다 (\(item))")
            }
            result.insert(d)
        }
        return result
    }
    func clock(_ key: String, default fallback: Int) throws -> Int {
        let t = try string(key)
        if t.isEmpty { return fallback }
        guard let v = parseClock(t) else { throw ConfigError(message: "\(key)의 시각 형식은 HH:mm입니다 (\(t))") }
        return v
    }

    var s = Settings()

    let type = try string("employmentType")
    guard ["", "contract", "permanent"].contains(type) else {
        throw ConfigError(message: "employmentType은 \"contract\" 또는 \"permanent\"입니다")
    }
    s.contractStart = try day("contractStart")
    s.contractEnd = try day("contractEnd")
    s.hireDate = try day("hireDate")
    s.isContract = type == "contract" || (type.isEmpty && s.contractEnd != nil)
    if let a = s.contractStart, let b = s.contractEnd, b < a {
        throw ConfigError(message: "contractEnd가 contractStart보다 이릅니다")
    }

    s.workStart = try clock("workStart", default: s.workStart)
    s.workEnd = try clock("workEnd", default: s.workEnd)
    guard s.workEnd > s.workStart else {
        throw ConfigError(message: "workEnd는 workStart보다 늦어야 합니다")
    }
    if value("lunchMinutes") != nil { s.lunchMinutes = try number("lunchMinutes") }

    // 급여는 연봉 → 월급 → 일급 → 시급 순서로 처음 있는 것 하나만 쓴다.
    let annual = try number("annualSalary")
    let severance = try bool("annualIncludesSeverance")
    let monthly = try number("monthlyPay")
    let daily = try number("dailyPay")
    let hourly = try number("hourlyPay")
    if annual > 0 {
        s.pay = .monthly(annual / (severance ? 13 : 12))
    } else if monthly > 0 {
        s.pay = .monthly(monthly)
    } else if daily > 0 {
        s.pay = .daily(daily)
    } else if hourly > 0 {
        s.pay = .hourly(hourly)
    }

    let hours = try number("monthlyHours")
    if hours > 0 { s.monthlyHours = hours }

    let payday = try number("payday")
    guard payday == payday.rounded(), payday <= 31 else {
        throw ConfigError(message: "payday는 0~31 사이 정수여야 합니다")
    }
    s.payday = Int(payday)

    s.holidays = try days("holidays")
    s.leaveDates = try days("leaveDates")
    s.leaveDays = Int(try number("leaveDays").rounded())
    s.leaveHoursTotal = try number("leaveHoursTotal")
    s.leaveHoursUsed = try number("leaveHoursUsed")

    let currency = try string("currency")
    if !currency.isEmpty { s.currency = currency }
    return s
}

final class ConfigStore {
    let url: URL
    private(set) var settings = Settings()
    private(set) var errorMessage: String?
    private var lastStamp: Date?
    private var lastSize: Int?

    init(url: URL) { self.url = url }

    static func defaultURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let p = env["WORKCLOCK_CONFIG"], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        let home = env["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".config/workclock/config.json")
    }

    /// 설정 파일이 없으면 빈 양식을 만들고 권한을 600으로 둔다.
    func ensureFile() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            fm.createFile(atPath: url.path, contents: Data(configTemplate.utf8),
                          attributes: [.posixPermissions: 0o600])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            errorMessage = "설정 파일을 만들지 못했습니다 (\(error.localizedDescription))"
        }
    }

    /// 파일이 바뀌었을 때만 다시 읽는다. 오류가 나면 마지막 정상 값을 유지한다.
    func reload(force: Bool = false) {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let stamp = attrs?[.modificationDate] as? Date
        let size = (attrs?[.size] as? NSNumber)?.intValue
        if !force, lastStamp != nil, stamp == lastStamp, size == lastSize { return }
        lastStamp = stamp
        lastSize = size

        guard let data = FileManager.default.contents(atPath: url.path) else {
            errorMessage = "설정 파일을 읽지 못했습니다"
            return
        }
        do {
            settings = try parseSettings(data)
            errorMessage = nil
        } catch let e as ConfigError {
            errorMessage = e.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 계산

enum DayKind { case workday, weekend, holiday, leave }

struct Remaining {
    var weekday = 0
    var weekend = 0
    var holiday = 0
    var leave = 0
    var total: Int { weekday + weekend + holiday + leave }
}

struct Engine {
    let s: Settings
    let now: Date
    let today: Date

    init(_ settings: Settings, now: Date) {
        s = settings
        self.now = now
        today = calendar.startOfDay(for: now)
    }

    // 날짜 분류: 휴가 > 공휴일 > 주말 > 평일
    func kind(_ d: Date) -> DayKind {
        if s.leaveDates.contains(d) { return .leave }
        if s.holidays.contains(d) { return .holiday }
        let wd = calendar.component(.weekday, from: d)
        if wd == 1 || wd == 7 { return .weekend }
        return .workday
    }

    /// 회사가 쉬는 날 (월급일 계산용, 개인 휴가는 제외)
    func isCompanyDayOff(_ d: Date) -> Bool {
        if s.holidays.contains(d) { return true }
        let wd = calendar.component(.weekday, from: d)
        return wd == 1 || wd == 7
    }

    var periodStart: Date? { s.isContract ? s.contractStart : s.hireDate }
    var periodEnd: Date? { s.isContract ? s.contractEnd : nil }

    func inPeriod(_ d: Date) -> Bool {
        if let a = periodStart, d < a { return false }
        if let b = periodEnd, d > b { return false }
        return true
    }

    func isWorkday(_ d: Date) -> Bool { kind(d) == .workday && inPeriod(d) }

    func at(_ day: Date, minutes: Int) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: day)!
    }

    // 오늘
    var todayIsWorkday: Bool { isWorkday(today) }

    var todayProgress: Double? {
        guard todayIsWorkday else { return nil }
        let a = at(today, minutes: s.workStart)
        let b = at(today, minutes: s.workEnd)
        return clamp01(now.timeIntervalSince(a) / b.timeIntervalSince(a))
    }

    // 계약
    var hasContract: Bool { s.isContract && s.contractStart != nil && s.contractEnd != nil }

    var contractProgress: Double? {
        guard hasContract, let a = s.contractStart, let end = s.contractEnd else { return nil }
        let b = addDays(end, 1)
        return clamp01(now.timeIntervalSince(a) / b.timeIntervalSince(a))
    }

    var remaining: Remaining? {
        guard hasContract, let start = s.contractStart, let end = s.contractEnd else { return nil }
        var r = Remaining()
        for d in eachDay(from: max(today, start), through: end) {
            switch kind(d) {
            case .workday: r.weekday += 1
            case .weekend: r.weekend += 1
            case .holiday: r.holiday += 1
            case .leave: r.leave += 1
            }
        }
        // 날짜 미정 휴가는 남은 평일에서 빼서 휴가로 옮긴다.
        let moved = min(s.leaveDays, r.weekday)
        r.weekday -= moved
        r.leave += moved
        return r
    }

    /// 지금까지 출근한 날. 오늘은 출근 시각이 지났으면 센다.
    var worked: (count: Int, todayCounted: Bool)? {
        guard hasContract, let start = s.contractStart, let end = s.contractEnd else { return nil }
        let last = min(addDays(today, -1), end)
        var count = eachDay(from: start, through: last).filter(isWorkday).count
        var todayCounted = false
        if todayIsWorkday, now >= at(today, minutes: s.workStart) {
            count += 1
            todayCounted = true
        }
        return (count, todayCounted)
    }

    var remainingWorkdays: Int? {
        guard let r = remaining, let w = worked else { return nil }
        return max(0, r.weekday - (w.todayCounted ? 1 : 0))
    }

    // 급여
    var month: DateInterval { calendar.dateInterval(of: .month, for: today)! }
    var monthLastDay: Date { addDays(month.end, -1) }
    var daysInMonth: Int { daysBetween(month.start, month.end) }

    /// 이번 달 중 재직 기간
    var monthOverlap: (Date, Date)? {
        var a = month.start
        var b = monthLastDay
        if let p = periodStart, p > a { a = p }
        if let q = periodEnd, q < b { b = q }
        return a <= b ? (a, b) : nil
    }

    var dailyAmount: Double? {
        guard let pay = s.pay else { return nil }
        switch pay {
        case .daily(let v):
            return v
        case .hourly(let v):
            return v * s.paidHoursPerDay
        case .monthly(let base):
            guard let (a, b) = monthOverlap else { return nil }
            let ratio = Double(daysBetween(a, b) + 1) / Double(daysInMonth)
            let workdays = eachDay(from: a, through: b).filter(isWorkday).count
            guard workdays > 0 else { return nil }
            return base * ratio / Double(workdays)
        }
    }

    var todayEarned: Double? {
        guard s.pay != nil else { return nil }
        guard let daily = dailyAmount else { return 0 }
        return daily * (todayProgress ?? 0)
    }

    var monthEarned: Double? {
        guard s.pay != nil else { return nil }
        guard let daily = dailyAmount else { return 0 }
        let passed = eachDay(from: month.start, through: addDays(today, -1)).filter(isWorkday).count
        return daily * Double(passed) + (todayEarned ?? 0)
    }

    var ordinaryHourly: Double? {
        guard let pay = s.pay else { return nil }
        switch pay {
        case .monthly(let base): return base / s.monthlyHours
        case .hourly(let v): return v
        case .daily(let v): return s.paidHoursPerDay > 0 ? v / s.paidHoursPerDay : nil
        }
    }

    /// 다음 월급일. 그 날이 주말·공휴일이면 직전 근무일로 당긴다.
    var nextPayday: Date? {
        guard s.payday > 0 else { return nil }
        for k in 0..<3 {
            let monthStart = calendar.date(byAdding: .month, value: k, to: month.start)!
            let dim = calendar.range(of: .day, in: .month, for: monthStart)!.count
            var d = addDays(monthStart, min(s.payday, dim) - 1)
            var steps = 0
            while isCompanyDayOff(d), steps < 14 {
                d = addDays(d, -1)
                steps += 1
            }
            if d >= today { return d }
        }
        return nil
    }

    // 정규직
    var yearProgress: Double {
        let y = calendar.dateInterval(of: .year, for: today)!
        return clamp01(now.timeIntervalSince(y.start) / y.duration)
    }

    var hireDayNumber: Int? {
        guard let h = s.hireDate, h <= today else { return nil }
        return daysBetween(h, today) + 1
    }

    /// 입사 1년 미만은 매달 입사일, 1년 이상은 매년 입사 기념일
    var nextLeaveAccrual: Date? {
        guard let h = s.hireDate else { return nil }
        for k in 1...11 {
            let d = calendar.date(byAdding: .month, value: k, to: h)!
            if d >= today { return d }
        }
        for n in 1...100 {
            let d = calendar.date(byAdding: .year, value: n, to: h)!
            if d >= today { return d }
        }
        return nil
    }
}

// MARK: - 표시

let moneyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US")
    f.maximumFractionDigits = 0
    f.roundingMode = .floor
    return f
}()

func percent(_ v: Double, digits: Int) -> String {
    let scale = pow(10, Double(digits))
    let floored = floor(v * 100 * scale) / scale
    return String(format: "%.\(digits)f%%", floored)
}

func number(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}

func dday(_ d: Date, from today: Date) -> String {
    let n = daysBetween(today, d)
    return n == 0 ? "D-Day" : "D-\(n)"
}

struct BarItem {
    let id: String
    let symbol: String
    let text: String
}

struct Report {
    var warning: String?
    var bar: [BarItem] = []
    var sections: [[String]] = []
}

func makeReport(_ store: ConfigStore, now: Date, hideAmounts: Bool) -> Report {
    let s = store.settings
    let e = Engine(s, now: now)
    var report = Report()
    report.warning = store.errorMessage.map { "⚠︎ 설정 파일 오류: \($0)" }

    func money(_ v: Double) -> String {
        if hideAmounts { return s.currency + "•••" }
        return s.currency + (moneyFormatter.string(from: NSNumber(value: floor(v))) ?? "0")
    }

    // 메뉴 막대
    if let p = e.contractProgress {
        report.bar.append(BarItem(id: "contract", symbol: "calendar", text: "\(Int(floor(p * 100)))%"))
    }
    if let p = e.todayProgress {
        report.bar.append(BarItem(id: "today", symbol: "clock", text: percent(p, digits: 3)))
    } else {
        report.bar.append(BarItem(id: "today", symbol: "beach.umbrella", text: "휴일"))
    }
    if let earned = e.todayEarned {
        report.bar.append(BarItem(id: "money", symbol: "banknote", text: money(earned)))
    }

    // 계약
    if e.hasContract, let end = s.contractEnd, let p = e.contractProgress,
       let r = e.remaining, let w = e.worked, let rw = e.remainingWorkdays {
        if e.today > end {
            report.sections.append([
                "계약 종료 (\(shortDayFormatter.string(from: end)))",
                "총 \(w.count)일 출근",
            ])
        } else {
            var lines = [
                "계약 진행 \(percent(p, digits: 1)) (남은 \(r.total)일)",
                "남은 날 = 평일 \(r.weekday)일 + 주말 \(r.weekend)일 + 공휴일 \(r.holiday)일 + 휴가 \(r.leave)일 (오늘 포함)",
            ]
            if w.count > 0 {
                let times = String(format: "%.1f", Double(rw) / Double(w.count))
                lines.append("지금까지 \(w.count)일 출근 · 이만큼을 \(times)번 더 하면 끝 (남은 근무 \(rw)일)")
            } else {
                lines.append("아직 출근 전 · 남은 근무 \(rw)일")
            }
            report.sections.append(lines)
        }
    }

    // 정규직
    if !s.isContract {
        var lines = ["올해 \(percent(e.yearProgress, digits: 1)) 지남"]
        if let n = e.hireDayNumber { lines.append("입사 \(n)일째") }
        if let d = e.nextLeaveAccrual {
            lines.append("다음 연차 발생 \(shortDayFormatter.string(from: d)) · \(dday(d, from: e.today))")
        }
        report.sections.append(lines)
    }

    // 휴가
    if s.leaveHoursTotal > 0 {
        let left = max(0, s.leaveHoursTotal - s.leaveHoursUsed)
        report.sections.append([
            "남은 휴가 \(number(left))시간 (총 \(number(s.leaveHoursTotal))시간 중 \(number(s.leaveHoursUsed))시간 사용)",
        ])
    }

    // 오늘
    if let p = e.todayProgress {
        // 지남과 남음의 합이 100.0%가 되도록, 남음은 내림한 지남 값에서 계산한다.
        // 0.1% 단위 정수로 계산해 부동소수점 오차를 피한다.
        let passed = Int(floor(p * 1000 + 1e-9))
        let fmt = { (tenths: Int) in String(format: "%.1f%%", Double(tenths) / 10) }
        report.sections.append(["오늘 \(fmt(passed)) 지남 / \(fmt(1000 - passed)) 남음"])
    } else if !e.inPeriod(e.today) {
        report.sections.append(["오늘은 근무 기간이 아님"])
    } else {
        switch e.kind(e.today) {
        case .leave: report.sections.append(["오늘은 휴가"])
        case .holiday: report.sections.append(["오늘은 공휴일"])
        default: report.sections.append(["오늘은 주말"])
        }
    }

    // 급여
    var payLines: [String] = []
    if let t = e.todayEarned { payLines.append("오늘 번 돈 \(money(t))") }
    if let m = e.monthEarned { payLines.append("이번 달 번 돈 \(money(m))") }
    if let h = e.ordinaryHourly { payLines.append("통상시급 \(money(h))") }
    if let d = e.nextPayday {
        let label = daysBetween(e.today, d) == 0 ? "오늘 월급일" : "다음 월급일"
        payLines.append("\(label) \(shortDayFormatter.string(from: d)) · \(dday(d, from: e.today))")
    }
    if !payLines.isEmpty { report.sections.append(payLines) }

    return report
}

func textReport(_ store: ConfigStore, now: Date) -> String {
    let r = makeReport(store, now: now, hideAmounts: false)
    var out = ["WorkClock \(appVersion) · \(headerFormatter.string(from: now))", "설정: \(store.url.path)"]
    if let w = r.warning { out.append(w) }
    let names = ["contract": "계약", "today": "오늘", "money": "오늘 번 돈"]
    out.append("메뉴 막대: " + r.bar.map { "\(names[$0.id] ?? $0.id) \($0.text)" }.joined(separator: " · "))
    for section in r.sections {
        out.append("")
        out.append(contentsOf: section)
    }
    return out.joined(separator: "\n")
}

// MARK: - 메뉴 막대 앱

func currentNow() -> Date {
    // 테스트용: WORKCLOCK_NOW="YYYY-MM-DD HH:mm"이면 그 시각으로 고정한다.
    if let s = ProcessInfo.processInfo.environment["WORKCLOCK_NOW"], let d = stampFormatter.date(from: s) {
        return d
    }
    return Date()
}

var runningFromAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store: ConfigStore
    var items: [String: NSStatusItem] = [:]
    var images: [String: NSImage] = [:]
    var timers: [Timer] = []
    let hideKey = "hideAmounts"

    init(store: ConfigStore) {
        self.store = store
    }

    var hideAmounts: Bool {
        get { UserDefaults.standard.bool(forKey: hideKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.ensureFile()
        store.reload(force: true)

        // 새 항목은 기존 항목의 왼쪽에 붙는다. 오른쪽 것부터 만든다.
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        for id in ["money", "today", "contract"] {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            item.menu = menu
            item.button?.imagePosition = .imageLeading
            item.button?.font = font
            items[id] = item
        }
        refreshBar()

        let tick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.refreshBar() }
        let reload = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            self?.store.reload()
            self?.refreshBar()
        }
        for t in [tick, reload] {
            RunLoop.main.add(t, forMode: .common)
            timers.append(t)
        }
    }

    func image(_ name: String) -> NSImage? {
        if let cached = images[name] { return cached }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
        img?.isTemplate = true
        images[name] = img
        return img
    }

    func refreshBar() {
        let report = makeReport(store, now: currentNow(), hideAmounts: hideAmounts)
        let shown = Dictionary(uniqueKeysWithValues: report.bar.map { ($0.id, $0) })
        for (id, item) in items {
            guard let bar = shown[id] else {
                item.isVisible = false
                continue
            }
            item.isVisible = true
            let symbol = (id == "today" && report.warning != nil) ? "exclamationmark.triangle" : bar.symbol
            item.button?.image = image(symbol)
            item.button?.title = " " + bar.text
        }
    }

    // 메뉴는 열릴 때마다 새로 계산한다.
    func menuNeedsUpdate(_ menu: NSMenu) {
        store.reload()
        menu.removeAllItems()
        let report = makeReport(store, now: currentNow(), hideAmounts: hideAmounts)

        func info(_ text: String) {
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = true
            menu.addItem(item)
        }

        if let w = report.warning {
            info(w)
            menu.addItem(.separator())
        }
        for (i, section) in report.sections.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            section.forEach(info)
        }
        menu.addItem(.separator())

        let hide = NSMenuItem(title: "금액 숨기기", action: #selector(toggleHide), keyEquivalent: "")
        hide.target = self
        hide.state = hideAmounts ? .on : .off
        menu.addItem(hide)

        let login = NSMenuItem(title: "로그인 시 실행", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        if runningFromAppBundle {
            switch SMAppService.mainApp.status {
            case .enabled: login.state = .on
            case .requiresApproval: login.title = "로그인 시 실행 (시스템 설정에서 승인 필요)"
            default: login.state = .off
            }
        } else {
            login.title = "로그인 시 실행 (WorkClock.app으로 실행해야 함)"
            login.isEnabled = false
        }
        menu.addItem(login)

        let open = NSMenuItem(title: "설정 파일 열기", action: #selector(openConfig), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc func toggleHide() {
        hideAmounts.toggle()
        refreshBar()
    }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showAlert("로그인 시 실행을 바꾸지 못했습니다", error.localizedDescription)
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc func openConfig() {
        store.ensureFile()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-t", store.url.path]
        try? p.run()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    func showAlert(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }
}

// MARK: - 진입점

let usage = """
WorkClock \(appVersion)
근무 진행률과 오늘 번 돈을 메뉴 막대에 보여 줍니다.

사용법:
  workclock                 메뉴 막대 앱으로 실행
  workclock --print         현재 값을 한 번 출력하고 종료
  workclock --enable-login  로그인 시 실행에 등록
  workclock --disable-login 로그인 시 실행 해제
  workclock --version       버전 출력

설정 파일: ~/.config/workclock/config.json
"""

let arguments = Array(CommandLine.arguments.dropFirst())
let store = ConfigStore(url: ConfigStore.defaultURL())

switch arguments.first {
case "--print":
    store.ensureFile()
    store.reload(force: true)
    print(textReport(store, now: currentNow()))
    exit(0)

case "--enable-login":
    guard runningFromAppBundle else {
        print("WorkClock.app 안의 실행 파일로 실행해야 등록할 수 있습니다.")
        exit(1)
    }
    do {
        try SMAppService.mainApp.register()
    } catch {
        print("등록하지 못했습니다: \(error.localizedDescription)")
        exit(1)
    }
    switch SMAppService.mainApp.status {
    case .enabled:
        print("로그인 시 실행에 등록했습니다.")
    case .requiresApproval:
        print("시스템 설정 > 일반 > 로그인 항목에서 WorkClock을 허용해 주세요.")
        SMAppService.openSystemSettingsLoginItems()
    default:
        print("등록 상태를 확인하지 못했습니다.")
    }
    exit(0)

case "--disable-login":
    guard runningFromAppBundle else {
        print("WorkClock.app 안의 실행 파일로 실행해야 해제할 수 있습니다.")
        exit(1)
    }
    do {
        try SMAppService.mainApp.unregister()
        print("로그인 시 실행을 해제했습니다.")
    } catch {
        print("해제하지 못했습니다: \(error.localizedDescription)")
        exit(1)
    }
    exit(0)

case "--version", "-v":
    print(appVersion)
    exit(0)

case "--help", "-h":
    print(usage)
    exit(0)

case nil:
    let app = NSApplication.shared
    let delegate = AppDelegate(store: store)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()

default:
    print("알 수 없는 옵션: \(arguments[0])\n")
    print(usage)
    exit(2)
}
