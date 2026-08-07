# VercelBar

Aplikacja paska menu macOS: stan deployów Vercela na żywo. Trójkąt w pasku
zmienia kolor (zielony = wdrożone, niebieski pulsujący = build w toku,
czerwony = błąd), popover pokazuje obserwowane projekty, a powiadomienia
zgłaszają padnięte i ukończone deploye.

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

Token ląduje w Keychain. Aplikacja odpytuje API co 30 s (10 s podczas builda).

## Rozwój

- `swift run vercelbar` — uruchomienie deweloperskie (z ikoną w Docku; bundle jej nie ma).
- `swift run vercelbar-tests` — testy rdzenia.
- Spec i makiety: `docs/`.

## Znane ograniczenia v1

- Lista projektów do 100 pozycji (bez paginacji).
- „Uruchamiaj przy logowaniu” może wymagać zatwierdzenia w Ustawieniach systemowych
  (Ogólne → Elementy logowania) — macOS pyta przy pierwszym włączeniu.
