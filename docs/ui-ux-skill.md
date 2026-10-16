# UI/UX Pro Max dla Learn Piano

Repozytorium zawiera wersjonowaną, lokalną kopię skilla UI/UX Pro Max w `.agents/skills/ui-ux-pro-max/`. Wspiera agentów projektujących i implementujących UI. Nie jest zależnością Fluttera ani częścią aplikacji produkcyjnej.

## Pochodzenie i licencja

- Oficjalny projekt: https://github.com/nextlevelbuilder/ui-ux-pro-max-skill
- Źródło skopiowanych skryptów, danych i szablonu: commit `56ea9cf174ed86786187daa9de0e6247cb0747e4`.
- Format: `universal`, czyli katalog `.agents/skills/ui-ux-pro-max/`.
- Licencja MIT znajduje się w `.agents/skills/ui-ux-pro-max/LICENSE`.

## Użycie

Uruchom z katalogu głównego repozytorium (Python 3, biblioteka standardowa, bez pobierania paczek):

```sh
python3 .agents/skills/ui-ux-pro-max/scripts/search.py "piano keyboard touch landscape" --stack flutter
python3 .agents/skills/ui-ux-pro-max/scripts/search.py "large touch targets accessible controls" --domain ux
python3 .agents/skills/ui-ux-pro-max/scripts/search.py "music learning mobile practice" --design-system -p "Learn Piano: Play & Train"
```

Na Windows można zastąpić `python3` poleceniem `python`.

Pierwsze dwa polecenia dają wytyczne dla istniejącego UI Flutter. Ostatnie jedynie *proponuje* system projektowy. Nie używaj `--persist`, nie zmieniaj globalnej stylistyki ani nie nadpisuj istniejącego systemu bez zatwierdzenia.

Agenci obsługujący standard Agent Skills mogą wykrywać `SKILL.md`. W pozostałych narzędziach wskaż bezpośrednio ten plik. Samo dodanie plików do repozytorium nie ładuje skilla automatycznie w każdej rozmowie ChatGPT.

## Aktualizacje

Aby uaktualnić skill, zweryfikuj nowe wydanie oficjalnego projektu i skopiuj jego odpowiednie dane, skrypty oraz szablon. Zaktualizuj wskazany SHA i zachowaj licencję. Nie uruchamiaj instalatora niezweryfikowanej wersji automatycznie w CI.

## Nadrzędne wymagania produktu

Przed zastosowaniem porad zewnętrznego skilla obowiązują `AGENTS.md`, decyzje w issue oraz obecny kod. W szczególności: Flutter Web-first, interfejs mobile-first w poziomie, dostępność dla dzieci i początkujących, spadające nuty, czytelna klawiatura i stabilne komunikaty o mikrofonie.
