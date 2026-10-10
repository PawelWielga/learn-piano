# Learn Piano: Play & Train — koncepcja produktu

**Decyzja z 10.10.2026:** MVP 1 jest aplikacją **Flutter Web hostowaną na GitHub Pages**. Poprzedni plan rozpoczęcia od testowego Android APK został zastąpiony prototypem przeglądarkowym. Android, iOS i landing page rozważamy po MVP 1.

- Repozytorium: [PawelWielga/learn-piano](https://github.com/PawelWielga/learn-piano)
- Docelowy URL: https://pawelwielga.github.io/learn-piano/
- Backlog wydania: [issue #18](https://github.com/PawelWielga/learn-piano/issues/18)
- Status: M0 ukończono. W M1 działa lokalne wejście PCM z mikrofonu oraz zaimplementowano detektor chwilowego kandydata wysokości nuty (YIN). Stabilizacja NoteOn jest zaimplementowana (#6), a użytkownik potwierdził działanie testera na instrumencie. Formalna walidacja przeglądarek (#7) i trening pozostają otwarte. W M2 działa parser i import MIDI (#8), a wybór pojedynczej partii z walidacją jednogłosowości jest realizowany w #9.

## Problem i odbiorcy

Chcemy darmowego trenera do ćwiczeń na **rzeczywistym pianinku/keyboardzie bez wyjścia MIDI**, również dla dziecka korzystającego z telefonu. Aplikacja nie zastępuje instrumentu, tylko pomaga ćwiczyć. Użytkownik importuje własny plik MIDI i gra, a telefon lub komputer słucha przez mikrofon.

Bez konta, subskrypcji ani backendu. Import MIDI i analiza mikrofonu działają po stronie przeglądarki, bez wysyłania dźwięku oraz plików na serwer. Przy pierwszej wizycie trzeba pobrać zasoby strony, a mikrofon wymaga HTTPS (lub localhost) i zgody użytkownika.

## Zakres MVP 1 i kolejność

### M0 — fundament (issues #1–#3, #17)

- Utworzyć projekt **Web-only Flutter** w katalogu `app/`.
- Dodawać testy jednostkowe/widgetowe i release build do GitHub Actions CI na pull requestach.
- Na merge/push do `main` powtarzać walidację i publikować `app/build/web` przez GitHub Pages.
- Stosować `--base-href /learn-piano/` i jednorazowo ustawić **Settings → Pages → Source: GitHub Actions**.
- Lokalnie: `cd app && flutter pub get && flutter run -d chrome`; szczegóły w [app/README.md](../app/README.md).

### M1 — najpierw potwierdzić rozpoznawanie dźwięku (issues #4–#7)

- Pobierać próbki mikrofonu przez Web Audio API po kliknięciu „Włącz mikrofon”; zwalniać mikrofon po zatrzymaniu.
- Detektor pojedynczej wysokości MIDI (A4=440 Hz; MIDI 60=C4), ciszy i niepewności. Porównać algorytmy np. YIN/autokorelację na syntetycznych próbkach.
- Stabilizować odczyt i odróżniać osobne uderzenia tej samej nuty.
- Udostępnić publiczny tester wysokości/częstotliwości i **zmierzyć** błędy/opóźnienia na prawdziwym keyboardzie w przeglądarce desktopowej i mobilnej.

**Bramka M1:** kontynuować MIDI/UI dopiero po potwierdzeniu, że ćwiczenia jednej ręki są technicznie wykonalne. Sam widok testera nie dowodzi jakości pomiaru.

### M2 — MIDI i wizualizacja (issues #8–#12)

- Lokalny import `.mid`/`.midi` (SMF typ 0/1, tempo/PPQ, czasy i długości nut).
- Wybór pojedynczej melodii/ścieżki; wykrywanie nakładających się nut. Akordy, puste partie i uszkodzone pliki obsłużyć komunikatem, nie ukrytym pomijaniem.
- Konfiguracja faktycznego zakresu klawiszy instrumentu; blokada niegrywalnej melodii.
- Wirtualna klawiatura i nuty spadające w ślad za postępem ćwiczenia.

### M3 — interaktywny trening (issues #13–#16)

- **Wait for Note:** oczekiwanie na właściwą nutę MIDI i oktawę, bez automatycznego przejścia przy błędzie.
- Osobne uderzenia wymagane dla powtarzanych nut; pauza, reset i zakończenie melodii.
- Jeden dostępny ekran mobilny i testy regresji z deterministycznymi zdarzeniami (bez mikrofonu w CI).
- Ręczne testy Chrome desktop, Chrome Android i Safari iOS; udokumentowanie różnic.

## Granice MVP i ryzyka

**MVP jest monofoniczne.** Nie rozpoznajemy akordów. Źle dobrane harmoniczne i wybrzmiewanie pianina mogą mylić wysokość nuty i moment ponownego uderzenia. Weryfikujemy to na realnym instrumencie, nie obiecujemy skuteczności bez pomiarów. Praca offline po otwarciu strony zależy od buforowania zasobów przez przeglądarkę.

**Wyraźnie poza MVP 1:** natywne aplikacje Android/iOS, landing page Jaspr/SEO, konta, backend, synchronizacja, gotowa biblioteka piosenek, nagrywanie i eksport MIDI z mikrofonu, podkład audio, akordy, statystyki, automatyczna transpozycja, sklepy mobilne i płatności.

## Architektura i granice odpowiedzialności

| Warstwa | Założenie |
| --- | --- |
| Interfejs | Flutter Web; mobile-first, duże elementy sterujące |
| Audio | Web Audio API i getUserMedia za interfejsem adaptera |
| Detekcja | Osobny testowalny moduł pitch detection i stabilizacji NoteOn |
| Muzyka | Numer MIDI 0–127 jako model nuty; parser SMF i walidacja zakresu |
| Trening | Deterministyczny silnik `Wait for Note`, niezależny od widoku |
| Hosting | Statyczne GitHub Pages z GitHub Actions |
| Przechowywanie | Wyłącznie lokalne, bez wysyłania danych dziecka i audio |

W pierwszym wydaniu jedna aplikacja w `app/`; osobne pakiety dopiero, gdy rzeczywiście będą potrzebne. Dodatkowe platformy i landing page powstaną po zatwierdzeniu wykonalności MVP.

## Potencjalny kierunek po MVP

- Android/iOS z osobnymi adapterami mikrofonu i wspólnym silnikiem Dart.
- Nagrywanie monofonicznej melodii do MIDI (note-on/off, momenty i długości), możliwość korekty i eksportu.
- Transpozycja i konfiguracja trudności, statystyki postępu, wiele rąk i ewentualne akordy po walidacji algorytmu.
- Publiczna strona informacyjna, jeżeli będzie uzasadnienie do rozwijania SEO.

Nie dołączamy komercyjnych utworów MIDI bez licencji. W razie rozbieżności ze starszymi pomysłami, aktualny zakres określają [AGENTS.md](../AGENTS.md) i [issue #18](https://github.com/PawelWielga/learn-piano/issues/18).
