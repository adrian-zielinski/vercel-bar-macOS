# VercelBar

Aplikacja paska menu macOS: stan deployów Vercela na żywo. Trójkąt w pasku
zmienia kolor (zielony = wdrożone, niebieski pulsujący = build w toku,
czerwony = błąd), popover pokazuje ostatnie deploye obserwowanych projektów,
a powiadomienia zgłaszają start, sukces i porażkę builda.

## Instalacja

1. Zbuduj: `./Scripts/build-app.sh` (wymaga Swift 6+ — Command Line Tools z Xcode 16
   lub nowszego).
2. Rozpakuj `build/VercelBar.zip` (dwuklik) i przenieś `VercelBar.app` do Programów.
   (Nie kopiuj `build/VercelBar.app` bezpośrednio — iCloud dokleja mu atrybuty,
   które psują pieczęć podpisu.)
3. Przy pierwszym uruchomieniu: prawy przycisk → Otwórz (aplikacja bez płatnego
   podpisu Apple).

## Konfiguracja

1. Wygeneruj token: vercel.com → Account Settings → Tokens. Jako zakres (scope) wybierz
   konto lub zespół, który chcesz obserwować.
2. Klik w trójkąt → Połącz z Vercelem → wklej token.
3. Zakładka Projekty → zaznacz, co obserwować.
4. Stopka Ustawień: długość listy w popoverze (3/5/10 pozycji łącznie) i to,
   o czym powiadamiać.

Token ląduje w Keychain. Aplikacja odpytuje API co 30 s (10 s podczas builda).

## Rozwój

- `swift run vercelbar` — uruchomienie deweloperskie (z ikoną w Docku; bundle jej nie ma).
- `swift run vercelbar-tests` — testy rdzenia.
- Spec i makiety: `docs/`.

## Znane ograniczenia v1

- Lista projektów do 100 pozycji (bez paginacji).
- „Uruchamiaj przy logowaniu” może wymagać zatwierdzenia w Ustawieniach systemowych
  (Ogólne → Elementy logowania) — macOS pyta przy pierwszym włączeniu.

Aplikacja podąża za językiem systemu: polski system → polski interfejs, każdy
inny → angielski. Bez przełącznika.

---

# English

macOS menu bar app showing live Vercel deploy status. The triangle in the menu
bar changes color (green = deployed, pulsing blue = build running, red = failed),
the popover lists the latest deploys across your watched projects, and
notifications report when a build starts, succeeds, or fails.

The UI follows your system language: Polish system → Polish, anything else →
English. No switch to flip.

## Install

1. Build: `./Scripts/build-app.sh` (needs Swift 6+ — Command Line Tools from
   Xcode 16 or newer).
2. Unzip `build/VercelBar.zip` (double-click) and move `VercelBar.app` to
   Applications. (Don't copy `build/VercelBar.app` directly — iCloud attaches
   attributes that break the code signature seal.)
3. On first launch: right-click → Open (the app has no paid Apple signature).

## Setup

1. Generate a token: vercel.com → Account Settings → Tokens. For scope, pick the
   account or team you want to watch.
2. Click the triangle → Connect to Vercel → paste the token.
3. Projects tab → check what to watch.
4. Settings footer: how many deploys the popover lists (3/5/10 in total) and
   what to be notified about.

The token goes into the Keychain. The app polls the API every 30 s (10 s during
a build).

## Development

- `swift run vercelbar` — dev run (shows a Dock icon; the bundle doesn't).
- `swift run vercelbar-tests` — core tests.
- Spec and mockups: `docs/` (Polish).

## Known limitations (v1)

- Project list capped at 100 entries (no pagination).
- "Launch at login" may need approval in System Settings (General → Login Items)
  — macOS asks the first time you enable it.
