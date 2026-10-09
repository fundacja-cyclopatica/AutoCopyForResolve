import SwiftUI
import AppKit

/// Menu z paska menu — szybki dostęp do najważniejszych akcji.
struct MenuBarMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SD Card Organizer")
                .font(.headline)

            Divider()

            if model.volumeMonitor.removableVolumes.isEmpty {
                Text("Brak karty SD").foregroundStyle(.secondary)
            } else {
                Picker("Karta:", selection: $model.selectedVolume) {
                    ForEach(model.volumeMonitor.removableVolumes) { volume in
                        Text(volume.name).tag(Volume?.some(volume))
                    }
                }
                .frame(width: 200)
            }

            Divider()

            Button("Otwórz okno główne") {
                openWindow(id: "main")
            }

            Button("Zakończ") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(8)
    }
}
