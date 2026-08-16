---
kind: handoff-topic
topic: vercelbar-projekt
status: in-progress
updated: 2026-08-17
---

# VercelBar — aplikacja paska menu macOS

> Zakres: cała apka paska (kit, UI, podpis, dystrybucja, update, powiadomienia, wydajność). NIE obejmuje: innych projektów Vercel/dashboard.

## Co to jest

Natywna aplikacja Swift/SwiftUI paska menu macOS pokazująca na żywo stan deployów Vercela: kolorowy trójkąt w pasku (zielony = wdrożone, pulsujący niebieski = build w toku, czerwony = padł, szary = idle/offline), popover z listą ostatnich deployów (feed 3/5/10 pozycji, każdy obserwowany projekt ma gwarantowany wiersz), powiadomienia z dźwiękiem (start 🚀 / sukces ✅ / błąd ❌), okno ustawień (token w Keychain, wybór projektów i zespołu, przełącznik języka pl/en, start przy logowaniu), silnik samoaktualizacji z GitHub Releases.

Zero zależności zewnętrznych, ~488 KB paczka, 459 testów w wykonywalnym runnerze (`swift run vercelbar-tests` — nie XCTest, bo build jest CLT-only bez Xcode).

## Repozytorium

- **GitHub:** https://github.com/adrian-zielinski/vercel-bar-macOS (publiczne, MIT)
- **Lokalnie:** `/Users/adrianmacbook2/Library/Mobile Documents/com~apple~CloudDocs/Claude Code/VercelBar`
- Repo było przemianowane z `vercelbar` na `vercel-bar-macOS` — stare linki działają przez przekierowanie GitHuba, ale **nigdy nie zakładać nowego repo o nazwie `vercelbar`** na koncie — przejęłoby przekierowanie i odcięło wydane binarki od aktualizacji.
- Historia commitów przepisana raz (`git filter-repo`) — autor: `Adrian Zieliński <257489848+adrian-zielinski@users.noreply.github.com>` (linkuje do profilu GitHub), lokalne ścieżki `/Users/adrianmacbook2/...` usunięte z historii. Kopia zapasowa sprzed przepisania: `vercelbar-backup.bundle` w scratchpadzie tamtej sesji (raczej nieaktualne po kolejnych commitach).

## Aktualny stan

- ✅ Kod wydajności i stopera na `main`: commit `384b53f` (https://github.com/adrian-zielinski/vercel-bar-macOS/commit/384b53f)
- 🔄 Wydanie **1.2.3 nie istnieje**. Homebrew, `install.sh` i silnik aktualizacji serwują nadal **v1.2.2**. `/Applications/VercelBar.app` to 1.2.2.
- ✅ Lokalny build z tej sesji: `build/VercelBar.app` (podpis „VercelBar Local Signing"), odpalony zamiast kopii z Applications. Wersja w `Scripts/build-app.sh` wciąż `1.2.2`.
- ⛔ Czeka na „wdrażaj": bump do 1.2.3, `./Scripts/build-app.sh`, tag + GitHub Release (`VercelBar.zip`), drugi commit z SHA w `Casks/vercelbar.rb` (wzorzec 1.2.1/1.2.2).

Aktualne wydanie produkcyjne: **v1.2.2** (https://github.com/adrian-zielinski/vercel-bar-macOS/releases/tag/v1.2.2).

### Dystrybucja (trzy ścieżki instalacji)
- Homebrew cask w tym samym repo: `Casks/vercelbar.rb` — `brew tap adrian-zielinski/vercel-bar-macOS https://github.com/adrian-zielinski/vercel-bar-macOS && brew install --cask --no-quarantine vercelbar`
- Jedna komenda: `curl -fsSL https://raw.githubusercontent.com/adrian-zielinski/vercel-bar-macOS/main/install.sh | bash` (curl omija kwarantannę Gatekeepera)
- Ręcznie: `VercelBar.zip`/`VercelBar.dmg` z Releases

### Kluczowe odkrycie sesji: podpis ad-hoc łamał powiadomienia całkowicie
Do wersji 1.2.1 aplikacja była podpisana ad-hoc (`codesign --force --sign -`). Zmierzone empirycznie na minimalnej aplikacji testowej: przy takim podpisie `UNUserNotificationCenter.requestAuthorization` **nigdy nie wołało callbacka** — okno zgody się nie pojawiało, system milczał w nieskończoność, więc ŻADNE powiadomienie nigdy nie wyszło. To samo powodowało powtarzające się monity o pęk kluczy po każdej aktualizacji (nowy podpis = "inna aplikacja" dla macOS).

**Naprawa w 1.2.2** (patrz [[vercelbar-signing-certificate]] — osobna pamięć projektowa):
1. Stały self-signed certyfikat „VercelBar Local Signing" w pęku kluczy login — `Scripts/build-app.sh` wykrywa go przez `security find-identity -p codesigning` (BEZ `-v`, bo certyfikat nie jest w magazynie zaufania i `-v` by go ukryło) i podpisuje nim; fallback na ad-hoc z ostrzeżeniem, gdy certyfikat zniknie.
2. Droga zapasowa powiadomień przez `osascript` (`Sources/VercelBar/NotificationPresenter.swift`) — działa niezależnie od zaufania do podpisu; ograniczenie: taki baner nie jest klikalny (deploy trzeba otworzyć z wiersza w popoverze).
3. Przycisk „Testuj powiadomienie" w Ustawieniach → Konto do weryfikacji, że cokolwiek dociera.

Kopia zapasowa certyfikatu: `~/.vercelbar-signing/vercelbar-signing.p12` (hasło `vbtemp`, zapisane w tamtym samym folderze w `README.txt`). **Utrata certyfikatu = powrót do stanu ad-hoc dla wszystkich przyszłych wydań** — to najważniejsza rzecz do pilnowania.

### Silnik samoaktualizacji (od 1.2.0, utwardzony w 1.2.1)
- Sprawdza GitHub Releases raz dziennie + przycisk ręczny w Ustawieniach; pasek w popoverze nad stopką, gdy jest nowa wersja
- Jeden klik: pobiera zip → weryfikuje bundle id, wersję, plik wykonywalny, podpis (`codesign --verify`) → podmienia atomowo (staging obok celu na tym samym wolumenie, potem `rename`, stara wersja do Kosza) → restartuje w nowej wersji
- Każda porażka: fallback otwiera stronę release'u w przeglądarce, aplikacja zostaje nietknięta
- 1.2.1 domknęła: rollback przy przerwanej podmianie (mutant M3, wcześniej bez pokrycia), limity pobierania (30s/180s/100MB), wymóg HTTPS, ochrona przed podwójnym kliknięciem
- **Użytkownicy na 1.0.x–1.1.0 (sprzed silnika) NIE dostaną powiadomienia o aktualizacji** — muszą raz zaktualizować ręcznie

### Funkcje dodane w tej sesji (chronologicznie)
1. Naprawa dekodowania `/v2/user` (Vercel zwraca `id`, nie `uid` — zły dekoder dawał fałszywe „token odrzucony")
2. Pełna angielska wersja UI (wcześniej tylko polska) — `Sources/VercelBarKit/L10n.swift`, język auto za systemem
3. Feed N ostatnich deployów (3/5/10) zamiast jednego wiersza na projekt; dźwięk w powiadomieniach (wcześniej go brakowało — realny bug); powiadomienie o starcie deployu; cache tokenu w pamięci (mniej monitów pęku)
4. README w stylu release'owym (wzorowany na Space Rabbit) + zrzuty ekranu w `docs/screenshots/`
5. Publikacja na GitHubie, Homebrew cask, `install.sh`, DMG
6. Przełącznik języka w Ustawieniach (System/Polski/English, na żywo bez restartu)
7. Przepisanie historii gita (usunięcie lokalnej tożsamości i ścieżek)
8. Silnik samoaktualizacji (1.2.0) + utwardzenie (1.2.1)
9. Naprawa powiadomień (1.2.2) — opisana wyżej

## Architektura (dla przyszłych zmian)

- `Sources/VercelBarKit/` — czysta logika, TDD, zero UI: modele, `VercelAPI` (klient REST), `RefreshCore` (agregacja migawki), `NotificationEngine` (zdarzenia z przejść stanów), `SettingsStore`/`KeychainStore`, `L10n` (pl+en), `UpdateChecker`/`UpdateInstallEngine`
- `Sources/VercelBar/` — SwiftUI: `AppModel` (@MainActor, polling **zawsze 10 s** + backoff 429/5xx), `StatusIconLabel` (puls 8 FPS przez `opacity` na jednej NSImage), `PopoverView`/`ProjectRowView`, `SettingsView`, `NotificationPresenter`, `UpdateInstaller`
- `Sources/VercelBarKit/PulsePolicy.swift` — czy ikona ma pulsować (Reduce Motion, ERROR > BUILDING, ten sam zestaw deployów max 45 min)
- `DeploymentSummary.elapsed(at:)` — stoper na żywo; `duration` tylko dla skończonego deployu
- `Sources/vercelbar-tests/` — wykonywalny runner testów (nie XCTest)
- `Scripts/build-app.sh` — buduje `.app`, podpisuje, pakuje zip; `Scripts/make-dmg.sh` — DMG z zipa
- Proces developerski w tej sesji: subagenci Opus 5 przez `Agent`/`SendMessage`, każda zmiana z dwustopniowym przeglądem (spec compliance + jakość, często z testami mutacyjnymi), poprawki wracają do tego samego wykonawcy, kontroler (główna sesja) commituje i wydaje

## Kluczowe decyzje i ustalenia

- Cel produktu: **powiadomić od razu, gdy idzie nowy deploy**. Silnik (`NotificationEngine`) jest OK; opóźnienie to był polling 30 s w spoczynku. Teraz 10 s zawsze.
- 17% CPU / 2 h 43 min czasu CPU: timer pulsu 10 Hz bez `tolerance` + nowy `NSImage`+BezierPath + `@Published iconAlpha` + hop `Task { @MainActor }` na tick. Idle bez utkniętego BUILDING nie ma prawa tyle żreć.
- Puls: jedna NSImage na stan, `TimelineView(.periodic(by: 0.125))` + `Image.opacity`. Nie ruszamy ręcznego `NSStatusItem` (MenuBarExtra nie oddaje buttona; migracja rozjechałaby powiadomienia i update).
- Ten sam zestaw id BUILDING > 45 min: ikona zostaje niebieska, puls gaśnie. Nowe id znowu pulsuje. ERROR + BUILDING: ikona czerwona, bez pulsu, polling 10 s zostaje.
- Vercel w QUEUED/BUILDING często wysyła `ready: 0` albo `ready == createdAt`. Stary kod liczył `duration = 0 s` i wyłączał TimelineView. `date(fromMs:)` odrzuca `<= 0`; `duration` tylko gdy `!state.isActive`.
- `anyActive` w kodzie nie utyka; utknie, gdy API trzyma deploy w BUILDING. Stąd limit 45 min na puls.
- Push na `main` ≠ wydanie. User napisał „puszyj wszystko" (źródło na GitHub), nie „wdrażaj". Cask i update checker zostają na 1.2.2 do osobnego release.

## Następny krok

Po „wdrażaj": bump `VERSION` w `Scripts/build-app.sh` do **1.2.3**, `./Scripts/build-app.sh`, tag `v1.2.3` + GitHub Release z `build/VercelBar.zip`, potem commit SHA w `Casks/vercelbar.rb` (osobny commit, jak przy 1.2.1/1.2.2). Potem zmierzyć w Monitorze aktywności 15 min idle i jeden trwający build.

## Czego NIE robić

- Nie zakładać repo `vercelbar` na koncie (zjada przekierowanie i odcina wydane binarki).
- Nie podpisywać ad-hoc, jeśli w pęku jest „VercelBar Local Signing". Szukać tożsamości **bez** `security find-identity -v`.
- Nie ruszać Keychain, NotificationPresenter, UpdateInstallEngine, L10n, codesign bez dowodu.
- Nie dodawać SPM / Sparkle / Electron.
- Nie publikować release / nie zmieniać caska bez „wdrażaj".
- Nie wracać do timera 10 Hz z nowym NSImage na tick.
- Nie traktować pola `ready` z API jako końca builda, gdy stan jest aktywny.

## Artefakty

- `Sources/VercelBarKit/PulsePolicy.swift` — bramka pulsu
- `Sources/VercelBar/VercelBarApp.swift` — `StatusIconLabel`
- `Sources/VercelBar/AppModel.swift` — `shouldPulse`, bez `pulseTimer`
- `Sources/VercelBar/ProjectRowView.swift` — stoper przez `elapsed(at:)`
- `Sources/VercelBarKit/Models.swift`, `APIDecoding.swift`, `PollScheduler.swift`, `StatusIconRenderer.swift`
- `Sources/vercelbar-tests/main.swift` — 459 testów
- `Scripts/build-app.sh` — VERSION nadal 1.2.2
- `Casks/vercelbar.rb` — cask 1.2.2
- `build/VercelBar.app` — lokalny build z tej sesji (nie w gicie)
- Commit: `384b53f` na `main`

## Do zrobienia / warto rozważyć

- **Wydanie 1.2.3** (następny krok wyżej)
- Zrzuty w README są nieaktualne (sprzed przełącznika języka i paska aktualizacji)
- Płatny podpis Apple Developer (99 USD/rok) — jeden raz Gatekeeper, nie tylko powiadomienia
- M9/M12/M13/M14 z przeglądu silnika aktualizacji świadomie odroczone (1.2.1)
- `brew audit --cask` przed ewentualnym zgłoszeniem do homebrew-cask (teraz własny tap)

## Dziennik sesji

- **2026-08-17** — Audyt CPU/baterii: puls z 10 Hz + alokacji NSImage na opacity 8 FPS, polling 10 s, limit pulsu 45 min, stoper builda (ready: 0 nie daje już 0 s). Testy 459. Kod na `main` (`384b53f`). Release 1.2.3 i Homebrew nie ruszone — czeka na „wdrażaj".
- **2026-08-06/07** — Projekt od zera do **1.2.2**: UI, feed, L10n, Homebrew/curl/DMG, silnik aktualizacji, naprawa powiadomień (ad-hoc podpis blokował `UNUserNotificationCenter`).
