import SwiftUI

/// Ayarlar on the phone: the Mac's settings pane with its tabs, under the screen title. Mac-only rows are hidden there.
struct MobileAyarlar: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ayarlar").font(.serif(25)).tracking(-0.4).padding(.screenHeader)
            SettingsPane(embedded: true)
        }
    }
}
