# ADR-001: Wybór technologii dla Learn Piano (Web teraz, Android z reklamami później)

**Data:** 2026-10-12  
**Status:** przyjęty kierunek implementacji; kompatybilność i jakość kilku adapterów muszą zostać potwierdzone przez CI/PoC  
**Powiązania:** #54–#71, roadmapa #67.

## Decyzja produktu

Pozostajemy przy **Flutter/Dart jako wspólnym UI i domenie**. Pierwszy produkt to Flutter Web na GitHub Pages, a planowany następny produkt to **natywny Android (AAB) z reklamami**, bez WebView jako głównej aplikacji. Analiza dźwięku użytkownika pozostaje lokalna/offline. Nie instalujemy SDK reklam w Web MVP.

## Wybrane technologie

| Obszar | Wybór | Status / rationale |
| --- | --- | --- |
| UI, piano roll, trening | Flutter + obecny `WaitForNoteEngine` (pure Dart) | **ZACHOWAĆ**. UI podzielić tylko w razie faktycznej komplikacji. |
| Mikrofon Android | `record` (testowany wariant PCM 16-bit stream) za `AudioInput` | **WYBRAĆ** do przyszłego adaptera; pakiet obejmuje Android i Web, BSD-3-Clause. |
| Mikrofon Web | obecny getUserMedia + AudioWorklet | **ZACHOWAĆ na teraz**. Migracja do `record` tylko, jeśli testy pokazują poprawność timestampów, latencję i obsługę przeglądarek. |
| Monofoniczne nuty real-time | obecny pure-Dart YIN + `NoteEventTracker` | **ZACHOWAĆ do pierwszej serii testów**. Opcja `pitch_detector_dart` (YIN) do porównania, nie wymieniać algorytmu bez pomiarów. Unikać `pitchy` jako jedynego silnika: JS-only. |
| Offline MP3 → MIDI wielogłosowe | **Spotify Basic Pitch ONNX** | **PREFEROWANY MODEL do wdrożenia**. Oficjalny model ma serializację ONNX oraz TFLite; nie uzależniać architektury od starego `@spotify/basic-pitch`/TFJS. |
| Runtime modelu | **`flutter_onnxruntime` (po pierwsze ONNX Runtime Web + Android)** | **PREFEROWANY RUNTIME PoC**; plugin MIT, obsługa Web i Android, native Android ONNX Runtime. Model dostarczać z zasobami, bez CDN. Fallback: TFLite Android + web adapter, jeśli ONNX w przeglądarce zawiedzie. |
| Resampling/FFT dla debug i lekkiego DSP | **`fftea`** (Apache-2.0) | **WYBRAĆ** zamiast własnego FFT; stosować prawidłowy low-pass przy downsampling, nie pomijać co drugiej próbki. Jeśli stary harmonic matcher zniknie, nie inwestować w jego przepisywanie. |
| MIDI format SMF | interfejs pure Dart, test kompatybilności `dart_midi_pro` | **NIE MIGROWAĆ W CIEMNO**. `dart_midi_pro` MIT ma parser/writer z buforów, ale pub.dev nie deklaruje Web jako obsługiwanej platformy mimo opisu pure Dart; mała adopcja. Migracja wyłącznie po zielonym Web build oraz regresjach tempo/sustain/track/channel/NoteOff. Obecny parser jest do tego czasu fallback. |
| Odtwarzanie nut Web | własny obecny WebAudio syntezator z poprawionym audio-clock schedulerem | **ZACHOWAĆ na MVP**; Tone.js jest opcjonalnym adapterem do oceny, nie wspólnym silnikiem aplikacji. |
| Odtwarzanie nut Android | `flutter_midi_pro` + legalny SoundFont za `NoteOutput` | **WYBRAĆ jako kandydat do native PoC**; zależność FluidSynth LGPL wymaga wypełnienia obowiązków dystrybucji. Nie dodawać dopóki #68 nie sprawdzi warunków biblioteki i osobnej licencji soundfontu. |
| Reklamy Android | `google_mobile_ads` / AdMob | **PREFEROWANY SDK, ale nie instalować teraz**. AdMob figuruje na liście Families Self-Certified SDK; grupa docelowa, aktualna certyfikowana wersja, neutralny age-screen dla audytorium mieszanego, ustawienia non-personalized, UMP/consent i deklaracje Play **muszą być zatwierdzone przed wdrożeniem**. |
| Zestawy do testów | własne syntetyczne MIDI → WAV/PCM/MP3, lokalnie renderowany instrument z wyjaśnioną licencją | **OBOWIĄZKOWE**. Nie używać niespójnej pary `your-reality`, nie zakładać prawa do komercyjnego wykorzystania MAESTRO (CC BY-NC-SA 4.0). |

## Dlaczego ONNX, a nie bezpośrednio Basic Pitch TypeScript?

Oficjalne Spotify Basic Pitch oferuje model w formatach TensorFlow, TFLite i ONNX. `flutter_onnxruntime` obsługuje Android i Web, przez co ten sam **format wag** można użyć w obu środowiskach. Przewagą jest przenośność modelu, nie obietnica identycznej wydajności.

**Ryzyko, które musi usunąć PoC:** biblioteka inferencji nie implementuje całego przetwarzania Basic Pitch. Trzeba zgodnie z implementacją Spotify przygotować resampling do 22050 Hz, okna modelu, preprocessing, kształty tensorów, stitching predykcji, dekodowanie onset/offset/pitch-bends; porównać outputy ONNX z oficjalną implementacją na małych znanych plikach. Istnieje ryzyko WebAssembly/CSP, zużycia pamięci, opóźnień i kosztu pobrania WASM/modelu.

**Fallback**, gdy ONNX nie działa stabilnie na Web: oficjalne `@spotify/basic-pitch` tylko jako adapter Web oraz `tflite_flutter` z tą samą rodziną modelu na Androidzie (zależności i wagi ponownie skontrolowane), **albo** własne rozwiązanie po porównaniu. Tego fallbacku nie wdrażać z góry.

## Biblioteki, których celowo teraz NIE wybieramy

- **`@tonejs/midi` jako kanoniczny parser**: TypeScript/JS oznacza dodatkową ścieżkę Android; preferujemy pure Dart kontrakt.
- **`flutter_midi_engine` jako jedyny odtwarzacz**: web deklarowany jako eksperymentalny/stub; mała adopcja; nie usuwa konieczności adapterów.
- **ByteDance Piano Transcription jako pierwszy silnik mobilny**: zależność od większego PyTorch/CRNN; brak prostego, gotowego Web/Android workflow; kandydat do ewentualnych testów jakości w przyszłości.
- **MAESTRO w CI jako legalny benchmark komercyjny**: licencja NC, wymaga odpowiedniego uprawnienia / osobnej oceny.
- **`just_audio` jako syntezator MIDI**: jest odtwarzaczem plików/strumieni audio, nie generatorem niskolatencyjnych NoteOn/NoteOff; może później służyć do odsłuchu nagrań.
- **`pitchy` jako docelowa detekcja**: JS-only; `pitch_detector_dart` to bardziej przenośny kandydat.
- Własny nowy algorytm FFT/MP3 polyphonic matcher: nie rozwijać bez testów.

## Kolejność implementacji bez sprzętu

1. **#54 + #68:** porządek praw i licencji kodu/wag/danych. Źródło modelu wyłącznie oficjalne Spotify, z lockiem wersji i hashem SHA256; potwierdzić zakres licencji wag.
2. **#55 + #56:** generator zsynchronizowanych fixtur i metryki, automatyczny pomiar na GitHub Actions.
3. **#60 + #69:** kontrakt `TranscriptionEngine` i niezależne od platformy porty audio/MIDI.
4. **#59:** zaimplementować adapter **Basic Pitch ONNX przez flutter_onnxruntime**, porównać wynik z oficjalnym Python Basic Pitch i starym DSP, automatyzować inferencję i metryki. Nie oczekiwać pracy użytkownika.
5. **#57 + #58:** synthetic PCM testy YIN, korekta decymacji albo usunięcie starego matcher, `fftea` jeśli nadal potrzebna analiza widma.
6. **#61 + #63:** wykonanie poza głównym wątkiem, przeglądarkowe headless E2E, pamięć i anulowanie.
7. **#62 + #64:** scheduler i opcjonalny parser pure Dart po testach, nie wymieniać całego playback tylko dla ujednolicenia stacku.
8. **#71, #70:** przyszły natywny build/emulator i reklamy po decyzji o grupie docelowej.

## Uzupełnienie: konkurencja i rozdział offline/realtime (2026-10-12)

Audyt rynku w [docs/research/competitive-landscape-2026-10.md](../research/competitive-landscape-2026-10.md) potwierdza, że:
- **Simply Piano** opisało historycznie (2018) własny on-device ML piano recognizer MusicSense (PCM → wektor aktywnych 88 klawiszy) oraz natywne TensorFlow C++/JNI na Androidzie. Nie jest to dowód obecnego stacku 2026.
- **Piano Marvel** ujawnia własny model ML i podaje 99% dla 2 oraz 90% dla 3 jednoczesnych nut **pod idealnymi warunkami**, bez porównywalnej metodologii F1. Wielogłosowy mikrofon pozostaje trudnym problemem.
- **Basic Pitch** to model do **offline transcription** i sam Spotify opisuje zastosowanie przede wszystkim do pojedynczego instrumentu. Nie deklarować jego przydatności jako niskolatencyjnego realtime piano scorer bez niezależnych testów.
- **ONNX Runtime** ma wiarygodne produkcyjne referencje m.in. Deezer i Goodnotes; to nie znaczy, że wrapper `flutter_onnxruntime` jest stosowany przez te firmy.
- **Tone.js** jest publicznie używany w Google Chrome Music Lab, ale to nadal biblioteka Web, nie wspólny Android/Web silnik muzyczny.
- **Synthesia** już wczytuje własne MIDI i oferuje Wait for Note. Te funkcje same nie odróżniają naszego produktu; szansą jest darmowy trening **na akustycznym pianinie przez mikrofon, bez kabla**.
- **Oboe/AAudio** są zalecane przez Android do natywnego low-latency audio; nie kopiować `OpenSL ES` reklamowanego przez Perfect Piano (API deprecated).

**Konsekwencja architektoniczna:** rekomendowany silnik **offline MP3 → MIDI = Spotify Basic Pitch ONNX** pod `TranscriptionEngine`, natomiast **real-time mic → NoteOn/NoteOff/scoring** ma osobny kontrakt i odmienny latency target, obecny YIN pozostaje baseline; przyszły niewielki on-device piano-specific 88-key/onset model dopiero po benchmarku. Do `NoteInput` warto dodać później adapter USB MIDI (Web MIDI/Android MIDI API) jako opcjonalną ścieżkę o wysokiej pewności. Odrębne wyjaśnienie problemu i źródła są w audycie rynku.

## Kryteria jakości dla implementatora, nie dla użytkownika

- **Automatyczne compatibility checks:** Flutter Web release build, Android emulator build, modele ładują się offline, przygotowanie tensorów daje wyniki zgodne z oficjalnym kodem na referencjach.
- **Metryki muzyczne:** precision/recall/F1 z jawnie przypisaną wersją modelu i source audio, oddzielnie mono, akordy, bass + melody, staccato/retriggers, false positives; brak oceny na niezsynchronizowanym audio.
- **Performance:** czas inferencji dla np. 10 s i 60 s PCM, max memory, rozmiar pobierania modelu, responsywność UI. Brak liczbowych gwarancji wydajności do czasu rzeczywistych pomiarów.
- **Licencje:** plik z rejestrem kodu, modelu, SoundFont i danych; compliance notice; licencje aktualizować z wersjami.
- **Pragmatyka:** jeśli sprawdzone gotowe rozwiązanie przegrywa lub integracja kosztuje zbyt dużo, zostawiamy działający kod i notujemy dlaczego; nie utrzymujemy dwóch równoległych silników produkcyjnych bez potrzeby.

## Źródła zweryfikowane 2026-10-12

- Spotify Basic Pitch (serializacje ONNX/TFLite): https://github.com/spotify/basic-pitch
- ONNX plugin multi-platform: https://pub.dev/packages/flutter_onnxruntime
- Natywny TFLite fallback: https://pub.dev/packages/tflite_flutter
- PCM stream Web/Android: https://pub.dev/packages/record
- FFT Dart: https://pub.dev/packages/fftea
- Pure Dart MIDI parser/writer (kandydat): https://pub.dev/packages/dart_midi_pro
- Dart YIN (kandydat): https://pub.dev/packages/pitch_detector_dart
- Android SF2 plugin: https://pub.dev/packages/flutter_midi_pro
- FluidSynth LGPL FAQ: https://github.com/FluidSynth/fluidsynth/blob/master/doc/wiki/LicensingFAQ.md
- AdMob Families certified SDK list: https://support.google.com/googleplay/android-developer/answer/12955712
- Google Play Families policy: https://support.google.com/googleplay/android-developer/answer/9893335
- MAESTRO license: https://magenta.tensorflow.org/datasets/maestro

**Ważne:** to jest decyzja oparta na analizie dokumentacji, API i warunków prawnych. **Nie przeprowadzono jeszcze pomiarów szybkości ani trafności tych nowych bibliotek w działającym Learn Piano.** W środowisku tej sesji nie ma lokalnego Flutter/Dart i brak dostępu do pobrania zależności; dlatego konkretne testy zostały przypisane do GitHub Actions, nie do użytkownika.
