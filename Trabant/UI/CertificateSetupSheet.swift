import SwiftUI

struct CertificateSetupWindow: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        CertificateView()
            .frame(minWidth: 980, minHeight: 760)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TrabantTheme.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background {
                                LiquidGlassBackground(cornerRadius: 10, strokeOpacity: 0.18)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
    }
}
