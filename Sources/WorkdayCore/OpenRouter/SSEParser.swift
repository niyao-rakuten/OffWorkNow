import Foundation

/// Byte-level framing preserves blank lines and UTF-8 split across network packets.
struct SSEParser {
    private var line: [UInt8] = []
    private var dataLines: [String] = []
    private var previousWasCR = false
    private var size = 0
    private var isFirstLine = true
    let maximumEventBytes: Int

    init(maximumEventBytes: Int) {
        self.maximumEventBytes = maximumEventBytes
    }

    mutating func append(_ byte: UInt8) throws -> String? {
        if previousWasCR {
            previousWasCR = false
            if byte == 10 { return nil }
        }
        if byte == 13 || byte == 10 {
            previousWasCR = byte == 13
            return try finishLine()
        }
        size += 1
        guard size <= maximumEventBytes else { throw OpenRouterError.eventTooLarge }
        line.append(byte)
        return nil
    }

    private mutating func finishLine() throws -> String? {
        guard var text = String(bytes: line, encoding: .utf8) else {
            throw OpenRouterError.malformedEvent("Invalid UTF-8")
        }
        line.removeAll(keepingCapacity: true)
        if isFirstLine {
            isFirstLine = false
            if text.first == "\u{FEFF}" { text.removeFirst() }
        }
        if text.isEmpty {
            let event = dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
            dataLines.removeAll(keepingCapacity: true)
            size = 0
            return event
        }
        if text.hasPrefix(":") { size -= text.utf8.count; return nil }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts[0] == "data" {
            var value = parts.count == 2 ? String(parts[1]) : ""
            if value.first == " " { value.removeFirst() }
            dataLines.append(value)
        }
        return nil
    }
}
