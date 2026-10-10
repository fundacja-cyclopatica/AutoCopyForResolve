import Foundation

/// Prędkość przesyłu liczona jako średnia z ostatnich kilku sekund, dzięki czemu
/// pojedyncze skoki (mały plik, pauza karty) nie szarpią wyświetlanym czasem do końca.
public struct TransferRateMeter {
    private var samples: [(time: TimeInterval, bytes: Int64)] = []
    /// Długość okna uśredniania w sekundach.
    public let window: TimeInterval

    public init(window: TimeInterval = 5) {
        self.window = window
    }

    /// Dodaje próbkę: łączną liczbę przesłanych bajtów w chwili `time` (np. `systemUptime`).
    public mutating func add(totalBytes: Int64, at time: TimeInterval) {
        samples.append((time, totalBytes))
        // Zostaw jedną próbkę sprzed początku okna, żeby okno było pełne.
        while samples.count > 2, samples[1].time <= time - window {
            samples.removeFirst()
        }
    }

    /// Bajty na sekundę albo `nil`, dopóki pomiar nie obejmuje co najmniej pół sekundy.
    public var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let elapsed = last.time - first.time
        guard elapsed >= 0.5 else { return nil }
        return Double(last.bytes - first.bytes) / elapsed
    }

    /// Szacowany czas do końca przy bieżącej prędkości.
    public func secondsRemaining(forRemainingBytes remaining: Int64) -> Double? {
        guard let rate = bytesPerSecond, rate > 0 else { return nil }
        return Double(max(0, remaining)) / rate
    }
}
