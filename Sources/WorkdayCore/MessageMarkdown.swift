import Foundation

/// Block structure is separate from inline styling so plain report line breaks are preserved.
public enum MessageMarkdown {
    public struct Block: Equatable, Identifiable {
        public let id: Int // Source line, stable as a streamed message grows.
        public let kind: Kind
    }
    public enum Kind: Equatable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case listItem(indent: Int, marker: String, text: String)
        case quote(String)
        case code(language: String, text: String)
        case table(headers: [String], rows: [[String]])
        case rule
    }
    private static let fence = try! NSRegularExpression(pattern: #"^ {0,3}(`{3,}|~{3,})(.*)$"#)
    private static let heading = try! NSRegularExpression(pattern: #"^ {0,3}(#{1,6})[ \t]+(.+?)(?:[ \t]+#+[ \t]*)?$"#)
    private static let list = try! NSRegularExpression(pattern: #"^(\s*)([-+*]|\d+[.)])[ \t]+(.*)$"#)
    private static let quote = try! NSRegularExpression(pattern: #"^ {0,3}>[ \t]?(.*)$"#)
    private static let rule = try! NSRegularExpression(pattern: #"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    private static func captures(_ regex: NSRegularExpression, _ line: String) -> [String]? {
        let text = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else { return nil }
        return (1..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : text.substring(with: match.range(at: $0)) }
    }
    public static func blocks(_ source: String) -> [Block] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var result: [Block] = [], index = 0
        func tableStart(_ line: Int) -> Bool {
            guard line + 1 < lines.count, lines[line].contains("|") else { return false }
            let headers = cells(lines[line]), separators = cells(lines[line + 1])
            return !headers.isEmpty && headers.count == separators.count
                && separators.allSatisfy { $0.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil }
        }
        func startsBlock(_ line: Int) -> Bool {
            let text = lines[line]
            return text.trimmingCharacters(in: .whitespaces).isEmpty || captures(fence, text) != nil
                || captures(heading, text) != nil || captures(list, text) != nil
                || captures(quote, text) != nil || captures(rule, text) != nil || tableStart(line)
        }
        while index < lines.count {
            let line = lines[index], start = index
            if line.trimmingCharacters(in: .whitespaces).isEmpty { index += 1; continue }
            if let match = captures(fence, line) {
                let marker = match[0], language = match[1].trimmingCharacters(in: .whitespaces)
                index += 1
                var code: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.count >= marker.count && candidate.allSatisfy({ $0 == marker.first! }) { index += 1; break }
                    code.append(lines[index]); index += 1
                }
                result.append(Block(id: start, kind: .code(language: language, text: code.joined(separator: "\n"))))
            } else if let match = captures(heading, line) {
                result.append(Block(id: start, kind: .heading(level: match[0].count, text: match[1]))); index += 1
            } else if tableStart(index) {
                let headers = cells(line); index += 2
                var rows: [[String]] = []
                while index < lines.count && lines[index].contains("|") && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    let row = cells(lines[index])
                    rows.append(Array((row + Array(repeating: "", count: headers.count)).prefix(headers.count)))
                    index += 1
                }
                result.append(Block(id: start, kind: .table(headers: headers, rows: rows)))
            } else if captures(rule, line) != nil {
                result.append(Block(id: start, kind: .rule)); index += 1
            } else if let match = captures(list, line) {
                var text = match[2]
                var marker = ["-", "+", "*"].contains(match[1]) ? "•" : match[1]
                if text.hasPrefix("[ ] ") { marker = "☐"; text = String(text.dropFirst(4)) }
                else if text.lowercased().hasPrefix("[x] ") { marker = "☑"; text = String(text.dropFirst(4)) }
                result.append(Block(id: start, kind: .listItem(indent: min(8, match[0].count), marker: marker, text: text))); index += 1
            } else if captures(quote, line) != nil {
                var quoted: [String] = []
                while index < lines.count, let match = captures(quote, lines[index]) { quoted.append(match[0]); index += 1 }
                result.append(Block(id: start, kind: .quote(quoted.joined(separator: "\n"))))
            } else {
                var paragraph = [line]; index += 1
                while index < lines.count && !startsBlock(index) { paragraph.append(lines[index]); index += 1 }
                result.append(Block(id: start, kind: .paragraph(paragraph.joined(separator: "\n"))))
            }
        }
        return result
    }
    private static func cells(_ source: String) -> [String] {
        var result: [String] = [], cell = "", escaped = false, inCode = false
        for character in source.trimmingCharacters(in: .whitespaces) {
            if escaped { cell.append(character); escaped = false; continue }
            if character == "\\" { cell.append(character); escaped = true; continue }
            if character == "`" { inCode.toggle() }
            if character == "|" && !inCode { result.append(cell.trimmingCharacters(in: .whitespaces)); cell = "" }
            else { cell.append(character) }
        }
        result.append(cell.trimmingCharacters(in: .whitespaces))
        if result.first == "" { result.removeFirst() }
        if result.last == "" { result.removeLast() }
        return result
    }
}
