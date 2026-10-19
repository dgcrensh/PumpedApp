import SwiftUI

/// The Night Shift look: near-black surfaces, one volt-green accent, and condensed heavy type for
/// names and numbers so they read at a glance between sets.
enum NightShift {
    static let background = Color(hex: 0x0B0C0E)
    /// Cards and grouped rows.
    static let surface = Color(hex: 0x16181C)
    /// Controls sitting on a surface.
    static let raised = Color(hex: 0x22252B)
    static let line = Color(hex: 0x2A2E35)
    static let text = Color(hex: 0xF2F3F5)
    static let muted = Color(hex: 0xA0A6B0)
    /// Quietest text that still reads on a surface (about 5:1).
    static let faint = Color(hex: 0x868C96)
    static let accent = Color(hex: 0xC8F31D)
    /// Text and icons on the accent.
    static let onAccent = background

    /// Condensed type for names, numbers and labels. Scales with Dynamic Type.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .heavy) -> Font {
        .system(style, weight: weight).width(.condensed)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// A small tracked, upper-case label, like "NEXT UP" or "TODAY".
struct NightShiftLabel: View {
    let text: String
    var color: Color = NightShift.muted

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// The volt button for the one main action on a screen: Start, Log set, Finish.
struct NightShiftPrimaryButtonStyle: ButtonStyle {
    /// Off for buttons that sit inline, like an empty state's action.
    var fillsWidth = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NightShift.display(.title3))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(NightShift.onAccent)
            .padding(.horizontal, 20)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: fillsWidth ? 56 : 44)
            .background(
                NightShift.accent.opacity(isEnabled ? 1 : 0.35),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A quiet outlined button for secondary actions next to a primary one.
struct NightShiftSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NightShift.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(NightShift.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(NightShift.line))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == NightShiftPrimaryButtonStyle {
    static var nightShiftPrimary: Self { .init() }
    static var nightShiftPrimaryInline: Self { .init(fillsWidth: false) }
}

extension ButtonStyle where Self == NightShiftSecondaryButtonStyle {
    static var nightShiftSecondary: Self { .init() }
}

extension View {
    /// A list or form on the Night Shift background instead of the system grouped gray.
    func nightShiftList() -> some View {
        scrollContentBackground(.hidden)
            .background(NightShift.background)
    }

    /// The app-wide look: dark, with the volt accent as the tint.
    func nightShiftTheme() -> some View {
        preferredColorScheme(.dark)
            .tint(NightShift.accent)
    }
}
