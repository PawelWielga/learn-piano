# Your Reality — kandydat na benchmark

- Film/tutorial: https://youtu.be/aRJ_UugCCAM
- Strona ze ścieżką MIDI: https://ichigos.com/sheets/1049
- Status: **kandydat, niezweryfikowany**. Nie potwierdziliśmy jeszcze, że MIDI
  odpowiada nuta po nucie i czasowo aranżacji słyszanej w filmie.
- Licencja na redystrybucję audio: **niepotwierdzona**.
- Licencja na redystrybucję MIDI: **niepotwierdzona**.

## Faktyczne pliki w repozytorium

```text
your-reality/
├── README.md
├── source.mp3
└── reference.mid
```

Referencyjny MIDI ma **278 nut, 289,46 s**, jedną ścieżkę,
zakres **F4–A5 (MIDI 65–81)** i **maksymalnie jedną nutę na raz**.
Nadaje się do badania melodii, ale **nie weryfikuje polifonicznej**
transkrypcji akordów ani basu. Nie zakładamy też, że dokładnie pokrywa się
z wykonaniem z filmu.

Importer MP3 ma limit **90 sekund**. Workflow
[`MP3 to MIDI benchmark`](../../../.github/workflows/mp3-benchmark.yml)
dekoduje tylko **pierwsze 80 sekund** nagrania przez ffmpeg i uruchamia
rzeczywisty `Mp3NoteTranscriber` w Dart. Porównuje tylko nuty mieszczące
się w tym fragmencie. W logach GitHub Actions znajdziesz
precision, recall, F1 dla wysokości i onsetu (±130 ms), a także wynik
wymagający zgodności offsetu (±160 ms). Wyniki są diagnostyczne, a nie
automatycznym testem zaliczonym/niezaliczonym.

**Prawa autorskie:** te pliki są obecnie w *publicznym* repozytorium,
chociaż prawa do ich redystrybucji nie zostały potwierdzone.
`.gitignore` nie chroni już śledzonych plików. Przed dalszym publicznym
udostępnianiem trzeba potwierdzić licencje albo zastąpić je własną,
swobodnie dystrybuowalną parą audio+MIDI.

Na pełnoprawny benchmark wielogłosowy potrzebujemy referencyjnego MIDI z
basem i akordami, a najlepiej audio wygenerowanego bezpośrednio z tej
samej wersji MIDI.
