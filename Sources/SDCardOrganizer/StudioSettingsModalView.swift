import SwiftUI
import SDCardOrganizerCore

/// Pływające studio okno ustawień (Floating Studio Settings Panel) zgodnie z projektem w code.html.
struct StudioSettingsModalView: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    let onOpenFullSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Specular border
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.3), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)

            // Pasek tytułowy okna ustawień
            HStack(spacing: 8) {
                Button {
                    onClose()
                } label: {
                    Circle()
                        .fill(Color(red: 255/255, green: 95/255, blue: 86/255))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color(red: 224/255, green: 68/255, blue: 62/255).opacity(0.6), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gray)
                    Text("SD Card Organizer Settings")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.gray.opacity(0.9))
                }

                Spacer()

                Button {
                    onOpenFullSettings()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.gray)
                }
                .buttonStyle(.plain)
                .help("Otwórz pełne ustawienia systemowe")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.5))

            Divider().overlay(Color.white.opacity(0.08))

            // Zawartość ustawień
            VStack(alignment: .leading, spacing: 14) {
                // Sekcja 1: Automatyczne otwieranie aplikacji
                VStack(alignment: .leading, spacing: 8) {
                    Text("AUTOMATYCZNE OTWIERANIE APLIKACJI PO ZGRANIU")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Color.gray.opacity(0.8))

                    // DaVinci Resolve Toggle
                    HStack {
                        HStack(spacing: 8) {
                            Text("Dv")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.white)
                                .frame(width: 22, height: 22)
                                .background(
                                    LinearGradient(
                                        colors: [Color.red, Color.orange, Color.blue],
                                        startPoint: .bottomLeading,
                                        endPoint: .topTrailing
                                    )
                                )
                                .cornerRadius(5)
                                .shadow(radius: 2)

                            Text("Otwórz projekt w DaVinci Resolve")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.9))
                        }

                        Spacer()

                        Toggle("", isOn: $model.settings.openInDaVinciResolve)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .tint(Color.orange)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))

                    // Adobe Lightroom Toggle
                    HStack {
                        HStack(spacing: 8) {
                            Text("Lr")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color(red: 49/255, green: 168/255, blue: 255/255))
                                .frame(width: 22, height: 22)
                                .background(Color(red: 0/255, green: 29/255, blue: 52/255))
                                .cornerRadius(5)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(red: 49/255, green: 168/255, blue: 255/255).opacity(0.5), lineWidth: 1))
                                .shadow(radius: 2)

                            Text("Otwórz folder zdjęć w Adobe Lightroom")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.9))
                        }

                        Spacer()

                        Toggle("", isOn: $model.settings.openInLightroom)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .tint(StudioTheme.accentBlue)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))

                    Text("Możesz również włączyć te opcje jednorazowo bezpośrednio przy przycisku zgrywania na dolnym pasku.")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.gray.opacity(0.7))
                        .lineSpacing(2)
                }

                Divider().overlay(Color.white.opacity(0.08))

                // Sekcja 2: Presety podpisów kamer („chmurki”)
                VStack(alignment: .leading, spacing: 8) {
                    Text("PRESETY PODPISÓW KAMER („CHMURKI”)")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Color.gray.opacity(0.8))

                    // Dodawanie
                    HStack(spacing: 6) {
                        TextField("Nowa etykieta (np. Sony FX3)", text: $model.newPresetInputText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))

                        Button {
                            model.addCameraPreset(model.newPresetInputText)
                            model.newPresetInputText = ""
                        } label: {
                            Text("Dodaj")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.12))
                                .foregroundStyle(Color.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.newPresetInputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    // Lista presetów
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(Array(model.settings.cameraPresets.enumerated()), id: \.offset) { index, preset in
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(StudioTheme.accentCyan)
                                        Text(preset)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.white.opacity(0.9))
                                    }

                                    Spacer()

                                    Button {
                                        model.removeCameraPreset(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Usuń preset")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.05), lineWidth: 1))
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }
            .padding(14)
        }
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 22/255, green: 26/255, blue: 36/255).opacity(0.98))
                .shadow(color: Color.black.opacity(0.9), radius: 30, x: 0, y: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
