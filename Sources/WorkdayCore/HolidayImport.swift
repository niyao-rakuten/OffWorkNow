import Foundation

public struct ImportedHoliday: Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let holidays: [String]
    public let workdays: [String]
}

public struct HolidayImportResult: Equatable {
    public let holidays: [ImportedHoliday]
    /// Same representation as WorkSettings.overrides: true works, false rests.
    public let overrides: [String: Bool]
    public var restCount: Int { overrides.values.filter { !$0 }.count }
    public var workCount: Int { overrides.values.filter { $0 }.count }
}

/// Parses the civil dates in Chinese holiday notices, never the lunar dates in parentheses.
public enum HolidayNoticeParser {
    private static let datePattern = #"(?:(\d{4})年)?(?:(\d{1,2})月)?(\d{1,2})日"#
    private static let rangeSeparator = #"(?:至|到|—|-|～|~)"#
    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    public static func parse(_ text: String, year: Int) throws -> HolidayImportResult {
        guard (1900...9998).contains(year) else { throw ValidationError(L10n.text("请输入有效的四位年份。")) }
        guard text.utf8.count <= 100_000 else { throw ValidationError(L10n.text("通知文本过长，请仅粘贴一年的放假安排。")) }
        var normalized = text.replacingOccurrences(of: "*", with: "")
        normalized = normalized.replacingOccurrences(of: #"[（(][^）)]*[）)]"#, with: "", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let source = normalized as NSString
        let yearHeaders = try NSRegularExpression(pattern: #"(\d{4})年[：:]"#).matches(in: normalized, range: NSRange(location: 0, length: source.length))
        guard yearHeaders.allSatisfy({ Int(source.substring(with: $0.range(at: 1))) == year }) else {
            throw ValidationError(L10n.text("通知中的年份与所选年份不同，请一次导入一年的安排。"))
        }
        let heading = try NSRegularExpression(pattern: #"[一二三四五六七八九十\d]+、([^：:。]+)[：:]"#)
        let headings = heading.matches(in: normalized, range: NSRange(location: 0, length: source.length))
        var sections: [(String, String)] = []
        if headings.isEmpty { sections = [(L10n.text("节假日"), normalized)] }
        else {
            for (index, match) in headings.enumerated() {
                let start = NSMaxRange(match.range)
                let end = index + 1 < headings.count ? headings[index + 1].range.location : source.length
                sections.append((source.substring(with: match.range(at: 1)), source.substring(with: NSRange(location: start, length: end - start))))
            }
        }
        let holidayPattern = datePattern + "(?:" + rangeSeparator + datePattern + ")?放假"
        let holidayRegex = try NSRegularExpression(pattern: holidayPattern)
        let workRegex = try NSRegularExpression(pattern: #"([^。；;]+)上班"#)
        let dateRegex = try NSRegularExpression(pattern: datePattern + "(?:" + rangeSeparator + datePattern + ")?")
        var groups: [ImportedHoliday] = []
        var overrides: [String: Bool] = [:]
        for (name, section) in sections {
            let body = section as NSString
            let holidays = holidayRegex.matches(in: section, range: NSRange(location: 0, length: body.length))
            guard !holidays.isEmpty, section.components(separatedBy: "放假").count - 1 == holidays.count else { throw invalid(name) }
            var rest: Set<String> = []
            for match in holidays { rest.formUnion(try dates(match, in: body, year: year, inheritedMonth: nil, name: name)) }
            var work: Set<String> = []
            for clause in workRegex.matches(in: section, range: NSRange(location: 0, length: body.length)) {
                let list = body.substring(with: clause.range(at: 1))
                let listSource = list as NSString
                let matches = dateRegex.matches(in: list, range: NSRange(location: 0, length: listSource.length))
                guard !matches.isEmpty else { throw invalid(name) }
                // No silently skipped text/dates in a make-up workday clause.
                let remainder = dateRegex.stringByReplacingMatches(in: list, range: NSRange(location: 0, length: listSource.length), withTemplate: "")
                guard remainder.replacingOccurrences(of: #"[、，,和及]"#, with: "", options: .regularExpression).isEmpty else { throw invalid(name) }
                var month: Int?
                for match in matches {
                    let expanded = try dates(match, in: listSource, year: year, inheritedMonth: month, name: name)
                    work.formUnion(expanded)
                    month = expanded.last.flatMap { Int($0.split(separator: "-")[1]) }
                }
            }
            for key in rest {
                guard overrides[key] != true else { throw conflict(key) }
                overrides[key] = false
            }
            for key in work {
                guard overrides[key] != false else { throw conflict(key) }
                overrides[key] = true
            }
            groups.append(ImportedHoliday(id: groups.count, name: name, holidays: rest.sorted(), workdays: work.sorted()))
        }
        guard !overrides.isEmpty else { throw invalid(L10n.text("节假日")) }
        return HolidayImportResult(holidays: groups, overrides: overrides)
    }
    private static func dates(_ match: NSTextCheckingResult, in source: NSString, year: Int, inheritedMonth: Int?, name: String) throws -> [String] {
        func number(_ index: Int) -> Int? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : Int(source.substring(with: range))
        }
        guard let month = number(2) ?? inheritedMonth, let day = number(3) else { throw invalid(name) }
        let startYear = number(1) ?? year
        let start = try date(year: startYear, month: month, day: day, name: name)
        guard let endDay = number(6) else { return [ScheduleCalculator.key(start, calendar: calendar)] }
        let endMonth = number(5) ?? month
        let endYear = number(4) ?? (endMonth < month ? startYear + 1 : startYear)
        let end = try date(year: endYear, month: endMonth, day: endDay, name: name)
        let distance = calendar.dateComponents([.day], from: start, to: end).day ?? -1
        guard (0...61).contains(distance) else { throw invalid(name) }
        return (0...distance).map { ScheduleCalculator.key(calendar.date(byAdding: .day, value: $0, to: start)!, calendar: calendar) }
    }
    private static func date(year: Int, month: Int, day: Int, name: String) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day)
        guard (1900...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: components), calendar.dateComponents([.year, .month, .day], from: date) == components else { throw invalid(name) }
        return date
    }
    private static func invalid(_ name: String) -> ValidationError {
        ValidationError(L10n.format("无法完整解析「{0}」的日期，请检查月份、日期范围和上班安排。", name))
    }
    private static func conflict(_ key: String) -> ValidationError {
        ValidationError(L10n.format("{0} 同时被标记为放假和上班，请检查原文。", key))
    }
}
