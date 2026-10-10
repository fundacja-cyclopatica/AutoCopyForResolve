import SwiftUI

/// Paleta wysuwanego panelu z paska menu (projekt `Design/menu_bar_widget`).
enum PanelTheme {
    /// Szerokość panelu w punktach.
    static let width: CGFloat = 520

    // Akcent (musztardowy) i jego poświata
    static let accent = Color(red: 249/255, green: 169/255, blue: 2/255)          // #F9A902

    // Tła
    static let backgroundTop = Color(red: 16/255, green: 17/255, blue: 20/255)    // #101114
    static let backgroundBottom = Color(red: 10/255, green: 11/255, blue: 13/255) // #0A0B0D
    static let card = Color(red: 22/255, green: 24/255, blue: 27/255)             // #16181B
    static let cardInner = Color(red: 15/255, green: 16/255, blue: 18/255)        // #0F1012
    static let chip = Color(red: 28/255, green: 30/255, blue: 34/255)             // #1C1E22
    static let tile = Color(red: 34/255, green: 36/255, blue: 40/255)             // #222428
    static let selectedButton = Color(red: 35/255, green: 38/255, blue: 44/255)   // #23262C
    static let destination = Color(red: 20/255, green: 21/255, blue: 24/255)      // #141518

    // Ramki
    static let border = Color(red: 34/255, green: 36/255, blue: 40/255)           // #222428
    static let borderStrong = Color(red: 45/255, green: 48/255, blue: 54/255)     // #2D3036
    static let selectedBorder = Color(red: 52/255, green: 56/255, blue: 66/255)   // #343842

    // Teksty
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 161/255, green: 161/255, blue: 170/255) // zinc-400
    static let textMuted = Color(red: 113/255, green: 113/255, blue: 122/255)     // zinc-500
    static let danger = Color(red: 255/255, green: 99/255, blue: 88/255)
    static let success = Color(red: 74/255, green: 222/255, blue: 128/255)
}
