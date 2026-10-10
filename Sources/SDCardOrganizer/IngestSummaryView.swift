import SwiftUI
import SDCardOrganizerCore

/// Arkusz z wynikami zakończonej sesji zgrywania: co skopiowano, co pominięto,
/// które pliki się nie udały oraz akcje „Pokaż w Finderze” i „Wysuń karty”.
struct IngestSummaryView: View {
    let session: IngestSessionSummary
    let onRevealInFinder: () -> Void
    let onEjectCards: () -> Void
    let onClose: () -> Void

    private var accent: Color {
        if session.wasCancelled { return StudioTheme.accentAmber }
        return session.failures.isEmpty ? StudioTheme.accentGreen : StudioTheme.accentRed
    }

    private var title: String {
        if session.wasCancelled { return "Zgrywanie anulowane" }
        return session.failures.isEmpty ? "Zgrywanie zakończone" : "Zgrywanie zakończone z błędami"
    }

    private var subtitle: String {
        if session.wasCancelled {
            return "Pliki skopiowane przed przerwaniem zostały w projekcie. Karty nie są zgrane w całości."
        }
        if !session.failures.isEmpty {
            return "Nie formatuj kart, dopóki nie zgrasz brakujących plików."
        }
        return session.verificationEnabled
            ? "Wszystkie kopie zweryfikowane sumą kontrolną — karty można bezpiecznie wysunąć."
            : "Wszystkie pliki skopiowane. Weryfikacja sum kontrolnych była wyłączona."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statsGrid
            if !session.failures.isEmpty {
                failuresList
            }
            perCardList
            actions
        }
        .padding(20)
        .frame(width: 520)
        .background(StudioTheme.panelBg)
    }

    // MARK: – Sekcje

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: session.wasCancelled
                  ? "stop.circle.fill"
                  : (session.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                .font(.system(size: 28))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
                Text("Projekt „\(session.projectName)”")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 10) {
            statTile(value: "\(session.totalCopied)", label: "skopiowano", color: StudioTheme.accentCyan)
            if session.verificationEnabled {
                statTile(value: "\(session.totalVerified)", label: "zweryfikowano", color: StudioTheme.accentGreen)
            }
            statTile(value: "\(session.totalSkipped)", label: "duplikaty pominięte", color: Color.gray)
            statTile(
                value: "\(session.failures.count)",
                label: "błędy",
                color: session.failures.isEmpty ? Color.gray : StudioTheme.accentRed
            )
            statTile(
                value: AppModel.formatBytes(session.totalBytes),
                label: session.averageBytesPerSecond.map {
                    "w \(AppModel.formatDuration(session.duration)) • \(AppModel.formatBytes(Int64($0)))/s"
                } ?? "w \(AppModel.formatDuration(session.duration))",
                color: Color.white
            )
        }
    }

    private func statTile(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.gray)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.35))
        .cornerRadius(8)
    }

    private var failuresList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pliki, których nie zgrano")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StudioTheme.accentRed)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(session.failures.enumerated()), id: \.offset) { _, failure in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(failure.url.lastPathComponent)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.white)
                            Text(failure.error)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.gray)
                                .lineLimit(2)
                        }
                        .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
        .padding(10)
        .background(StudioTheme.accentRed.opacity(0.08))
        .cornerRadius(8)
    }

    private var perCardList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(session.cards) { card in
                HStack {
                    Image(systemName: card.isManual ? "folder.fill" : "sdcard.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.gray)
                    Text(card.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                    Spacer()
                    Text("\(card.report.totalCopied) skop. • \(card.report.totalSkipped) pomin. • \(PolishPlural.errors(card.report.totalFailed))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(card.report.totalFailed > 0 ? StudioTheme.accentRed : Color.gray)
                }
            }
            Text(session.destination.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color.gray.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 2)
        }
    }

    private var actions: some View {
        HStack {
            Button("Pokaż w Finderze", action: onRevealInFinder)

            if session.cards.contains(where: { !$0.isManual }) {
                Button("Wysuń karty", action: onEjectCards)
                    .disabled(!session.isSafeToEject)
                    .help(session.isSafeToEject
                          ? "Bezpiecznie wysuń karty zgrane w tej sesji"
                          : "Nie wszystkie pliki zostały zgrane — sprawdź błędy przed wysunięciem kart")
            }

            Spacer()

            Button("Gotowe", action: onClose)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
    }
}
