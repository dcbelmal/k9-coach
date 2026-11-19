import '../l10n/l10n.dart';

/// Zakres z wzorca rasy: [min]–[max], „ok. X” (gdy min == max)
/// albo „min. X” (gdy wzorzec podaje tylko dolną granicę, [max] == null).
class Span {
  final double min;
  final double? max;
  const Span(this.min, [this.max]);
  const Span.atLeast(this.min) : max = null;

  /// Ten sam wymiar jako wartość idealna („ok. X”).
  const Span.about(double v) : min = v, max = v;

  String label(String unit) {
    String n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
    if (max == null) return tr('min. {0} {1}', [n(min), unit]);
    if (max == min) return tr('ok. {0} {1}', [n(min), unit]);
    return '${n(min)}–${n(max!)} $unit';
  }

  /// Największa wartość, jaką da się porównać (dla „min. X” – samo X).
  double get upper => max ?? min;
}

/// Wymiary według płci, tak jak podaje je wzorzec FCI. Pole puste (null)
/// oznacza, że wzorzec nie podaje tej wartości osobno dla płci (albo
/// w ogóle jej nie podaje) – wtedy aplikacja pokazuje tylko zakres ogólny.
class SexDims {
  final Span? maleHeight, femaleHeight;
  final Span? maleWeight, femaleWeight;
  const SexDims({this.maleHeight, this.femaleHeight, this.maleWeight, this.femaleWeight});

  /// Ten sam zakres dla obu płci.
  const SexDims.both({Span? height, Span? weight})
    : maleHeight = height,
      femaleHeight = height,
      maleWeight = weight,
      femaleWeight = weight;

  bool get sameForBoth => _eq(maleHeight, femaleHeight) && _eq(maleWeight, femaleWeight);

  static bool _eq(Span? a, Span? b) => a?.min == b?.min && a?.max == b?.max;
}

typedef _S = Span;

/// Wymiary według płci z wzorców FCI (cm w kłębie, kg). Tylko rasy, dla
/// których wzorzec podaje konkretne wartości; rasy z kilkoma odmianami
/// wielkości (jamnik, pudel, szpic niemiecki, xolo) i rasy z niepewnymi
/// danymi (kangal, mastif, foksterier) celowo pominięto.
const breedSexDims = <String, SexDims>{
  // Grupa I
  'malinois': _belg,
  'groenendael': _belg,
  'tervueren': _belg,
  'laekenois': _belg,
  'gsd': SexDims(maleHeight: _S(60, 65), femaleHeight: _S(55, 60), maleWeight: _S(30, 40), femaleWeight: _S(22, 32)),
  'dutch_shepherd': SexDims(maleHeight: _S(57, 62), femaleHeight: _S(55, 60)),
  'aussie': SexDims(maleHeight: _S(51, 58), femaleHeight: _S(46, 53)),
  'collie_rough': SexDims(maleHeight: _S(56, 61), femaleHeight: _S(51, 56)),
  'sheltie': SexDims(maleHeight: _S.about(37), femaleHeight: _S.about(35.5)),
  'pon': SexDims(maleHeight: _S(45, 50), femaleHeight: _S(42, 47)),
  'podhalanski': SexDims(maleHeight: _S(65, 70), femaleHeight: _S(60, 65)),
  'white_swiss': SexDims(
    maleHeight: _S(58, 66),
    femaleHeight: _S(53, 61),
    maleWeight: _S(30, 40),
    femaleWeight: _S(25, 35),
  ),
  'corgi_pembroke': SexDims(
    maleHeight: _S(25.4, 30.5),
    femaleHeight: _S(25.4, 30.5),
    maleWeight: _S(10, 12),
    femaleWeight: _S(9, 11),
  ),
  'corgi_cardigan': SexDims.both(height: _S.about(30)),
  'kelpie': SexDims(maleHeight: _S(46, 51), femaleHeight: _S(43, 48)),
  'mudi': SexDims(maleHeight: _S(41, 47), femaleHeight: _S(38, 44), maleWeight: _S(11, 13), femaleWeight: _S(8, 11)),
  'pumi': SexDims(maleHeight: _S(41, 47), femaleHeight: _S(38, 44), maleWeight: _S(10, 15), femaleWeight: _S(8, 13)),
  'puli': SexDims(maleHeight: _S(39, 45), femaleHeight: _S(36, 42), maleWeight: _S(13, 15), femaleWeight: _S(10, 13)),
  'briard': SexDims(maleHeight: _S(62, 68), femaleHeight: _S(56, 64)),
  'beauceron': SexDims(maleHeight: _S(65, 70), femaleHeight: _S(61, 68)),
  'cattle_dog': SexDims(maleHeight: _S(46, 51), femaleHeight: _S(43, 48)),
  'czech_wolfdog': SexDims(
    maleHeight: _S.atLeast(65),
    femaleHeight: _S.atLeast(60),
    maleWeight: _S.atLeast(26),
    femaleWeight: _S.atLeast(20),
  ),
  'saarloos': SexDims(maleHeight: _S(65, 75), femaleHeight: _S(60, 70)),
  // Grupa II
  'dobermann': SexDims(
    maleHeight: _S(68, 72),
    femaleHeight: _S(63, 68),
    maleWeight: _S(40, 45),
    femaleWeight: _S(32, 35),
  ),
  'rottweiler': SexDims(
    maleHeight: _S(61, 68),
    femaleHeight: _S(56, 63),
    maleWeight: _S.about(50),
    femaleWeight: _S.about(42),
  ),
  'boxer': SexDims(
    maleHeight: _S(57, 63),
    femaleHeight: _S(53, 59),
    maleWeight: _S.atLeast(30),
    femaleWeight: _S.about(25),
  ),
  'giant_schnauzer': SexDims.both(height: _S(60, 70), weight: _S(35, 47)),
  'standard_schnauzer': SexDims.both(height: _S(45, 50), weight: _S(14, 20)),
  'mini_schnauzer': SexDims.both(height: _S(30, 35), weight: _S(4.5, 8)),
  'pinscher': SexDims.both(height: _S(45, 50), weight: _S(14, 20)),
  'min_pinscher': SexDims.both(height: _S(25, 30), weight: _S(4, 6)),
  'great_dane': SexDims(
    maleHeight: _S.atLeast(80),
    femaleHeight: _S.atLeast(72),
    maleWeight: _S.atLeast(54),
    femaleWeight: _S.atLeast(50),
  ),
  'cane_corso': SexDims(
    maleHeight: _S(64, 68),
    femaleHeight: _S(60, 64),
    maleWeight: _S(45, 50),
    femaleWeight: _S(40, 45),
  ),
  'bernese': SexDims(maleHeight: _S(64, 70), femaleHeight: _S(58, 66)),
  'newfoundland': SexDims(
    maleHeight: _S.about(71),
    femaleHeight: _S.about(66),
    maleWeight: _S.about(68),
    femaleWeight: _S.about(54),
  ),
  'leonberger': SexDims(maleHeight: _S(72, 80), femaleHeight: _S(65, 75)),
  'st_bernard': SexDims(maleHeight: _S(70, 90), femaleHeight: _S(65, 80)),
  'english_bulldog': SexDims(maleWeight: _S.about(25), femaleWeight: _S.about(23)),
  'dogue_bordeaux': SexDims(
    maleHeight: _S(60, 68),
    femaleHeight: _S(58, 66),
    maleWeight: _S.atLeast(50),
    femaleWeight: _S.atLeast(45),
  ),
  'bullmastiff': SexDims(
    maleHeight: _S(64, 69),
    femaleHeight: _S(61, 66),
    maleWeight: _S(50, 59),
    femaleWeight: _S(41, 50),
  ),
  'shar_pei': SexDims.both(height: _S(44, 51)),
  'dogo_argentino': SexDims(
    maleHeight: _S(62, 68),
    femaleHeight: _S(60, 65),
    maleWeight: _S(40, 45),
    femaleWeight: _S(40, 43),
  ),
  'caucasian': SexDims(
    maleHeight: _S.atLeast(68),
    femaleHeight: _S.atLeast(64),
    maleWeight: _S.atLeast(50),
    femaleWeight: _S.atLeast(45),
  ),
  'central_asian': SexDims(
    maleHeight: _S.atLeast(70),
    femaleHeight: _S.atLeast(65),
    maleWeight: _S.atLeast(50),
    femaleWeight: _S.atLeast(40),
  ),
  'hovawart': SexDims(
    maleHeight: _S(63, 70),
    femaleHeight: _S(58, 65),
    maleWeight: _S(30, 40),
    femaleWeight: _S(25, 35),
  ),
  'entlebucher': SexDims(maleHeight: _S(44, 50), femaleHeight: _S(42, 48)),
  'appenzeller': SexDims(maleHeight: _S(52, 56), femaleHeight: _S(50, 54)),
  'swiss_mountain': SexDims(maleHeight: _S(65, 72), femaleHeight: _S(60, 68)),
  'black_russian': SexDims(
    maleHeight: _S(72, 76),
    femaleHeight: _S(68, 72),
    maleWeight: _S(50, 60),
    femaleWeight: _S(45, 50),
  ),
  // Grupa III
  'amstaff': SexDims(maleHeight: _S(46, 48), femaleHeight: _S(43, 46)),
  'staffie': SexDims(
    maleHeight: _S(35.5, 40.5),
    femaleHeight: _S(35.5, 40.5),
    maleWeight: _S(13, 17),
    femaleWeight: _S(11, 15.4),
  ),
  'jack_russell': SexDims.both(height: _S(25, 30), weight: _S(5, 6)),
  'parson_russell': SexDims(maleHeight: _S.about(36), femaleHeight: _S.about(33)),
  'yorkshire': SexDims.both(weight: _S(2, 3.2)),
  'westie': SexDims.both(height: _S.about(28)),
  'airedale': SexDims(maleHeight: _S(58, 61), femaleHeight: _S(56, 59)),
  'scottish_terrier': SexDims.both(height: _S(25.4, 28), weight: _S(8.6, 10.4)),
  'cairn': SexDims.both(height: _S(28, 31), weight: _S(6, 7.5)),
  'border_terrier': SexDims(maleWeight: _S(5.9, 7.1), femaleWeight: _S(5.1, 6.4)),
  'german_hunting_terrier': SexDims(
    maleHeight: _S(33, 40),
    femaleHeight: _S(33, 40),
    maleWeight: _S(9, 10),
    femaleWeight: _S(7.5, 8.5),
  ),
  // Grupa V
  'husky': SexDims(
    maleHeight: _S(53.5, 60),
    femaleHeight: _S(50.5, 56),
    maleWeight: _S(20.5, 28),
    femaleWeight: _S(15.5, 23),
  ),
  'malamute': SexDims(
    maleHeight: _S.about(63.5),
    femaleHeight: _S.about(58.5),
    maleWeight: _S.about(38),
    femaleWeight: _S.about(34),
  ),
  'samoyed': SexDims(maleHeight: _S(54, 60), femaleHeight: _S(50, 56)),
  'akita': SexDims(maleHeight: _S(64, 70), femaleHeight: _S(58, 64)),
  'american_akita': SexDims(maleHeight: _S(66, 71), femaleHeight: _S(61, 66)),
  'shiba': SexDims(maleHeight: _S(38.5, 41.5), femaleHeight: _S(35.5, 38.5)),
  'pomeranian': SexDims.both(height: _S(18, 22)),
  'keeshond': SexDims.both(height: _S(43, 55)),
  'chow': SexDims(maleHeight: _S(48, 56), femaleHeight: _S(46, 51)),
  'basenji': SexDims(
    maleHeight: _S.about(43),
    femaleHeight: _S.about(40),
    maleWeight: _S.about(11),
    femaleWeight: _S.about(9.5),
  ),
  'eurasier': SexDims(
    maleHeight: _S(52, 60),
    femaleHeight: _S(48, 56),
    maleWeight: _S(23, 32),
    femaleWeight: _S(18, 26),
  ),
  'pharaoh': SexDims(maleHeight: _S(56, 63.5), femaleHeight: _S(53, 61)),
  // Grupa VI
  'beagle': SexDims.both(height: _S(33, 40)),
  'basset': SexDims.both(height: _S(33, 38)),
  'dalmatian': SexDims(maleHeight: _S(56, 62), femaleHeight: _S(54, 60)),
  'rhodesian': SexDims(
    maleHeight: _S(63, 69),
    femaleHeight: _S(61, 66),
    maleWeight: _S.about(36.5),
    femaleWeight: _S.about(32),
  ),
  'ogar': SexDims(maleHeight: _S(56, 65), femaleHeight: _S(55, 60)),
  'gonczy_polski': SexDims(maleHeight: _S(55, 59), femaleHeight: _S(50, 55)),
  'bloodhound': SexDims(
    maleHeight: _S(64, 72),
    femaleHeight: _S(58, 66),
    maleWeight: _S(46, 54),
    femaleWeight: _S(40, 48),
  ),
  'hanover_hound': SexDims(maleHeight: _S(50, 55), femaleHeight: _S(48, 53)),
  'bavarian_hound': SexDims(maleHeight: _S(47, 52), femaleHeight: _S(44, 48)),
  // Grupa VII
  'gsp': SexDims(maleHeight: _S(62, 66), femaleHeight: _S(58, 63), maleWeight: _S(29, 32), femaleWeight: _S(20, 27)),
  'gwp': SexDims(maleHeight: _S(61, 68), femaleHeight: _S(57, 64), maleWeight: _S(27, 32), femaleWeight: _S(22, 27)),
  'vizsla': SexDims(maleHeight: _S(58, 64), femaleHeight: _S(54, 60), maleWeight: _S(20, 27), femaleWeight: _S(18, 25)),
  'wire_vizsla': SexDims(maleHeight: _S(58, 64), femaleHeight: _S(54, 60)),
  'weimaraner': SexDims(
    maleHeight: _S(59, 70),
    femaleHeight: _S(57, 65),
    maleWeight: _S(30, 40),
    femaleWeight: _S(25, 35),
  ),
  'pointer': SexDims(maleHeight: _S(63, 69), femaleHeight: _S(61, 66)),
  'irish_setter': SexDims(maleHeight: _S(58, 67), femaleHeight: _S(55, 62)),
  'english_setter': SexDims(maleHeight: _S(65, 68), femaleHeight: _S(61, 65)),
  'gordon_setter': SexDims(
    maleHeight: _S.about(66),
    femaleHeight: _S.about(62),
    maleWeight: _S.about(29.5),
    femaleWeight: _S.about(25.5),
  ),
  'brittany': SexDims(maleHeight: _S(48, 51), femaleHeight: _S(47, 50)),
  // Grupa VIII
  'labrador': SexDims(maleHeight: _S(56, 57), femaleHeight: _S(54, 56)),
  'golden': SexDims(maleHeight: _S(56, 61), femaleHeight: _S(51, 56)),
  'flatcoat': SexDims(
    maleHeight: _S(59, 61.5),
    femaleHeight: _S(56.5, 59),
    maleWeight: _S(27, 36),
    femaleWeight: _S(25, 32),
  ),
  'toller': SexDims(maleHeight: _S(48, 51), femaleHeight: _S(45, 48), maleWeight: _S(20, 23), femaleWeight: _S(17, 20)),
  'chesapeake': SexDims(
    maleHeight: _S(58, 66),
    femaleHeight: _S(53, 61),
    maleWeight: _S(29.5, 36.5),
    femaleWeight: _S(25, 32),
  ),
  'cocker': SexDims(
    maleHeight: _S(39, 41),
    femaleHeight: _S(38, 39),
    maleWeight: _S(13, 14.5),
    femaleWeight: _S(13, 14.5),
  ),
  'american_cocker': SexDims(maleHeight: _S.about(38), femaleHeight: _S.about(35.5)),
  'springer': SexDims.both(height: _S.about(51)),
  'wachtel': SexDims(maleHeight: _S(48, 54), femaleHeight: _S(45, 52)),
  'lagotto': SexDims(
    maleHeight: _S(43, 48),
    femaleHeight: _S(41, 46),
    maleWeight: _S(13, 16),
    femaleWeight: _S(11, 14),
  ),
  'portuguese_water': SexDims(
    maleHeight: _S(50, 57),
    femaleHeight: _S(43, 52),
    maleWeight: _S(19, 25),
    femaleWeight: _S(16, 22),
  ),
  // Grupa IX
  'chihuahua': SexDims.both(weight: _S(1.5, 3)),
  'maltese': SexDims(maleHeight: _S(21, 25), femaleHeight: _S(20, 23), maleWeight: _S(3, 4), femaleWeight: _S(3, 4)),
  'french_bulldog': SexDims(
    maleHeight: _S(27, 35),
    femaleHeight: _S(24, 32),
    maleWeight: _S(9, 14),
    femaleWeight: _S(8, 13),
  ),
  'pug': SexDims.both(weight: _S(6.3, 8.1)),
  'cavalier': SexDims.both(weight: _S(5.4, 8)),
  'papillon': SexDims.both(height: _S(20, 28)),
  'havanese': SexDims.both(height: _S(23, 27)),
  'coton': SexDims(maleHeight: _S(26, 28), femaleHeight: _S(23, 25), maleWeight: _S(4, 6), femaleWeight: _S(3.5, 5)),
  // Grupa X
  'greyhound': SexDims(maleHeight: _S(71, 76), femaleHeight: _S(68, 71)),
  'whippet': SexDims(maleHeight: _S(47, 51), femaleHeight: _S(44, 47)),
  'saluki': SexDims.both(height: _S(58, 71)),
  'borzoi': SexDims(maleHeight: _S(75, 85), femaleHeight: _S(68, 78)),
  'afghan': SexDims(maleHeight: _S(68, 74), femaleHeight: _S(63, 69)),
  'chart_polski': SexDims(maleHeight: _S(70, 80), femaleHeight: _S(68, 75)),
  'italian_greyhound': SexDims.both(height: _S(32, 38), weight: _S(2.5, 5)),
  'irish_wolfhound': SexDims(
    maleHeight: _S.atLeast(79),
    femaleHeight: _S.atLeast(71),
    maleWeight: _S.atLeast(54.5),
    femaleWeight: _S.atLeast(40.5),
  ),
};

const _belg = SexDims(
  maleHeight: _S(60, 66),
  femaleHeight: _S(56, 62),
  maleWeight: _S(25, 30),
  femaleWeight: _S(20, 25),
);
