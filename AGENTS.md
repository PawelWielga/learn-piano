# AGENTS.md — Learn Piano: Play & Train

Instrukcje dla agentów AI i osób wprowadzających zmiany w repozytorium `PawelWielga/learn-piano`. Obowiązują w całym repozytorium, chyba że konkretny podkatalog otrzyma bardziej szczegółowy `AGENTS.md`.

## 1. Produkt i aktualny cel

Budujemy **darmową dla użytkownika** aplikację do ćwiczenia gry na **fizycznym pianinie lub keyboardzie bez wyjścia MIDI**. Docelowo powstanie natywna wersja Android na Google Play finansowana reklamami; aktualne MVP pozostaje Web-first, bez reklam. Użytkownik otwiera stronę, udziela dostępu do mikrofonu, importuje własny plik MIDI i ćwiczy melodię; aplikacja przechodzi dalej po wykryciu właściwej nuty.

**Pierwsze MVP jest Web-first**: Flutter Web hostowany na GitHub Pages, bez backendu, kont użytkowników, abonamentów i obowiązkowego połączenia z internetem po załadowaniu niezbędnych zasobów. Audio i importowane MIDI przetwarzamy lokalnie zarówno na Web, jak docelowo na Androidzie. Nie dodawaj usług serwerowych ani transmisji mikrofonu. Przyszły SDK reklam może mieć własną, jawną komunikację sieciową niezwiązaną z dźwiękiem.

Docelowy adres GitHub Pages po uruchomieniu publikacji:
`https://pawelwielga.github.io/learn-piano/`.

**Kolejność źródeł wymagań:**
1. Bieżące polecenie użytkownika i zaakceptowany zakres danego GitHub Issue.
2. Zbiorcze [MVP 1 — issue #18](https://github.com/PawelWielga/learn-piano/issues/18) oraz powiązane issues #1–#17.
3. [Roadmapa stabilizacji — issue #67](https://github.com/PawelWielga/learn-piano/issues/67), ten plik i aktualna implementacja.
4. [docs/project-concept.md](docs/project-concept.md) oraz [README.md](README.md) jako kontekst produktu.

Starsza dokumentacja opisuje Android APK jako pierwszy prototyp. **To założenie jest nieaktualne**; aktualny kierunek to najpierw Flutter Web i testy mikrofonu w przeglądarce. Aktualizacja dokumentacji jest śledzona w issue #17.

## 2. Zakres i etapy MVP 1

- **M0 — fundament:** aplikacja Flutter Web w `app/`, CI dla PR oraz automatyczny build i publikacja GitHub Pages przez GitHub Actions.
- **M1 — proof of concept:** przechwytywanie dźwięku z mikrofonu, detekcja pojedynczej nuty z oktawą, stabilizacja zdarzeń i ekran testera. Jakość na prawdziwym pianinie wymaga późniejszej walidacji (#7); do czasu dostępności sprzętu prowadzimy testy syntetyczne i benchmarki (#55–#57), bez przedstawiania ich jako testów fizycznego instrumentu.
- **M2 — MIDI i wizualizacja:** lokalny import `.mid`/`.midi`, wybór monofonicznej partii, konfiguracja faktycznego zakresu instrumentu, wirtualna klawiatura i spadające nuty.
- **M3 — trening:** tryb „Wait for Note”, który przechodzi do kolejnej nuty dopiero po poprawnym, osobnym uderzeniu; pełny przepływ ekranów, testy i dopracowanie mobilnego UX.

Nagrywanie nut do MIDI (z mikrofonu lub klawiatury ekranowej) zostało dodane osobnym wymaganiem użytkownika. Nie przechowujemy surowego audio.

**Poza MVP 1, ale w planie:** natywna aplikacja Flutter Android z reklamami (#69–#71), później ewentualnie iOS. Pozostałe przyszłe pomysły: landing page Jaspr, konta, backend, synchronizacja, gotowa biblioteka komercyjnych utworów, transpozycja i statystyki. Wykrywanie akordów i trening akordowy istnieją eksperymentalnie i wymagają walidacji na fizycznym instrumencie. Nie dodawaj Android SDK ani reklam przy okazji bieżących zadań Web.

## 3. Stack i układ repozytorium

- Język: **Dart**; aplikacja i UI: **Flutter**, obecnie Web, docelowo natywny Android. Nie zastępuj docelowo natywnej aplikacji opakowaniem całego Web w WebView.
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
3. Rozdziel detekcję **pojedynczych nut** (YIN) od eksperymentalnej detekcji **akordów/wielogłosowości**. Zwracaj stan „brak wiarygodnej nuty” dla ciszy, hałasu i niepewnego pomiaru; nie przedstawiaj przypuszczeń jako pewnego trafienia.
4. Rozdziel chwilowego kandydata pitch od **stabilnego zdarzenia NoteOn**. Jedno przytrzymanie klawisza nie może zaliczyć wielu kolejnych kroków. Sekwencja `C4, C4, C4` wymaga trzech odrębnych uderzeń; uwzględniaj wybrzmiewanie instrumentu i możliwość błędów detekcji początku dźwięku.
5. Nie blokuj wątku UI intensywną analizą audio. Zachowaj kontrolę nad rozmiarem buforów, częstotliwością aktualizacji widoku i opóźnieniem detekcji. Zachowuj sample rate rzeczywistego wejścia.
6. Import MIDI musi respektować `note on/off` (w tym `note on` z velocity 0), ticks/PPQ, tempo i jego zmiany, czasy nut oraz strukturę ścieżek/kanałów. Obsłuż poprawne pliki typu 0/1 w granicach MVP i błędy danych bez crasha.
7. W treningu wybieramy jedną partię MIDI (ścieżka/kanał). Partie monofoniczne i akordy obsługuj zgodnie z możliwościami silnika; zbyt niejednoznaczne nakładanie tego samego pitch oraz nuty poza zakresem instrumentu zgłaszaj czytelnie. Bez ukrytej transpozycji i cichego usuwania zdarzeń.
8. **Wait for Note** porównuje zdarzenia z detektora do oczekiwanej nuty MIDI. Błędna nuta nie przesuwa postępu; pauza/reset nie zaliczają zdarzeń; postęp i animacja wynikają z tego samego stanu treningu, nie z autonomicznego zegara odtwarzania.
9. Projektuj **mobile-first w orientacji poziomej**: czytelne klawisze, duże przyciski dotykowe i zrozumiałe komunikaty. W pionie pokaż ekran z prośbą o obrót, zachowaj stan nawigacji i ćwiczenia, a aktywny nasłuch wstrzymaj bez automatycznego wznowienia. Pokaż status mikrofonu oraz stan rozpoznawania; unikaj migotania UI.
10. **Preferuj sprawdzone biblioteki zamiast własnej implementacji typowych rozwiązań.** Dodawaj zależności wtedy, gdy rozwiązują realny problem; sprawdzaj Flutter Web, wsparcie offline, aktualność, licencje kodu/modeli/sampli, wydajność, koszt rozmiaru i złożoność integracji. Nie wprowadzaj rozbudowanych frameworków bez wyraźnego powodu.

## 4a. Library-first i selektywna przebudowa (decyzja 2026-10-12)

**Właściciel projektu dopuszcza zastąpienie lub napisanie od nowa całych modułów, jeśli uzasadniają to pomiary, brak utrzymywalności albo możliwość użycia sprawdzonej biblioteki.** Nie zachowuj własnego kodu wyłącznie dlatego, że już powstał. Nie oznacza to zgody na bezwarunkowy rewrite całego produktu.

1. **Przed pisaniem DSP, MIDI, syntezatora, odtwarzacza lub mechanizmów przeglądarkowych od zera** zbadaj istniejące biblioteki. Preferowane kierunki do weryfikacji: `@spotify/basic-pitch` dla offline polyphonic transcription (#59), `fftea` dla FFT (#58), `@tonejs/midi` dla MIDI (#64), `Tone.js` dla syntezy/schedulingu (#62/#64) oraz `pitchy` jako alternatywa dla monofonicznego pitch detection (#57). To kandydaci, nie zatwierdzone zależności.
2. Porównuj kandydatów na **identycznych, poprawnie zsynchronizowanych i legalnych fixturach**, mierząc accuracy (pitch/onset/offset, precision/recall/F1), fałszywe nuty, latencję, czas obliczeń, pamięć i rozmiar builda. Podawaj ograniczenia testów syntetycznych.
3. Sprawdzaj **licencję osobno dla kodu, wag modeli, soundfontów, sampli i danych testowych** pod kątem **komercyjnej dystrybucji Androida z reklamami**. Preferuj prawidłowo licencjonowane komponenty dopuszczające komercyjne użycie (MIT/BSD/Apache-2.0 itp.). GPL/AGPL wymagają oceny obowiązków, a NC (np. zbiór MAESTRO CC BY-NC-SA) dodatkowego uprawnienia lub oceny przed użyciem w komercyjnym procesie; nie zakładaj automatycznej zgody. Rejestr ryzyk: #68. Żadnych CDN/backendu niezbędnych do analizy muzycznego audio.
4. **Zamieniaj moduły etapami** przez testowalne interfejsy i adaptery: nowy silnik obok starego → porównanie → migracja → usunięcie zbędnego kodu. Nie trzymaj dwóch stałych implementacji bez ważnego powodu.
5. **Wolno usunąć lub przepisać własną FFT, transkrypcję MP3, parser/writer MIDI, syntezator lub zbyt rozbudowane widżety**, jeżeli nowy moduł zachowuje wymagane funkcje i przechodzi porównawcze testy regresji. Nie przepisuj niezwiązanego UI, nawigacji ani CI tylko z przyzwyczajenia.
6. Basic Pitch TS ma starszy stos TensorFlow.js i zgłoszenia kompatybilności mobilnej: przed wyborem konieczny jest działający proof of concept w docelowej przeglądarce i test offline (#59), a nie jedynie README biblioteki. JS-only model nie jest automatycznie dostępny w natywnym Androidzie; wymagana ocena natywnego backendu lub adaptera (#69).
7. **Bez fizycznego sprzętu** działamy na deterministycznym audio/MIDI i automatycznych przeglądarkach. Ograniczenia sprzętowe z #7 i #16 pozostają otwarte; nie raportuj tych kryteriów jako zaliczonych.
8. Każdą większą migrację poprzedź krótkim ADR: co usuwamy, co zastępujemy, dlaczego, wymagania licencyjne i zgodność komercyjna, obsługa natywnego Androida, dane benchmarkowe, plan powrotu i lista testów. Główny backlog: [#67](https://github.com/PawelWielga/learn-piano/issues/67).

## 4b. Komercyjny Android i reklamy (cel po Web MVP, 2026-10-12)

1. **Wspólny Flutter i domena, oddzielne adaptery Web/Android.** MIDI, nuty, WaitForNote, normalizacja zdarzeń i testy pozostają niezależne od platformy. Mikrofon/PCM, dekodowanie plików, wyjście audio, transkrypcja AI, zapis plików i ustawienia mają testowalne interfejsy; `dart:js_interop` i Web Audio pozostają tylko w web adapterach (#69).
2. Każdy kandydat library-first musi mieć sprawdzoną **komercyjną licencję** na kod, modele/wagi, soundfonty/sample i dane testowe oraz realistyczny plan natywnego działania na Androidzie (np. TFLite/ONNX jeśli uzasadniają to benchmarki). Nie wybieraj Basic Pitch TS ani Tone.js jako jedynego rozwiązania domenowego tylko dlatego, że działają w przeglądarce (#59, #60, #64, #68).
3. **Web MVP bez reklam.** Google Mobile Ads Flutter Plugin działa na Androidzie/iOS, nie w Flutter Web; integracja dopiero w fazie Android. Podstawowy trening lokalny ma pozostać dostępny offline, przy odmowie zgód i braku reklam. SDK nie dostaje surowego audio ani importowanych MIDI (#70).
4. Przed wyborem SDK reklamowego ustal rzeczywistą **grupę wiekową** odbiorców; obecny projekt dotyka także scenariuszy dziecięcych. Google Play Families wymaga szczególnych ograniczeń reklam i odpowiednich wersji samocertyfikowanych SDK dla dzieci i nieustalonego wieku; nie zakładaj, że AdMob nadaje się do każdej grupy. Nie deklaruj sztucznie grupy dorosłej tylko po to, by obejść wymagania (#70).
5. Gdy reklamy będą wdrażane, zweryfikuj aktualne przepisy i polityki (GDPR/RODO, UMP/CMP, Google Play Data safety, deklaracja reklam, dane i identyfikatory SDK). Nie wstawiaj reklam w aktywnym treningu, nad klawiaturą, podczas pracy mikrofonu ani w miejscach generujących przypadkowe kliknięcia; nie blokuj podstawowego treningu przy braku reklam. W development używaj testowych jednostek reklamowych (#70).
6. Docelowo CI buduje Flutter Web i Android (AAB), testy adapterów i emulator/fake PCM. Emulator nie zastępuje fizycznego Androida ani pianina; #7 i #16 pozostają do walidacji sprzętowej (#71).

## 5. Mikrofon, bezpieczeństwo i prywatność

- O dostęp do mikrofonu pytaj **po świadomej akcji użytkownika**, a nie automatycznie po otwarciu strony.
- Korzystaj z bezpiecznego kontekstu (`HTTPS` na Pages, `localhost` podczas developmentu); obsłuż odmowę uprawnień, brak urządzenia, zmianę/utratę strumienia i nieobsługiwaną przeglądarkę.
- Po zakończeniu nasłuchu zwolnij zasoby, zamknij/wycisz przetwarzanie i zatrzymaj `MediaStreamTrack`. Zadbaj o ponowne uruchamianie oraz usypianie/wznawianie karty.
- **Nie przesyłaj, nie loguj i domyślnie nie zapisuj surowego audio**, importowanych plików MIDI ani danych dziecka. Lokalne ustawienia mogą być przechowywane w przeglądarce, jeśli jest to niezbędne i czytelne dla użytkownika.
- Nie wprowadzaj analityki, trackerów, reklam, kluczy API ani usług chmurowych do Web MVP. Reklamy Android wymagają odrębnej integracji i audytu prywatności (#70); ich transfer danych nigdy nie obejmuje mikrofonu ani plików muzycznych.
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

**Aktualny stan repozytorium (2026-10-12):** Flutter Web jest wdrożony na GitHub Pages, działają import MIDI, parser SMF 0/1, ekranowa klawiatura, podgląd spadających nut, trening Wait for Note (w tym ćwiczenia akordowe), lokalne nagrywanie MIDI i eksperymentalna transkrypcja MP3 do MIDI. Mikrofon korzysta z getUserMedia/AudioWorklet; tryb monofoniczny z YIN, wielogłosowy z autorskim analizatorem widma. Kodu DSP, wyniku MP3 ani kompatybilności na realnym pianinie nie uznawaj za zweryfikowane tylko dlatego, że przechodzą testy syntetyczne. Aktualna roadmapa jakości i przebudowy to #67 (#54–#66); testy rzeczywistego instrumentu #7 i fizycznych urządzeń #16 pozostają do wykonania, gdy sprzęt będzie dostępny. W `app/pubspec.lock` jest Flutter/Dart kompatybilny z CI, a workflowy przypinają Flutter 3.47.7. Każdą nową zmianę weryfikuj bieżącym CI, nie wcześniejszym wynikiem.

Weryfikacja istniejącego `app/`:

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
- [Stabilizacja i przebudowa library-first — #67](https://github.com/PawelWielga/learn-piano/issues/67)
- [Komercyjny audyt licencji — #68](https://github.com/PawelWielga/learn-piano/issues/68)
- [Przenośna architektura Web/Android — #69](https://github.com/PawelWielga/learn-piano/issues/69)
- [Reklamy, zgody i Google Play — #70](https://github.com/PawelWielga/learn-piano/issues/70)
- [Android build i emulator CI — #71](https://github.com/PawelWielga/learn-piano/issues/71)
