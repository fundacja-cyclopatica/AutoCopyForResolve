# SD Card Organizer

Natywna aplikacja macOS (Swift + SwiftUI) do automatycznego zgrywania materiałów z kart SD
na wybrany dysk oraz przygotowania struktury katalogów i projektu DaVinci Resolve.

## Działanie

1. Aplikacja działa w tle — jej ikona (karta SD) jest w pasku menu przy zegarze.
2. Kliknięcie ikony wysuwa z prawej strony ekranu **panel** (jak widget) z podłączonymi
   kartami. Panel:
   - dopasowuje wysokość do liczby kart i płynnie się rozszerza po włożeniu kolejnej,
   - jest zawsze na wierzchu (także nad aplikacjami na pełnym ekranie i na każdym biurku),
   - chowa się po kliknięciu poza panelem, przyciskiem **Zamknij**, klawiszem Esc albo
     ponownym kliknięciem ikony,
   - przy większej liczbie kart niż mieści ekran przewija listę kart.
3. Włożenie karty automatycznie wysuwa panel i skanuje kartę.
4. W panelu wybierasz zakres dni, typy materiałów, podpis kamery, dysk docelowy i nazwę
   projektu, a **Szybki zrzut** zgrywa materiał (z weryfikacją, postępem i możliwością
   anulowania).
5. Ikona zębatki w panelu (albo prawy klik na ikonie → „Ustawienia…” / „Historia zgrań…”)
   otwiera okno **Ustawienia** z dwiema zakładkami: ustawienia i historia zgrań.

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

## Uruchamianie i Instalator

```bash
# Bezpośrednio (bez pakietu .app):
swift run SDCardOrganizer

# Jako aplikacja .app (pełny pasek menu):
./Scripts/make-app.sh
open .build/SDCardOrganizer.app

# Utworzenie kompletnego instalatora dla testerów (DMG + PKG + ZIP w folderze dist/):
./Scripts/create-installer.sh
```

## Testy

```bash
# Szybki samodzielny runner (nie wymaga Xcode):
swift run SDCardOrganizerSelftest

# Pełne testy jednostkowe (wymaga pełnego Xcode):
swift test
```

## Praca z projektami

- Pole nazwy projektu w sekcji dysku docelowego ma listę projektów istniejących już na
  dysku — wybranie projektu (także z innego dnia) dogrywa do niego kolejne karty zamiast
  tworzyć nowy folder. Pod polem widać pełną ścieżkę, do której trafi materiał.
- Obok dysku docelowego widać wolne miejsce (na czerwono, gdy wybrane materiały się nie
  zmieszczą) albo informację, że dysk jest niedostępny.
- Gdy przycisk **Szybki zrzut** jest nieaktywny, pod podsumowaniem widać, czego brakuje.
- Skróty w panelu: ⌘↩ zgraj, ⌘R skanuj karty, Esc schowaj panel. W oknie ustawień:
  ⌘1 ustawienia, ⌘2 historia.

## Konfiguracja

Ustawienia przechowywane są w pliku:
`~/Library/Application Support/SDCardOrganizer/settings.json`

Można je zmieniać w oknie **Ustawienia** (ikona zębatki w panelu albo menu pod prawym
kliknięciem ikony w pasku menu):
- **Dysk docelowy** — folder, do którego trafią materiały.
- **Typy plików** — które rozszerzenia zgrywać (Wideo, Dźwięk, Zdjęcia i RAW). Podglądy DJI
  `.LRF` są domyślnie wyłączone; miniatury kamer (np. Sony `THMBNL`) są zawsze pomijane.
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
- Każda kopia jest domyślnie weryfikowana sumą kontrolną SHA-256: karta jest czytana raz
  (kopiowanie i liczenie sumy w jednym przebiegu), a zapisany plik jest odczytywany ponownie
  z dysku i porównywany z oryginałem. Opcję można wyłączyć w ustawieniach (Zaawansowane).
- Plik powstaje najpierw jako ukryty `.<nazwa>.part` i dostaje właściwą nazwę dopiero po
  udanym skopiowaniu i weryfikacji — przerwane zgrywanie nie zostawia niepełnych plików.
- W trakcie zgrywania widać postęp w bajtach, bieżącą prędkość i szacowany czas do końca;
  zgrywanie można przerwać przyciskiem **Anuluj** (lub Esc) — bieżący plik jest porzucany bez
  śladu, a już skopiowane zostają. Po zakończeniu pojawia się podsumowanie z listą błędów
  oraz przyciskami „Pokaż w Finderze” i „Wysuń karty” (aktywnym tylko po zgraniu bez błędów).
- Błąd pojedynczego pliku nie przerywa zgrywania; pliki, których nie udało się zgrać, są
  pokazywane na karcie i liczone w historii.
- Można wielokrotnie zgrywać do tego samego projektu tego samego dnia — istniejący plik
  `.drp` nie jest nadpisywany.
- Deduplikacja domyślnie porównuje rozmiar i datę modyfikacji pliku; opcjonalnie można
  włączyć porównanie checksum SHA-256 (wolniejsze, ale pewniejsze). Sprawdzane są też kopie
  zapisane wcześniej pod nazwą z sufiksem (`nazwa_1.ext`), więc ponowne zgranie tej samej
  karty niczego nie duplikuje.
- Gdy dwie karty zawierają pliki o identycznych nazwach, ale różnej zawartości, aplikacja
  tworzy unikalną nazwę (`nazwa_1.ext`, `nazwa_2.ext`, …).
