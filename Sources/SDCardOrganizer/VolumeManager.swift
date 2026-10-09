import Foundation
import AppKit

/// Narzędzia do zarządzania nośnikami wymiennymi (wysuwanie, zmiana nazwy).
public struct VolumeManager {
    /// Bezpiecznie wysuwa nośnik (odmontowuje i wysuwa z czytnika).
    public static func eject(url: URL) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: url)
    }

    /// Zmienia nazwę karty SD / wolumenu w systemie macOS.
    public static func renameVolume(at url: URL, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "VolumeManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Nowa nazwa karty nie może być pusta."]
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["rename", url.path, trimmed]

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Błąd diskutil"
            throw NSError(
                domain: "VolumeManager",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: output.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
    }
}
