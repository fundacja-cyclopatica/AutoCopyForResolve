import SwiftUI

/// Paleta i style wizualne inspirowane projektem "macOS Studio Dark Glass" (Design).
public enum StudioTheme {
    // Kolory tła i szkła
    public static let obsidian = Color(red: 10/255, green: 12/255, blue: 16/255)
    public static let glassBg = Color(red: 12/255, green: 15/255, blue: 20/255).opacity(0.85)
    public static let surface = Color(red: 20/255, green: 24/255, blue: 33/255).opacity(0.70)
    public static let cardBg = Color(red: 18/255, green: 22/255, blue: 30/255).opacity(0.92)
    public static let panelBg = Color(red: 22/255, green: 26/255, blue: 36/255).opacity(0.95)

    // Ramki i refleksy
    public static let border = Color.white.opacity(0.08)
    public static let borderBright = Color.white.opacity(0.16)

    // Akcenty kolorystyczne
    public static let accentCyan = Color(red: 0/255, green: 210/255, blue: 255/255) // #00D2FF
    public static let accentBlue = Color(red: 10/255, green: 132/255, blue: 255/255) // #0A84FF
    public static let accentGreen = Color(red: 48/255, green: 209/255, blue: 88/255) // #30D158
    public static let accentPurple = Color(red: 191/255, green: 90/255, blue: 242/255) // #BF5AF2
    public static let accentAmber = Color(red: 255/255, green: 159/255, blue: 10/255) // #FF9F0A
    public static let accentRed = Color(red: 255/255, green: 69/255, blue: 58/255) // #FF453A

    /// Zwraca unikalny kolor przewodni dla danego slotu karty
    public static func slotColor(for index: Int) -> Color {
        switch index % 4 {
        case 0: return accentBlue
        case 1: return accentGreen
        case 2: return accentPurple
        default: return accentAmber
        }
    }

    /// Etykieta slotu wyświetlana na karcie (np. „Slot 1”)
    public static func slotTag(for index: Int) -> String {
        "Slot \(index + 1)"
    }
}
