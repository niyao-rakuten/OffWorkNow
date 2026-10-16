import SwiftUI
import WorkdayCore

struct MarkdownMessageView: View {
    let source: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(MessageMarkdown.blocks(source)) { block in
                content(block.kind)
            }
        }
    }
    @ViewBuilder private func content(_ block: MessageMarkdown.Kind) -> some View {
        switch block {
        case .paragraph(let text): inline(text)
        case .heading(let level, let text):
            inline(text).font(.system(size: CGFloat(max(14, 23 - level * 2)), weight: .bold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
        case .listItem(let indent, let marker, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: marker).fontWeight(.medium)
                inline(text)
            }.padding(.leading, CGFloat(indent) * 5)
        case .quote(let text):
            HStack(spacing: 8) {
                Rectangle().fill(.primary.opacity(0.3)).frame(width: 3)
                inline(text).padding(.vertical, 4)
            }.fixedSize(horizontal: false, vertical: true)
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 4) {
                if !language.isEmpty { Text(verbatim: language).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary) }
                ScrollView(.horizontal) {
                    Text(verbatim: text.isEmpty ? " " : text).font(.system(size: 12, design: .monospaced))
                        .fixedSize(horizontal: true, vertical: true).padding(.bottom, 3)
                }.fixedSize(horizontal: false, vertical: true)
            }.padding(8).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        case .table(let headers, let rows):
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 0) {
                    tableRow(headers, header: true)
                    ForEach(rows.indices, id: \.self) { index in
                        Divider()
                        tableRow(rows[index], header: false)
                    }
                }
            }.fixedSize(horizontal: false, vertical: true)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        case .rule: Divider().padding(.vertical, 2)
        }
    }
    private func tableRow(_ cells: [String], header: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(cells.indices, id: \.self) { index in
                inline(cells[index]).fontWeight(header ? .semibold : .regular)
                    .frame(width: 120, alignment: .leading).padding(6)
            }
        }
    }
    private func inline(_ source: String) -> Text {
        var text = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(source)
        for run in text.runs where run.inlinePresentationIntent?.contains(.code) == true {
            text[run.range].font = .system(size: 12, design: .monospaced)
        }
        return Text(text)
    }
}
