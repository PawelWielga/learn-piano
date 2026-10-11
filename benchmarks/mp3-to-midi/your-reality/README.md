# Your Reality — kandydat na benchmark

- Film/tutorial: https://youtu.be/aRJ_UugCCAM
- Strona ze ścieżką MIDI: https://ichigos.com/sheets/1049
- Status: **kandydat, niezweryfikowany**. Nie potwierdziliśmy jeszcze, że MIDI
  odpowiada nuta po nucie i czasowo aranżacji słyszanej w filmie.
- Licencja na redystrybucję audio: **niepotwierdzona**.
- Licencja na redystrybucję MIDI: **niepotwierdzona**.

## Pliki do umieszczenia lokalnie

```text
your-reality/
├── README.md
├── source.mp3       # dźwięk odpowiadający tutorialowi
└── reference.mid    # ta sama aranżacja, do weryfikacji
```

**Nie wrzucaj tych plików do publicznego GitHuba** bez sprawdzenia praw do
redystrybucji. Są domyślnie ignorowane przez Git. Możesz trzymać je lokalnie
w tym katalogu i testować transkrypcję, a w repozytorium pozostawić sam opis.

Przed pomiarem jakości porównaj zgodność obu wersji, sprawdź opóźnienie
rozpoczęcia i tempo. Jeśli MIDI okaże się inną aranżacją, wygeneruj audio
bezpośrednio z MIDI i używaj tej pary jako deterministycznego benchmarku.
