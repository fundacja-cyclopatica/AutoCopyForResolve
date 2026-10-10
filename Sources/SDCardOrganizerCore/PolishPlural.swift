import Foundation

/// Odmiana rzeczowników po liczebnikach w języku polskim:
/// 1 plik, 2–4 pliki (poza 12–14), 0 i 5+ plików.
public enum PolishPlural {
    public static func format(_ count: Int, one: String, few: String, many: String) -> String {
        "\(count) \(form(count, one: one, few: few, many: many))"
    }

    public static func form(_ count: Int, one: String, few: String, many: String) -> String {
        let n = abs(count)
        if n == 1 { return one }
        let lastDigit = n % 10
        let lastTwoDigits = n % 100
        if (2...4).contains(lastDigit) && !(12...14).contains(lastTwoDigits) {
            return few
        }
        return many
    }

    public static func files(_ count: Int) -> String {
        format(count, one: "plik", few: "pliki", many: "plików")
    }

    public static func cards(_ count: Int) -> String {
        format(count, one: "karta", few: "karty", many: "kart")
    }

    public static func photos(_ count: Int) -> String {
        format(count, one: "zdjęcie", few: "zdjęcia", many: "zdjęć")
    }

    public static func errors(_ count: Int) -> String {
        format(count, one: "błąd", few: "błędy", many: "błędów")
    }
}
