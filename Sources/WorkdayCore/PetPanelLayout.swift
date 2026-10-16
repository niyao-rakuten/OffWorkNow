import Foundation
import CoreGraphics

public enum ChatPanelPosition: String, Codable, CaseIterable {
    case right, left, above, below
    public var title: String {
        switch self {
        case .right: return L10n.text("右侧")
        case .left: return L10n.text("左侧")
        case .above: return L10n.text("上侧")
        case .below: return L10n.text("下侧")
        }
    }
}

/// Coordinates inside the SwiftUI canvas use a top-left origin.
public struct PetPanelLayout: Equatable {
    public static let petSize = CGSize(width: 240, height: 330)
    public static let chatSize = CGSize(width: 344, height: 294)
    public let size: CGSize
    public let petOrigin: CGPoint
    public let chatOrigin: CGPoint
    public init(position: ChatPanelPosition, expanded: Bool) {
        let gap: CGFloat = 8
        if !expanded {
            size = Self.petSize; petOrigin = .zero
            switch position {
            case .right: chatOrigin = CGPoint(x: Self.petSize.width + gap, y: 4)
            case .left: chatOrigin = CGPoint(x: -Self.chatSize.width - gap, y: 4)
            case .above: chatOrigin = CGPoint(x: (Self.petSize.width - Self.chatSize.width) / 2, y: -Self.chatSize.height - gap)
            case .below: chatOrigin = CGPoint(x: (Self.petSize.width - Self.chatSize.width) / 2, y: Self.petSize.height + gap)
            }
            return
        }
        switch position {
        case .right:
            size = CGSize(width: Self.petSize.width + gap + Self.chatSize.width, height: Self.petSize.height)
            petOrigin = .zero; chatOrigin = CGPoint(x: Self.petSize.width + gap, y: 4)
        case .left:
            size = CGSize(width: Self.petSize.width + gap + Self.chatSize.width, height: Self.petSize.height)
            petOrigin = CGPoint(x: Self.chatSize.width + gap, y: 0); chatOrigin = CGPoint(x: 0, y: 4)
        case .above:
            size = CGSize(width: Self.chatSize.width, height: Self.chatSize.height + gap + Self.petSize.height)
            petOrigin = CGPoint(x: (Self.chatSize.width - Self.petSize.width) / 2, y: Self.chatSize.height + gap)
            chatOrigin = .zero
        case .below:
            size = CGSize(width: Self.chatSize.width, height: Self.petSize.height + gap + Self.chatSize.height)
            petOrigin = CGPoint(x: (Self.chatSize.width - Self.petSize.width) / 2, y: 0)
            chatOrigin = CGPoint(x: 0, y: Self.petSize.height + gap)
        }
    }
    /// Native window frames use a bottom-left origin. Preserve the pet's screen position.
    public func windowFrame(from frame: CGRect, previous: PetPanelLayout, visibleFrame: CGRect? = nil) -> CGRect {
        let petX = frame.minX + previous.petOrigin.x
        let petY = frame.minY + previous.size.height - previous.petOrigin.y - Self.petSize.height
        var result = CGRect(x: petX - petOrigin.x,
            y: petY - size.height + petOrigin.y + Self.petSize.height, width: size.width, height: size.height)
        if let area = visibleFrame {
            result.origin.x = min(max(result.minX, area.minX), max(area.minX, area.maxX - size.width))
            result.origin.y = min(max(result.minY, area.minY), max(area.minY, area.maxY - size.height))
        }
        return result
    }
}
