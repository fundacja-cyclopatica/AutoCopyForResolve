import Foundation
import AppKit

/// Narzędzia do zarządzania nośnikami wymiennymi.
public struct VolumeManager {
    /// Bezpiecznie wysuwa nośnik (odmontowuje i wysuwa z czytnika).
    public static func eject(url: URL) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: url)
    }
}
