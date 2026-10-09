#!/bin/bash
# Skrypt do tworzenia pełnego pakietu instalacyjnego (DMG + PKG + ZIP) dla testerów.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_DIR="$ROOT/.build/SDCardOrganizer.app"

echo "=================================================="
echo " Budowanie pakietu instalacyjnego SD Card Organizer"
echo "=================================================="

# 1. Zbuduj aplikację w wersji produkcyjnej
"$ROOT/Scripts/make-app.sh"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/* 2>/dev/null || true

# 2. Tworzenie instalatora .pkg
echo "Tworzenie pakietu instalatora .pkg..."
pkgbuild --install-location /Applications \
         --component "$APP_DIR" \
         "$DIST_DIR/SDCardOrganizer-Installer.pkg"

# 3. Tworzenie obrazu dysku .dmg z drag-and-drop
echo "Tworzenie obrazu instalatora .dmg..."
STAGING_DIR="$ROOT/.build/dmg_staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

cat << 'EOF' > "$STAGING_DIR/Instrukcja instalacji.txt"
SD Card Organizer — Wersja Testowa dla macOS

Instalacja:
1. Przeciągnij aplikację "SD Card Organizer" do folderu "Applications" (Programy).
2. Przejdź do folderu Programy i uruchom aplikację.

Wskazówka bezpieczeństwa dla testerów (Gatekeeper):
Ponieważ aplikacja jest wersją testową przygotowaną dla testerów bez certyfikatu Apple Developer,
macOS może przy pierwszym otwarciu wyświetlić komunikat:
"Nie można otworzyć programu, ponieważ pochodzi od niezidentyfikowanego dewelopera".

Aby uruchomić aplikację:
1. Kliknij prawym przyciskiem myszy (lub Control + klik) na ikonie SD Card Organizer w folderze Programy.
2. Z menu wybierz "Otwórz".
3. W oknie ostrzeżenia kliknij przycisk "Otwórz mimo to" (Open Anyway).

Alternatywnie w Terminalu można usunąć atrybut kwarantanny poleceniem:
xattr -cr /Applications/SDCardOrganizer.app
EOF

hdiutil create -volname "SD Card Organizer" \
        -srcfolder "$STAGING_DIR" \
        -ov -format UDZO \
        "$DIST_DIR/SDCardOrganizer-Installer.dmg"

rm -rf "$STAGING_DIR"

# 4. Tworzenie archiwum .zip (z zachowaniem atrybutów macOS)
echo "Tworzenie archiwum .zip..."
ditto -c -k --keepParent "$APP_DIR" "$DIST_DIR/SDCardOrganizer-macOS.zip"

# 5. Przygotowanie instrukcji dla testera
cat << 'EOF' > "$DIST_DIR/INSTRUKCJA-DLA-TESTERA.md"
# 📦 SD Card Organizer — Pakiet dla testera

W tym folderze znajdują się gotowe pakiety instalacyjne dla systemu macOS (Apple Silicon / arm64, macOS 13+):

1. **`SDCardOrganizer-Installer.dmg`** *(Rekomendowany)*  
   Tradycyjny obraz dysku macOS. Po otwarciu wystarczy przeciągnąć aplikację do folderu `Applications` (Programy).

2. **`SDCardOrganizer-Installer.pkg`**  
   Standardowy instalator pakietowy macOS. Po dwukrotnym kliknięciu przeprowadza przez proces instalacji bezpośrednio do `/Applications`.

3. **`SDCardOrganizer-macOS.zip`**  
   Skompresowany pakiet aplikacji `.app` gotowy do rozpakowania i uruchomienia.

---

### ⚠️ Ważna uwaga dla testera (macOS Gatekeeper)

Aplikacja jest wewnętrzną wersją testową podpisaną lokalnie (ad-hoc). System macOS może przy pierwszej próbie uruchomienia wyświetlić standardowe ostrzeżenie:
> *„Nie można otworzyć programu, ponieważ pochodzi od niezidentyfikowanego dewelopera”*.

**Jak uruchomić:**
- W folderze **Programy** kliknij aplikację prawym przyciskiem myszy (lub **Control + klik**),
- Wybierz z menu pozycję **Otwórz**,
- W oknie dialogowym kliknij przycisk **Otwórz mimo to**.

*Alternatywnie (jedno polecenie w Terminalu):*
```bash
xattr -cr /Applications/SDCardOrganizer.app
```

---

### 🧪 Co przetestować:
- **Wykrywanie kart:** Włożenie karty SD/microSD lub pendrive'a powinno natychmiast wysunąć okno aplikacji i wyświetlić powiadomienie.
- **Pasek menu:**
  - Lewy klik: natychmiastowe otwarcie/wysunięcie okna aplikacji.
  - Prawy klik: menu ze statusem i skrótami.
- **Wielokartowość:** Podłączenie 1–4 kart powinno utworzyć osobne kolumny z kolorami slotów.
- **Podpisy kamer:** Możliwość wpisania własnego podpisu lub wyboru z „chmurek”.
- **Wybór dni i typów:** Przyciski „Filmy” i „Zdjęcia” (podświetlane na zielono) oraz wybór dni nagrań (Dzisiaj / Wczoraj / data).
- **Zgrywanie materiałów:** Bezpieczne kopiowanie, deduplikacja, tworzenie folderów oraz opcje uruchomienia DaVinci Resolve lub Lightroom.
EOF

echo ""
echo "=================================================="
echo " Pakiety instalacyjne zostały utworzone w folderze:"
echo " $DIST_DIR"
echo "=================================================="
ls -lh "$DIST_DIR"
