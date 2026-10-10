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

## CI i GitHub Pages

- **Pull request do `main`:** `.github/workflows/ci.yml` uruchamia format, analizę, testy oraz release build. Nie publikuje strony.
- **Merge/push do `main`:** `.github/workflows/deploy-pages.yml` powtarza kontrole, buduje projekt z `--base-href /learn-piano/` i publikuje `app/build/web` przez oficjalne akcje GitHub Pages.
- **Jednorazowa konfiguracja repozytorium:** `Settings → Pages → Build and deployment → Source: GitHub Actions`. Bez tego ustawienia workflow nie gwarantuje publicznego wdrożenia. Jeśli środowisko `github-pages` jest chronione, może wymagać zatwierdzenia.

Pierwszy workflow publikacji na GitHub Pages zakończył się sukcesem; dostępność i obsługę mikrofonu trzeba zweryfikować ręcznie na docelowych przeglądarkach.

## Poza MVP 1

Landing page Jaspr, natywne Android/iOS, akordy, nagrywanie melodii do MIDI, gotowe utwory, konta, statystyki, transpozycja i płatności. Pomysły na później opisuje [koncepcja projektu](docs/project-concept.md).

## Aktualny stan

M0 jest zrealizowane. W M1 tester mikrofonu wykrywa kandydackie nuty (YIN) oraz stabilizuje zdarzenia NoteOn/NoteOff. W M2 można lokalnie importować MIDI typu 0/1, wybierać jednogłosową partię, ustawić zakres instrumentu i oglądać spadające nuty nad klawiaturą (#8–#12). W M3 działa trening Wait for Note (#13–#14): po wyborze partii zgodnej z zakresem wybierz **Rozpocznij trening**, następnie **Start i mikrofon**. Każda stabilnie rozpoznana poprawna nuta przesuwa melodię, błędna nie zmienia postępu, a powtórzenie dźwięku wymaga oddzielnego uderzenia. Przy rozpoczęciu i wznowieniu trzeba najpierw wyciszyć instrument na krótką chwilę, aby już brzmiący dźwięk nie został zaliczony. Pauza, reset, ukończenie oraz wyjście z treningu wyłączają mikrofon. Rzeczywista jakość detekcji i wydajność wymagają testów na pianinie i przeglądarkach mobilnych. Szczegóły: [app/README.md](app/README.md).
