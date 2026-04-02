import SwiftUI

struct DashboardEmptyState: View {
    let systemName: String
    let title: String
    var subtitle: String? = nil
    var iconSize: CGFloat = 30
    var subtitleMaxWidth: CGFloat? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(TrabantTheme.accentLight)
                .frame(height: 42)

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TrabantTheme.primaryText)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(TrabantTheme.secondaryText)
                    .frame(maxWidth: subtitleMaxWidth)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
