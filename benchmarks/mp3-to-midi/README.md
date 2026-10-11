# Benchmark transkrypcji MP3 → MIDI

Tu trzymamy opis zestawów testowych dla funkcji importu MP3 i eksportu MIDI.
Katalog jest poza `app/`, więc nie jest publikowany jako zasób Flutter Web na GitHub Pages.

## Struktura jednego benchmarku

Każdy utwór ma osobny katalog, na przykład `your-reality/`:

- `source.mp3` — nagranie, które podajemy algorytmowi transkrypcji.
- `reference.mid` — referencyjne nuty: numery MIDI, momenty rozpoczęcia i zakończenia.
- `README.md` — pochodzenie nagrania, MIDI, licencje i uwagi o zgodności wersji.

Oba pliki muszą reprezentować **to samo wykonanie/aranżację**. Sam tytuł
utworu nie wystarcza: inne tempo, transpozycja albo uproszczone nuty powodują
pozorne błędy algorytmu. Najpewniejszy wariant testu automatycznego to
wyrenderowanie `source.mp3` bezpośrednio z `reference.mid` znanym
instrumentem/soundfontem.

## Jak przygotować zestaw

1. Uzyskaj nagranie z legalnego źródła oraz referencyjny plik MIDI.
2. Umieść je lokalnie w katalogu wybranego benchmarku pod nazwami
   `source.mp3` i `reference.mid`.
3. Sprawdź słuchowo i na osi czasu, czy obie wersje zawierają te same nuty,
   akordy i pauzy. Zanotuj przesunięcie czasu, jeśli nagranie ma wstęp.
4. W przyszłych testach porównuj co najmniej pitch, onset, offset oraz
   precyzję, recall i F1 wykrytych nut.

## Prawa autorskie i Git

Repozytorium jest publiczne. Lokalna reguła `.gitignore` domyślnie wyklucza
pliki audio i MIDI, aby nie opublikować przypadkowo materiałów z YouTube lub
zewnętrznych serwisów. Nie dodawaj ich do Gita bez licencji lub zgody
pozwalającej na **publiczną redystrybucję**. Sama możliwość pobrania
materiału nie oznacza prawa do jego ponownej publikacji.

Jeśli przygotujesz własny/syntetyczny benchmark albo znajdziesz parę z
odpowiednią licencją, opisz jej pochodzenie i licencję w `README.md`.
Następnie można świadomie dodać pliki do repozytorium (np. `git add -f`)
i wykorzystać je w automatycznych testach CI.
