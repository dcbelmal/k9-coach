import 'breeding_models.dart';
import '../l10n/l10n.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Etap ciąży / opieki – dzień liczony od krycia (albo owulacji).
class PregnancyMilestone {
  final int day;
  final String _title;
  String get title => tr(_title);
  final String _text;
  String get text => tr(_text);
  const PregnancyMilestone(this.day, this._title, this._text);
}

/// Kalkulator ciąży suki. Wartości orientacyjne – ciąża trwa zwykle 63 dni
/// od owulacji (62–64), a liczona od krycia 58–68 dni.
class PregnancyCalc {
  static const typical = 63;
  static const minFromMating = 58;
  static const maxFromMating = 68;

  /// Etapy liczone od dnia krycia (dzień 0).
  static const milestones = <PregnancyMilestone>[
    PregnancyMilestone(0, 'Krycie', 'Zapisz każde zbliżenie. Od teraz bez forsownego treningu i skoków.'),
    PregnancyMilestone(18, 'Zagnieżdżenie zarodków', 'Ok. 18.–21. dnia zarodki zagnieżdżają się w macicy. Spokój i zwykła dieta.'),
    PregnancyMilestone(25, 'USG – potwierdzenie ciąży', 'Między 25. a 30. dniem weterynarz potwierdzi ciążę w USG.'),
    PregnancyMilestone(35, 'Więcej jedzenia', 'Od ok. 5. tygodnia stopniowo zwiększaj porcje (do ok. +50% pod koniec), najlepiej karma dla szczeniąt.'),
    PregnancyMilestone(45, 'RTG – liczba szczeniąt', 'Po 45. dniu widać szkielety szczeniąt – RTG pokaże, ile ich jest.'),
    PregnancyMilestone(55, 'Kojec porodowy', 'Przygotuj kojec w cichym, ciepłym miejscu. Niech suka się do niego przyzwyczai.'),
    PregnancyMilestone(57, 'Mierz temperaturę', 'Mierz temperaturę 2–3 razy dziennie. Spadek poniżej 37 °C = poród zwykle w ciągu 24 h.'),
    PregnancyMilestone(63, 'Przewidywany poród', 'Typowy termin. Poród między 58. a 68. dniem od krycia jest normalny.'),
  ];

  /// Dzień, od którego liczymy (owulacja, jeśli znana – dokładniej).
  static DateTime base(Mating m) => _day(m.ovulation ?? m.first);

  /// Przewidywany dzień porodu.
  static DateTime due(Mating m) => base(m).add(const Duration(days: typical));

  /// Okno porodu (od – do).
  static (DateTime, DateTime) window(Mating m) {
    if (m.ovulation != null) {
      final b = base(m);
      return (b.add(const Duration(days: 62)), b.add(const Duration(days: 64)));
    }
    return (
      _day(m.first).add(const Duration(days: minFromMating)),
      _day(m.last).add(const Duration(days: maxFromMating)),
    );
  }

  /// Dzień ciąży liczony od pierwszego krycia (0 = dzień krycia).
  static int dayOf(Mating m, DateTime now) => _day(now).difference(_day(m.first)).inDays;

  /// Dni do przewidywanego porodu (ujemne = po terminie).
  static int daysToDue(Mating m, DateTime now) => due(m).difference(_day(now)).inDays;

  /// Czy ciążę (albo oczekiwanie) należy jeszcze śledzić.
  static bool isActive(Mating m, DateTime now) =>
      (m.status == PregnancyStatus.waiting || m.status == PregnancyStatus.confirmed) &&
      _day(now).isBefore(window(m).$2.add(const Duration(days: 5)));

  /// Data etapu – od owulacji, jeśli znana (przesunięcie względem krycia).
  static DateTime milestoneDate(Mating m, PregnancyMilestone ms) {
    if (ms.day == 0) return _day(m.first);
    return base(m).add(Duration(days: ms.day));
  }

  /// Następny etap (pierwszy w przyszłości lub dzisiaj).
  static PregnancyMilestone? next(Mating m, DateTime now) {
    final today = _day(now);
    for (final ms in milestones) {
      if (!milestoneDate(m, ms).isBefore(today)) return ms;
    }
    return null;
  }

  /// Opis tygodnia ciąży.
  static String weekLabel(int day) => day < 0 ? '—' : tr('{0}. tydzień', [day ~/ 7 + 1]);
}

/// Normy przyrostu masy szczeniąt.
class PuppyGrowth {
  /// Szczenię powinno podwoić masę urodzeniową ok. 7.–10. dnia.
  static bool doubledOnTime(Puppy p, DateTime born) {
    final b = p.birthGrams;
    if (b == null) return true;
    for (final w in p.weights) {
      final d = _day(w.date).difference(_day(born)).inDays;
      if (w.grams >= 2 * b) return d <= 10;
    }
    final last = p.weights.isEmpty ? null : p.weights.last;
    if (last == null) return true;
    return _day(last.date).difference(_day(born)).inDays <= 10;
  }
}
