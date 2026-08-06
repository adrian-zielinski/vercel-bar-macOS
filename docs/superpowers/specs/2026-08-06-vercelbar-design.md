# VercelBar. Specyfikacja projektu (2026-08-06)

## Cel

Natywna aplikacja paska menu macOS. Pokazuje na żywo stan deployów wybranych projektów Vercel i wysyła powiadomienia o błędach oraz sukcesach. Wzorzec działania: Space Rabbit (LSUIElement, ikona w pasku, popover po kliknięciu, okno ustawień, start przy logowaniu).

## Zakres

- Użytkownik wybiera obserwowane projekty w ustawieniach (haczyki na liście pobranej z konta).
- Konta osobiste i teamy: aplikacja pobiera dostępne scope'y i pozwala wybrać.
- Ikona pokazuje stan zbiorczy. Popover pokazuje szczegóły per projekt. Powiadomienia zgłaszają zmiany.
- Poza zakresem wersji 1: wyzwalanie deployów, logi buildów, wiele kont naraz.

## UI

### Ikona paska menu

Trójkąt w stylu logo Vercela. Stany:

| Stan | Wygląd |
|---|---|
| Wszystkie obserwowane projekty Ready | zielony |
| Trwa build (Building/Queued) | niebieski, pulsuje |
| Ostatni deploy któregoś projektu Error | czerwony |
| Brak konfiguracji, offline, błąd tokenu | szary |

Priorytet przy agregacji: Error > Building/Queued > Ready. Canceled nie zmienia stanu zbiorczego.

### Popover (klik w ikonę)

- Nagłówek: kropka stanu zbiorczego, tekst („Wszystko wdrożone", „Build w toku…", „1 deploy padł"), czas ostatniego odświeżenia.
- Lista obserwowanych projektów. Wiersz: nazwa, badge statusu, gałąź, treść commita (przycięta), czas względny. Klik otwiera deploy w dashboardzie Vercela.
- Stopka: Odśwież, Ustawienia…, Zakończ.
- Stany specjalne: onboarding (brak tokenu, przycisk „Połącz z Vercelem"), offline, błąd tokenu.
- Tryb jasny i ciemny. Reduced Motion wyłącza animacje.

### Okno ustawień

- Zakładka Konto: pole tokenu (link do instrukcji vercel.com → Settings → Tokens), status połączenia, nazwa konta, wybór teamu.
- Zakładka Projekty: lista z haczykami, wyszukiwarka.
- Przełączniki: uruchamiaj przy logowaniu, powiadomienia o sukcesach, powiadomienia o błędach.

Docelowy wygląd UI powstanie w Claude Design; makiety trafią do docs/design/.

## Dane i API

- Vercel REST API, autoryzacja Personal Access Token w nagłówku `Authorization: Bearer`.
- Endpointy: `/v2/user` (walidacja tokenu), `/v2/teams` (scope'y), `/v9/projects` (lista projektów z `latestDeployments`), `/v6/deployments` (odświeżanie stanu).
- Token przechowywany w Keychain. Lista obserwowanych projektów i przełączniki w UserDefaults.
- Polling: co 30 s; co 10 s, gdy jakikolwiek obserwowany deploy jest w stanie Building/Queued. Odświeżenie także na żądanie (przycisk) i po obudzeniu Maca ze snu.

## Stany deployu

READY, ERROR, BUILDING, QUEUED, INITIALIZING, CANCELED. INITIALIZING traktujemy jak BUILDING.

## Powiadomienia

- Przejście najnowszego deployu projektu do ERROR: „❌ {projekt}: deploy padł".
- Przejście z BUILDING do READY: „✅ {projekt} wdrożony".
- Deduplikacja po id deploymentu: jedno powiadomienie na zdarzenie.
- Klik w powiadomienie otwiera deploy w przeglądarce.
- Brak powiadomień przy pierwszym pobraniu danych po starcie (bez zalewu historią).

## Obsługa błędów

- Brak sieci: ikona szara, wpis „offline" w popoverze, zero powiadomień, ponawianie w tle.
- HTTP 401: jedno powiadomienie, popover prosi o nowy token.
- HTTP 429 i 5xx: wykładniczy backoff, bez alarmowania użytkownika.

## Technika

- Swift 6, SwiftUI `MenuBarExtra` (styl window), macOS 14+, SwiftPM. Bez zależności zewnętrznych.
- Struktura: `VercelBarKit` (klient API, modele, agregacja stanu, silnik decyzji o powiadomieniach) i `VercelBar` (UI). Logika testowalna bez UI.
- Frameworki systemowe: Security (Keychain), UserNotifications, ServiceManagement (SMAppService, start przy logowaniu).
- Pakowanie: skrypt budujący `.app` na wzór Skryby (LSUIElement=true, ikona, dmg/zip).

## Testy

Wykonywalny runner testów rdzenia (wzorzec skryba-tests): parsowanie odpowiedzi API, agregacja stanu zbiorczego, decyzje o powiadomieniach (przejścia stanów, deduplikacja, cisza po starcie), logika backoffu.
