# SD Card Organizer

Natywna aplikacja macOS (Swift + SwiftUI) do automatycznego zgrywania materiałów z kart SD
na wybrany dysk oraz przygotowania struktury katalogów i projektu DaVinci Resolve.

## Działanie

1. Aplikacja działa w tle (ikona w pasku menu).
2. Po włożeniu karty SD do czytnika wykrywa nośnik i pokazuje go w oknie/pasku menu.
3. Po kliknięciu **„Zgraj"** aplikacja:
   - pyta o nazwę projektu,
   - skanuje kartę pod kątem wybranych typów plików,
   - kopiuje materiały z pomijaniem duplikatów,
   - tworzy strukturę katalogów i plik projektu DaVinci Resolve.

## Struktura katalogów

```
<dysk_docelowy>/<YYYY-MM-DD>_<NazwaProjektu>/
  ├── Video/
  ├── Audio/
  ├── Zdjęcia/
  └── DaVinci/
      ├── <YYYY-MM-DD>_<NazwaProjektu>.drp
      └── project_manifest.json
```

## Wymagania

- macOS 13 (Ventura) lub nowszy
- Xcode lub CommandLineTools (do kompilacji)

## Budowanie

```bash
swift build
```

## Uruchamianie

```bash
# Bezpośrednio (bez pakietu .app):
swift run SDCardOrganizer

# Jako aplikacja .app (pełny pasek menu):
./Scripts/make-app.sh
open .build/SDCardOrganizer.app
```

## Testy

```bash
# Szybki samodzielny runner (nie wymaga Xcode):
swift run SDCardOrganizerSelftest

# Pełne testy jednostkowe (wymaga pełnego Xcode):
swift test
```

## Konfiguracja

Ustawienia przechowywane są w pliku:
`~/Library/Application Support/SDCardOrganizer/settings.json`

Można je zmieniać w oknie **Ustawienia**:
- **Dysk docelowy** — folder, do którego trafią materiały.
- **Typy plików** — które rozszerzenia zgrywać (Wideo, Dźwięk, Zdjęcia i RAW).
- **Projekt DaVinci Resolve** — rozdzielczość (np. `1920x1080`), liczba klatek (25 fps),
  opcjonalny wzorcowy plik `.drp`.

## Plik projektu DaVinci Resolve (`.drp`)

Format `.drp` nie jest publicznie udokumentowany przez Blackmagic Design, dlatego aplikacja
**nie generuje go od zera**. Zamiast tego:

- Jeżeli w ustawieniach podasz wzorcowy plik `.drp` (wyeksportowany wcześniej z DaVinci Resolve
  z żądanymi ustawieniami), zostanie on skopiowany do folderu `DaVinci/` i nazwany wg projektu.
- Zawsze tworzony jest plik `project_manifest.json` z metadanymi projektu (nazwa, rozdzielczość,
  liczba klatek, data, struktura katalogów).

> Wskazówka: wyeksportuj raz pusty projekt o docelowych ustawieniach z DaVinci Resolve
> (File → Export Project) i wskaż go jako szablon w ustawieniach.

## Uprawnienia macOS

Aplikacja wymaga dostępu do nośników wymiennych. Przy pierwszym uruchomieniu macOS może
poprosić o:
- **Full Disk Access** (Preferencje systemowe → Prywatność i bezpieczeństwo) — do odczytu kart
  SD i zapisu na dyski zewnętrzne,
- dostęp do folderów dokumentów, jeśli dysk docelowy znajduje się w chronionej lokalizacji.

## Struktura kodu

```
Sources/
  SDCardOrganizerCore/    # logika czysta: ustawienia, filtr typów, skaner, deduplikacja,
                          # budowa ścieżek, kopiowanie, generator projektu
  SDCardOrganizer/        # aplikacja: pasek menu, monitor wolumenów, widoki SwiftUI
  SDCardOrganizerSelftest/ # lekki runner testowy (bez Xcode)
Tests/
  SDCardOrganizerCoreTests/ # testy jednostkowe XCTest
```

## Uwagi

- Karty exFAT/FAT32: FAT32 nie obsługuje plików > 4 GB.
- Deduplikacja domyślnie porównuje rozmiar pliku; opcjonalnie można włączyć weryfikację
  checksum SHA-256 (wolniejsze, ale pewniejsze).
- Gdy dwie karty zawierają pliki o identycznych nazwach, ale różnej zawartości, aplikacja
  tworzy unikalną nazwę (`nazwa_1.ext`, `nazwa_2.ext`, …).
