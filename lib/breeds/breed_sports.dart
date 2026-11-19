import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import 'breed_info.dart';
import 'breed_profile.dart';

/// Rodzaj aktywności. Jedna aktywność może należeć do kilku kategorii
/// (np. mantrailing to sport, praca użytkowa i praca węchowa).
enum ActivityCategory {
  sport('Sporty kynologiczne', Icons.emoji_events_outlined),
  recreation('Aktywności rekreacyjne', Icons.directions_walk_rounded),
  work('Praca użytkowa', Icons.work_outline_rounded),
  mental('Aktywności umysłowe i węchowe', Icons.psychology_outlined);

  final String _label;
  final IconData icon;
  String get label => tr(_label);
  const ActivityCategory(this._label, this.icon);
}

/// Główny rodzaj obciążenia – decyduje o wieku rozpoczęcia treningu.
enum ActivityLoad { light, running, pulling, jumping, sprint, strength }

typedef _K = ActivityCategory;
typedef _L = ActivityLoad;

class Activity {
  final String id;
  final String _name;
  final Set<ActivityCategory> categories;
  final ActivityLoad load;
  const Activity(this.id, this._name, this.categories, this.load);
  String get name => tr(_name);

  /// Nazwa polska (klucz tłumaczenia).
  String get namePl => _name;
}

/// Wszystkie aktywności oceniane w Atlasie ras.
const activities = <Activity>[
  Activity('canicross', 'Canicross', {_K.sport, _K.recreation}, _L.running),
  Activity('bikejoring', 'Bikejoring', {_K.sport}, _L.pulling),
  Activity('dogtrekking', 'Dogtrekking', {_K.sport, _K.recreation}, _L.running),
  Activity('sled', 'Psie zaprzęgi', {_K.sport}, _L.pulling),
  Activity('weightpull', 'Weight pulling', {_K.sport}, _L.strength),
  Activity('agility', 'Agility', {_K.sport}, _L.jumping),
  Activity('flyball', 'Flyball', {_K.sport}, _L.jumping),
  Activity('frisbee', 'Dogfrisbee', {_K.sport}, _L.jumping),
  Activity('obedience', 'Obedience', {_K.sport}, _L.light),
  Activity('rally', 'Rally-O', {_K.sport}, _L.light),
  Activity('igp', 'IGP', {_K.sport, _K.work}, _L.jumping),
  Activity('mondio', 'Mondioring', {_K.sport, _K.work}, _L.jumping),
  Activity('coursing', 'Coursing', {_K.sport}, _L.sprint),
  Activity('racing', 'Wyścigi chartów', {_K.sport}, _L.sprint),
  Activity('nosework', 'Nosework', {_K.sport, _K.mental}, _L.light),
  Activity('tracking', 'Tropienie użytkowe', {_K.sport, _K.work, _K.mental}, _L.light),
  Activity('mantrailing', 'Mantrailing', {_K.sport, _K.work, _K.mental}, _L.light),
  Activity('dummy', 'Dummy', {_K.sport, _K.work}, _L.light),
  Activity('herding', 'Pasienie', {_K.work, _K.sport}, _L.running),
  Activity('hunting', 'Praca myśliwska', {_K.work}, _L.running),
  Activity('sar', 'Ratownictwo', {_K.work}, _L.running),
  Activity('water_rescue', 'Ratownictwo wodne', {_K.work, _K.sport}, _L.strength),
  Activity('lgd', 'Ochrona stada', {_K.work}, _L.light),
  Activity('therapy', 'Dogoterapia', {_K.work}, _L.light),
  Activity('walks', 'Spacery i wędrówki', {_K.recreation}, _L.light),
  Activity('swimming', 'Pływanie', {_K.recreation}, _L.light),
  Activity('tricks', 'Sztuczki (trick dog)', {_K.mental, _K.recreation}, _L.light),
];

Activity? activityById(String id) {
  for (final a in activities) {
    if (a.id == id) return a;
  }
  return null;
}

/// Kategoria predyspozycji. Nie polega tylko na kolorze: ma literę i ikonę.
enum Fit {
  a('A', 'Wysokie predyspozycje', Icons.check_circle_rounded, Color(0xFF34C759)),
  b('B', 'Odpowiedni warunkowo', Icons.tune_rounded, Color(0xFFFFC53D)),
  c('C', 'Niezalecany', Icons.block_rounded, Color(0xFFFF453A)),
  d('D', 'Indywidualna ocena', Icons.help_outline_rounded, Color(0xFF9A9AA1));

  final String letter;
  final String _label;
  final IconData icon;
  final Color color;
  String get label => tr(_label);
  const Fit(this.letter, this._label, this.icon, this.color);
}

/// Ocena jednej aktywności dla rasy.
class SportFit {
  final Activity activity;
  final Fit fit;
  final String _reason;
  final List<String> _limits;

  /// Czy przed startem potrzebne jest stopniowe przygotowanie kondycyjne.
  final bool needsConditioning;

  const SportFit(this.activity, this.fit, this._reason, this._limits, this.needsConditioning);
  String get reason => tr(_reason);
  List<String> get limits => trList(_limits);
  String get reasonPl => _reason;
  List<String> get limitsPl => _limits;
}

// ---------------------------------------------------------------------------
// Reguły
// ---------------------------------------------------------------------------

class _F {
  final Fit fit;
  final String reason;
  final List<String> limits;
  const _F(this.fit, this.reason, [this.limits = const []]);
}

typedef _T = BreedTrait;
typedef _R = BreedRole;

class _C {
  final String id;
  final BreedInfo i;
  final BreedProfile p;
  _C(this.id, this.i, this.p);
  double get w => (i.weightMin + i.weightMax) / 2;
  bool has(BreedTrait t) => p.has(t);
  bool get small => w < 10;
  bool get bulky => has(_T.giant) || has(_T.heavy);
  BreedRole get role => p.role;
}

// Wspólne uzasadnienia i ograniczenia (polskie klucze tłumaczeń).
const _rBrachyRun =
    'Budowa krótkoczaszkowa utrudnia oddychanie i chłodzenie – przy długim biegu duże ryzyko przegrzania i duszności.';
const _rBrachyShort = 'Budowa krótkoczaszkowa – intensywny wysiłek nasila duszność i ryzyko przegrzania.';
const _rBrachyMild = 'Skrócona kufa – gorzej oddaje ciepło, ale przy umiarkowanym wysiłku zwykle dobrze trenuje.';
const _rLongBackPull =
    'Krótkie kończyny i długi kręgosłup – bieg w uprzęży z ciągnięciem obciąża kręgosłup (ryzyko dyskopatii).';
const _rLongBackJump = 'Skoki, nawroty i strome przeszkody silnie obciążają długi kręgosłup (ryzyko dyskopatii).';
const _rToyRun = 'Bardzo mały pies – tempo biegnącego człowieka lub roweru przekracza jego naturalne tempo.';
const _rSmallPull = 'Za mała masa ciała do pracy pociągowej przy prędkości roweru lub zaprzęgu.';
const _rHeavyRun = 'Duża masa ciała – długi, równy bieg mocno obciąża stawy i układ krążenia.';
const _rHeavyJump = 'Duża masa ciała – skoki i gwałtowne zwroty obciążają stawy i więzadła.';
const _rLgd =
    'Rasa stróżująca o samodzielnym charakterze – brak podstaw do ogólnej rekomendacji; oceń konkretnego psa.';
const _rSight = 'Chart to sprinter – lepiej znosi krótkie, szybkie odcinki niż długi, równy bieg.';
const _rIndep =
    'Rasa niezależna – praca sportowa wymaga cierpliwej, motywacyjnej pracy; o przydatności decyduje konkretny pies.';
const _rNoBasis =
    'Rasa rzadko trenowana w tej dyscyplinie – brak podstaw do ogólnej rekomendacji; oceń konkretnego psa.';
const _rBig = 'Duży, ciężki pies – możliwy rekreacyjnie, w umiarkowanym tempie i na krótszych dystansach.';
const _rCond = 'Możliwy przy stopniowym budowaniu kondycji i dopasowaniu intensywności do psa.';

const _lHeat = 'Trenuj tylko w chłodne dni, krótko, z przerwami; przerwij przy głośnym oddechu.';
const _lBrachyAlt = 'Zamiast tego: spokojne spacery, nosework, sztuczki, rally-O.';
const _lLongBackAlt = 'Zamiast tego: marsze bez ciągnięcia, nosework, tropienie, rally-O.';
const _lHeavy = 'Spokojne tempo, krótsze dystanse, kontrola masy ciała.';
const _lCardio = 'Przed regularnym treningiem wytrzymałościowym zrób badanie kardiologiczne (echo serca).';
const _lCoat = 'Gęsta szata – trenuj w chłodne dni.';
const _lPatella = 'Przed treningiem skoków oceń stawy kolanowe (rzepki).';
const _lJoints = 'Przed rozpoczęciem intensywnego sportu oceń stawy (RTG bioder i łokci).';
const _lJumpLow = 'Niższe skoki, nauka techniki, miękkie podłoże.';
const _lHarness = 'Dobrze dopasowane szelki sportowe, które nie uciskają łopatek.';

_F? _canicross(_C c) {
  if (c.has(_T.brachy)) return const _F(Fit.c, _rBrachyRun, [_lBrachyAlt]);
  if (c.has(_T.longBack)) return const _F(Fit.c, _rLongBackPull, [_lLongBackAlt]);
  if (c.has(_T.toy)) return const _F(Fit.c, _rToyRun, ['Zamiast tego: spacery, zabawy węchowe, sztuczki.']);
  if (c.bulky) return const _F(Fit.c, _rHeavyRun, ['Lepsze spokojne marsze i pływanie.']);
  if (c.role == _R.lgd) return const _F(Fit.d, _rLgd);
  if (c.has(_T.brachyMild)) return const _F(Fit.b, _rBrachyMild, [_lHeat]);
  if (c.has(_T.sprinter)) return const _F(Fit.b, _rSight, ['Krótkie trasy, ochrona przed zimnem i urazami łap.']);
  if (c.w >= 40) return const _F(Fit.b, _rBig, [_lHeavy, _lJoints]);
  if (c.has(_T.endurance)) {
    return const _F(Fit.a, 'Atletyczna budowa i wytrzymałość – dobre predyspozycje do biegu w uprzęży.', [_lHarness]);
  }
  if (c.has(_T.independent) || c.i.energy <= 2) return const _F(Fit.d, _rNoBasis);
  if (c.small) {
    return const _F(Fit.b, 'Mały, ale sprawny pies – krótkie dystanse i tempo dopasowane do psa.', [_lHarness]);
  }
  return const _F(Fit.b, _rCond, [_lHarness]);
}

_F? _pulling(_C c, {required bool sled}) {
  if (c.has(_T.brachy) || c.has(_T.brachyMild)) {
    return const _F(Fit.c, 'Skrócona kufa – długi, szybki bieg w zaprzęgu grozi przegrzaniem.', [_lBrachyAlt]);
  }
  if (c.has(_T.longBack)) return const _F(Fit.c, _rLongBackPull, [_lLongBackAlt]);
  if (c.has(_T.toy) || c.w < 12) return const _F(Fit.c, _rSmallPull);
  if (c.bulky) return const _F(Fit.c, _rHeavyRun);
  if (c.role == _R.lgd) return const _F(Fit.d, _rLgd);
  if (c.has(_T.sprinter)) return const _F(Fit.d, _rSight);
  if (c.w >= 40 && c.role != _R.sled) return const _F(Fit.b, _rBig, [_lHeavy, _lJoints]);
  if (c.role == _R.sled) {
    return const _F(Fit.a, 'Rasa zaprzęgowa – naturalna chęć ciągnięcia i wytrzymałość.', [_lCoat]);
  }
  if (c.role == _R.pointer && c.has(_T.endurance)) {
    return const _F(Fit.a, 'Szybki i wytrzymały wyżeł – dobre predyspozycje do biegu w zaprzęgu (klasy otwarte).', [
      _lHarness,
    ]);
  }
  if (c.has(_T.endurance) && !sled) {
    return const _F(Fit.a, 'Atletyczna budowa i wytrzymałość – dobre predyspozycje do pracy przed rowerem.', [
      _lHarness,
    ]);
  }
  if (c.has(_T.endurance) || c.i.energy >= 4) return const _F(Fit.b, _rCond, [_lHarness]);
  return const _F(Fit.d, _rNoBasis);
}

_F? _dogtrekking(_C c) {
  if (c.has(_T.brachy)) {
    return const _F(Fit.c, 'Długie marsze, zwłaszcza w cieple, są dla ras krótkoczaszkowych dużym obciążeniem.', [
      'Krótkie spacery w chłodne dni są w porządku.',
    ]);
  }
  if (c.has(_T.longBack)) {
    return const _F(Fit.b, 'Spokojny marsz jest odpowiedni, ale bez ciągnięcia na lince – krótsze trasy rekreacyjne.', [
      _lHarness,
    ]);
  }
  if (c.has(_T.toy)) {
    return const _F(
      Fit.d,
      'Trasy zawodów (zwykle kilkadziesiąt km) są za długie dla bardzo małego psa; krótkie wycieczki – tak.',
    );
  }
  if (c.bulky || c.has(_T.brachyMild)) {
    return const _F(Fit.b, 'Spokojne tempo marszu i krótsze dystanse z przerwami.', [_lHeavy]);
  }
  if (c.has(_T.endurance) || c.i.energy >= 4) {
    return const _F(Fit.a, 'Wytrzymały pies, który dobrze znosi długie marsze w terenie.');
  }
  return const _F(Fit.b, 'Odpowiedni przy stopniowym wydłużaniu tras.');
}

_F? _agility(_C c) {
  if (c.has(_T.brachy)) return const _F(Fit.c, _rBrachyShort, [_lBrachyAlt]);
  if (c.has(_T.longBack)) return const _F(Fit.c, _rLongBackJump, [_lLongBackAlt]);
  if (c.bulky) return const _F(Fit.c, _rHeavyJump, ['Zamiast tego: rally-O, nosework, obedience.']);
  if (c.has(_T.agile)) {
    return const _F(Fit.a, 'Zwinny, szybki i chętny do współpracy – bardzo dobre predyspozycje do agility.', [
      _lJoints,
    ]);
  }
  if (c.has(_T.toy)) {
    return const _F(Fit.b, 'Możliwy w najniższej klasie wysokości, przy ostrożnym wprowadzaniu skoków.', [_lJumpLow]);
  }
  if (c.has(_T.brachyMild)) return const _F(Fit.b, _rBrachyMild, [_lHeat]);
  if (c.has(_T.sprinter)) {
    return const _F(Fit.b, 'Szybki, ale delikatny – ostrożnie na śliskim podłożu i w ciasnych zakrętach.', [_lJumpLow]);
  }
  if (c.w >= 38) {
    return const _F(Fit.b, 'Duży i ciężki pies – możliwy przy niższych skokach i umiarkowanej intensywności.', [
      _lJumpLow,
      _lJoints,
    ]);
  }
  if (c.has(_T.independent)) return const _F(Fit.d, _rIndep);
  return const _F(Fit.b, 'Możliwy przy właściwym przygotowaniu i nauce techniki.', [_lJoints]);
}

_F? _flyball(_C c) {
  if (c.has(_T.brachy)) return const _F(Fit.c, _rBrachyShort, [_lBrachyAlt]);
  if (c.has(_T.longBack)) return const _F(Fit.c, _rLongBackJump, [_lLongBackAlt]);
  if (c.bulky) return const _F(Fit.c, _rHeavyJump);
  if (c.has(_T.agile) && !c.has(_T.toy)) {
    return const _F(Fit.a, 'Szybki, zwinny i zmotywowany do zabawy piłką – dobre predyspozycje do flyballa.', [
      _lJoints,
    ]);
  }
  if (c.has(_T.toy)) {
    return const _F(Fit.b, 'Niskie skoki są możliwe, ale nawrót przy maszynie obciąża drobne stawy.', [_lJumpLow]);
  }
  if (c.has(_T.independent) || c.role == _R.lgd) return const _F(Fit.d, _rNoBasis);
  return const _F(Fit.b, 'Możliwy przy nauce bezpiecznego nawrotu i stopniowym treningu.', [_lJoints]);
}

_F? _frisbee(_C c) {
  if (c.has(_T.brachy)) return const _F(Fit.c, _rBrachyShort, [_lBrachyAlt]);
  if (c.has(_T.longBack)) return const _F(Fit.c, _rLongBackJump, [_lLongBackAlt]);
  if (c.bulky || c.w >= 38) {
    return const _F(Fit.c, 'Ciężki pies – skoki po dysk i lądowania mocno obciążają stawy i kręgosłup.');
  }
  if (c.has(_T.toy)) return const _F(Fit.d, 'Bardzo mały pies – dysk i chwyty w skoku słabo pasują do jego wielkości.');
  const low = 'Rzuty nisko przy ziemi, bez wysokich skoków i lądowań na tylnych łapach, szczególnie u młodych psów.';
  if (c.has(_T.agile)) {
    return const _F(Fit.a, 'Szybki, zwinny i zmotywowany do aportu – dobre predyspozycje do dogfrisbee.', [
      low,
      _lJoints,
    ]);
  }
  if (c.has(_T.independent) || c.role == _R.lgd || c.has(_T.sprinter)) return const _F(Fit.d, _rNoBasis);
  return const _F(Fit.b, 'Możliwy jako zabawa i sport przy nauce bezpiecznych chwytów.', [low]);
}

const _trainable = {_R.herding, _R.shepherdWorking, _R.working, _R.retriever};

_F? _obedience(_C c) {
  if (c.has(_T.brachy)) {
    return const _F(Fit.b, 'Mały wysiłek fizyczny – odpowiedni przy krótkich sesjach w chłodzie.', [_lHeat]);
  }
  if (_trainable.contains(c.role) || c.id == 'poodle') {
    return const _F(
      Fit.a,
      'Rasa chętna do współpracy z przewodnikiem – bardzo dobre predyspozycje do posłuszeństwa sportowego.',
    );
  }
  if (c.has(_T.independent) || c.role == _R.lgd || c.role == _R.sighthound) return const _F(Fit.b, _rIndep);
  return const _F(Fit.b, 'Odpowiedni przy pracy opartej na motywacji i krótkich sesjach.');
}

_F? _rally(_C c) {
  if (c.has(_T.brachy)) {
    return const _F(
      Fit.b,
      'Niskie obciążenie fizyczne – dobra dyscyplina dla rasy przy krótkich przebiegach w chłodzie.',
      [_lHeat],
    );
  }
  if (c.has(_T.longBack)) {
    return const _F(Fit.a, 'Spokojna dyscyplina o niskim obciążeniu – dobra alternatywa dla sportów skokowych.', [
      'Ćwiczenie skoku wykonuj nisko lub pomiń w treningu.',
    ]);
  }
  if (c.has(_T.giant)) {
    return const _F(Fit.b, 'Niskie obciążenie, ale ćwiczenia ze skokiem i ciasne zwroty dostosuj do masy psa.');
  }
  if (c.has(_T.independent) || c.role == _R.lgd) return const _F(Fit.b, _rIndep);
  return const _F(Fit.a, 'Spokojna dyscyplina o niskim obciążeniu – dobra dla większości psów chętnych do współpracy.');
}

const _igpA = {
  'malinois',
  'groenendael',
  'tervueren',
  'laekenois',
  'gsd',
  'dutch_shepherd',
  'dobermann',
  'rottweiler',
  'giant_schnauzer',
  'beauceron',
  'hovawart',
};
const _igpB = {'white_swiss', 'boxer', 'black_russian', 'standard_schnauzer', 'cane_corso', 'airedale', 'briard'};

_F? _igp(_C c) {
  if (_igpA.contains(c.id)) {
    return const _F(Fit.a, 'Tradycyjna rasa użytkowa – predyspozycje do tropienia, posłuszeństwa i ochrony.', [
      _lJoints,
    ]);
  }
  if (_igpB.contains(c.id)) {
    return const _F(
      Fit.b,
      'Rasa użytkowa, ale rzadziej szkolona w IGP – przydatność zależy od charakteru i motywacji psa.',
      [_lJoints],
    );
  }
  if (c.has(_T.brachy) || c.small || c.has(_T.toy)) {
    return const _F(
      Fit.c,
      'Część ochronna (praca z pozorantem) wymaga siły i masy – rasa nie jest do niej przystosowana.',
      ['Można trenować samo tropienie lub posłuszeństwo.'],
    );
  }
  if (c.bulky) {
    return const _F(Fit.c, 'Masa i budowa ciała utrudniają skoki przez przeszkody i dynamiczną pracę w ochronie.');
  }
  return const _F(Fit.d, _rNoBasis);
}

_F? _mondio(_C c) {
  if (c.id == 'malinois') {
    return const _F(
      Fit.a,
      'Szybki, zwinny i bardzo zmotywowany – rasa dominująca w sportach obronnych z wysokimi skokami.',
      [_lJoints],
    );
  }
  if (c.role == _R.shepherdWorking || (_igpA.contains(c.id) && c.w < 45)) {
    return const _F(
      Fit.b,
      'Rasa użytkowa – możliwy przy dobrej sprawności, bo program zawiera wysokie skoki i dynamiczną ochronę.',
      [_lJoints],
    );
  }
  if (c.has(_T.brachy) || c.small || c.has(_T.toy)) {
    return const _F(
      Fit.c,
      'Część ochronna (praca z pozorantem) wymaga siły i masy – rasa nie jest do niej przystosowana.',
    );
  }
  if (c.bulky) {
    return const _F(Fit.c, 'Masa i budowa ciała utrudniają skoki przez przeszkody i dynamiczną pracę w ochronie.');
  }
  return const _F(Fit.d, _rNoBasis);
}

const _coursingBreeds = {'basenji', 'pharaoh', 'rhodesian'};

_F? _coursing(_C c) {
  if (c.role != _R.sighthound && !_coursingBreeds.contains(c.id)) return null;
  const lim = ['Przed startem badanie weterynaryjne, rozgrzewka i bezpieczny, równy teren.'];
  if (c.has(_T.giant)) {
    return const _F(
      Fit.b,
      'Instynkt pogoni zachowany, ale rasa olbrzymia – większe obciążenie stawów i serca przy sprincie.',
      [_lCardio, ...lim],
    );
  }
  if (c.id == 'italian_greyhound') {
    return const _F(Fit.b, 'Szybki i chętny do pogoni, ale cienkie kości kończyn – ryzyko złamań przy upadkach.', lim);
  }
  return const _F(Fit.a, 'Polowanie wzrokiem i sprint to naturalne predyspozycje rasy.', lim);
}

_F? _racing(_C c) {
  const lim = ['Wymagana licencja wyścigowa; zasady dopuszczenia określa regulamin organizatora.'];
  if (c.id == 'pharaoh') {
    return const _F(
      Fit.d,
      'Szybki pies w typie charta, ale dopuszczenie rasy do wyścigów zależy od regulaminu – sprawdź u organizatora.',
      lim,
    );
  }
  if (c.role != _R.sighthound) return null;
  switch (c.id) {
    case 'greyhound' || 'whippet' || 'chart_polski':
      return const _F(Fit.a, 'Sprinter wyhodowany do szybkiego biegu – bardzo dobre predyspozycje do wyścigów.', lim);
    case 'italian_greyhound':
      return const _F(Fit.b, 'Szybki, ale cienkie kości kończyn – ryzyko złamań przy upadkach.', lim);
    case 'irish_wolfhound':
      return const _F(Fit.b, 'Rasa olbrzymia – szybki bieg po torze z wirażami mocno obciąża stawy i serce.', [
        _lCardio,
        ...lim,
      ]);
    default:
      return const _F(
        Fit.b,
        'Chart lepiej odnajduje się w coursingu (bieg w terenie) niż na owalnym torze, ale wyścigi są możliwe.',
        lim,
      );
  }
}

_F? _weightpull(_C c) {
  const lim = ['Tylko w szelkach do weight pullingu, od małych ciężarów i nigdy przed zakończeniem wzrostu.'];
  if (c.has(_T.brachy)) return const _F(Fit.c, _rBrachyShort);
  if (c.has(_T.longBack)) {
    return const _F(Fit.c, 'Długi kręgosłup i krótkie kończyny – praca siłowa grozi urazem kręgosłupa.');
  }
  if (c.has(_T.toy) || c.small) {
    return const _F(Fit.c, 'Mała masa ciała – ciągnięcie ciężarów jest dla rasy nieodpowiednie.');
  }
  if (c.has(_T.cardiac)) {
    return const _F(Fit.c, 'Maksymalny wysiłek siłowy przy predyspozycji do chorób serca – niezalecany.');
  }
  if (c.has(_T.sprinter)) return const _F(Fit.c, 'Lekka budowa charta nie jest przystosowana do pracy siłowej.');
  if (c.id == 'malamute') return const _F(Fit.a, 'Pies zaprzęgowy do ciężkich ładunków – siła i wytrzymałość.', lim);
  if (c.role == _R.bully) return const _F(Fit.b, 'Silna, zwarta i umięśniona budowa – predyspozycje siłowe.', lim);
  if (c.role == _R.sled || c.role == _R.mountain || c.id == 'rottweiler') {
    return const _F(Fit.b, 'Rasa o tradycji pracy pociągowej – przy umiarkowanym obciążeniu.', lim);
  }
  return const _F(Fit.d, 'Rasa nie jest typowo używana do pracy siłowej – brak podstaw do ogólnej rekomendacji.');
}

const _noseRoles = {
  _R.scentHound,
  _R.retriever,
  _R.spaniel,
  _R.dachshund,
  _R.pointer,
  _R.shepherdWorking,
  _R.herding,
  _R.terrier,
  _R.water,
  _R.working,
};

_F? _nosework(_C c) {
  if (c.has(_T.brachy)) {
    return const _F(
      Fit.b,
      'Odpowiedni, ale węszenie przy krótkiej kufie męczy szybciej – krótkie sesje w chłodnym miejscu.',
    );
  }
  if (c.role == _R.sighthound) {
    return const _F(
      Fit.b,
      'Chart poluje głównie wzrokiem – nosework to dobre urozmaicenie, choć motywacja bywa mniejsza.',
    );
  }
  if (_noseRoles.contains(c.role)) {
    return const _F(Fit.a, 'Dobry węch i chęć pracy – bardzo dobre predyspozycje do pracy węchowej.');
  }
  return const _F(Fit.a, 'Niskie obciążenie fizyczne i praca węchem – odpowiedni dla niemal każdego psa.');
}

_F? _tracking(_C c) {
  if (c.role == _R.scentHound || c.role == _R.dachshund) {
    return const _F(Fit.a, 'Bardzo dobry węch i tradycja pracy na tropie – wysokie predyspozycje.');
  }
  if (c.role == _R.shepherdWorking || c.role == _R.working) {
    return const _F(Fit.a, 'Rasa użytkowa z dobrym węchem – tropienie to część jej tradycyjnej pracy.');
  }
  if (c.role == _R.sighthound) return const _F(Fit.d, 'Chart poluje wzrokiem – brak podstaw do ogólnej rekomendacji.');
  if (c.has(_T.brachy)) {
    return const _F(Fit.b, 'Wolne tempo pracy, ale krótka kufa utrudnia długie węszenie – krótkie ślady, chłodne dni.');
  }
  return const _F(Fit.b, 'Spokojne tempo i praca węchem – odpowiedni po nauce pracy na śladzie.');
}

_F? _mantrailing(_C c) {
  const line = 'Prowadź w szelkach na amortyzującej lince, bez szarpnięć.';
  if (c.role == _R.scentHound || c.role == _R.dachshund) {
    return const _F(Fit.a, 'Bardzo dobry węch i wytrwałość w pracy na śladzie – wysokie predyspozycje.', [line]);
  }
  if (c.role == _R.shepherdWorking || c.role == _R.retriever || c.role == _R.spaniel) {
    return const _F(Fit.a, 'Dobry węch i chęć pracy z przewodnikiem – dobre predyspozycje do szukania ludzi.', [line]);
  }
  if (c.has(_T.brachy)) {
    return const _F(
      Fit.b,
      'Odpowiedni w spokojnym tempie, ale krótka kufa męczy się szybciej – krótkie ślady, chłodne dni.',
      [line],
    );
  }
  return const _F(Fit.b, 'Praca węchowa odpowiednia dla większości psów – przydatność zależy od motywacji psa.', [
    line,
  ]);
}

const _dummyRoles = {_R.retriever, _R.spaniel, _R.pointer, _R.water};

_F? _dummy(_C c) {
  if (!_dummyRoles.contains(c.role) && c.id != 'poodle') return null;
  if (c.role == _R.retriever || c.id == 'cocker' || c.id == 'springer') {
    return const _F(Fit.a, 'Rasa aportująca – naturalne predyspozycje do pracy z dummy.');
  }
  return const _F(Fit.b, 'Aportuje chętnie, ale dummy to specjalność retrieverów i spanieli.');
}

const _herdingB = {
  'entlebucher',
  'appenzeller',
  'collie_rough',
  'white_swiss',
  'gsd',
  'groenendael',
  'tervueren',
  'laekenois',
  'malinois',
  'dutch_shepherd',
};

_F? _herding(_C c) {
  const lim = ['Zacznij od testu instynktu pasienia pod okiem instruktora.'];
  if (_herdingB.contains(c.id)) {
    return const _F(
      Fit.b,
      'Rasa o pasterskim pochodzeniu – instynkt pasienia bywa zachowany, ale dziś jest głównie użytkowa.',
      lim,
    );
  }
  if (c.role == _R.herding || c.id == 'beauceron') {
    return const _F(Fit.a, 'Rasa pasterska z naturalnym instynktem pasienia.', lim);
  }
  return null;
}

_F? _lgd(_C c) => c.role == _R.lgd
    ? const _F(Fit.a, 'Rasa wyhodowana do samodzielnej ochrony stad przed drapieżnikami.', [
        'To praca przy stadzie, nie sport – wymaga zwierząt gospodarskich i doświadczenia.',
      ])
    : null;

const _huntingTerriers = {'jack_russell', 'parson_russell', 'fox_terrier', 'border_terrier', 'german_hunting_terrier'};

_F? _hunting(_C c) {
  const lim = ['Wymaga szkolenia, prób pracy i przestrzegania prawa łowieckiego.'];
  if (c.role == _R.terrier) {
    if (_huntingTerriers.contains(c.id)) {
      return const _F(Fit.a, 'Rasa myśliwska z zachowanymi predyspozycjami do pracy w łowisku.', lim);
    }
    return const _F(Fit.d, 'Historycznie pies myśliwski – dziś rzadko używany w łowiectwie; oceń konkretnego psa.');
  }
  if (c.id == 'american_cocker') {
    return const _F(
      Fit.d,
      'Rasa dziś hodowana głównie jako pies do towarzystwa – predyspozycje łowieckie zależą od linii.',
    );
  }
  if ({_R.dachshund, _R.scentHound, _R.pointer, _R.retriever, _R.spaniel}.contains(c.role)) {
    return const _F(Fit.a, 'Rasa myśliwska z zachowanymi predyspozycjami do pracy w łowisku.', lim);
  }
  return null;
}

_F? _sar(_C c) {
  const lim = ['Wymaga wieloletniego szkolenia i egzaminów w grupie ratowniczej.'];
  if (c.has(_T.brachy) || c.has(_T.toy)) {
    return const _F(Fit.c, 'Długa praca w trudnym terenie przekracza możliwości fizyczne rasy.');
  }
  if (c.bulky || c.has(_T.longBack)) {
    return const _F(Fit.c, 'Praca na gruzowisku i w trudnym terenie wymaga zwinności i umiarkowanej masy ciała.');
  }
  if (c.role == _R.shepherdWorking || c.id == 'border_collie' || c.id == 'labrador') {
    return const _F(Fit.a, 'Wytrzymały, zwinny i chętny do pracy z przewodnikiem – typowa rasa w ratownictwie.', lim);
  }
  if ((c.role == _R.herding || c.role == _R.retriever || c.role == _R.working || c.role == _R.spaniel) && c.w >= 12) {
    return const _F(
      Fit.b,
      'Dobre cechy użytkowe – przydatność do ratownictwa zależy od charakteru i sprawności psa.',
      lim,
    );
  }
  return const _F(Fit.d, _rNoBasis);
}

const _waterA = {'newfoundland', 'leonberger'};
const _waterB = {'portuguese_water', 'labrador', 'golden', 'chesapeake', 'flatcoat'};

_F? _waterRescue(_C c) {
  const lim = ['Wymaga specjalistycznego szkolenia i stopniowego budowania kondycji w wodzie.'];
  if (_waterA.contains(c.id)) {
    return const _F(Fit.a, 'Silny pływak o odpowiedniej budowie i szacie – tradycyjny pies ratownik wodny.', [
      _lCardio,
      ...lim,
    ]);
  }
  if (_waterB.contains(c.id)) {
    return const _F(Fit.b, 'Dobrze pływa – ratownictwo wodne możliwe po specjalistycznym szkoleniu.', lim);
  }
  return null;
}

const _therapyB = {
  'labrador',
  'golden',
  'collie_rough',
  'white_swiss',
  'poodle',
  'cavalier',
  'bichon',
  'havanese',
  'coton',
  'maltese',
  'newfoundland',
  'bernese',
};

_F? _therapy(_C c) {
  const lim = ['Wymaga egzaminu i atestu psa oraz przewodnika.'];
  if (_therapyB.contains(c.id)) {
    return const _F(
      Fit.b,
      'Rasa zwykle łagodna i kontaktowa – o przydatności decyduje charakter konkretnego psa.',
      lim,
    );
  }
  return const _F(
    Fit.d,
    'Przydatność zależy przede wszystkim od charakteru konkretnego psa – wymagana ocena behawioralna.',
    lim,
  );
}

_F? _walks(_C c) {
  if (c.has(_T.brachy) || c.has(_T.brachyMild)) {
    return const _F(Fit.a, 'Codzienne spacery to podstawa ruchu – dopasuj je do pogody i oddechu psa.', [
      'Unikaj upału; wychodź rano i wieczorem.',
    ]);
  }
  return const _F(Fit.a, 'Codzienne spacery dopasowane do wieku i kondycji – podstawa ruchu każdego psa.');
}

_F? _swimming(_C c) {
  if (c.has(_T.brachy)) {
    return const _F(Fit.c, 'Krótka kufa i ciężki przód utrudniają utrzymanie głowy nad wodą – ryzyko zachłyśnięcia.', [
      'Tylko w kamizelce asekuracyjnej, płytko i pod pełnym nadzorem.',
    ]);
  }
  if (c.role == _R.retriever || c.role == _R.water) {
    return const _F(Fit.a, 'Dobry pływak – pływanie to świetny ruch bez obciążania stawów.');
  }
  if (c.has(_T.longBack) || c.has(_T.toy)) {
    return const _F(
      Fit.b,
      'Ruch odciążający stawy, ale krótkie łapy lub mała masa – pływaj w kamizelce, blisko brzegu.',
    );
  }
  return const _F(Fit.b, 'Dobry ruch bez obciążania stawów – przyzwyczajaj stopniowo, nie każdy pies lubi wodę.');
}

_F? _tricks(_C c) {
  if (c.has(_T.longBack)) {
    return const _F(Fit.b, 'Dobra praca umysłowa, ale bez sztuczek obciążających kręgosłup.', [
      'Bez stawania na tylnych łapach, „proszenia” i skoków.',
    ]);
  }
  if (c.has(_T.giant)) {
    return const _F(Fit.b, 'Dobra praca umysłowa, ale bez sztuczek obciążających stawy.', [
      'Bez stawania na tylnych łapach i skoków.',
    ]);
  }
  return const _F(Fit.a, 'Praca umysłowa o małym obciążeniu – odpowiednia dla każdego psa.');
}

final _rules = <String, _F? Function(_C)>{
  'canicross': _canicross,
  'bikejoring': (c) => _pulling(c, sled: false),
  'dogtrekking': _dogtrekking,
  'sled': (c) => _pulling(c, sled: true),
  'weightpull': _weightpull,
  'agility': _agility,
  'flyball': _flyball,
  'frisbee': _frisbee,
  'obedience': _obedience,
  'rally': _rally,
  'igp': _igp,
  'mondio': _mondio,
  'coursing': _coursing,
  'racing': _racing,
  'nosework': _nosework,
  'tracking': _tracking,
  'mantrailing': _mantrailing,
  'dummy': _dummy,
  'herding': _herding,
  'hunting': _hunting,
  'sar': _sar,
  'water_rescue': _waterRescue,
  'lgd': _lgd,
  'therapy': _therapy,
  'walks': _walks,
  'swimming': _swimming,
  'tricks': _tricks,
};

/// Corgi (pembroke i cardigan): ta sama budowa – krótkie kończyny, długi tułów.
const _corgi = <String, _F>{
  'canicross': _F(Fit.b, 'Aktywny pies pasterski, ale krótkie kończyny i długi tułów – tylko rekreacyjnie.', [
    'Krótkie dystanse w tempie kłusa, bez mocnego ciągnięcia.',
    _lHarness,
    'Utrzymuj szczupłą sylwetkę.',
  ]),
  'agility': _F(Fit.b, 'Zwinny i chętny do pracy – agility możliwe w niższych klasach wysokości.', [
    'Niższe skoki; ostrożnie ze slalomem i palisadą (obciążenie kręgosłupa).',
    _lJoints,
  ]),
};

/// Wyjątki dla konkretnych ras, gdy ogólna reguła nie oddaje rzeczywistości.
const _overrides = <String, Map<String, _F>>{
  'corgi_pembroke': _corgi,
  'corgi_cardigan': _corgi,
  'cavalier': {
    'canicross': _F(
      Fit.b,
      'Mały, aktywny pies, ale wysoka predyspozycja do choroby zastawki mitralnej (MVD) i skrócona kufa – tylko rekreacyjnie.',
      ['Krótkie dystanse w spokojnym tempie, bez upału.', _lCardio],
    ),
  },
  'chow': {
    'canicross': _F(
      Fit.c,
      'Proste kątowanie kończyn tylnych i bardzo gęsta szata – słaba tolerancja długiego biegu i ciepła.',
    ),
    'dogtrekking': _F(Fit.b, 'Spokojne marsze w chłodne dni, krótsze dystanse.', [_lCoat]),
    'agility': _F(Fit.c, 'Proste kątowanie kończyn tylnych zwiększa obciążenie stawów przy skokach.'),
  },
  'malamute': {
    'canicross': _F(Fit.b, 'Silny i wytrzymały, ale wolniejszy i cięższy niż psy wyścigowe – umiarkowane tempo.', [
      _lCoat,
    ]),
    'bikejoring': _F(Fit.b, 'Pies do ciężkich ładunków – lepiej znosi wolniejsze tempo niż sprint przed rowerem.', [
      _lCoat,
    ]),
  },
  'dalmatian': {
    'canicross': _F(Fit.a, 'Wytrzymały biegacz, historycznie towarzyszył powozom na długich trasach.', [_lHarness]),
  },
  'whippet': {
    'canicross': _F(Fit.b, 'Szybki i lekki – dobrze sprawdza się na krótkich dystansach.', [
      'Krótkie trasy, ochrona przed zimnem i urazami łap.',
    ]),
  },
  'italian_greyhound': {
    'agility': _F(Fit.b, 'Szybki i lekki, ale cienkie kości kończyn – ryzyko złamań przy skokach i upadkach.', [
      _lJumpLow,
    ]),
    'frisbee': _F(Fit.c, 'Cienkie kości kończyn – skoki po dysk i twarde lądowania grożą złamaniem.'),
  },
  'dachshund': {
    'dogtrekking': _F(
      Fit.b,
      'Wytrwały w terenie, ale długi kręgosłup – spokojne marsze, krótsze trasy, bez ciągnięcia.',
      [_lHarness],
    ),
  },
  'basset': {'tracking': _F(Fit.a, 'Jeden z najlepszych węchów wśród psów gończych – praca w wolnym tempie.')},
  'bloodhound': {
    'mantrailing': _F(Fit.a, 'Rasa wzorcowa dla mantrailingu – wyjątkowy węch i wytrwałość na śladzie.', [
      'Prowadź w szelkach na amortyzującej lince, bez szarpnięć.',
    ]),
  },
  'husky': {
    'weightpull': _F(
      Fit.d,
      'Pies zaprzęgowy do szybkiego biegu, nie do ciężkich ładunków – brak podstaw do ogólnej rekomendacji.',
    ),
  },
  'samoyed': {
    'weightpull': _F(Fit.d, 'Pies zaprzęgowy, ale nie do ciężkich ładunków – brak podstaw do ogólnej rekomendacji.'),
  },
};

/// Ograniczenia dopisywane automatycznie na podstawie cech rasy.
_F _adjust(_C c, Activity a, _F f) {
  var fit = f.fit;
  final limits = [...f.limits];
  final endurance = a.load == _L.running || a.load == _L.pulling || a.load == _L.sprint;
  if (fit == Fit.a || fit == Fit.b) {
    if (c.has(_T.cardiac) && (endurance || a.load == _L.strength) && !limits.contains(_lCardio)) {
      // Predyspozycja kardiologiczna: sport wytrzymałościowy tylko po badaniu serca.
      if (fit == Fit.a && (a.load == _L.running || a.load == _L.pulling)) fit = Fit.b;
      limits.add(_lCardio);
    }
    if (c.has(_T.heatSensitive) && endurance && !limits.contains(_lCoat)) limits.add(_lCoat);
    if (c.has(_T.patella) && a.load == _L.jumping && !limits.contains(_lPatella)) limits.add(_lPatella);
  }
  return _F(fit, f.reason, limits);
}

final _cache = <String, List<SportFit>>{};

/// Oceny aktywności dla rasy (pusta lista, gdy rasa nie ma danych).
List<SportFit> sportFitsFor(String? breedId) {
  if (breedId == null) return const [];
  return _cache.putIfAbsent(breedId, () {
    final i = breedInfos[breedId];
    final p = breedProfiles[breedId];
    if (i == null || p == null) return const [];
    final c = _C(breedId, i, p);
    final out = <SportFit>[];
    for (final a in activities) {
      final base = _overrides[breedId]?[a.id] ?? _rules[a.id]!(c);
      if (base == null) continue;
      final f = _adjust(c, a, base);
      final prep = a.load != _L.light && (f.fit == Fit.a || f.fit == Fit.b);
      out.add(SportFit(a, f.fit, f.reason, f.limits, prep));
    }
    return out;
  });
}

SportFit? sportFit(String? breedId, String activityId) {
  for (final f in sportFitsFor(breedId)) {
    if (f.activity.id == activityId) return f;
  }
  return null;
}

/// Identyfikatory wyjątków (do testów integralności).
Iterable<String> get sportOverrideBreedIds => _overrides.keys;
Iterable<String> get sportOverrideActivityIds => _overrides.values.expand((m) => m.keys);

// ---------------------------------------------------------------------------
// Wiek rozpoczęcia treningu
// ---------------------------------------------------------------------------

/// Klasa tempa wzrostu (od niej zależy dojrzałość układu kostno-stawowego).
enum GrowthClass {
  small('mała – wzrost kończy się zwykle ok. 9.–12. miesiąca'),
  medium('średnia – wzrost kończy się zwykle ok. 12.–15. miesiąca'),
  large('duża – wzrost kończy się zwykle ok. 15.–18. miesiąca'),
  giant('olbrzymia – wzrost trwa często do 18.–24. miesiąca');

  final String _label;
  String get label => tr(_label);
  const GrowthClass(this._label);
}

GrowthClass growthClassOf(BreedInfo i, BreedProfile? p) {
  final w = (i.weightMin + i.weightMax) / 2;
  if (p?.has(BreedTrait.giant) == true || w >= 45) return GrowthClass.giant;
  if (w >= 25) return GrowthClass.large;
  if (w >= 10) return GrowthClass.medium;
  return GrowthClass.small;
}

/// Orientacyjny wiek (miesiące) stopniowego wprowadzania obciążenia.
class StartAge {
  final ActivityLoad load;
  final int from, to;
  const StartAge(this.load, this.from, this.to);
}

const _startAges = <GrowthClass, Map<ActivityLoad, (int, int)>>{
  GrowthClass.small: {_L.running: (10, 12), _L.pulling: (12, 15), _L.jumping: (12, 15)},
  GrowthClass.medium: {_L.running: (12, 15), _L.pulling: (15, 18), _L.jumping: (15, 18)},
  GrowthClass.large: {_L.running: (15, 18), _L.pulling: (18, 24), _L.jumping: (18, 24)},
  GrowthClass.giant: {_L.running: (18, 24), _L.pulling: (24, 24), _L.jumping: (24, 24)},
};

StartAge startAgeFor(GrowthClass g, ActivityLoad load) {
  final key = load == _L.strength ? _L.pulling : (load == _L.sprint ? _L.jumping : load);
  final r = _startAges[g]![key] ?? (0, 0);
  return StartAge(load, r.$1, r.$2);
}

String startAgeLabel(StartAge s) => s.from == s.to
    ? tr('nie wcześniej niż ok. {0}. miesiąc', [s.from])
    : tr('nie wcześniej niż ok. {0}.–{1}. miesiąc', [s.from, s.to]);

/// Czy dla rasy jest choć jedna zalecana (A/B) aktywność danego obciążenia.
bool hasRecommended(String breedId, Set<ActivityLoad> loads) =>
    sportFitsFor(breedId).any((f) => loads.contains(f.activity.load) && (f.fit == Fit.a || f.fit == Fit.b));
