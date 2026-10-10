import SwiftUI

/// Widok wolnego slotu czytnika kart (karta 4 w siatce) zgodnie z projektem Studio.
struct EmptyCardSlotView: View {
    let onChooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Image(systemName: "plus.circle")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.gray)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.gray.opacity(0.8))
                    .frame(width: 6, height: 6)
                Text("Wolny slot czytnika")
                    .font(.caption.bold())
                    .foregroundStyle(Color.gray.opacity(0.9))
            }

            Text("Wsuń kolejną kartę SD/CFexpress, aby automatycznie wykryć materiał")
                .font(.caption2)
                .foregroundStyle(Color.gray.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 160)
                .lineSpacing(2)

            Button {
                onChooseFolder()
            } label: {
                Text("Wybierz folder ręcznie")
                    .font(.caption2.bold())
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.secondary)
            .padding(.top, 4)

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 460)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(Color.white.opacity(0.12))
        )
    }
}
