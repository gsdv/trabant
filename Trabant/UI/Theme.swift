import SwiftUI

enum TrabantTheme {
    // Backgrounds
    static let windowBackground = Color(red: 0.055, green: 0.060, blue: 0.074)
    static let panelBackground = Color(red: 0.090, green: 0.100, blue: 0.126)
    static let cardBackground = Color(red: 0.122, green: 0.132, blue: 0.163)
    static let selectedBackground = Color(red: 0.165, green: 0.220, blue: 0.305)
    static let hoverBackground = Color(red: 0.125, green: 0.145, blue: 0.185)

    // Dashboard Backdrop
    static let dashboardBackdropTop = Color(red: 0.095, green: 0.108, blue: 0.150)
    static let dashboardBackdropBottom = Color(red: 0.046, green: 0.053, blue: 0.070)
    static let dashboardGlowPrimary = Color(red: 0.22, green: 0.50, blue: 0.92)
    static let dashboardGlowSecondary = Color(red: 0.35, green: 0.63, blue: 0.98)
    static let dashboardGlowTertiary = Color(red: 0.56, green: 0.80, blue: 1.00)

    // Titlebar
    static let titleBarBackgroundTop = Color(red: 0.165, green: 0.185, blue: 0.225)
    static let titleBarBackgroundBottom = Color(red: 0.092, green: 0.104, blue: 0.138)
    static let titleBarControlBackground = Color.white.opacity(0.085)
    static let titleBarControlBorder = Color.white.opacity(0.12)
    static let titleBarHighlight = Color.white.opacity(0.10)
    static let titleBarSelection = Color(red: 0.40, green: 0.67, blue: 0.98)
    static let toolbarChipBackground = Color(red: 0.18, green: 0.19, blue: 0.23).opacity(0.92)
    static let toolbarChipBorder = Color.white.opacity(0.14)
    static let toolbarButtonBackground = Color(red: 0.12, green: 0.13, blue: 0.16).opacity(0.96)
    static let toolbarButtonBorder = Color.white.opacity(0.08)
    static let sidebarContainerBackground = Color(red: 0.16, green: 0.17, blue: 0.20).opacity(0.88)
    static let sidebarContainerBorder = Color.white.opacity(0.10)
    static let glassShadow = Color.black.opacity(0.28)
    static let glassPanelBorder = Color.white.opacity(0.16)
    static let glassPanelFill = Color.white.opacity(0.025)
    static let sidebarBadgeFill = Color.white.opacity(0.10)
    static let sidebarBadgeText = Color(red: 0.78, green: 0.90, blue: 1.00)
    static let sidebarRowFill = Color.white.opacity(0.028)
    static let sidebarRowBorder = Color.white.opacity(0.06)
    static let sidebarRowSelectedFill = Color(red: 0.32, green: 0.52, blue: 0.86).opacity(0.24)
    static let sidebarRowSelectedBorder = Color(red: 0.54, green: 0.76, blue: 1.00).opacity(0.38)
    static let sidebarIconFill = Color.white.opacity(0.08)

    // Text
    static let primaryText = Color(white: 0.90)
    static let secondaryText = Color(white: 0.55)
    static let dimText = Color(white: 0.35)

    // Accents
    static let accent = Color(red: 0.37, green: 0.63, blue: 0.98)
    static let accentLight = Color(red: 0.62, green: 0.82, blue: 1.00)

    // Status
    static let statusGreen = Color(red: 0.30, green: 0.75, blue: 0.45)
    static let statusOrange = Color(red: 0.90, green: 0.60, blue: 0.20)
    static let statusRed = Color(red: 0.90, green: 0.30, blue: 0.30)
    static let statusBlue = Color(red: 0.40, green: 0.60, blue: 0.90)

    // Separator
    static let separator = Color(white: 0.20)
    static let cardBorder = Color.white.opacity(0.06)

    // Methods
    static let methodGET = Color(red: 0.40, green: 0.70, blue: 0.40)
    static let methodPOST = Color(red: 0.50, green: 0.50, blue: 0.90)
    static let methodPUT = Color(red: 0.80, green: 0.60, blue: 0.30)
    static let methodDELETE = Color(red: 0.85, green: 0.35, blue: 0.35)
    static let methodOther = Color(white: 0.55)

    static func colorForMethod(_ method: String) -> Color {
        switch method.uppercased() {
        case "GET": return methodGET
        case "POST": return methodPOST
        case "PUT", "PATCH": return methodPUT
        case "DELETE": return methodDELETE
        default: return methodOther
        }
    }

    static func colorForStatus(_ code: Int?) -> Color {
        guard let code else { return dimText }
        switch code {
        case 200..<300: return statusGreen
        case 300..<400: return statusBlue
        case 400..<500: return statusOrange
        case 500..<600: return statusRed
        default: return dimText
        }
    }

    static let monoFont = Font.system(.body, design: .monospaced)
    static let monoSmall = Font.system(.caption, design: .monospaced)
}
