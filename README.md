# K9 Coach

Aplikacja mobilna (Android i iPhone) dla właścicieli psów sportowych i wystawowych.
Napisana we Flutterze: jeden kod działa na obu systemach.

## Wersja 0.1 (MVP) zawiera

- **Start**: zdjęcie i dane psa, wskaźnik kondycji (forma i ryzyko przetrenowania), skróty, najbliższe wydarzenia, podsumowanie tygodnia.
- **Zdrowie**: szczepienia, odrobaczanie, kleszcze, badania (HD/ED, DNA, oczy), wizyty, suplementacja. Terminy z przypomnieniami (7 dni przed i w dniu terminu).
- **Trening**: IGP, BH-VT, Canicross, Bikejoring, Obedience, Nosework, Kondycja, Regeneracja. Plan tygodnia z odhaczaniem, historia, statystyki dyscypliny.
- **Kalendarz**: treningi, terminy zdrowotne, zawody, wystawy, wizyty i przypomnienia.
- **Statystyki**: dystans i czas (tydzień, miesiąc, rok), typy treningów, obciążenie, wykres wagi, postęp do celów.
- **Profil psa**: dane, pomiary wagi, notatki, zdjęcie.

Dane zapisują się tylko na telefonie (bez konta i internetu).
Moduły Wystawy, Dokumenty, Sprzęt, Cele, GPS i Asystent AI są zaplanowane na kolejne wersje.

## Jak uruchomić

**Android:** po wgraniu kodu na GitHub zakładka *Actions* sama zbuduje plik APK
(paczka „K9-Coach-Android”). Pobierz go na telefon i zainstaluj.

**Na komputerze (dla programisty):**

```
flutter pub get
flutter run
```

**iPhone:** wymaga Maca z Xcode albo konta Apple Developer i TestFlight.

## Struktura kodu

- `lib/models.dart` – dane (pies, zdrowie, treningi, wydarzenia)
- `lib/store.dart` – zapis na telefonie, obliczenia formy i statystyk, dane przykładowe
- `lib/notifications.dart` – przypomnienia
- `lib/theme.dart` – kolory, czcionka Inter, formatowanie po polsku
- `lib/screens/` – ekrany aplikacji
- `lib/widgets/common.dart` – wspólne elementy (karty, pierścienie, przełączniki)

Czcionka Inter jest na licencji SIL Open Font License.
