import SwiftUI

/// Compact illustrated controls; live text keeps time, counts and accessibility accurate.
struct PetControls: View {
    let time: String
    let timeDescription: String
    let cups: Int
    let cupVolume: Int
    let totalML: Int
    let overtime: Bool
    let openSettings: () -> Void
    let drink: () -> Void
    let undoDrink: () -> Void

    private let ink = Color(red: 0.29, green: 0.20, blue: 0.14)
    var body: some View {
        HStack(spacing: 6) {
            Button(action: drink) {
                HStack(spacing: 2) {
                    PetControlImage(asset: .cup).frame(width: 33, height: 33)
                    Text("×\(cups)").font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit().foregroundStyle(ink)
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Color(red: 1, green: 0.96, blue: 0.86).opacity(0.95), in: Capsule())
                }
                .frame(width: 66, height: 36).contentShape(Capsule())
            }
            .accessibilityLabel("喝一杯水，\(cupVolume)毫升")
            .accessibilityValue("今天\(cups)杯，共\(totalML)毫升")
            .help("喝一杯 +\(cupVolume) ml · 今天共 \(totalML) ml")
            .contextMenu { Button("撤销上一杯", action: undoDrink).disabled(cups == 0) }

            Button(action: openSettings) {
                Text(time)
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(overtime ? Color(red: 0.67, green: 0.26, blue: 0.15) : ink)
                    .frame(width: 166, height: 44)
                    .background { PetControlImage(asset: .clock) }
                    .contentShape(Capsule())
            }
            .accessibilityLabel(timeDescription)
            .accessibilityHint("打开时间与提醒设置")
            .help(timeDescription + " · 点击设置")
        }
        .buttonStyle(PetPressStyle())
    }
}

/// Reserve the same footer height while hidden so the pet does not move at clock-out time.
struct PetCheckoutButton: View {
    let visible: Bool
    let checkout: () -> Void
    var body: some View {
        ZStack {
            if visible {
                Button(action: checkout) {
                    Text("打卡下班")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.29, green: 0.20, blue: 0.14))
                        .padding(.leading, 10)
                        .frame(width: 111, height: 36)
                        .background { PetControlImage(asset: .checkout) }
                        .contentShape(Capsule())
                }
                .buttonStyle(PetPressStyle())
                .accessibilityHint("记录今天下班并停止当天提醒")
                .help("打卡下班，停止今天的提醒")
            }
        }.frame(width: 111, height: 36)
    }
}

private struct PetPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
