---
temat: vercelbar-projekt
status: aktywny
updated: 2026-08-07
---

# VercelBar — aplikacja paska menu macOS

## Co to jest

Natywna aplikacja Swift/SwiftUI paska menu macOS pokazująca na żywo stan deployów Vercela: kolorowy trójkąt w pasku (zielony = wdrożone, pulsujący niebieski = build w toku, czerwony = padł, szary = idle/offline), popover z listą ostatnich deployów (feed 3/5/10 pozycji, każdy obserwowany projekt ma gwarantowany wiersz), powiadomienia z dźwiękiem (start 🚀 / sukces ✅ / błąd ❌), okno ustawień (token w Keychain, wybór projektów i zespołu, przełącznik języka pl/en, start przy logowaniu), silnik samoaktualizacji z GitHub Releases.

Zero zależności zewnętrznych, ~470 KB paczka, 427 testów w wykonywalnym runnerze (`swift run vercelbar-tests` — nie XCTest, bo build jest CLT-only bez Xcode).

## Repozytorium

- **GitHub:** https://github.com/adrian-zielinski/vercel-bar-macOS (publiczne, MIT)
- **Lokalnie:** `/Users/adrianmacbook2/Library/Mobile Documents/com~apple~CloudDocs/Claude Code/VercelBar`
- Repo było przemianowane z `vercelbar` na `vercel-bar-macOS` — stare linki działają przez przekierowanie GitHuba, ale **nigdy nie zakładać nowego repo o nazwie `vercelbar`** na koncie — przejęłoby przekierowanie i odcięło wydane binarki od aktualizacji.
- Historia commitów przepisana raz (`git filter-repo`) — autor: `Adrian Zieliński <257489848+adrian-zielinski@users.noreply.github.com>` (linkuje do profilu GitHub), lokalne ścieżki `/Users/adrianmacbook2/...` usunięte z historii. Kopia zapasowa sprzed przepisania: `vercelbar-backup.bundle` w scratchpadzie tamtej sesji (raczej nieaktualne po kolejnych commitach).

## Stan na 2026-08-07: wersja 1.2.2, opublikowana, działająca u użytkownika

Aktualne wydanie: **v1.2.2** (https://github.com/adrian-zielinski/vercel-bar-macOS/releases/tag/v1.2.2), zainstalowane w `/Applications/VercelBar.app` na Macu użytkownika i uruchomione.

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
- `Sources/VercelBar/` — SwiftUI: `AppModel` (@MainActor, pętla odpytywania 30s/10s+backoff), `PopoverView`/`ProjectRowView`, `SettingsView`, `NotificationPresenter`, `UpdateInstaller`
- `Sources/vercelbar-tests/` — wykonywalny runner testów (nie XCTest)
- `Scripts/build-app.sh` — buduje `.app`, podpisuje, pakuje zip; `Scripts/make-dmg.sh` — DMG z zipa
- Proces developerski w tej sesji: subagenci Opus 5 przez `Agent`/`SendMessage`, każda zmiana z dwustopniowym przeglądem (spec compliance + jakość, często z testami mutacyjnymi), poprawki wracają do tego samego wykonawcy, kontroler (główna sesja) commituje i wydaje

## Do zrobienia / warto rozważyć

- Zrzuty ekranu w README są nieaktualne (sprzed przełącznika języka i paska aktualizacji) — do odświeżenia przy okazji
- Rozważyć płatny podpis Apple Developer (99 USD/rok) — zdjąłby też taniec Gatekeepera przy pierwszym uruchomieniu, nie tylko problem z powiadomieniami
- M9/M12/M13/M14 z przeglądu silnika aktualizacji świadomie odroczone (drobne, nieblokujące — szczegóły w historii commitów 1.2.1)
- Warto sprawdzić czy `brew audit --cask` przechodzi przed ewentualnym zgłoszeniem do homebrew-cask (obecnie własny tap, niezależny)

## Dziennik sesji

- **2026-08-06/07** — Cały projekt od brainstormingu przez implementację (Taski 1–13 wg planu, subagent-driven development) do finałowego przeglądu, publikacji na GitHubie, dystrybucji (Homebrew/curl/DMG), lokalizacji EN, feedu deployów, silnika samoaktualizacji i naprawy powiadomień (diagnoza: ad-hoc podpis blokował `UNUserNotificationCenter` w nieskończoność). Wersja końcowa sesji: **1.2.2**, opublikowana i zweryfikowana działająca u użytkownika.
