# Learn Piano — konkurencja i publicznie ujawnione technologie

**Data audytu:** 2026-10-12  
**Kontekst:** Flutter Web teraz; natywny Android z reklamami później, darmowy trening fizycznego pianina, mikrofon, własne MIDI i offline MP3 → MIDI.  
**Zasada dowodowa:** opisy funkcji i liczby z oficjalnych stron producentów ≠ wiedza o ich implementacji, trafności ani przychodach. Historyczne wpisy inżynierskie oznaczamy rokiem. Gdy brak ujawnionej biblioteki, piszemy „nie ujawniono”, nie zgadujemy. Nie analizowaliśmy kodu APK ani naruszalnych zabezpieczeń.

## 1. Konkurencja: nauka gry i ćwiczenia

| Produkt | Zakres potwierdzony u producenta | Potwierdzony stack / jakość dowodów | Wniosek dla Learn Piano |
| --- | --- | --- | --- |
| **Simply Piano** (Simply/JoyTunes) | Mikrofon, MIDI i natychmiastowe sprzężenie zwrotne; lekcje i akordy | **Najmocniejszy dowód techniczny, ale historyczny (2018)**: własny **MusicSense**, PCM → wektor 88 klawiszy, on-device ML; Android korzystał z TensorFlow C++/JNI, iOS z Accelerate; osobny UI natywny i rendering `libGDX` Android/`Sparrow` iOS. Nie wiadomo, czy tak samo jest w 2026. | Własny model 88-note ML i lokalna inferencja to potwierdzony kierunek, ale nie kopiujemy starego stosu platformowego. |
| **flowkey** | Web/mobile, akustyczny mikrofon lub bezpośredni USB/Bluetooth MIDI; deklaruje własną technologię rozpoznawania | **Marketing firmy + support**; konkretnych bibliotek, modeli i trenowania nie potwierdzono. Firma jawnie mówi, że MIDI daje dużo pewniejszy wynik niż mikrofon. | Rozważyć opcjonalne fizyczne USB MIDI jako fallback, nie obiecywać równie dobrej jakości mikrofonu. |
| **Yousician** | Aplikacja ocenia wykonanie instrumentu na żywo | **Marketing producenta**: 'proprietary audio recognition', bez publicznej nazwy bibliotek lub konkretnego modelu. | Nie zakładać, że duzi gracze korzystają z Basic Pitch/ONNX. |
| **Skoove** | Nauka na pianinie akustycznym, Web i mobilnie, microphone/USB MIDI, feedback na żywo | **Funkcje oficjalne**, szczegóły ML/DSP nieujawnione; producent poleca MIDI dla sprawniejszej i dokładniejszej detekcji. | UX treningu i obsługa problematycznych mikrofonów to ważniejsza przewaga niż liczba trybów. |
| **Piano Marvel** | Ćwiczenia i scoring; mikrofon w pierwszej fazie na iPhone/iPad | **Oficjalne deklaracje producenta**: ML, pod idealnymi warunkami 99% poprawności polifonii 2 nut i 90% dla 3 nut. To ich własna metryka, **nie** nasz onset/offset F1; wsparcie na innych platformach jest ograniczone. | Nawet duży produkt przyznaje ograniczenia akordów. Nie obiecywać bezbłędnej oceny 4–5 nut na mikrofonie. |
| **Playground Sessions** | Scoring z mikrofonu lub MIDI, pianino akustyczne i cyfrowe | **Funkcje oficjalne**; określenie pitch detection, bez ujawnionej biblioteki. | Rozwiązanie „mikrofon lub MIDI” to rynkowy standard. |
| **Piano Academy** (Yokee) | Mikrofon, MIDI, klawiatura ekranowa, nauka z nut, gry; ponad 10 mln pobrań w Google Play | **Opis Google Play**; implementacja audio/ML nieujawniona. Monetyzacja w opisie sklepu przez in-app purchases. | Darmowa podstawowa oferta nie wystarcza; liczy się płynność nauki i skuteczność. |
| **Synthesia** (synthesia.app, NIE serwis wideo o tej samej nazwie) | Własne MIDI, spadające nuty, Wait for Note, osobne ręce, eksport/recorder | **Oficjalne funkcje**, pełny stos silnika nieujawniony; potwierdzone MIDI/USB. Nie znaleziono udokumentowanego rozpoznawania fizycznego pianina przez mikrofon. | Import dowolnego MIDI i Wait for Note **nie są unikalne**. Wyróżnik może stanowić brak kabla + darmowość. |
| **Perfect Piano** (Revontulet Soft) | Android, klawiatura dotykowa, MIDI, spadające nuty, nagrywanie, multiplayer; ponad **100 mln pobrań** | **Google Play**: reklamy i IAP, deklaruje także obsługę OpenSL ES (beta), ale nie ujawnia modelu rozpoznawania akustycznego pianina. OpenSL ES jest przestarzałym API; Android dziś poleca **Oboe/AAudio**. | Model darmowy + reklamy ma rzeczywiste wdrożenie o ogromnej skali, ale to bardziej instrument ekranowy niż precyzyjna ocena gry akustycznej. Bez dowodów na poziom przychodów. |

### Źródła konkurencji (oficjalne)

- Simply Piano — ML/PCM/TensorFlow/C++ (2018): https://medium.com/hellosimply/a-look-under-the-hood-of-simply-piano-part-2-3ba3cafa1bbf
- Simply Piano — UI `libGDX`/`Sparrow` (2018): https://medium.com/hellosimply/a-look-under-the-hood-of-simply-piano-part-1-7050d297f611
- flowkey — firma i własny note recognition: https://www.flowkey.com/en/about
- flowkey — MIDI względem mikrofonu: https://help.flowkey.com/en/articles/412902-connect-your-instrument-to-your-android-device
- Yousician — własne audio recognition: https://yousician.com/company
- Skoove — funkcje i mic/MIDI: https://www.skoove.com/blog/skoove-vs-simply-piano/
- Piano Marvel — ML i procenty pod warunkami idealnymi: https://pianomarvel.com/en/feature/microphone-assessment
- Playground Sessions — mikrofon / MIDI: https://support.playgroundsessions.com/hc/en-us/articles/40387576759956-What-is-the-difference-between-feedback-and-scoring-from-my-device-s-microphone-and-connecting-with-a-cable
- Piano Academy — Google Play: https://play.google.com/store/apps/details?id=com.yokee.piano.keyboard
- Synthesia — własne MIDI i Wait for Note: https://synthesia.app/ , https://synthesia.app/support/guide/addSongsAndroid
- Perfect Piano — reklamy, 100M+ pobrań, OpenSL ES: https://play.google.com/store/apps/details?id=com.gamestar.perfectpiano
- Android recommends **Oboe/AAudio**, not OpenSL ES for new designs: https://developer.android.com/ndk/guides/audio

## 2. Osobni konkurenci funkcji MP3 → MIDI

| Produkt | Ujawniony zakres | Technologia |
| --- | --- | --- |
| **Spotify Basic Pitch** | audio z pojedynczego instrumentu, także akordy, → MIDI; darmowa demonstracja | Open-source model ML, TensorFlow/TFLite/ONNX, Spotify Audio Intelligence Lab |
| **Klangio Piano2Notes** | audio/nagranie/link → nuty/MIDI/MusicXML, edycja wyniku | Producent ujawnia AI, ale nie potwierdza zastosowania konkretnego open-source modelu. Import audio i edytor wskazują wartość korekty nut po ML. |
| **Google Magenta Piano Scribe / Onsets and Frames** | naukowy model piano-specific, działający demonstrator w przeglądarce | Jawny kod + CNN/LSTM onsets/frames. Historyczny framework, dane i metryki nieporównywalne automatycznie z Basic Pitch. |

**Bardzo ważne:** Spotify zaznacza, że Basic Pitch działa najlepiej przy **jednym instrumencie**. To nie jest gwarantowana transkrypcja całego miksu MP3 (pianino + wokal + perkusja), ani gotowy silnik **realtime piano score**. Traktować offline MP3→MIDI i realtime PCM→aktywne nuty jako odrębne zadania/adaptery.

Źródła:
- https://basicpitch.spotify.com/
- https://github.com/spotify/basic-pitch
- https://engineering.atspotify.com/2022/6/meet-basic-pitch
- https://piano2notes.klang.io/
- https://magenta.tensorflow.org/onsets-frames

## 3. Które open-source rozwiązania mają udokumentowane popularne produkty?

| Technologia | Potwierdzony produkt / referencja | Co to faktycznie dowodzi i czego NIE |
| --- | --- | --- |
| **Tone.js** | **Google Chrome Music Lab / Song Maker**; autorzy Google jawnie podają Web Audio, Web MIDI i Tone.js. Oficjalne demo Tone.js podaje też Ableton Learning Music. | Dowód sprawdzonego **webowego** audio/timing. **Nie** dowód, że Tone.js jest dobrą kanoniczną implementacją w natywnym Flutter Android. |
| **ONNX Runtime** (silnik Microsoft) | **Deezer** (ML do rekomendacji muzyki), **Goodnotes** (Scribble to Erase przez ONNX Runtime Web na Android/Windows/Web), również Adobe. | Silny dowód **runtime inferencji w produkcji i cross-platform**, lecz **nie** dowód, że konkretny Flutter wrapper `flutter_onnxruntime` ma takich klientów albo że Basic Pitch realtime działa szybko na tanim telefonie. |
| **Spotify Basic Pitch** | **Spotify Basic Pitch demo** produkowane i utrzymywane przez Spotify; powstał we współpracy z zespołem **Soundtrap** (Spotify). Spotify mówi, że pierwotnie tworzono model dla Soundtrap. | Dowód użycia modelu we własnym narzędziu i udziału profesjonalnego zespołu. **Nie** znaleziono jednoznacznego publicznego potwierdzenia, że Simply Piano, flowkey, Yousician lub inni liderzy używają Basic Pitch. Współpraca Soundtrap nie stanowi samodzielnie dowodu obecnej integracji w Soundtrap. |
| **TensorFlow** | **Simply Piano MusicSense**, historyczny wpis inżynierski z 2018 opisuje Android C++ TF/JNI i training w TensorFlow. | Najbardziej bezpośrednie potwierdzenie techniki typu piano realtime ML w dużej aplikacji do nauki. **Nie** dowodzi, że Simply Piano obecnie nadal używa tej samej implementacji. |
| **Magenta Onsets & Frames** | **Piano Scribe**, oficjalna demonstracja Google Magenta. | Przykład technologii piano-specific, ale nie duży niezależny produkt komercyjny. |
| **record / fftea / dart_midi_pro / flutter_midi_pro / flutter_onnxruntime** | Nie znaleziono równie wiarygodnych publicznych referencji dużych produktów wykorzystujących dokładnie te pakiety Flutter/Dart. | Brak referencji ≠ zła biblioteka; ważne są licencja, utrzymanie, wsparcie platform i testy integracji w CI. Nie przypisuj tych referencji na podstawie popularności bazowego ONNX Runtime. |

Źródła:
- Google Chrome Music Lab: https://musiclab.chromeexperiments.com/ , https://developers.googleblog.com/en/introducing-chrome-music-lab/
- Tone.js public demos: https://tonejs.github.io/demos
- ONNX Runtime testimonials: https://onnxruntime.ai/testimonials
- Spotify Basic Pitch: https://engineering.atspotify.com/2022/6/meet-basic-pitch
- Spotify własny demonstrator: https://basicpitch.spotify.com/
- Simply Piano (2018): https://medium.com/hellosimply/a-look-under-the-hood-of-simply-piano-part-2-3ba3cafa1bbf
- Google Magenta: https://magenta.tensorflow.org/onsets-frames

## 4. Konsekwencje strategiczne dla Learn Piano

### A. Dwa zupełnie różne silniki

- **Offline plik MP3 → MIDI:** Spotify Basic Pitch ONNX to wybrany pierwszy kandydat; warunek uruchomienia benchmarków #55/#56/#59 i zgodności Web/Android, licencji kodu i wag.
- **Live mikrofon → scoring nut:** potrzebujemy niskolatencyjnego strumienia aktywnych nut, retriggerów, akordów i stanów niepewności. Obecny YIN wystarcza jako baseline dla monofonii. Dla akordów rozważyć mały, streamingowy model piano-specific zamiast bezkrytycznego przepychania całych okien przez offline Basic Pitch. Tak działa koncepcyjnie MusicSense (2018); własnego modelu nie pisać bez powodu i danych.
- Gdy model nie rozpoznaje kilku nut, informować o niepewności; nie nadawać fałszywej, arbitralnej oceny.

### B. Nie twierdzić, że „własne MIDI” nas wyróżnia

Synthesia importuje dowolne pliki MIDI, ma Wait for Note i ćwiczenie każdej ręki. Uczciwy wyróżnik to **połączenie**: darmowy bez abonamentu, bez kabla, własne utwory, trening offline i czytelny ekran. To jest hipoteza, którą należy zweryfikować rozmowami/testami z użytkownikami.

### C. Opcjonalny USB MIDI input

Mimo że główny użytkownik może mieć keyboard bez MIDI, konkurenci jawnie rekomendują MIDI przy problemach z mikrofonem. Dodanie drugiego adaptera `NoteInput` dla USB MIDI (Web MIDI / Android MIDI API) zmniejszy błędne oceny na wspieranych instrumentach. To nie powinno blokować MVP mikrofonowego. Bluetooth MIDI później, gdy potwierdzimy cross-platform support.

### D. Dobra korekta transkrypcji ważniejsza niż marketing AI

Klangio umożliwia edycję wykrytych nut, co rozwiązuje praktyczne niedoskonałości modeli. Po #59, jeśli jakość nadal jest nieidealna, priorytetem może być prosty edytor wykrytych nut/zdarzeń MIDI zamiast kolejnego modelu.

### E. Reklamy wyłącznie poza grą

Perfect Piano pokazuje, że istnieje masowo pobierana darmowa aplikacja z reklamami, ale bez danych o RPM/revenue **nie wolno wnioskować o opłacalności**. Kluczowe są regulacje dla dzieci, EOG, non-personalized ads i brak irytujących przerw w aktywnym treningu (#70).

## 5. Sugerowane zmiany backlogu

1. **#59 + #60:** potwierdzić Basic Pitch ONNX jako silnik **offline transcription**; nie deklarować go docelowym silnikiem mikrofonowym realtime.
2. **#57:** utrzymać YIN jako realtime baseline i dodać w osobnym etapie ewaluację streamingowego modelu rozpoznawania klawiszy/akordów (88-note multi-label/onsets), stosując automatyczne synthetic PCM tests i późniejsze sprzętowe.
3. **#69:** wydzielić `NoteInput` i przewidzieć `MidiInput` jako drugi adapter poza mikrofonem, Android + Web.
4. **#62/#71:** gdy opóźnienia audio native Android okażą się problemem, badać **Oboe/AAudio**, a nie kopiować stare OpenSL ES z Perfect Piano.
5. **UX:** po eksperymentach dorzucić krótkie ćwiczenia, zapętlanie fragmentu, tempo, pomiary postępu, korektę wyniku rozpoznania i opcję słuchawek. Nie pisać kolejnej rozbudowanej biblioteki utworów bez praw do licencji.
6. **#68/#70:** trzymać ryzyko komercyjnych licencji i reklam dziecięcych przed implementacją.

**Granice audytu:** research stron publicznych w dniu 2026-10-12, brak analizy APK, testów hands-on konkurentów i pomiarów przychodów. Brak jawnego dowodu ≠ dowód, że konkurent nie używa danego frameworka.
