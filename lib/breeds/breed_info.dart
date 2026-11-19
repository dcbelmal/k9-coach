import 'breeds.dart';
import 'breed_sports.dart';
import '../l10n/l10n.dart';

/// Dane o rasie: numer wzorca FCI, wzrost, masa, długość życia,
/// potrzeba ruchu i zalecane badania. Predyspozycje sportowe liczone są
/// w breed_sports.dart (kategorie A–D z uzasadnieniem), a cechy budowy
/// i użytkowość w breed_profile.dart.
///
/// Wartości są orientacyjne (zakres dla suk i psów razem). Dokładne liczby
/// podaje wzorzec rasy FCI – link w aplikacji prowadzi do niego.
class BreedInfo {
  /// Numer wzorca FCI (null = rasa nieuznana w pełni lub numer niepewny).
  final int? fciNo;
  final int heightMin, heightMax; // cm w kłębie
  final double weightMin, weightMax; // kg
  final int lifeMin, lifeMax; // lata
  /// Potrzeba ruchu 1–5.
  final int energy;
  final List<String> _tests;
  List<String> get tests => trList(_tests);

  /// Skróty badań (polskie klucze) – do grupowania i testów.
  List<String> get testKeys => _tests;
  const BreedInfo(
    this.fciNo,
    this.heightMin,
    this.heightMax,
    this.weightMin,
    this.weightMax,
    this.lifeMin,
    this.lifeMax,
    this.energy,
    this._tests,
  );

  String get heightLabel =>
      heightMin == heightMax ? tr('{0} cm', [heightMin]) : tr('{0}–{1} cm', [heightMin, heightMax]);
  String get weightLabel => tr('{0}–{1} kg', [_n(weightMin), _n(weightMax)]);
  String get lifeLabel => tr('{0}–{1} lat', [lifeMin, lifeMax]);

  /// Link do wzorca rasy (PDF na stronie FCI).
  String? fciUrl(int group) => fciNo == null
      ? null
      : 'https://www.fci.be/Nomenclature/Standards/${fciNo.toString().padLeft(3, '0')}g${group.toString().padLeft(2, '0')}-en.pdf';

  BreedSize get size => switch ((weightMin + weightMax) / 2) {
    < 10 => BreedSize.small,
    < 25 => BreedSize.medium,
    < 50 => BreedSize.large,
    _ => BreedSize.giant,
  };

  String get energyLabel => switch (energy) {
    1 => tr('Niska'),
    2 => tr('Umiarkowana'),
    3 => tr('Średnia'),
    4 => tr('Wysoka'),
    _ => tr('Bardzo wysoka'),
  };

  String get energyHint => switch (energy) {
    1 => tr('Wystarczą spokojne spacery, ok. 45–60 min dziennie.'),
    2 => tr('Ok. 1 h spacerów dziennie, bez forsowania w upały.'),
    3 => tr('Ok. 1–1,5 h ruchu dziennie, w tym zabawa i węszenie.'),
    4 => tr('Ok. 1,5–2 h ruchu dziennie i praca dla głowy.'),
    _ => tr('Ponad 2 h ruchu dziennie i codzienna praca umysłowa – bez tego się nudzi.'),
  };

  static String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
}

enum BreedSize {
  small('Mała'),
  medium('Średnia'),
  large('Duża'),
  giant('Olbrzymia');

  final String _label;
  String get label => tr(_label);
  const BreedSize(this._label);
}

/// Rodzaj badania: przed hodowlą, profilaktyka u każdego psa rasy
/// albo według wskazań lekarza.
enum TestKind {
  breeding('Badania przed hodowlą'),
  preventive('Profilaktyka'),
  indication('Według wskazań lekarza');

  final String _label;
  String get label => tr(_label);
  const TestKind(this._label);
}

const _preventive = {'Oczy', 'Serce', 'DCM', 'MVD', 'BOAS', 'Rzepki', 'MDR1', 'Fanconi'};
const _indication = {'Kręgosłup', 'Tarczyca', 'Nerki'};

TestKind testKindOf(String key) => _preventive.contains(key)
    ? TestKind.preventive
    : (_indication.contains(key) ? TestKind.indication : TestKind.breeding);

/// Krótkie wyjaśnienia skrótów badań.
const testDescriptions = <String, String>{
  'HD': 'Dysplazja stawów biodrowych – RTG po 12. (rasy duże: 18.) miesiącu',
  'ED': 'Dysplazja stawów łokciowych – RTG razem z HD',
  'Oczy': 'Badanie oczu u okulisty (ECVO/ECVO-PL), powtarzane co 1–2 lata',
  'Serce': 'Badanie kardiologiczne (osłuchanie, echo serca)',
  'DCM': 'Kardiomiopatia rozstrzeniowa – echo serca i Holter, zwykle co rok od ok. 2.–3. roku życia',
  'MDR1': 'Test DNA – wrażliwość na niektóre leki (np. iwermektynę)',
  'CEA': 'Anomalia oka collie – test DNA i badanie okulistyczne szczeniąt',
  'PRA': 'Postępujący zanik siatkówki – test DNA odpowiedni dla rasy',
  'DM': 'Zwyrodnieniowa mielopatia – test DNA',
  'Słuch': 'Test słuchu BAER (szczególnie u psów z dużą ilością bieli)',
  'Rzepki': 'Ocena luksacji rzepek u weterynarza',
  'Tarczyca': 'Badanie hormonów tarczycy (T4, TSH)',
  'vWD': 'Choroba von Willebranda – test DNA (krzepliwość)',
  'EIC': 'Zapaść wysiłkowa – test DNA',
  'BOAS': 'Ocena drożności dróg oddechowych (rasy krótkoczaszkowe)',
  'Kręgosłup':
      'Ocena kręgosłupa (np. dyskopatia, wady kręgów) – RTG lub tomografia przy objawach albo wg programu klubu',
  'Nerki': 'Badanie moczu i krwi pod kątem chorób nerek',
  'TNS': 'Zespół uwięzienia neutrofili – test DNA',
  'CL': 'Ceroidolipofuscynoza – test DNA',
  'JLPP': 'Młodzieńcza polineuropatia krtaniowa – test DNA',
  'HUU': 'Hiperurikozuria (kamienie moczanowe) – test DNA',
  'Zatoka skórna': 'Kontrola szczeniąt pod kątem zatoki skórnej',
  'LPN1': 'Polineuropatia leonbergerów – test DNA',
  'SM': 'Syringomielia – rezonans magnetyczny',
  'MVD': 'Choroba zwyrodnieniowa zastawki mitralnej – osłuchiwanie serca co rok, echo wg zaleceń kardiologa',
  'PLL': 'Pierwotne przemieszczenie soczewki – test DNA',
  'L2HGA': 'Kwasica L-2-hydroksyglutarowa – test DNA',
  'HC': 'Dziedziczna zaćma – test DNA',
  'Fanconi': 'Zespół Fanconiego (nerki) – test DNA u rodziców, u psa okresowe badanie moczu (glukoza)',
  'IGS': 'Zespół Imerslund-Gräsbeck (wit. B12) – test DNA',
  'NCCD': 'Ataksja móżdżkowa noworodków – test DNA',
  'MLS': 'Zespół Musladina-Luekego – test DNA',
  'ICT-A': 'Rybia łuska – test DNA',
  'PFK': 'Niedobór fosfofruktokinazy – test DNA',
  'FN': 'Rodzinna nefropatia – test DNA',
  'GM1': 'Gangliozydoza GM1 – test DNA',
  'CNM': 'Miopatia centronuklearna – test DNA',
  'NCL': 'Ceroidolipofuscynoza neuronalna – test DNA',
};

const _hed = ['HD', 'ED'];
const _hedEye = ['HD', 'ED', 'Oczy'];

const breedInfos = <String, BreedInfo>{
  // Grupa I
  'malinois': BreedInfo(15, 56, 66, 20, 30, 12, 14, 5, _hedEye),
  'groenendael': BreedInfo(15, 56, 66, 20, 30, 12, 14, 4, _hedEye),
  'tervueren': BreedInfo(15, 56, 66, 20, 30, 12, 14, 4, _hedEye),
  'laekenois': BreedInfo(15, 56, 66, 20, 30, 12, 14, 4, _hedEye),
  'gsd': BreedInfo(166, 55, 65, 22, 40, 9, 13, 4, ['HD', 'ED', 'DM']),
  'dutch_shepherd': BreedInfo(223, 55, 62, 23, 32, 12, 15, 5, _hed),
  'border_collie': BreedInfo(297, 46, 56, 14, 22, 12, 15, 5, ['HD', 'ED', 'Oczy', 'CEA', 'TNS', 'CL']),
  'aussie': BreedInfo(342, 46, 58, 16, 32, 12, 15, 5, ['HD', 'ED', 'Oczy', 'MDR1', 'PRA']),
  'collie_rough': BreedInfo(156, 51, 61, 18, 29, 12, 14, 3, ['MDR1', 'CEA', 'Oczy', 'DM']),
  'sheltie': BreedInfo(88, 35, 39, 6, 12, 12, 14, 4, ['MDR1', 'CEA', 'Oczy', 'HD']),
  'pon': BreedInfo(251, 42, 50, 14, 22, 12, 15, 3, ['HD', 'Oczy', 'PRA']),
  'podhalanski': BreedInfo(252, 60, 70, 36, 59, 10, 12, 2, _hed),
  'white_swiss': BreedInfo(347, 53, 66, 25, 40, 12, 14, 4, ['HD', 'ED', 'MDR1', 'DM']),
  'corgi_pembroke': BreedInfo(39, 25, 30, 9, 12, 12, 15, 3, ['DM', 'vWD', 'Oczy', 'HD', 'Kręgosłup']),
  'kelpie': BreedInfo(293, 43, 51, 11, 20, 12, 15, 5, ['HD', 'Oczy', 'CEA', 'PRA', 'CL']),
  'mudi': BreedInfo(238, 38, 47, 8, 13, 12, 14, 5, _hedEye),
  'pumi': BreedInfo(56, 38, 47, 8, 15, 12, 14, 4, ['HD', 'Rzepki', 'DM']),
  'puli': BreedInfo(55, 36, 45, 10, 15, 12, 16, 3, ['HD', 'Oczy']),
  'briard': BreedInfo(113, 56, 68, 25, 40, 10, 12, 3, ['HD', 'Oczy']),
  'beauceron': BreedInfo(44, 61, 70, 30, 45, 10, 12, 4, _hed),
  'cattle_dog': BreedInfo(287, 43, 51, 15, 22, 12, 16, 5, ['HD', 'ED', 'Oczy', 'PRA', 'PLL', 'Słuch']),
  'czech_wolfdog': BreedInfo(332, 60, 75, 20, 35, 12, 16, 5, ['HD', 'ED', 'DM']),
  'saarloos': BreedInfo(311, 60, 76, 30, 45, 10, 12, 4, ['HD', 'DM', 'Oczy']),
  // Grupa II
  'dobermann': BreedInfo(143, 63, 72, 32, 45, 10, 12, 4, ['DCM', 'vWD', 'HD']),
  'rottweiler': BreedInfo(147, 56, 68, 40, 55, 9, 10, 3, ['HD', 'ED', 'Oczy', 'JLPP', 'Serce']),
  'boxer': BreedInfo(144, 53, 63, 25, 32, 10, 12, 4, ['Serce', 'HD', 'DM', 'Słuch']),
  'giant_schnauzer': BreedInfo(181, 60, 70, 35, 47, 10, 12, 4, ['HD', 'Tarczyca']),
  'standard_schnauzer': BreedInfo(182, 45, 50, 14, 20, 13, 15, 4, ['HD', 'Oczy']),
  'mini_schnauzer': BreedInfo(183, 30, 35, 4, 8, 12, 15, 3, ['Oczy']),
  'pinscher': BreedInfo(184, 45, 50, 14, 20, 12, 14, 4, ['HD', 'Oczy', 'vWD']),
  'min_pinscher': BreedInfo(185, 25, 30, 4, 6, 12, 16, 4, ['Rzepki', 'Oczy']),
  'great_dane': BreedInfo(235, 72, 90, 50, 90, 8, 10, 2, ['HD', 'ED', 'DCM']),
  'cane_corso': BreedInfo(343, 60, 70, 40, 50, 9, 12, 3, _hed),
  'bernese': BreedInfo(45, 58, 70, 38, 50, 7, 10, 2, ['HD', 'ED', 'DM']),
  'newfoundland': BreedInfo(50, 63, 71, 54, 68, 8, 10, 2, ['HD', 'ED', 'Serce']),
  'leonberger': BreedInfo(145, 65, 80, 45, 75, 8, 10, 2, ['HD', 'ED', 'LPN1']),
  'st_bernard': BreedInfo(61, 65, 90, 60, 90, 8, 10, 1, _hed),
  'english_bulldog': BreedInfo(149, 31, 40, 23, 25, 8, 10, 1, ['BOAS', 'Serce', 'HD', 'Kręgosłup', 'Oczy']),
  'dogue_bordeaux': BreedInfo(116, 58, 68, 45, 65, 6, 8, 2, ['HD', 'ED', 'Serce']),
  'mastiff': BreedInfo(264, 70, 80, 70, 90, 8, 10, 1, _hed),
  'bullmastiff': BreedInfo(157, 61, 69, 41, 59, 8, 10, 2, _hed),
  'shar_pei': BreedInfo(309, 44, 51, 18, 25, 8, 12, 2, ['Oczy', 'Nerki', 'HD']),
  'dogo_argentino': BreedInfo(292, 60, 68, 40, 45, 10, 12, 4, ['HD', 'Słuch']),
  'kangal': BreedInfo(331, 72, 86, 41, 66, 12, 15, 2, _hed),
  'caucasian': BreedInfo(328, 64, 75, 45, 75, 10, 12, 2, _hed),
  'central_asian': BreedInfo(335, 65, 75, 40, 80, 12, 15, 2, _hed),
  'hovawart': BreedInfo(190, 58, 70, 25, 40, 12, 14, 4, ['HD', 'ED', 'Tarczyca']),
  'entlebucher': BreedInfo(47, 42, 52, 20, 30, 11, 13, 4, ['HD', 'ED', 'Oczy', 'PRA']),
  'appenzeller': BreedInfo(46, 50, 56, 22, 32, 12, 14, 4, _hed),
  'swiss_mountain': BreedInfo(58, 60, 72, 50, 70, 8, 11, 2, _hed),
  'black_russian': BreedInfo(327, 68, 77, 45, 60, 10, 12, 3, ['HD', 'ED', 'JLPP']),
  // Grupa III
  'amstaff': BreedInfo(286, 43, 48, 25, 30, 12, 14, 4, ['HD', 'ED', 'NCL', 'Serce']),
  'staffie': BreedInfo(76, 35, 41, 11, 17, 12, 14, 4, ['L2HGA', 'HC', 'HD']),
  'bull_terrier': BreedInfo(11, 50, 55, 20, 35, 11, 14, 3, ['Słuch', 'Nerki', 'Serce']),
  'jack_russell': BreedInfo(345, 25, 30, 5, 6, 13, 16, 5, ['PLL', 'Słuch', 'Rzepki']),
  'parson_russell': BreedInfo(339, 33, 36, 6, 8, 13, 15, 5, ['PLL', 'Słuch', 'Rzepki']),
  'yorkshire': BreedInfo(86, 18, 23, 2, 3.2, 13, 16, 3, ['Rzepki', 'Oczy']),
  'westie': BreedInfo(85, 25, 28, 6, 10, 12, 16, 3, ['Rzepki', 'Oczy']),
  'fox_terrier': BreedInfo(12, 36, 39, 7, 8.5, 13, 15, 5, ['PLL', 'Słuch']),
  'airedale': BreedInfo(7, 56, 61, 18, 29, 11, 13, 4, _hed),
  'scottish_terrier': BreedInfo(73, 25, 28, 8, 10.5, 11, 13, 3, ['vWD', 'Oczy']),
  'cairn': BreedInfo(4, 28, 31, 6, 7.5, 13, 15, 4, ['Oczy', 'Rzepki']),
  'border_terrier': BreedInfo(10, 30, 40, 5, 7, 12, 15, 4, ['Oczy', 'Serce']),
  'german_hunting_terrier': BreedInfo(103, 33, 40, 7.5, 10, 13, 15, 5, ['PLL', 'Rzepki']),
  // Grupa IV
  'dachshund': BreedInfo(148, 20, 27, 3.5, 9, 12, 16, 3, ['Kręgosłup', 'Oczy', 'PRA', 'Rzepki']),
  // Grupa V
  'husky': BreedInfo(270, 50, 60, 16, 28, 12, 14, 5, ['HD', 'Oczy']),
  'malamute': BreedInfo(243, 58, 64, 34, 45, 10, 14, 4, ['HD', 'Oczy']),
  'samoyed': BreedInfo(212, 51, 60, 17, 30, 12, 14, 4, ['HD', 'Oczy', 'PRA']),
  'akita': BreedInfo(255, 61, 70, 30, 50, 10, 13, 3, ['HD', 'Oczy', 'PRA', 'Tarczyca']),
  'american_akita': BreedInfo(344, 61, 71, 32, 59, 10, 13, 3, ['HD', 'ED', 'Tarczyca']),
  'shiba': BreedInfo(257, 35, 41, 7, 11, 13, 16, 4, ['Rzepki', 'Oczy', 'GM1']),
  'pomeranian': BreedInfo(97, 18, 24, 1.5, 3.5, 12, 16, 3, ['Rzepki', 'Oczy']),
  'german_spitz': BreedInfo(97, 30, 55, 7, 20, 12, 15, 3, ['Rzepki', 'Oczy', 'HD']),
  'keeshond': BreedInfo(97, 43, 55, 15, 20, 12, 15, 3, ['HD', 'Oczy']),
  'chow': BreedInfo(205, 46, 56, 20, 32, 9, 12, 1, ['HD', 'ED', 'Oczy']),
  'basenji': BreedInfo(43, 40, 43, 9.5, 11, 12, 16, 4, ['Fanconi', 'Oczy', 'PRA']),
  'eurasier': BreedInfo(291, 48, 60, 18, 32, 12, 14, 3, ['HD', 'ED', 'Oczy', 'Tarczyca']),
  'pharaoh': BreedInfo(248, 53, 63, 18, 27, 12, 14, 4, ['HD', 'Oczy']),
  'xolo': BreedInfo(234, 25, 60, 4, 25, 13, 18, 3, ['Rzepki', 'Oczy']),
  // Grupa VI
  'beagle': BreedInfo(161, 33, 40, 9, 14, 12, 15, 4, ['IGS', 'NCCD', 'MLS', 'HD', 'Kręgosłup']),
  'basset': BreedInfo(163, 33, 38, 20, 29, 10, 12, 2, ['Oczy', 'Kręgosłup']),
  'dalmatian': BreedInfo(153, 54, 61, 24, 32, 11, 13, 5, ['Słuch', 'HUU', 'HD']),
  'rhodesian': BreedInfo(146, 61, 69, 32, 37, 10, 12, 4, ['HD', 'ED', 'DM', 'Zatoka skórna']),
  'ogar': BreedInfo(52, 55, 65, 25, 32, 12, 14, 4, ['HD']),
  'gonczy_polski': BreedInfo(354, 50, 59, 20, 26, 12, 14, 4, ['HD']),
  'bloodhound': BreedInfo(84, 58, 72, 40, 54, 10, 12, 3, _hedEye),
  'hanover_hound': BreedInfo(213, 48, 55, 25, 45, 12, 14, 3, ['HD']),
  'bavarian_hound': BreedInfo(217, 44, 52, 17, 30, 12, 15, 4, ['HD']),
  // Grupa VII
  'gsp': BreedInfo(119, 58, 66, 20, 32, 12, 14, 5, _hedEye),
  'gwp': BreedInfo(98, 57, 68, 22, 32, 12, 14, 5, ['HD', 'ED', 'vWD']),
  'vizsla': BreedInfo(57, 54, 64, 18, 27, 12, 15, 5, _hed),
  'wire_vizsla': BreedInfo(239, 54, 64, 22, 30, 12, 14, 5, _hed),
  'weimaraner': BreedInfo(99, 57, 70, 25, 40, 11, 14, 5, _hed),
  'pointer': BreedInfo(1, 53, 69, 20, 34, 12, 15, 5, ['HD', 'Oczy']),
  'irish_setter': BreedInfo(120, 55, 67, 24, 32, 12, 15, 5, ['HD', 'ED', 'PRA']),
  'english_setter': BreedInfo(2, 61, 68, 20, 36, 11, 14, 4, ['HD', 'ED', 'Słuch']),
  'gordon_setter': BreedInfo(6, 62, 66, 25, 32, 10, 13, 4, ['HD', 'ED', 'PRA']),
  'brittany': BreedInfo(95, 47, 52, 14, 18, 12, 14, 5, ['HD']),
  'wyzel_polski': BreedInfo(null, 56, 66, 22, 32, 12, 14, 4, _hed),
  'munsterlander': BreedInfo(null, 50, 65, 15, 30, 12, 14, 4, _hed),
  // Grupa VIII
  'labrador': BreedInfo(122, 54, 57, 25, 36, 11, 14, 4, ['HD', 'ED', 'Oczy', 'PRA', 'EIC', 'CNM']),
  'golden': BreedInfo(111, 51, 61, 25, 36, 10, 12, 3, ['HD', 'ED', 'Oczy', 'Serce', 'ICT-A']),
  'flatcoat': BreedInfo(121, 56, 61, 25, 36, 8, 10, 4, ['HD', 'ED', 'Oczy', 'Rzepki']),
  'toller': BreedInfo(312, 45, 51, 17, 23, 12, 14, 5, ['HD', 'ED', 'Oczy', 'CEA', 'PRA']),
  'chesapeake': BreedInfo(263, 53, 66, 25, 36, 10, 13, 4, ['HD', 'ED', 'DM', 'EIC']),
  'cocker': BreedInfo(5, 38, 41, 13, 15, 12, 15, 4, ['HD', 'Oczy', 'PRA', 'FN']),
  'american_cocker': BreedInfo(167, 34, 39, 9, 13, 12, 15, 3, ['Oczy', 'HD', 'Rzepki']),
  'springer': BreedInfo(125, 48, 51, 18, 25, 12, 14, 5, ['HD', 'ED', 'Oczy', 'PFK']),
  'wachtel': BreedInfo(104, 45, 54, 18, 30, 12, 14, 4, ['HD']),
  'lagotto': BreedInfo(298, 41, 48, 11, 16, 15, 17, 4, _hedEye),
  'portuguese_water': BreedInfo(37, 43, 57, 16, 25, 11, 13, 4, ['HD', 'Oczy', 'PRA', 'GM1', 'DCM']),
  // Grupa IX
  'poodle': BreedInfo(172, 24, 60, 3, 30, 12, 15, 4, ['HD', 'Oczy', 'PRA', 'Rzepki']),
  'chihuahua': BreedInfo(218, 15, 23, 1.5, 3, 14, 17, 3, ['Rzepki', 'MVD']),
  'maltese': BreedInfo(65, 20, 25, 3, 4, 12, 15, 3, ['Rzepki', 'Oczy']),
  'shih_tzu': BreedInfo(208, 20, 27, 4.5, 8, 10, 16, 2, ['BOAS', 'Oczy', 'Nerki', 'Rzepki']),
  'french_bulldog': BreedInfo(101, 27, 35, 8, 14, 10, 12, 2, ['BOAS', 'Kręgosłup', 'HD', 'Oczy']),
  'pug': BreedInfo(253, 25, 33, 6.3, 8.1, 12, 15, 2, ['BOAS', 'Oczy', 'Kręgosłup']),
  'cavalier': BreedInfo(136, 30, 33, 5.4, 8, 9, 14, 3, ['MVD', 'SM', 'Oczy', 'Rzepki']),
  'papillon': BreedInfo(77, 20, 28, 2.5, 4.5, 13, 16, 4, ['Rzepki', 'Oczy', 'PRA']),
  'havanese': BreedInfo(250, 23, 27, 4, 6, 14, 16, 3, ['Rzepki', 'Oczy']),
  'bichon': BreedInfo(215, 25, 29, 5, 8, 12, 15, 3, ['Rzepki', 'Oczy']),
  'boston': BreedInfo(140, 38, 43, 4.5, 11.4, 11, 13, 3, ['Oczy', 'BOAS', 'Rzepki']),
  'lhasa': BreedInfo(227, 23, 28, 5, 8, 12, 15, 2, ['Oczy', 'PRA', 'Nerki']),
  'pekingese': BreedInfo(207, 15, 23, 3, 5, 12, 14, 1, ['BOAS', 'Oczy', 'Kręgosłup']),
  'coton': BreedInfo(283, 22, 30, 3.5, 6, 14, 16, 3, ['Rzepki', 'Oczy', 'PRA']),
  'prague_ratter': BreedInfo(null, 20, 23, 1.5, 3.5, 12, 14, 4, ['Rzepki']),
  // Grupa X
  'greyhound': BreedInfo(158, 68, 76, 27, 40, 10, 13, 3, ['Serce']),
  'whippet': BreedInfo(162, 44, 51, 9, 19, 12, 15, 4, ['MVD', 'Oczy']),
  'saluki': BreedInfo(269, 58, 71, 18, 27, 12, 14, 4, ['Serce', 'Tarczyca']),
  'borzoi': BreedInfo(193, 68, 85, 25, 48, 10, 12, 3, ['Serce', 'Oczy']),
  'afghan': BreedInfo(228, 63, 74, 23, 29, 12, 14, 3, ['Oczy', 'Tarczyca', 'HD']),
  'chart_polski': BreedInfo(333, 68, 80, 25, 40, 12, 14, 3, ['Serce']),
  'italian_greyhound': BreedInfo(200, 32, 38, 3, 5, 13, 15, 4, ['Oczy', 'PRA', 'Rzepki']),
  'irish_wolfhound': BreedInfo(160, 71, 90, 40, 60, 6, 9, 2, ['DCM', 'HD']),
};

/// Nazwy aktywności z kategorią A lub B (zgodność ze starszym kodem).
List<String> sportsFor(String breedId) => [
  for (final f in sportFitsFor(breedId))
    if (f.fit == Fit.a || f.fit == Fit.b) f.activity.name,
];

BreedInfo? breedInfoFor(String? breedId) => breedId == null ? null : breedInfos[canonicalBreedId(breedId)];

/// Ile ras z bazy ma pełne dane (do testów).
int get breedsWithInfo => breeds.where((b) => breedInfos.containsKey(b.id)).length;
