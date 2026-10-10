# AGENTS.md — Learn Piano: Play & Train

Instrukcje dla agentów AI i osób wprowadzających zmiany w repozytorium `PawelWielga/learn-piano`. Obowiązują w całym repozytorium, chyba że konkretny podkatalog otrzyma bardziej szczegółowy `AGENTS.md`.

## 1. Produkt i aktualny cel

Budujemy darmową aplikację do ćwiczenia gry na **fizycznym pianinie lub keyboardzie bez wyjścia MIDI**. Użytkownik otwiera stronę, udziela dostępu do mikrofonu, importuje własny plik MIDI i ćwiczy melodię; aplikacja przechodzi dalej po wykryciu właściwej nuty.

**Pierwsze MVP jest Web-first**: Flutter Web hostowany na GitHub Pages, bez backendu, kont użytkowników, abonamentów i obowiązkowego połączenia z internetem po załadowaniu niezbędnych zasobów. Audio i importowane MIDI przetwarzamy lokalnie w przeglądarce. Nie dodawaj usług serwerowych ani transmisji mikrofonu.

Docelowy adres GitHub Pages po uruchomieniu publikacji:
`https://pawelwielga.github.io/learn-piano/`.

**Kolejność źródeł wymagań:**
1. Bieżące polecenie użytkownika i zaakceptowany zakres danego GitHub Issue.
2. Zbiorcze [MVP 1 — issue #18](https://github.com/PawelWielga/learn-piano/issues/18) oraz powiązane issues #1–#17.
3. Ten plik i aktualna implementacja.
4. [docs/project-concept.md](docs/project-concept.md) oraz [README.md](README.md) jako kontekst produktu.

Starsza dokumentacja opisuje Android APK jako pierwszy prototyp. **To założenie jest nieaktualne**; aktualny kierunek to najpierw Flutter Web i testy mikrofonu w przeglądarce. Aktualizacja dokumentacji jest śledzona w issue #17.

## 2. Zakres i etapy MVP 1

- **M0 — fundament:** aplikacja Flutter Web w `app/`, CI dla PR oraz automatyczny build i publikacja GitHub Pages przez GitHub Actions.
- **M1 — proof of concept:** przechwytywanie dźwięku z mikrofonu, detekcja pojedynczej nuty z oktawą, stabilizacja zdarzeń i ekran testera. Sprawdzamy skuteczność na prawdziwym pianinku, zanim rozbudujemy produkt.
- **M2 — MIDI i wizualizacja:** lokalny import `.mid`/`.midi`, wybór monofonicznej partii, konfiguracja faktycznego zakresu instrumentu, wirtualna klawiatura i spadające nuty.
- **M3 — trening:** tryb „Wait for Note”, który przechodzi do kolejnej nuty dopiero po poprawnym, osobnym uderzeniu; pełny przepływ ekranów, testy i dopracowanie mobilnego UX.

**Poza MVP 1:** aplikacje natywne Android/iOS, landing page Jaspr, konta, backend, synchronizacja w chmurze, gotowa biblioteka komercyjnych utworów, rozpoznawanie akordów, nagrywanie audio do MIDI, transpozycja i statystyki. Nie implementuj ich przy okazji innych zadań.

## 3. Stack i układ repozytorium

- Język: **Dart**; aplikacja i UI: **Flutter Web**.
- Audio: przeglądarkowe **Web Audio API / getUserMedia**; sposób dostarczania próbek (np. AudioWorklet i interop JS) należy potwierdzić eksperymentem na obsługiwanych przeglądarkach.
- Detekcja wysokości: testowalny, niezależny od UI algorytm; rozważ YIN lub autokorelację, ale wybierz rozwiązanie na podstawie pomiarów. Nie zakładaj, że FFT z największym pikiem jest wystarczające.
- MIDI: lokalny parser/import zdarzeń i tempa; dobór biblioteki po ocenie kompatybilności Flutter Web, utrzymania i licencji.
- Grafika nut/klawiatury: widgety Flutter, w razie potrzeby `CustomPainter`; utrzymuj płynność na telefonach.
- Hosting: statyczne pliki Flutter Web publikowane przez GitHub Actions na **GitHub Pages**.

Planowany podział (nie zakładaj, że katalog już istnieje):

```text
/
├── AGENTS.md
├── README.md
├── docs/
│   └── project-concept.md
├── app/                    # Flutter Web: główna aplikacja MVP
│   ├── lib/
│   ├── test/
│   └── web/
└── .github/
    └── workflows/         # CI i GitHub Pages deployment
```

Jeśli moduły audio, MIDI lub treningu trzeba rozdzielić, preferuj na początek logiczny podział w `app/lib/`. Osobne pakiety `packages/` wydzielaj dopiero wtedy, gdy istnieje uzasadniona potrzeba współdzielenia i testowania. `site/` oraz natywne katalogi platform są poza aktualnym MVP.

## 4. Reguły architektury i implementacji

1. Oddziel **źródło audio**, **algorytm pitch detection**, **stabilizację zdarzeń nut**, **parser MIDI**, **silnik treningu** oraz **prezentację**. Komponenty logiki powinny działać bez widgetów i bez przeglądarkowego mikrofonu.
2. Modeluj nuty przede wszystkim jako **numery MIDI (0–127)**; nazwy typu `C4` i częstotliwości to reprezentacje pochodne. Utrzymaj konsekwentną konwencję oktaw (MIDI 60 = C4) i standardowe strojenie A4 = 440 Hz, o ile wymagania nie mówią inaczej.
3. Detektor rozpoznaje **pojedynczy dźwięk**, nie akord. Zwracaj stan „brak wiarygodnej nuty” dla ciszy, hałasu i niepewnego pomiaru; nie przedstawiaj przypuszczeń jako pewnego trafienia.
4. Rozdziel chwilowego kandydata pitch od **stabilnego zdarzenia NoteOn**. Jedno przytrzymanie klawisza nie może zaliczyć wielu kolejnych kroków. Sekwencja `C4, C4, C4` wymaga trzech odrębnych uderzeń; uwzględniaj wybrzmiewanie instrumentu i możliwość błędów detekcji początku dźwięku.
5. Nie blokuj wątku UI intensywną analizą audio. Zachowaj kontrolę nad rozmiarem buforów, częstotliwością aktualizacji widoku i opóźnieniem detekcji. Zachowuj sample rate rzeczywistego wejścia.
6. Import MIDI musi respektować `note on/off` (w tym `note on` z velocity 0), ticks/PPQ, tempo i jego zmiany, czasy nut oraz strukturę ścieżek/kanałów. Obsłuż poprawne pliki typu 0/1 w granicach MVP i błędy danych bez crasha.
7. W treningu wybieramy pojedynczą monofoniczną partię. Wykryte akordy/nachodzące nuty oraz nuty poza zakresem fizycznej klawiatury zgłaszamy czytelnie, bez ukrytej transpozycji, automatycznego wybierania dowolnej nuty akordu lub cichego usuwania zdarzeń.
8. **Wait for Note** porównuje zdarzenia z detektora do oczekiwanej nuty MIDI. Błędna nuta nie przesuwa postępu; pauza/reset nie zaliczają zdarzeń; postęp i animacja wynikają z tego samego stanu treningu, nie z autonomicznego zegara odtwarzania.
9. Projektuj **mobile-first**: czytelne klawisze, duże przyciski dotykowe, zrozumiałe komunikaty i obsługa pionowego ekranu. Pokaż status mikrofonu oraz stan rozpoznawania; unikaj migotania UI.
10. Dodawaj zależności tylko wtedy, gdy są potrzebne do bieżącego issue. Sprawdzaj wsparcie Flutter Web, aktualność, licencję i koszt rozmiaru aplikacji; nie wprowadzaj rozbudowanych frameworków bez wyraźnego powodu.

## 5. Mikrofon, bezpieczeństwo i prywatność

- O dostęp do mikrofonu pytaj **po świadomej akcji użytkownika**, a nie automatycznie po otwarciu strony.
- Korzystaj z bezpiecznego kontekstu (`HTTPS` na Pages, `localhost` podczas developmentu); obsłuż odmowę uprawnień, brak urządzenia, zmianę/utratę strumienia i nieobsługiwaną przeglądarkę.
- Po zakończeniu nasłuchu zwolnij zasoby, zamknij/wycisz przetwarzanie i zatrzymaj `MediaStreamTrack`. Zadbaj o ponowne uruchamianie oraz usypianie/wznawianie karty.
- **Nie przesyłaj, nie loguj i domyślnie nie zapisuj surowego audio**, importowanych plików MIDI ani danych dziecka. Lokalne ustawienia mogą być przechowywane w przeglądarce, jeśli jest to niezbędne i czytelne dla użytkownika.
- Nie wprowadzaj analityki, trackerów, reklam, kluczy API ani usług chmurowych bez osobnego wymagania.
- Waliduj rozmiar i strukturę wczytywanego pliku. Błędy wejścia są normalnym przypadkiem UX, nie nieobsłużonym wyjątkiem.
- Nie kopiuj do repozytorium chronionych prawem autorskim piosenek lub cudzych nagrań bez odpowiedniej licencji. Fixtury testowe twórz samodzielnie albo używaj materiałów z jasną licencją.

## 6. GitHub Actions, CI i GitHub Pages

Docelowo są dwa niezależne workflowy:
- **CI** na `pull_request` do `main`: pobranie zależności, formatowanie, analiza statyczna, testy i kontrolny build Web. CI nie publikuje strony.
- **Deploy** na `push` do `main` (oraz opcjonalnie `workflow_dispatch`): te same kontrole jakości, release build i publikacja poprzez `actions/configure-pages`, `actions/upload-pages-artifact` i `actions/deploy-pages`, z oddzielnymi uprawnieniami tylko dla deploymentu.

Ważne zasady:
- Publikuj **`app/build/web`**; buduj dla podścieżki repozytorium:
  ```sh
  cd app
  flutter build web --release --base-href /learn-piano/
  ```
- Zachowaj zgodną, **przypiętą i udokumentowaną wersję Flutter/Dart** w lokalnym środowisku i obu workflowach. Nie wpisuj arbitralnej wersji, dopóki nie zostanie sprawdzona przy implementacji #1/#2.
- Ustaw minimalne permissions: tylko odczyt dla CI; dla joba deploy m.in. `pages: write` i `id-token: write`, środowisko `github-pages` oraz kontrolę współbieżnych wdrożeń.
- Preferuj oficjalny mechanizm Pages **GitHub Actions** zamiast wypychania wygenerowanych plików na gałąź `gh-pages`. Nie commituj `build/` ani wygenerowanych artefaktów.
- Publikacja następuje tylko po pomyślnym buildzie i testach. Na repozytorium trzeba jednorazowo ustawić **Settings → Pages → Source: GitHub Actions**.
- Sprawdzaj `base href`, ścieżki do assets i zachowanie odświeżania strony. Nie zakładaj, że dowolny deep link będzie działał na statycznym hostingu bez dodatkowej konfiguracji.
- Nie używaj sekretów w klienckiej aplikacji Web: skompilowany JS i zasoby są publiczne.

## 7. Komendy developerskie i weryfikacja

**Aktualny stan repozytorium:** w ramach M0 przygotowano projekt Flutter Web w `app/` oraz workflowy CI/Pages. Ekran testera jest na razie przygotowawczy, bez uruchomionego mikrofonu. W pierwszym przebiegu walidacyjnym przeprowadzono formatowanie, analizę, test widgetowy i release build Flutter Web w GitHub Actions. `app/pubspec.lock` został wygenerowany Flutterem 3.47.7 i dodany do repozytorium. Nie twierdź, że testy/build zakończyły się powodzeniem bez ich uruchomienia.

Gdy `app/` zostanie utworzony:

```sh
cd app
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release --base-href /learn-piano/
```

Uruchamianie lokalne: `flutter run -d chrome` z `app/`. Jeżeli środowisko nie ma Fluttera, jasno zaznacz ograniczenie zamiast pozorować walidację.

**Wymagane testy odpowiednio do zmiany:**
- Unit: pitch → nuta/oktawa, cisza, harmoniczne, stabilizacja, powtarzane uderzenia, walidacja zakresu, odczyt MIDI (tempo, note-off, wiele ścieżek, akordy), przejścia stanu treningu.
- Widget/integration: wybór MIDI → wybór partii → trening; fałszywy i poprawny dźwięk; pauza/reset; błędy uprawnień i importu.
- CI nie wymaga mikrofonu: wstrzykuj deterministyczny fake wejścia audio i syntetyczne/legitne fixtury.
- Ręcznie na prawdziwym sprzęcie: Chrome desktop, Chrome Android i Safari iOS, w miarę dostępności; dokumentuj realne opóźnienia, błędy i różnice przeglądarek. Nie deklaruj kompatybilności bez testu.

## 8. Sposób pracy agenta

1. Przed edycją przeczytaj ten plik, `README.md`, odpowiednie fragmenty `docs/project-concept.md` i issue, którego dotyczy zadanie. Sprawdź rzeczywistą strukturę repozytorium.
2. Realizuj **jedno konkretne issue lub niewielki, uzasadniony zakres**. Nie rozszerzaj MVP ani architektury „na zapas”. Trzymaj zmiany małe i nadające się do code review.
3. Dla zmian w działaniu dodaj lub zaktualizuj testy, komunikaty błędów oraz dokumentację użytkową/developerską. Stosuj `dart format`, `flutter analyze` i `flutter test` tam, gdzie są dostępne.
4. Unikaj platformowo zależnych importów w logice domenowej. Izoluj interop Web Audio za kontraktem, żeby testy i późniejsze platformy mogły użyć innych adapterów.
5. Nie wykonuj destrukcyjnych operacji repozytorium, nie zmieniaj konfiguracji Pages, nie dodawaj sekretów ani nie usuwaj funkcji bez wymagania. Zmiany w workflowach oceniaj pod kątem uprawnień, triggerów i ryzyka publikacji.
6. W podsumowaniu pracy podaj: wykonany zakres, zmienione pliki, wyniki faktycznie uruchomionych testów, nierozwiązane ryzyka oraz numer powiązanego issue.

## 9. Przydatne odnośniki

- [Backlog i kryteria ukończenia MVP 1 — #18](https://github.com/PawelWielga/learn-piano/issues/18)
- [Web-first: zmiana dokumentacji — #17](https://github.com/PawelWielga/learn-piano/issues/17)
- [Flutter Web — #1](https://github.com/PawelWielga/learn-piano/issues/1)
- [CI GitHub Actions — #2](https://github.com/PawelWielga/learn-piano/issues/2)
- [Deployment GitHub Pages — #3](https://github.com/PawelWielga/learn-piano/issues/3)
- [Web Audio — #4](https://github.com/PawelWielga/learn-piano/issues/4)
- [Tester nut i próby sprzętowe — #7](https://github.com/PawelWielga/learn-piano/issues/7)
