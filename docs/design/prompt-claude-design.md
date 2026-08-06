# Prompt do Claude Design (UI VercelBar)

Zaprojektuj UI natywnej aplikacji macOS do paska menu o nazwie VercelBar. Aplikacja monitoruje na żywo deploye z Vercela. Ma wyglądać jak część systemu: typografia SF Pro, ikony SF Symbols, półprzezroczysty materiał okien macOS, zaokrąglenia jak w natywnych popoverach. Estetyka Vercela: czerń, biel, dużo powietrza, jeden kolor akcentu na stan. Przygotuj każdy ekran w wersji jasnej i ciemnej.

Ekrany:

1. Popover paska menu, szerokość 340 px.
   Nagłówek: kropka stanu zbiorczego, tekst stanu („Wszystko wdrożone", „Build w toku…", „1 deploy padł"), po prawej dyskretny czas ostatniego odświeżenia.
   Lista 4–6 projektów. Wiersz: nazwa projektu, badge statusu (Ready zielony, Building niebieski, Error czerwony, Queued szary), niżej gałąź i treść commita w jednej przyciętej linii, po prawej czas względny („2 min temu").
   Stopka z trzema drobnymi akcjami: Odśwież, Ustawienia, Zakończ.

2. Warianty popovera: build w toku (wiersz z delikatnym shimmerem lub cienkim paskiem postępu), deploy z błędem (wiersz wyróżniony czerwienią), onboarding (pusty stan: jedno zdanie zachęty i przycisk „Połącz z Vercelem"), offline (ikona wifi.slash i jedno zdanie).

3. Okno ustawień około 480×380 px, dwie zakładki.
   Konto: pole na token, status połączenia z avatarem i nazwą konta, wybór teamu.
   Projekty: wyszukiwarka i lista projektów z haczykami.
   Na dole trzy przełączniki: uruchamiaj przy logowaniu, powiadamiaj o sukcesach, powiadamiaj o błędach.

4. Ikona paska menu: trójkąt w duchu logo Vercela, cztery stany: zielony, niebieski, czerwony, szary. Pokaż je osadzone w pasku menu macOS, w trybie jasnym i ciemnym.

5. Powiadomienia macOS: „❌ mój-projekt: deploy padł" oraz „✅ mój-projekt wdrożony".

Animacje: lekkie i celowe, 150–250 ms, sprężysty easing. Zaprojektuj i opisz:

- pulsowanie niebieskiej kropki podczas builda (skala 1→1,15 plus opacity),
- crossfade badge'a przy zmianie statusu,
- płynna zmiana wysokości popovera, gdy przybywa lub ubywa wierszy,
- krótki zielony rozbłysk wiersza przy przejściu z Building do Ready,
- hover wiersza: subtelne tło i strzałka „otwórz" wysuwająca się z prawej,
- wszystkie animacje respektują systemowe „Ogranicz ruch" (Reduced Motion).

Unikaj: ciężkich cieni, gradientów, więcej niż jednego koloru akcentu na element, zagęszczonych układów. Wzorzec jakości: natywne aplikacje Apple i dashboard Vercela.
