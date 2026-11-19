import 'breeding_models.dart';
import '../l10n/l10n.dart';
import '../date_math.dart';

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

/// Kalkulator ciąży suki. Wartości orientacyjne.
///
/// Źródła: Concannon P.W. 2011 (Anim Reprod Sci 124:200–210), BSAVA Manual of
/// Canine and Feline Reproduction and Neonatology (2. wyd.), NRC 2006.
/// * Od owulacji ciąża trwa 63 ± 1 dzień (62–64), od piku LH 65 ± 1.
/// * Od krycia 57–72 dni – plemniki przeżywają kilka dni, a krycie bywa przed
///   owulacją, więc sama data krycia daje szerokie okno.
///
/// Wszystkie etapy i [dayOf] liczone są od tego samego punktu odniesienia:
/// owulacji, jeśli potwierdził ją lekarz, w przeciwnym razie od pierwszego krycia.
class PregnancyCalc {
  static const typical = 63;
  static const minFromMating = 57;
  static const maxFromMating = 72;
  static const minFromOvulation = 62;
  static const maxFromOvulation = 64;

  /// Etapy liczone w dniach od punktu odniesienia (owulacja albo krycie).
  static const milestones = <PregnancyMilestone>[
    PregnancyMilestone(0, 'Krycie', 'Zwykła codzienna aktywność jest w porządku. Unikaj przegrzania, bardzo forsownego wysiłku i zawodów, a plan treningów omów z lekarzem weterynarii.'),
    PregnancyMilestone(18, 'Zagnieżdżenie zarodków', 'Ok. 17.–21. dnia od owulacji zarodki zagnieżdżają się w macicy. Zwykła dieta i umiarkowany ruch.'),
    PregnancyMilestone(25, 'USG – potwierdzenie ciąży', 'Od ok. 25. dnia od owulacji (po samym kryciu zwykle od 28.–30. dnia) lekarz może potwierdzić ciążę w USG. USG nie służy do dokładnego liczenia szczeniąt.'),
    PregnancyMilestone(35, 'Więcej energii w diecie', 'W drugiej połowie ciąży zapotrzebowanie rośnie stopniowo. Ilość karmy zwiększaj wg masy i kondycji suki oraz zaleceń lekarza – zwykle o 25–50% pod koniec ciąży, zależnie od liczby szczeniąt. Najczęściej poleca się karmę dla szczeniąt lub ciężarnych suk.'),
    PregnancyMilestone(45, 'RTG – liczba szczeniąt', 'Szkielety szczeniąt są widoczne w RTG od ok. 45. dnia, a najdokładniej liczy się je zwykle po 55. dniu. O badaniu decyduje lekarz.'),
    PregnancyMilestone(50, 'Spokojniejszy ruch', 'Pod koniec ciąży krótsze, spokojne spacery. Bez skoków, ciągnięcia i biegu przy rowerze.'),
    PregnancyMilestone(55, 'Kojec porodowy', 'Przygotuj kojec w cichym, ciepłym miejscu. Niech suka się do niego przyzwyczai. Ustal z lekarzem, jak się kontaktować w razie porodu.'),
    PregnancyMilestone(57, 'Mierz temperaturę', 'Mierz temperaturę 2 razy dziennie o stałych porach. Spadek (często poniżej ok. 37,5 °C) zwykle poprzedza poród o 12–24 h, ale nie u każdej suki – to nie jest pewny znak porodu.'),
    PregnancyMilestone(63, 'Środek okna porodu', '63. dzień to tylko orientacyjny środek okna. Gdy znane jest tylko krycie, poród może być wyraźnie wcześniej lub później – patrz okno porodu powyżej. Po jego przekroczeniu skontaktuj się z lekarzem.'),
  ];

  /// Objawy wymagające pilnego kontaktu z lekarzem weterynarii (BSAVA).
  static const urgentSigns = <String>[
    'Zielona lub czarna wydzielina przed urodzeniem pierwszego szczenięcia',
    'Silne parcie przez 20–30 minut bez urodzenia szczenięcia',
    'Ponad 2 godziny przerwy między szczeniętami, gdy w macicy są kolejne',
    'Ponad 24 godziny od spadku temperatury bez akcji porodowej',
    'Obfite krwawienie, gorączka, apatia, wymioty lub odmowa jedzenia',
    'Drżenia, niepokój, sztywność mięśni w ciąży lub karmieniu (możliwa tężyczka)',
    'Termin porodu przekroczony (ponad 64–66 dni od owulacji lub 72 dni od krycia)',
  ];

  /// Czy termin liczymy od owulacji potwierdzonej przez lekarza.
  static bool fromOvulation(Mating m) => m.ovulation != null;

  /// Punkt odniesienia (dzień 0): owulacja, jeśli znana – dokładniej, inaczej pierwsze krycie.
  static DateTime base(Mating m) => _day(m.ovulation ?? m.first);

  /// Przewidywany (orientacyjny) dzień porodu.
  static DateTime due(Mating m) => base(m).plusDays(typical);

  /// Okno porodu (od – do): wąskie od owulacji, szerokie od samego krycia.
  static (DateTime, DateTime) window(Mating m) {
    if (m.ovulation != null) {
      final b = base(m);
      return (b.plusDays(minFromOvulation), b.plusDays(maxFromOvulation));
    }
    final last = m.last.difference(m.first).inCalDays > 7 ? m.first.plusDays(7) : m.last;
    return (
      _day(m.first).plusDays(minFromMating),
      _day(last).plusDays(maxFromMating),
    );
  }

  /// Dzień ciąży liczony od tego samego punktu co etapy (0 = owulacja albo krycie).
  static int dayOf(Mating m, DateTime now) => _day(now).difference(base(m)).inCalDays;

  /// Dni do przewidywanego porodu (ujemne = po terminie orientacyjnym).
  static int daysToDue(Mating m, DateTime now) => due(m).difference(_day(now)).inCalDays;

  /// Dni do początku okna porodu (ujemne = okno już trwa).
  static int daysToWindowStart(Mating m, DateTime now) => window(m).$1.difference(_day(now)).inCalDays;

  /// Tekst terminu porodu do pokazania użytkownikowi. Jeden dzień tylko przy
  /// owulacji potwierdzonej badaniem; przy samym kryciu – wyłącznie przedział.
  static String dueLabel(Mating m, String Function(DateTime) fmt) {
    final (from, to) = window(m);
    if (fromOvulation(m)) return tr('ok. {0} ({1} – {2})', [fmt(due(m)), fmt(from), fmt(to)]);
    return '${fmt(from)} – ${fmt(to)}';
  }

  /// Dni do końca okna porodu (ujemne = okno przekroczone, potrzebny lekarz).
  static int daysToWindowEnd(Mating m, DateTime now) => window(m).$2.difference(_day(now)).inCalDays;

  /// Czy ciążę (albo oczekiwanie) należy jeszcze śledzić.
  static bool isActive(Mating m, DateTime now) =>
      (m.status == PregnancyStatus.waiting || m.status == PregnancyStatus.confirmed) &&
      _day(now).isBefore(window(m).$2.plusDays(5));

  /// Data etapu – od tego samego punktu odniesienia co [dayOf].
  static DateTime milestoneDate(Mating m, PregnancyMilestone ms) {
    if (ms.day == 0) return _day(m.first);
    return base(m).plusDays(ms.day);
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

/// Normy przyrostu masy szczeniąt (orientacyjne, BSAVA Neonatology).
///
/// * W pierwszych 24–48 h spadek do ok. 10% masy urodzeniowej może być
///   fizjologiczny – wymaga obserwacji, nie alarmu.
/// * Później szczenię powinno przybierać codziennie, a masę urodzeniową
///   podwoić ok. 7.–10. dnia.
class PuppyGrowth {
  /// Szczenię powinno podwoić masę urodzeniową ok. 7.–10. dnia.
  static bool doubledOnTime(Puppy p, DateTime born) {
    final b = p.birthGrams;
    if (b == null) return true;
    for (final w in p.weights) {
      final d = _day(w.date).difference(_day(born)).inCalDays;
      if (w.grams >= 2 * b) return d <= 10;
    }
    final last = p.weights.isEmpty ? null : p.weights.last;
    if (last == null) return true;
    return _day(last.date).difference(_day(born)).inCalDays <= 10;
  }

  /// Ocena ostatniego ważenia: 0 = w normie, 1 = obserwuj, 2 = skontaktuj się z lekarzem.
  static int alert(Puppy p, DateTime born) {
    if (p.weights.length < 2) return 0;
    final last = p.weights.last, prev = p.weights[p.weights.length - 2];
    final birth = p.birthGrams ?? prev.grams;
    final age = _day(last.date).difference(_day(born)).inCalDays;
    final change = last.grams - prev.grams;
    if (change < 0) {
      // Fizjologiczny spadek w pierwszych 2 dobach – do ok. 10% masy urodzeniowej.
      if (age <= 2 && last.grams >= birth * 0.9) return 1;
      return 2;
    }
    if (change == 0 && age > 2) return 1;
    if (!doubledOnTime(p, born)) return 2;
    return 0;
  }
}
