# Audyt aplikacji SD Card Organizer

Stan na commit `542cde3` (2026-10-09). Przejrzany cały kod: `SDCardOrganizerCore` (logika),
`SDCardOrganizer` (aplikacja/UI), testy, selftest i skrypty budowania.

> **Ograniczenie:** audyt jest statyczny (czytanie kodu). Środowisko audytu to Linux bez
> toolchaina Swift dla macOS (brak AppKit/CryptoKit), więc kod nie był kompilowany ani
> uruchamiany. Punkty oznaczone *(do potwierdzenia na Macu)* wynikają z wiedzy o zachowaniu
> macOS/SwiftUI i warto je sprawdzić ręcznie.

> **Status poprawek:** B1–B16 oraz błędy w obsłudze okien są naprawione (zob. historię gałęzi
> `claude/intelligent-keller-legdgb`). Pozostałe punkty czekają na realizację.

Priorytety: 🔴 krytyczne (utrata danych / crash / zablokowany główny scenariusz),
🟠 wysokie, 🟡 średnie, ⚪ niskie.

---

## 1. Backend — błędy

### ✅ 🔴 B1. Powtórne zgranie do tego samego projektu tego samego dnia kończy się błędem (gdy jest szablon `.drp`)
`ProjectBuilder.swift:51`. `FileManager.copyItem` rzuca błąd, gdy plik docelowy już istnieje.
Scenariusz: zgrywasz kartę A, nagrywasz dalej, zgrywasz jeszcze raz do projektu o tej samej
nazwie. Folder `2026-10-09_Nazwa` już istnieje, `.drp` też, więc `build()` rzuca wyjątek i
**nic się nie kopiuje**. Bez szablonu błędu nie ma, bo zapis z `.atomic` nadpisuje plik.
**Naprawa:** jeśli `.drp` istnieje, pomiń kopiowanie i nie nadpisuj go. Manifest aktualizuj,
nie zastępuj (teraz za każdym razem nadpisuje się `createdAt`).

### ✅ 🔴 B2. Błąd jednego pliku przerywa całe zgrywanie, a raport błędów nigdy nie jest wypełniany
`CopyService.swift:85` i `:90` używają `try copyFile(...)` bez `do/catch` w pętli.
Uszkodzony klip albo chwilowy błąd odczytu karty kończy całą sesję. Pozostałe pliki i
pozostałe karty nie są kopiowane, a wpis w historii nie powstaje. `report.failed`
(`CopyService.swift:25`) nie jest nigdzie uzupełniany, więc `filesFailed` zawsze wynosi 0, a
powiadomienie mówi „Zgrywanie zakończone **pomyślnie**” (`AppModel.swift:372`).
Dodatkowo przerwane kopiowanie może zostawić **niepełny plik** w miejscu docelowym. Przy
ponownym zgraniu ma on inny rozmiar, więc trafia do kopii jako `nazwa_1.ext`, a uszkodzony
`nazwa.ext` zostaje w projekcie *(do potwierdzenia na Macu)*.
**Naprawa:** łap błąd na poziomie pliku i dopisuj go do `report.failed`, a potem kontynuuj.
Kopiuj do pliku tymczasowego (`.nazwa.ext.part`) i rób `rename` dopiero po sukcesie. W UI
pokaż listę błędów.

### ✅ 🔴 B3. Brak weryfikacji integralności skopiowanych plików
Opcja „Weryfikuj checksum (SHA-256)” działa **tylko przy wykrywaniu duplikatów**
(`CopyPlanner.swift:54`). Po skopiowaniu nikt nie porównuje źródła z kopią. Dla narzędzia,
po którym ktoś sformatuje kartę, to najważniejsza brakująca funkcja. Każdy profesjonalny
offload (Hedge, ShotPut, Silverstack) robi weryfikację.
**Naprawa:** licz hash w trakcie kopiowania, w tym samym przebiegu odczytu, a potem
zweryfikuj kopię. Do weryfikacji lepszy jest xxHash64 (wielokrotnie szybszy od SHA-256).
Opcjonalnie zapisuj manifest MHL.

### ✅ 🔴 B4. Starsze `settings.json` po aktualizacji aplikacji kasuje się do wartości domyślnych
`Settings.swift:4` używa syntetyzowanego `Codable`, a pola `cameraPresets`,
`openInDaVinciResolve` i `openInLightroom` dodano później (commit `4a0390a`). Dekodowanie
starego pliku się nie udaje, `SettingsStore.load` (`Settings.swift:83`) po cichu zwraca
`Settings()`, a pierwszy `didSet` **nadpisuje plik użytkownika domyślnymi**. Znika dysk
docelowy, szablon `.drp` i typy plików. Ten sam problem wróci przy każdym nowym polu.
**Naprawa:** własny `init(from:)` z `decodeIfPresent` i wartościami domyślnymi. Przy błędzie
dekodowania zrób kopię zapasową uszkodzonego pliku, zamiast go nadpisywać.

### ✅ 🟠 B5. Deduplikacja porównuje tylko z oryginalną nazwą, więc ponowne zgranie tworzy duplikaty
`CopyPlanner.swift:27-39`. Jeśli przy pierwszym zgraniu plik dostał nazwę `clip_1.mov` (bo
`clip.mov` z innej kamery już był), przy kolejnym zgraniu porównanie idzie tylko z
`clip.mov`. Wynik: inna zawartość, więc powstaje nowa kopia `clip_2.mov`. Każde ponowne
zgranie tej samej karty mnoży pliki.
**Naprawa:** sprawdzaj też `nazwa_N.ext` albo trzymaj w folderze projektu indeks
(nazwa źródłowa + rozmiar + data/hash → plik docelowy).

### ✅ 🟠 B6. Duplikat rozpoznawany tylko po rozmiarze (domyślnie)
`CopyPlanner.swift:48-61`. Ta sama nazwa i ten sam rozmiar są traktowane jako ten sam plik.
Przy kodekach o stałym bitrate (BRAW, ProRes, WAV) dwa różne ujęcia o tej samej długości i
nazwie (np. po sformatowaniu karty numeracja startuje od nowa) mają ten sam rozmiar. Drugi
plik zostanie wtedy **pominięty, czyli utracony**.
**Naprawa:** porównuj co najmniej rozmiar i datę modyfikacji, a najlepiej szybki hash
(xxHash) pierwszych i ostatnich MB.

### ✅ 🟠 B7. Uruchomienie przez `swift run SDCardOrganizer` (jak w README) kończy się crashem
`AppModel.swift:56`. `UNUserNotificationCenter.current()` w procesie bez bundle'a `.app`
rzuca `NSInternalInconsistencyException` („bundleProxyForCurrentProcess is nil”).
**Naprawa:** wywołuj tylko, gdy `Bundle.main.bundleIdentifier != nil`, albo popraw README.

### ✅ 🟠 B8. Przy starcie z kilkoma włożonymi kartami skanowana jest tylko pierwsza
`AppModel.swift:169-192`. Przy pierwszym odczycie wszystkie karty są „nowe”, ale skanowana
jest tylko `newIDs.first`. Gałąź `else`, która skanuje resztę, wtedy się nie wykona.
Pozostałe karty pokazują „Brak pasujących plików” do czasu ręcznego „Skanuj karty”. Ten
sam problem występuje, gdy dwie karty zamontują się w jednym odświeżeniu.
**Naprawa:** skanuj wszystkie `newIDs`, a powiadomienie wysyłaj tylko dla kart włożonych
po starcie.

### ✅ 🟠 B9. Ręcznie dodany folder znika po każdej zmianie wolumenów
`AppModel.swift:147-166`. Lista `cardConfigs` jest budowana od nowa wyłącznie z
zamontowanych wolumenów, więc konfiguracja dodana przez „Wybierz folder ręcznie” jest
usuwana, gdy włożysz lub wysuniesz dowolną kartę.
**Naprawa:** oznacz źródła ręczne (`isManual`) i zachowuj je przy przebudowie listy.

### ✅ 🟠 B10. Wyścigi wątków i ryzyko crasha „Index out of range”
- `AppModel.swift:301` czyta `self.cardConfigs` z wątku w tle, a wątek główny w tym samym
  czasie je modyfikuje. To wyścig danych na tablicy Swift.
- `AppModel.swift:303-306` używa indeksu `cardIdx` policzonego w tle wewnątrz
  `main.async`. Jeśli w międzyczasie karta zniknie z listy (wysunięcie, odłączenie), dostęp
  wypada poza zakres i aplikacja się wywraca albo aktualizuje złą kartę.
- `MainWindow.swift:298-300` używa `ForEach(indices)` z `$model.cardConfigs[index]`. To
  znany wzorzec, który w SwiftUI wywraca aplikację przy usunięciu elementu (wysunięcie karty).
- `scanCard`/`startBatchCopy` czytają `self.settings` z wątku w tle.

**Naprawa:** przed startem zrób na wątku głównym migawkę wszystkiego, czego potrzebuje
wątek w tle (pliki, etykiety, ustawienia), a karty aktualizuj zawsze po `id`, nie po
indeksie. W `ForEach` iteruj po `cardConfigs` z `id: \.id` i twórz binding przez wyszukanie
po `id`. Docelowo: `@MainActor` dla `AppModel` i `async/await`.

### ✅ 🟡 B11. Odznaczenie wszystkich dni powoduje zgranie *wszystkiego*
`CardIngestConfig.swift:74-76`. Pusta `selectedDays` oznacza „wszystkie pliki”. Gdy
użytkownik odznaczy ostatni dzień, przycisk dalej pokazuje „Zgraj (N plików)”, a segment
„Wszystkie” się podświetla (`CardColumnView.swift:333`). Komentarz w linii 23 opisuje
odwrotne zachowanie. **Naprawa:** pusta selekcja oznacza 0 plików.

### ✅ 🟡 B12. Pliki audio są kopiowane „po cichu”
`includeAudio = true` domyślnie, ale w UI karty nie ma przełącznika audio
(`CardColumnView.swift:277-291`). Audio nie jest też liczone w stopce, w pasku zajętości
ani w wierszu dnia (`CardColumnView.swift:385`). Użytkownik nie wie, że zgrywa WAV-y i nie
może tego wyłączyć dla karty.

### ✅ 🟡 B13. Miniatury kamer trafiają do „Zdjęć”
`MediaScanner.swift:120-153` skanuje wszystko rekurencyjnie. Sony (FX3, A7…) trzyma
miniatury JPG w `M4ROOT/THMBNL/`, więc każdy klip daje dodatkowe „zdjęcie”. Do tego DJI
`.LRF` (proxy) jest domyślnie włączone i ląduje w `Video/` obok oryginałów, co podwaja liczbę
klipów w Resolve.
**Naprawa:** lista wykluczonych katalogów (`THMBNL`, `MISC`, `AVF_INFO`, `CANONMSC`,
`.Spotlight-V100`…). `LRF` domyślnie wyłączone albo zgrywane do podfolderu `Proxy/`.

### ✅ 🟡 B14. Rozjazd list rozszerzeń (cztery źródła prawdy)
`Settings.defaultExtensions`, `MediaCategory.extensions` i dwie kopie `allExtensions` w
widokach ustawień to cztery osobne listy. `mpg`/`mpeg` są w domyślnych, ale nie ma ich w UI,
więc **nie da się ich wyłączyć**, a „Odznacz wszystkie” ich nie odznacza. Z kolei
odznaczenie wszystkich typów zostaje cofnięte do domyślnych przy następnym starcie
(`Settings.swift:84`). Zmiana typów plików nie wywołuje też ponownego skanu kart.

### ✅ 🟡 B15. Brak sprawdzeń przed startem (preflight)
Przed zgraniem aplikacja nie sprawdza, czy:
- dysk docelowy jest zamontowany i zapisywalny (odłączony SSD daje niejasny błąd uprawnień
  przy tworzeniu folderu w `/Volumes`),
- jest na nim **wystarczająco miejsca** (teraz wykrywa się to w połowie kopiowania),
- system plików przyjmie pliki > 4 GB (FAT32 jako cel).

### ✅ 🟡 B16. Wysuwanie i zmiana nazwy karty są dostępne w trakcie zgrywania
`CardColumnView.swift` (przyciski eject i ołówek) nie są blokowane, gdy `isCopying`. Tak samo
przełączniki filtrów, które w trakcie i tak nic nie zmieniają, a mylą.

### ⚪ B17. Pozostałe drobne
- `ProjectBuilder.swift:53-56`: pusty plik `.drp` jako „zastępczy”. Dwuklik w Finderze daje
  błąd importu w Resolve. Lepiej nie tworzyć pliku wcale.
- `resolution` i `frameRate` trafiają **tylko do manifestu JSON**, nie wpływają na projekt
  Resolve. W UI wyglądają, jakby coś ustawiały.
- Stepper FPS (`StudioSettingsModalView.swift:369`) ma zakres 23.976…120 z krokiem 1, co daje
  23.976, 24.976, 25.976… Nie da się wybrać 29.97/59.94, a `%.0f` pokazuje 23.976 jako „24”.
- Ręczny folder bez danych o pojemności dostaje fikcyjne 64 GB / 32 GB (`AppModel.swift:120-121`),
  a `freePercent` przy braku danych zwraca zmyślone 50%.
- `MediaFile.init` tworzy nowy `DateFormatter` dla każdego pliku. Przy tysiącach zdjęć to
  zauważalny koszt; wystarczy jeden statyczny.
- Postęp karty jest liczony po liczbie plików, nie bajtów. Jeden klip 20 GB i 500 JPG-ów
  daje bardzo nierówny pasek. Postęp ogólny aktualizuje się dopiero po zakończeniu
  **całej** karty, więc przy jednej karcie przez całe kopiowanie widać 0%.
- Callback postępu po każdym pliku przebudowuje całe okno. `filteredFiles` (O(n)) jest
  liczone kilkanaście razy na render.
- `settings.didSet` zapisuje plik na dysk przy każdym naciśnięciu klawisza w polach tekstowych.
- Martwy kod: `MenuBarMenu.swift` (cały plik nieużywany), `CopyFileResult`,
  `CopyService.directory(for:)`, nieużywane przypadki `CopyError`.

### ✅ Błędy w obsłudze okien (do potwierdzenia na Macu)
- 🟠 **Po zamknięciu okna głównego nie da się go otworzyć z paska menu.**
  `MenuBarController.swift:148-155` wysyła notyfikację, którą odbiera `onReceive` *wewnątrz*
  `MainWindow`, a ten po zamknięciu okna już nie istnieje. Pętla po `NSApp.windows` nie
  znajdzie zamkniętego okna SwiftUI. Należy użyć `openWindow(id: "main")` z kontekstu
  SwiftUI albo trzymać własny `NSWindow`.
- 🟡 **„Ustawienia…” w menu paska** (`MenuBarController.swift:136-140`) używa selektora
  `showSettingsWindow:`, który od macOS 14 jest ignorowany (Apple wymaga `SettingsLink`).
  Skoro ustawienia są już w panelu w oknie głównym, ta pozycja powinna otwierać okno główne
  z `isSettingsPanelOpen = true`, a osobny `SettingsView` (duplikat ~190 linii) można usunąć.

---

## 2. Testy i budowanie

- 🟠 **Test `testCopyCreatesProjectAndFiles` nie przechodzi.**
  `Tests/SDCardOrganizerCoreTests/SettingsScannerCopyTests.swift:108` sprawdza manifest i
  `.drp` po samym `CopyService.copy`, który ich nie tworzy (robi to `ProjectBuilder`).
- 🟡 Testy i selftest **zapisują do prawdziwej historii użytkownika**
  (`SettingsScannerCopyTests.swift:122`, `SDCardOrganizerSelftest/main.swift:90`). Po każdym
  uruchomieniu w zakładce Historia pojawia się „SampleProject”/„XCTestProject”. Trzeba
  przekazywać tymczasowy URL.
- Brak testów dla scenariuszy z sekcji 1: ponowne zgranie (B1, B5), błąd w połowie (B2),
  migracja ustawień (B4), pusta selekcja dni (B11).
- Instrukcja dla testerów (`Scripts/create-installer.sh:46-52`, `:88-95`): od **macOS 15
  Sequoia** „prawy klik → Otwórz” nie omija już Gatekeepera. Trzeba wejść w
  *Ustawienia systemowe → Prywatność i ochrona → „Otwórz mimo to”*.
- `Info.plist` nie ma `NSRemovableVolumesUsageDescription`, więc systemowy monit o dostęp do
  karty nie ma opisu, po co aplikacja go potrzebuje.

---

## 3. Frontend — propozycje UX/UI

### Najważniejsze (wpływ na codzienną pracę)
1. **Stan zgrywania z prawdziwego zdarzenia:** postęp w bajtach, bieżąca prędkość (MB/s),
   ETA liczone na żywo i przycisk **Anuluj**. Stała „~350 MB/s” jest myląca, bo karty
   UHS-I mają realnie 80–170 MB/s.
2. **Ekran podsumowania po zgraniu:** skopiowano / pominięto (duplikaty) / błędy z listą
   plików, wynik weryfikacji oraz przyciski „Pokaż w Finderze”, „Otwórz w Resolve” i
   „Wysuń karty”.
3. **Nazwa projektu:** pole ma 100 pt szerokości. Proponuję szersze pole z listą ostatnich
   projektów (z historii i z folderów na dysku docelowym), co upraszcza dogrywanie do
   istniejącego projektu, oraz podgląd ścieżki wynikowej
   (`/Volumes/SSD/2026-10-09_Nazwa/Video/Kamera A/`).
4. **Wyraźny stan „nic nie wybrano”:** gdy przycisk „Zgraj” jest wyłączony, powiedz
   dlaczego (brak nazwy projektu / dysku / plików), zamiast tylko go przyciemniać.
5. **Przełącznik Audio** na karcie (obok Filmy/Zdjęcia) oraz audio w statystykach (B12).
6. **Ostrzeżenie o miejscu:** pasek „Dysk docelowy” powinien pokazywać wolne miejsce i
   świecić na czerwono, gdy wybrane materiały się nie mieszczą.

### Czytelność i spójność
7. **Rozmiary fontów:** większość tekstów ma 9–11 pt, co przy ciemnym tle i szarym kolorze
   (`Color.gray.opacity(0.7)`) jest na granicy czytelności (kontrast poniżej WCAG AA).
   Minimum 11 pt dla treści, 10 pt dla etykiet pomocniczych.
8. **Dekoracyjny żargon** mówi mniej niż mógłby: „STUDIO 2.4” (fikcyjna wersja),
   „KONTROLER I/O: GOTOWY”, „CAM_SLOT_01”. Proponuję zastąpić je realną informacją:
   wersją z `Info.plist`, liczbą kart, wolnym miejscem na dysku docelowym.
9. **Polska odmiana liczebników:** „1 plików”, „2 kart(y)”, „1 skopiowanych”. Warto mieć
   helper `plural(n, "plik", "pliki", "plików")` albo `.stringsdict`.
10. **Panel ustawień:** przycisk zamknięcia udaje czerwony „semafor” okna macOS, co myli
    użytkownika. Lepiej dać zwykły „×” albo „Gotowe”, zamykanie klawiszem **Esc** i
    przyciemnienie tła pod panelem.
11. **Tryb jasny / dostępność:** motyw jest na sztywno ciemny. Warto choć respektować
    „Zwiększ kontrast” i „Ogranicz ruch” (spring-animacje i poświaty).
12. **Skróty klawiszowe:** ⌘R (skanuj), ⌘↩ (zgraj), ⌘, (ustawienia), ⌘E (wysuń wszystkie).
13. **Historia:** „Pokaż w Finderze” przy wpisie, liczba pominiętych i błędów, potwierdzenie
    przed „Wyczyść historię” (teraz kasuje bez pytania).
14. **Lista dni:** przy wielu dniach dodaj zakres („ostatnie 3 dni”) i podgląd miniatur.
    Kolumna jest wąska, więc lista na 110 pt przy 10+ dniach jest mało wygodna.
15. **Okno:** `minWidth: 1060` nie mieści się wygodnie na 13" MacBooku z Dockiem. Przy
    jednej karcie pusta przestrzeń jest marnowana; lepiej dopasować kolumny do szerokości
    okna.

---

## 4. Propozycje nowych funkcji

| Funkcja | Wartość | Nakład |
|---|---|---|
| Weryfikacja kopii (xxHash) + raport/MHL | Bezpieczne formatowanie kart | Średni |
| **Druga kopia zapasowa** (zapis równocześnie na 2 dyski) | Standard na planie | Średni |
| Preflight: miejsce, montowanie, FAT32 | Brak porażek w połowie | Mały |
| Wznawianie / pomijanie już zgranych plików (indeks projektu) | Szybkie dogrywanie | Średni |
| Równoległe kopiowanie z różnych czytników | 2–4× szybciej przy wielu kartach | Średni |
| Szablon nazw plików (`{data}_{kamera}_{oryginał}`) | Porządek w Resolve | Mały |
| Automatyczne wysunięcie kart po zweryfikowanym zgraniu | Mniej klikania | Mały |
| Profile ustawień (np. „Wesele”, „Reklama”) | Szybka zmiana konfiguracji | Mały |
| Zachowanie plików sidecar (XML Sony, SRT DJI) | Metadane w Resolve | Mały |
| Prawdziwy projekt Resolve przez API skryptowe¹ (biny per kamera, ustawienia timeline) | Gotowy projekt zamiast pustego `.drp` | Duży |

¹ Zewnętrzne skryptowanie Resolve (`DaVinciResolveScript`) w pełni działa w wersji Studio. W
wersji darmowej skrypt trzeba uruchomić z menu *Workspace → Scripts*. Można by
dostarczyć gotowy skrypt Python, który czyta `project_manifest.json`, tworzy projekt, biny
`Kamera A/B/…` i importuje materiał.

---

## 5. Kolejność prac (rekomendacja)

1. **Bezpieczeństwo danych:** B2 (błąd per plik + `.part`), B3 (weryfikacja), B4 (migracja
   ustawień), B1 (ponowne zgranie), B5/B6 (deduplikacja), preflight (B15).
2. **Stabilność:** B10 (wątki/indeksy), B8, B9, ponowne otwieranie okna, B7.
3. **Poprawność UI:** B11, B12, B13, B14, B16 i naprawa testów.
4. **UX:** postęp w bajtach + ETA + Anuluj, ekran podsumowania, wybór istniejącego
   projektu, czytelność.
5. **Nowe funkcje** z tabeli w sekcji 4.
