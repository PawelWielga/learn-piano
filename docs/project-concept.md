# Learn Piano: Play & Train

> Szczegółowa dokumentacja projektu w repozytorium [PawelWielga/learn-piano](https://github.com/PawelWielga/learn-piano). Ogólny wpis katalogowy znajduje się w [PawelWielga/ideas](https://github.com/PawelWielga/ideas/blob/main/ideas/piano-midi-trainer.md).

**Wybrana nazwa aplikacji:** Learn Piano: Play & Train  
**Poprzednia nazwa robocza:** Piano MIDI Trainer  
**Uzasadnienie wyboru:** nazwa zawiera frazy „Learn”, „Piano”, „Play” i „Train”, aby jasno komunikować naukę gry na pianinie i wspierać wyszukiwalność w Google Play.  
**Uwaga przed publikacją:** sprawdzić dostępność nazwy, podobne aplikacje i ewentualne kolizje znaków towarowych.  

**Status:** koncepcja; repozytorium projektu utworzone, bez rozpoczętej implementacji  
**Data zapisania:** 2026-10-10  
**Platformy docelowe:** Android, iOS i przeglądarka (desktop/mobile); dodatkowo landing page pod SEO  
**Proponowany stos:** Flutter + Dart (aplikacja) oraz Jaspr + Dart (landing page); biblioteki audio do weryfikacji

## Problem

Aplikacje do nauki gry na pianinie, np. Harmono, często ograniczają liczbę dostępnych ćwiczeń lub wymagają abonamentu. Chcemy darmowego rozwiązania do nauki na **fizycznym pianinku/keyboardzie dziecka, który nie ma wyjścia MIDI**. Telefon słucha gry przez wbudowany mikrofon.

## Cel

Stworzyć **bezpłatną, działającą lokalnie aplikację**, która:
- pozwala wczytywać własne pliki `.mid` / `.midi` bez limitu utworów;
- pokazuje nuty na ekranie jako kolorowe „spadające” bloki nad wizualną klawiaturą (styl znany z Synthesii);
- rozpoznaje grane dźwięki z mikrofonu, bez fizycznego połączenia MIDI z instrumentem;
- w trybie nauki **czeka na zagranie poprawnej nuty** przed przesunięciem utworu dalej;
- jest zrozumiała i wygodna dla dziecka;
- nie wymaga konta, serwera, internetu, abonamentu ani zakupów w aplikacji do podstawowej nauki.

## MVP – minimalna wersja użytkowa

1. **Test dźwięku:** zgoda na mikrofon, nasłuchiwanie i wyświetlanie wykrytej nuty (np. C4, D4), opcjonalnie częstotliwości/pewności rozpoznania.
2. **Import MIDI:** wybór pliku z telefonu, odczyt nut, ich czasu startu i długości, wybranie ścieżki melodycznej, jeżeli plik ma ich kilka.
3. **Widok nauki:** klawiatura i spadające nuty, oznaczenie aktualnie oczekiwanej nuty.
4. **Tryb „zagraj, aby kontynuować”:** przesuwanie melodii po wykryciu prawidłowej nuty z mikrofonu.
5. **Proste sterowanie:** start/pauza, reset, wybór utworu i regulacja szybkości prezentacji.
6. **Zakres klawiatury:** ustawienie liczby i zakresu klawiszy pianinka (np. 37/49/61), z wyraźną informacją, gdy utwór wychodzi poza jego zakres.

**Ograniczenie MVP:** rozpoznawanie **pojedynczych nut (monofonicznie)**, najlepiej melodii jedną ręką. Nie obiecywać w pierwszej wersji rozpoznawania akordów.

## Tryb nagrywania melodii z mikrofonu do MIDI (planowana funkcja po bazowym MVP)

**Pomysł:** dziecko gra na fizycznym pianinku bez wyjścia MIDI, a telefon rozpoznaje nuty i zapisuje je jako plik `.mid`, który można później odtworzyć, udostępnić lub otworzyć w trybie nauki.

### Scenariusz użytkownika

1. Użytkownik otwiera **Nagraj melodię** i rozpoczyna nagrywanie.
2. Aplikacja słucha mikrofonu i na bieżąco pokazuje rozpoznawane dźwięki.
3. Dla każdej nuty rejestruje jej wysokość, moment rozpoczęcia i przybliżony czas trwania; przerwy między nutami również mają znaczenie.
4. Po zatrzymaniu pokazuje podgląd i umożliwia odsłuchanie wyniku za pomocą syntezatora dźwięku.
5. Użytkownik zapisuje nagranie do biblioteki, eksportuje plik MIDI lub uruchamia z niego ćwiczenie ze spadającymi nutami.

### Pierwsza wersja nagrywania

- Obsługa pojedynczej linii melodycznej (jedna nuta naraz), bez rozpoznawania akordów.
- Zapis MIDI z komunikatami Note On / Note Off i poprawnymi czasami zdarzeń.
- Możliwość ponownego odsłuchania, nazwania i zapisania utworu lokalnie.
- Opcjonalna poprawka błędnie wykrytej nuty i podstawowa korekta rytmu/kwantyzacja **dopiero gdy okaże się potrzebna**.
- Brak konieczności podłączania instrumentu MIDI i brak limitu długości/liczby nagrań narzuconego przez aplikację.

### Ograniczenia i jakość

- To **transkrypcja nut**, nie zapis brzmienia instrumentu: odtwarzanie MIDI wymaga syntezatora i może brzmieć inaczej niż pianinko.
- Z samego mikrofonu trudno precyzyjnie określić moment puszczenia klawisza, ponieważ dźwięk może wybrzmiewać. Trzeba przetestować progi głośności, tłumienie drgań odczytu, detekcję początku nuty i zmianę wysokości.
- Przy niskiej jakości głośnika, szumie lub graniu kilku klawiszy równocześnie zapis może zawierać pomyłki.
- Priorytet: rozpoznawanie nut i sprawdzanie czasu zdarzeń na rzeczywistym pianinku, dopiero potem eksport standardowego pliku MIDI.

**Status:** pomysł do realizacji po bazowym trybie nauki, bez rozpoczęcia implementacji.

## Kluczowa decyzja techniczna: najpierw prototyp nasłuchu

Zanim powstanie pełne UI, przygotować małe testowe APK, które:
- słucha fizycznego pianinka przez mikrofon telefonu;
- rozpoznaje pojedyncze dźwięki i ich oktawy;
- sprawdza stabilność odczytu, opóźnienia i błędy przy kolejnych nutach;
- pozwala przetestować działanie z konkretnym pianinkiem dziecka.

Sukces tego eksperymentu jest warunkiem sensownego dalszego rozwoju projektu. Nie zakładać bez pomiaru, że biblioteka do wykrywania wysokości dźwięku sprawdzi się z każdym instrumentem.

## Wyzwania i ryzyka

- **Polifonia:** wykrycie kilku klawiszy naraz z mikrofonu jest znacznie trudniejsze niż jednej nuty.
- **Charakter brzmienia:** elektroniczne zabawkowe keyboardy mogą mieć harmoniczne utrudniające identyfikację nuty i oktawy.
- **Hałas oraz dźwięk odtwarzany przez telefon:** mogą powodować fałszywe trafienia; rozważyć pracę bez odtwarzania podkładu podczas nasłuchu.
- **Opóźnienia i migotanie odczytu:** potrzebna filtracja, minimalny czas stabilnej nuty i tolerancja częstotliwości.
- **MIDI a rzeczywiste pianinko:** pliki mogą zawierać akordy, wiele ścieżek i nuty spoza zakresu instrumentu.
- **Prawa do utworów:** aplikacja przyjmuje pliki użytkownika; nie dołączamy cudzej biblioteki komercyjnych piosenek.

## Wstępna architektura

**Założenie:** jedno repozytorium (monorepo), współdzielone komponenty i logika, z możliwością generowania aplikacji Android, iOS oraz Flutter Web; landing page jako oddzielna część w tym samym repozytorium. Nie oznacza to jednego identycznego artefaktu ani jednej implementacji dostępu do mikrofonu dla wszystkich systemów.

| Obszar | Wstępne rozwiązanie |
| --- | --- |
| Aplikacja Android / iOS / Web | Flutter / Dart, wspólny interfejs nauki gry i większość logiki |
| Parsowanie plików MIDI | Biblioteka Dart lub własna warstwa odczytu, wybór po prototypie |
| Nasłuch i rozpoznawanie pojedynczych nut | Capture audio + algorytm pitch detection (np. YIN/autokorelacja/FFT), po porównaniu dokładności na realnym sprzęcie |
| Rysowanie klawiatury i nut | Flutter CustomPainter / animacja zależna od osi czasu |
| Nagrywanie MIDI (późniejszy etap) | Zamiana stabilnych detekcji na zdarzenia Note On / Note Off z czasem; zapis pliku SMF i odsłuch przez syntezator |
| Przechowywanie | Lokalnie w pamięci urządzenia / przeglądarki; szczegóły zależne od platformy |
| Landing page | Jaspr / Dart z HTML przyjaznym SEO, treści marketingowe osobno od interaktywnej aplikacji |
| Integracja audio | Wspólny kontrakt wejścia audio, adaptery mobilne i webowe; algorytm analizy możliwie współdzielony |
| Backend i konto | Brak na start |

Framework landing page i nazwy pakietów Flutter potwierdzimy po sprawdzeniu ich aktualnego wsparcia, licencji i działania na Androidzie, iOS oraz Web.

## Wspólny projekt: landing page + aplikacja webowa + Android + iOS

### Decyzja architektoniczna (na poziomie koncepcji)

- **Preferowany kierunek:** Flutter i Dart dla samej aplikacji; **Jaspr i Dart** dla strony marketingowej, aby utrzymywać oba obszary w jednym języku i repozytorium.
- **Alternatywa rozważona:** .NET MAUI Blazor Hybrid + Blazor Web App (C#), szczególnie ze względu na doświadczenie w .NET. Flutter jest preferowany ze względu na animowane nuty, wizualizację klawiatury i możliwość wspólnej aplikacji mobilnej oraz webowej.
- **Jeden projekt organizacyjnie = monorepo**, nie jedna kompilacja na wszystkie platformy. Każda platforma ma własne komendy builda i integracje.
- **Bez backendu na początku:** rozpoznawanie nut, import MIDI i zapisywanie postępów działają lokalnie, na ile pozwala dana platforma.

### Proponowany podział katalogów w tym repozytorium

```text
learn-piano/
├── app/                 # Flutter: Android, iOS, Web
│   ├── lib/
│   ├── android/
│   ├── ios/
│   └── web/
├── site/                # Jaspr: landing page, opisy i treści SEO
├── packages/
│   ├── midi_core/       # Import, analiza i eksport MIDI
│   ├── pitch_detection/ # Wspólny algorytm analizy dźwięku
│   └── piano_core/      # Logika lekcji i ćwiczeń
└── scripts/             # Skrypty build/publikacji (dopiero przy realizacji)
```

To wyłącznie proponowana przyszła struktura tego repozytorium. Na obecnym etapie zachowujemy dokumentację, bez implementowania aplikacji.

### Strona WWW i dystrybucja

| Kanał | Rola |
| --- | --- |
| Główna domena, np. `example.com` | Landing page: opis, korzyści, materiały edukacyjne, FAQ, pobieranie aplikacji; treść indeksowalna przez wyszukiwarki |
| Ścieżka, np. `example.com/play` | Pełna aplikacja Flutter Web uruchamiana w przeglądarce |
| Google Play | Dystrybucja AAB/APK dla Androida |
| App Store | Dystrybucja aplikacji iOS |

Podane adresy są **przykładowe**, bez decyzji o domenie. Należy zadbać o rozdzielenie routingu statycznej strony i Flutter Web (w tym przekierowań dla tras aplikacji), spójny branding, analitykę tylko jeśli będzie potrzebna i politykę prywatności dla dostępu do mikrofonu.

### Wspólna logika a różnice platformowe

- **Wspólne:** modele nut i zdarzeń MIDI, parser/zapis MIDI, logika lekcji, rozpoznawanie prawidłowych nut, rysowanie spadających nut oraz zasadniczy UI Flutter.
- **Specyficzne dla platform:** otwieranie/zapisywanie plików, uprawnienia, przechwytywanie strumienia audio, trwałe przechowywanie i publikacja aplikacji.
- **Web:** mikrofon przez przeglądarkę (np. Web Audio API / AudioWorklet), po zgodzie użytkownika; na zwykłej domenie wymagany HTTPS. Sprawdzić opóźnienie i kompatybilność przeglądarek.
- **Android/iOS:** natywne uprawnienia mikrofonu i adapter przechwytywania audio; na iOS budowanie i podpisywanie aplikacji zwykle wymaga macOS + Xcode i odpowiedniej konfiguracji Apple Developer.
- **Weryfikacja:** ten sam zestaw testowych melodii i referencyjnych nut dla Androida, iOS i Web; nie zakładać identycznej dokładności mikrofonu na wszystkich platformach.

### Kolejność sprawdzenia wykonalności

1. Rozpoznać pojedyncze nuty na prawdziwym pianinku w Androidzie.
2. Uruchomić odpowiednik w przeglądarce i porównać dokładność/opóźnienia; potwierdzić współdzielenie rdzenia algorytmu Dart.
3. Zweryfikować działanie na iOS, zanim obiecamy pełną równorzędność wersji mobilnych.
4. Dopiero po udanych testach zbudować wspólny ekran nauki, integrację MIDI, aplikację Flutter Web i landing page.
5. Publikację do sklepów i automatyzację wydań zaplanować na późniejszy etap.

## Późniejsze pomysły (po MVP)

- ćwiczenie osobno prawej/lewej ręki;
- transpozycja melodii do zakresu pianinka;
- powtarzanie fragmentów, regulacja tolerancji i kalibracja mikrofonu;
- statystyki i postępy dziecka, przyjazne osiągnięcia;
- obsługa akordów po opracowaniu wiarygodnego wykrywania wielu nut;
- opcjonalna obsługa instrumentów MIDI w przyszłości (nie jest wymagana);
- ewentualne udostępnienie aplikacji innym rodzicom jako darmowego projektu.

## Kolejność realizacji

1. **Proof of concept:** aplikacja wykrywająca i pokazująca nuty z mikrofonu na rzeczywistym pianinku.
2. **MIDI:** odczyt utworu i wybór melodii.
3. **Wizualizacja:** klawiatura i spadające nuty.
4. **Integracja:** tryb czekania na poprawną nutę.
5. **Nagrywanie MIDI:** przechwytywanie wykrytych pojedynczych nut wraz z rytmem, odsłuch i eksport plików .mid.
6. **Dopracowanie:** ergonomia dla dziecka, kompatybilność różnych telefonów i pianinek.
7. **Dalszy rozwój:** dodatkowe tryby i bardziej zaawansowana analiza audio.

## Aktualny następny krok

Repozytorium aplikacji zostało już utworzone jako miejsce na dokumentację i przyszły kod, ale implementacja nie została rozpoczęta. Gdy zapadnie decyzja o starcie, zaczynamy od sprawdzenia wykrywania pojedynczych nut przez mikrofon na Androidzie, a następnie w przeglądarce i na iOS. Dopiero wtedy ostatecznie potwierdzamy architekturę Flutter + Jaspr.
