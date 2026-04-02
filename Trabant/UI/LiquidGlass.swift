import SwiftUI

struct LiquidGlassBackground: View {
    let cornerRadius: CGFloat
    let strokeOpacity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(TrabantTheme.glassPanelFill))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(TrabantTheme.glassPanelBorder.opacity(strokeOpacity / 0.18), lineWidth: 1)
            }
            .shadow(color: TrabantTheme.glassShadow, radius: 18, y: 10)
    }
}

private struct LiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let strokeOpacity: Double

    func body(content: Content) -> some View {
        content.background {
            LiquidGlassBackground(
                cornerRadius: cornerRadius,
                strokeOpacity: strokeOpacity
            )
        }
    }
}

extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = 22,
        strokeOpacity: Double = 0.18
    ) -> some View {
        modifier(
            LiquidGlassCardModifier(
                cornerRadius: cornerRadius,
                strokeOpacity: strokeOpacity
            )
        )
    }
}
