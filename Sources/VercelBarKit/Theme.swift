import AppKit

/// Kolory z makiet Claude Design — pary jasny/ciemny jako NSColor dynamiczne.
public enum Theme {

    public static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    public static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: alpha)
    }

    // Kolory stanów (kropka, badge, ikona) — wartości wprost z makiet.
    public static let ready = dynamicColor(light: hex(0x1d7f38), dark: hex(0x30d158))
    public static let building = dynamicColor(light: hex(0x0064e0), dark: hex(0x0a84ff))
    public static let error = dynamicColor(light: hex(0xd70015), dark: hex(0xff453a))
    public static let gray = dynamicColor(light: hex(0x8e8e93), dark: hex(0x98989d))

    public static let badgeReadyBg = dynamicColor(light: hex(0x1d7f38, alpha: 0.10), dark: hex(0x30d158, alpha: 0.15))
    public static let badgeBuildingBg = dynamicColor(light: hex(0x0064e0, alpha: 0.10), dark: hex(0x0a84ff, alpha: 0.17))
    public static let badgeErrorBg = dynamicColor(light: hex(0xd70015, alpha: 0.09), dark: hex(0xff453a, alpha: 0.17))
    public static let badgeQueuedFg = dynamicColor(light: hex(0x6e6e73), dark: hex(0x98989d))
    public static let badgeQueuedBg = dynamicColor(light: NSColor(srgbRed: 60/255, green: 60/255, blue: 67/255, alpha: 0.08),
                                                   dark: NSColor(srgbRed: 235/255, green: 235/255, blue: 245/255, alpha: 0.11))

    // Wiersz błędu i rozbłysk sukcesu — pary z makiet (jasny/ciemny różnią się nie tylko barwą, ale i alfą).
    public static let rowErrorBg = dynamicColor(light: hex(0xd70015, alpha: 0.055), dark: hex(0xff453a, alpha: 0.085))
    public static let rowErrorHoverBg = dynamicColor(light: hex(0xd70015, alpha: 0.085), dark: hex(0xff453a, alpha: 0.13))
    public static let rowErrorRing = dynamicColor(light: hex(0xd70015, alpha: 0.20), dark: hex(0xff453a, alpha: 0.24))
    public static let successFlash = dynamicColor(light: hex(0x1d7f38, alpha: 0.16), dark: hex(0x30d158, alpha: 0.20))

    // Powierzchnie neutralne — makieta rozróżnia motywy, więc nie Color.primary.opacity.
    public static let rowHoverBg = dynamicColor(light: hex(0x000000, alpha: 0.045), dark: hex(0xffffff, alpha: 0.065))
    public static let controlHoverBg = dynamicColor(light: hex(0x000000, alpha: 0.05), dark: hex(0xffffff, alpha: 0.07))
    public static let progressTrack = dynamicColor(light: hex(0x000000, alpha: 0.07), dark: hex(0xffffff, alpha: 0.10))
    public static let onboardingLogo = dynamicColor(light: hex(0x3c3c43, alpha: 0.28), dark: hex(0xebebf5, alpha: 0.28))

    // Pasek aktualizacji nad stopką — ten sam błękit co „buduje się", ale ledwo widoczny,
    // żeby informował, a nie krzyczał ponad wierszami deployów.
    public static let updateBarBg = dynamicColor(light: hex(0x0064e0, alpha: 0.07), dark: hex(0x0a84ff, alpha: 0.12))

    // Przycisk akcji onboardingu — makieta: czarny na jasnym, biały na ciemnym.
    public static let actionBg = dynamicColor(light: hex(0x1c1c1e), dark: hex(0xf2f2f7))
    public static let actionFg = dynamicColor(light: hex(0xfbfbfd), dark: hex(0x16161a))
}
