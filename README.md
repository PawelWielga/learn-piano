# Learn Piano: Play & Train

Darmowa aplikacja do nauki na **fizycznym pianinie lub keyboardzie, także bez wyjścia MIDI**. Docelowo użytkownik otwiera stronę, importuje własną monofoniczną melodię MIDI i ćwiczy; mikrofon pozwala aplikacji przejść do kolejnej nuty dopiero po jej poprawnym zagraniu.

## MVP 1: najpierw Web

Pierwszym celem jest **Flutter Web na GitHub Pages**, nie Android APK. Docelowy adres po włączeniu publikacji:

**https://pawelwielga.github.io/learn-piano/**

Aplikacja przetwarza dźwięk i pliki MIDI **lokalnie w przeglądarce**. Bez backendu, logowania, płatności i wysyłania nagrań na serwer.

### Plan prac

| Etap | Funkcjonalność | Issues |
| --- | --- | --- |
| M0 | Projekt Flutter Web, testy CI, deployment Pages, dokumentacja | [#1–#3](https://github.com/PawelWielga/learn-piano/issues/18), [#17](https://github.com/PawelWielga/learn-piano/issues/17) |
| M1 | Mikrofon, rozpoznawanie i stabilizacja pojedynczych nut, publiczny tester | [#4–#7](https://github.com/PawelWielga/learn-piano/issues/18) |
| M2 | Lokalny import MIDI, wybór partii, zakres pianinka, klawiatura, spadające nuty | [#8–#12](https://github.com/PawelWielga/learn-piano/issues/18) |
| M3 | Wait for Note, pełny ekran treningu, testy end-to-end i UX | [#13–#16](https://github.com/PawelWielga/learn-piano/issues/18) |

Szczegółowy backlog i kryteria wydania: **[MVP 1, issue #18](https://github.com/PawelWielga/learn-piano/issues/18)**.

## Uruchomienie lokalne

Wymagany Flutter **3.47.7** (stable) z Dart 3.13.5 oraz Chrome.

```sh
cd app
flutter pub get
flutter run -d chrome
```

Weryfikacja używana również przez GitHub Actions:

```sh
cd app
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
node --test test_js/*.test.cjs
flutter build web --release --base-href /learn-piano/
```

Więcej: [app/README.md](app/README.md).

## Układ poziomy

Na pionowym ekranie pojawia się komunikat o obróceniu urządzenia. Aplikacja
zachowuje wczytane MIDI, wybór melodii i postęp treningu po obrocie.
Jeśli podczas ćwiczenia działał mikrofon, jego nasłuch zostaje zatrzymany,
a trening wstrzymany. Po powrocie do poziomu trzeba ręcznie wznowić ćwiczenie.
Manifest zainstalowanej PWA sugeruje orientację poziomą, ale zwykła karta
mobilnej przeglądarki (szczególnie Safari iOS) nie udostępnia niezawodnego
wymuszenia fizycznego obrotu. Można też poszerzyć okno na desktopie.

## Trening na telefonie w poziomie

Na niskich ekranach w orientacji poziomej (wysokość poniżej 560 pikseli
logicznych) trening przechodzi w układ kompaktowy. Nad klawiaturą widoczne są:
stan mikrofonu, oczekiwana i wykryta nuta, komunikat o trafieniu oraz postęp.
Pianino i podgląd kolejnych nut dopasowują wysokość do dostępnego miejsca,
a Start/Pauza i Reset pozostają na ekranie bez przewijania całej strony.
Po wejściu do treningu klawiatura ustawia się raz pod zakres melodii i
**nie podąża za kolejnymi nutami**. Można ją przesuwać poziomo ręcznie,
a postęp, pauza i reset nie zmieniają wybranej pozycji. Na większych ekranach
pozostaje pełny widok treningu. W wyjątkowo niskim oknie sam podgląd
może przewijać się pionowo.

## Gra na ekranowej klawiaturze (#41)

Na ekranie treningu przycisk **mikrofonu / pianina** w górnym pasku
przełącza sposób gry. Wybierz **klawiaturę ekranową**, a następnie **Start**.
Dotykaj białych i czarnych klawiszy na dole ekranu: przeglądarka odtwarza
odpowiednie wysokości MIDI przez głośnik i zalicza poprawne naciśnięcia.
Mikrofon nie jest potrzebny ani uruchamiany w tym trybie. Nutę trzeba puścić,
zanim ponownie naciśnie się ten sam klawisz. Błędne nuty brzmią, ale nie
przesuwają ćwiczenia.

Przy przełączeniu źródła, pauzie, resecie i wyjściu z treningu aktywne
dźwięki są wyciszane. Na ekranie używany jest prosty syntezator Web Audio,
więc barwa jest przybliżeniem pianina, nie nagraniem prawdziwego instrumentu.
Przeglądarka musi obsługiwać Web Audio i zezwalać na odtwarzanie dźwięku
po interakcji użytkownika. Na fizycznym telefonie warto sprawdzić głośność,
opóźnienie i zachowanie przewijania. Gra z mikrofonu działa nadal jako
oddzielny tryb, aby głośnik nie powodował przypadkowego naliczania nut.

## Płynne nuty i odsłuch MIDI

W trybie **Wait for Note** spadające nuty po trafieniu płynnie przechodzą
do kolejnej pozycji, zamiast przeskakiwać. Gdy czekamy na zagranie nuty,
widok pozostaje w miejscu, a ćwiczenie nie zalicza kolejnych dźwięków samo.
Pozioma pozycja klawiatury pozostaje taka, jak ustawiono ją na początku
lub ręcznie przesunięto.

Przycisk z ikoną nuty w górnym pasku, **Posłuchaj wybranej partii MIDI**,
odtwarza melodię przez przeglądarkowy syntezator i jednocześnie przesuwa
nuty zgodnie z czasami i długościami zapisanymi w MIDI. Ponowne naciśnięcie
przerywa odsłuch. W tym trybie mikrofon nie ocenia gry i postęp treningu
pozostaje zachowany. Odsłuch dotyczy wybranej partii jednogłosowej, a nie
wszystkich ścieżek utworu. Dźwięki są syntezowane lokalnie bez sieci.

## CI i GitHub Pages

- **Pull request do `main`:** `.github/workflows/ci.yml` uruchamia format, analizę, testy oraz release build. Nie publikuje strony.
- **Merge/push do `main`:** `.github/workflows/deploy-pages.yml` powtarza kontrole, buduje projekt z `--base-href /learn-piano/` i publikuje `app/build/web` przez oficjalne akcje GitHub Pages.
- **Jednorazowa konfiguracja repozytorium:** `Settings → Pages → Build and deployment → Source: GitHub Actions`. Bez tego ustawienia workflow nie gwarantuje publicznego wdrożenia. Jeśli środowisko `github-pages` jest chronione, może wymagać zatwierdzenia.

Pierwszy workflow publikacji na GitHub Pages zakończył się sukcesem; dostępność i obsługę mikrofonu trzeba zweryfikować ręcznie na docelowych przeglądarkach.

## Poza MVP 1

Landing page Jaspr, natywne Android/iOS, akordy, nagrywanie melodii do MIDI, gotowe utwory, konta, statystyki, transpozycja i płatności. Pomysły na później opisuje [koncepcja projektu](docs/project-concept.md).

## Aktualny stan

M0 jest zrealizowane. W M1 tester mikrofonu wykrywa kandydackie nuty (YIN) oraz stabilizuje zdarzenia NoteOn/NoteOff. W M2 można lokalnie importować MIDI typu 0/1, wybierać jednogłosową partię, ustawić zakres instrumentu i oglądać spadające nuty nad klawiaturą (#8–#12). W M3 działa trening Wait for Note (#13–#14): po wyborze partii zgodnej z zakresem wybierz **Rozpocznij trening**, następnie **Start i mikrofon**. Każda stabilnie rozpoznana poprawna nuta przesuwa melodię, błędna nie zmienia postępu, a powtórzenie dźwięku wymaga oddzielnego uderzenia. Przy rozpoczęciu i wznowieniu trzeba najpierw wyciszyć instrument na krótką chwilę, aby już brzmiący dźwięk nie został zaliczony. Pauza, reset, ukończenie oraz wyjście z treningu wyłączają mikrofon. Rzeczywista jakość detekcji i wydajność wymagają testów na pianinie i przeglądarkach mobilnych. Szczegóły: [app/README.md](app/README.md).

## Nagrywanie nut do MIDI

Na ekranie głównym wybierz **Nagraj własną melodię**. Wybierz źródło nut:
**pianino przez mikrofon** (pozwolenie dopiero po wciśnięciu nagrywania, rozpoznawanie pojedynczych nut)
lub **klawiatura ekranowa** (wielodotyk i odsłuch naciskanych klawiszy).
Wciśnij **Rozpocznij nagrywanie**, zagraj melodię i wybierz **Zatrzymaj**.
Przycisk **Zapisz MIDI** pobiera lokalny plik `.mid` (SMF typ 0, 120 BPM),
który można później ponownie zaimportować. Zachowywane są numery MIDI, czasy
rozpoczęcia i zakończenia nut, nie surowe audio. Nagranie jest tylko w pamięci
otwartej strony do czasu pobrania; rozpoczęcie nowego zastępuje poprzednie.
Przerwanie mikrofonu lub przejście aplikacji w tło kończy nagranie z zachowaniem
już rozpoznanych nut. Detekcja akustyczna jest monofoniczna i przybliża momenty
naciśnięcia i puszczenia klawiszy na podstawie dźwięku.
