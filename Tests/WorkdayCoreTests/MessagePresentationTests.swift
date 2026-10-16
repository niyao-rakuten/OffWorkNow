import XCTest
import CoreGraphics
@testable import WorkdayCore

final class MessagePresentationTests: ChineseLocalizationTestCase {
    func testOldSettingsDefaultToRightAndAllPlacementsPersist() throws {
        XCTAssertEqual(try SettingsCodec.decode(Data("{}".utf8)).chatPanelPosition, .right)
        for position in ChatPanelPosition.allCases {
            var settings = WorkSettings(); settings.chatPanelPosition = position
            XCTAssertEqual(try SettingsCodec.decode(JSONEncoder().encode(settings)), settings)
        }
    }
    func testExpandedLayoutsContainBothViewsAndUseRequestedDirection() {
        for position in ChatPanelPosition.allCases {
            let layout = PetPanelLayout(position: position, expanded: true)
            let canvas = CGRect(origin: .zero, size: layout.size)
            let pet = CGRect(origin: layout.petOrigin, size: PetPanelLayout.petSize)
            let chat = CGRect(origin: layout.chatOrigin, size: PetPanelLayout.chatSize)
            XCTAssertTrue(canvas.contains(pet))
            XCTAssertTrue(canvas.contains(chat))
            XCTAssertFalse(pet.intersects(chat))
            switch position {
            case .right: XCTAssertGreaterThan(chat.minX, pet.maxX)
            case .left: XCTAssertLessThan(chat.maxX, pet.minX)
            case .above: XCTAssertLessThan(chat.maxY, pet.minY)
            case .below: XCTAssertGreaterThan(chat.minY, pet.maxY)
            }
        }
    }
    func testOpeningClosingAndChangingPositionPreservePetScreenAnchor() {
        let collapsed = PetPanelLayout(position: .right, expanded: false)
        let original = CGRect(x: 800, y: 700, width: 240, height: 330)
        var previous = collapsed, frame = original
        for position in ChatPanelPosition.allCases {
            let layout = PetPanelLayout(position: position, expanded: true)
            frame = layout.windowFrame(from: frame, previous: previous)
            XCTAssertEqual(frame.minX + layout.petOrigin.x, original.minX)
            XCTAssertEqual(frame.minY + layout.size.height - layout.petOrigin.y - PetPanelLayout.petSize.height, original.minY)
            previous = layout
        }
        XCTAssertEqual(collapsed.windowFrame(from: frame, previous: previous), original)
    }
    func testAllDirectionsStayWithinScreenEdges() {
        let area = CGRect(x: 100, y: 80, width: 1000, height: 900)
        let collapsed = PetPanelLayout(position: .right, expanded: false)
        for position in ChatPanelPosition.allCases {
            let layout = PetPanelLayout(position: position, expanded: true)
            for point in [CGPoint(x: 100, y: 80), CGPoint(x: 1050, y: 900)] {
                let old = CGRect(origin: point, size: PetPanelLayout.petSize)
                XCTAssertTrue(area.contains(layout.windowFrame(from: old, previous: collapsed, visibleFrame: area)))
            }
        }
    }
    func testReportLineBreaksAndInlineMarkdownArePreserved() throws {
        let source = "日期：2026-10-16\n时区：Asia/Shanghai\n**今天收入** 100 元\n\n快乐下班～"
        let blocks = MessageMarkdown.blocks(source)
        XCTAssertEqual(blocks.map(\.kind), [.paragraph("日期：2026-10-16\n时区：Asia/Shanghai\n**今天收入** 100 元"), .paragraph("快乐下班～")])
        let attributed = try AttributedString(markdown: "**加粗**、*斜体*、`代码`、[链接](https://example.com)", options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        XCTAssertEqual(String(attributed.characters), "加粗、斜体、代码、链接")
        XCTAssertTrue(attributed.runs.contains { $0.link?.absoluteString == "https://example.com" })
    }
    func testHeadingsListsQuotesAndRules() {
        XCTAssertEqual(MessageMarkdown.blocks("## 标题\n- **饮水**\n  1. 工作\n- [x] 已完成\n> 引用\n> 第二行\n\n---").map(\.kind), [
            .heading(level: 2, text: "标题"), .listItem(indent: 0, marker: "•", text: "**饮水**"),
            .listItem(indent: 2, marker: "1.", text: "工作"), .listItem(indent: 0, marker: "☑", text: "已完成"),
            .quote("引用\n第二行"), .rule
        ])
    }
    func testUnfinishedStreamedCodeFenceIsRenderedAsLiteralCode() {
        let partial = MessageMarkdown.blocks("```swift\nlet greeting = \"**你好**\"")
        let complete = MessageMarkdown.blocks("```swift\nlet greeting = \"**你好**\"\n```\n结束")
        XCTAssertEqual(partial.first?.kind, .code(language: "swift", text: "let greeting = \"**你好**\""))
        XCTAssertEqual(partial.first, complete.first)
        XCTAssertEqual(complete.last?.kind, .paragraph("结束"))
    }
    func testTablesRespectEscapedPipesAndInlineCode() {
        let source = "| 项目 | 值 |\n| :--- | ---: |\n| **饮水** | 1500 ml |\n| `a|b` | a\\|b |"
        XCTAssertEqual(MessageMarkdown.blocks(source).map(\.kind), [.table(headers: ["项目", "值"], rows: [["**饮水**", "1500 ml"], ["`a|b`", "a\\|b"]])])
    }
}
