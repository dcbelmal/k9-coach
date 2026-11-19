import '../l10n/l10n.dart';

/// Pierwotna użytkowość rasy (do czego została wyhodowana).
enum BreedRole {
  herding('Pies pasterski (zaganiający)'),
  shepherdWorking('Pies pasterski i użytkowy (obrończy, służbowy)'),
  working('Pies użytkowy – stróżujący i obrończy'),
  pinscher('Pinczer / sznaucer – stróż i tępiciel gryzoni'),
  molosser('Molos – pies stróżujący i obrończy'),
  mountain('Szwajcarski pies pasterski – pędzenie bydła i praca pociągowa'),
  lgd('Pies pasterski stróżujący – samodzielna ochrona stad'),
  water('Pies wodny / ratowniczy'),
  wolfdog('Wilczak – rasa użytkowa w typie wilka'),
  terrier('Terier – pies myśliwski (norowiec) i tępiciel gryzoni'),
  bully('Terier typu bull'),
  dachshund('Pies myśliwski – norowiec i tropowiec'),
  sled('Pies zaprzęgowy'),
  spitz('Pies w typie szpica – stróżujący, myśliwski lub do towarzystwa'),
  primitive('Rasa pierwotna – pies myśliwski'),
  scentHound('Pies gończy / posokowiec – praca węchem'),
  carriage('Pies myśliwski i towarzyszący powozom (historycznie)'),
  ridgeback('Pies myśliwski do polowań na grubą zwierzynę'),
  pointer('Pies myśliwski – wyżeł'),
  retriever('Pies myśliwski – aporter (retriever)'),
  spaniel('Pies myśliwski – płochacz'),
  companion('Pies do towarzystwa'),
  sighthound('Chart – polowanie wzrokiem');

  final String _label;
  String get label => tr(_label);
  const BreedRole(this._label);
}

/// Cechy budowy i zdrowia ważne przy doborze aktywności.
enum BreedTrait {
  /// Budowa krótkoczaszkowa z ryzykiem BOAS.
  brachy,

  /// Skrócona kufa – gorsza termoregulacja przy wysiłku, BOAS rzadziej/łagodniej.
  brachyMild,

  /// Krótkie kończyny i długi kręgosłup (chondrodystrofia).
  longBack,

  /// Podwyższone ryzyko dyskopatii (IVDD).
  ivdd,

  /// Rasa olbrzymia (wolny rozwój, duże obciążenie stawów).
  giant,

  /// Masywna, ciężka budowa.
  heavy,

  /// Rasa miniaturowa (ok. < 5 kg).
  toy,

  /// Znana predyspozycja do chorób serca (np. DCM, MVD, ARVC, SAS).
  cardiac,

  /// Gęsta szata lub budowa utrudniająca oddawanie ciepła.
  heatSensitive,

  /// Głęboka klatka piersiowa – ryzyko skrętu żołądka (GDV).
  deepChest,

  /// Predyspozycja do zwichnięcia rzepki.
  patella,

  /// Wytrzymały biegacz.
  endurance,

  /// Sprinter (charty).
  sprinter,

  /// Wyjątkowo zwinny i szybki w pracy z przewodnikiem.
  agile,

  /// Rasa samodzielna, mniej nastawiona na współpracę.
  independent,
}

typedef _T = BreedTrait;
typedef _R = BreedRole;

/// Profil rasy: nazwa międzynarodowa (FCI, po angielsku), użytkowość i cechy.
class BreedProfile {
  final String intlName;
  final BreedRole role;
  final Set<BreedTrait> traits;
  const BreedProfile(this.intlName, this.role, [this.traits = const {}]);

  bool has(BreedTrait t) => traits.contains(t);

  /// Uwagi o budowie i zdrowiu wynikające z cech rasy.
  List<String> get bodyNotes => [
    if (has(_T.brachy)) tr('Budowa krótkoczaszkowa – ryzyko BOAS (duszność), słaba tolerancja upału i wysiłku.'),
    if (has(_T.brachyMild)) tr('Skrócona kufa – gorsza tolerancja upału przy wysiłku.'),
    if (has(_T.longBack)) tr('Krótkie kończyny i długi kręgosłup – podwyższone ryzyko dyskopatii (IVDD).'),
    if (has(_T.ivdd) && !has(_T.longBack)) tr('Predyspozycja do dyskopatii (IVDD) – unikaj skoków z wysokości.'),
    if (has(_T.giant)) tr('Rasa olbrzymia – wolny rozwój kości i stawów, krótsza średnia długość życia.'),
    if (has(_T.heavy) && !has(_T.giant)) tr('Masywna budowa – duże obciążenie stawów przy skokach i długim biegu.'),
    if (has(_T.toy)) tr('Bardzo mała rasa – delikatna budowa, uważaj na skoki z wysokości.'),
    if (has(_T.cardiac)) tr('Predyspozycja do chorób serca – badanie kardiologiczne przed intensywnym sportem.'),
    if (has(_T.deepChest))
      tr('Głęboka klatka piersiowa – ryzyko skrętu żołądka: bez intensywnego wysiłku ok. 1–2 h przed i po posiłku.'),
    if (has(_T.heatSensitive)) tr('Gęsta szata lub masywna budowa – trudniej oddaje ciepło; trenuj w chłodne dni.'),
    if (has(_T.patella)) tr('Predyspozycja do zwichnięcia rzepki – kontroluj stawy kolanowe.'),
    if (has(_T.sprinter)) tr('Mało tkanki tłuszczowej i cienka skóra – wrażliwość na zimno i otarcia.'),
  ];
}

/// Profile wszystkich ras z bazy (klucz = id rasy z breeds.dart).
/// Nazwy międzynarodowe według nomenklatury FCI (wersja angielska).
const breedProfiles = <String, BreedProfile>{
  // Grupa I
  'malinois': BreedProfile('Belgian Shepherd Dog (Malinois)', _R.shepherdWorking, {_T.endurance, _T.agile}),
  'groenendael': BreedProfile('Belgian Shepherd Dog (Groenendael)', _R.shepherdWorking, {_T.endurance, _T.agile}),
  'tervueren': BreedProfile('Belgian Shepherd Dog (Tervueren)', _R.shepherdWorking, {_T.endurance, _T.agile}),
  'laekenois': BreedProfile('Belgian Shepherd Dog (Laekenois)', _R.shepherdWorking, {_T.endurance}),
  'gsd': BreedProfile('German Shepherd Dog', _R.shepherdWorking),
  'dutch_shepherd': BreedProfile('Dutch Shepherd Dog', _R.shepherdWorking, {_T.endurance}),
  'border_collie': BreedProfile('Border Collie', _R.herding, {_T.endurance, _T.agile}),
  'aussie': BreedProfile('Australian Shepherd', _R.herding, {_T.agile}),
  'collie_rough': BreedProfile('Collie Rough', _R.herding),
  'sheltie': BreedProfile('Shetland Sheepdog', _R.herding, {_T.agile}),
  'pon': BreedProfile('Polish Lowland Sheepdog', _R.herding),
  'podhalanski': BreedProfile('Tatra Shepherd Dog', _R.lgd, {_T.heatSensitive}),
  'white_swiss': BreedProfile('White Swiss Shepherd Dog', _R.shepherdWorking),
  'corgi_pembroke': BreedProfile('Welsh Corgi (Pembroke)', _R.herding, {_T.longBack, _T.ivdd}),
  'corgi_cardigan': BreedProfile('Welsh Corgi (Cardigan)', _R.herding, {_T.longBack, _T.ivdd}),
  'kelpie': BreedProfile('Australian Kelpie', _R.herding, {_T.endurance, _T.agile}),
  'mudi': BreedProfile('Mudi', _R.herding, {_T.agile}),
  'pumi': BreedProfile('Pumi', _R.herding, {_T.agile}),
  'puli': BreedProfile('Puli', _R.herding, {_T.heatSensitive}),
  'briard': BreedProfile('Berger de Brie (Briard)', _R.herding),
  'beauceron': BreedProfile('Berger de Beauce (Beauceron)', _R.shepherdWorking),
  'cattle_dog': BreedProfile('Australian Cattle Dog', _R.herding, {_T.endurance}),
  'czech_wolfdog': BreedProfile('Czechoslovakian Wolfdog', _R.wolfdog, {_T.endurance, _T.independent}),
  'saarloos': BreedProfile('Saarloos Wolfhond', _R.wolfdog, {_T.independent}),
  // Grupa II
  'dobermann': BreedProfile('Dobermann', _R.working, {_T.endurance, _T.cardiac}),
  'rottweiler': BreedProfile('Rottweiler', _R.working),
  'boxer': BreedProfile('Boxer (German Boxer)', _R.working, {_T.brachyMild, _T.cardiac}),
  'giant_schnauzer': BreedProfile('Giant Schnauzer', _R.working),
  'standard_schnauzer': BreedProfile('Schnauzer', _R.pinscher),
  'mini_schnauzer': BreedProfile('Miniature Schnauzer', _R.pinscher),
  'pinscher': BreedProfile('German Pinscher', _R.pinscher),
  'min_pinscher': BreedProfile('Miniature Pinscher', _R.pinscher, {_T.patella}),
  'great_dane': BreedProfile('Great Dane', _R.molosser, {_T.giant, _T.heavy, _T.cardiac, _T.deepChest}),
  'cane_corso': BreedProfile('Cane Corso Italiano', _R.molosser),
  'bernese': BreedProfile('Bernese Mountain Dog', _R.mountain, {_T.heavy, _T.heatSensitive}),
  'newfoundland': BreedProfile('Newfoundland', _R.water, {_T.giant, _T.heavy, _T.heatSensitive, _T.cardiac}),
  'leonberger': BreedProfile('Leonberger', _R.water, {_T.giant, _T.heavy, _T.heatSensitive}),
  'st_bernard': BreedProfile('St. Bernard', _R.mountain, {_T.giant, _T.heavy, _T.heatSensitive, _T.deepChest}),
  'english_bulldog': BreedProfile('Bulldog', _R.molosser, {_T.brachy, _T.heavy}),
  'dogue_bordeaux': BreedProfile('Dogue de Bordeaux', _R.molosser, {_T.brachyMild, _T.giant, _T.heavy, _T.cardiac}),
  'mastiff': BreedProfile('Mastiff', _R.molosser, {_T.brachyMild, _T.giant, _T.heavy}),
  'bullmastiff': BreedProfile('Bullmastiff', _R.molosser, {_T.brachyMild, _T.heavy}),
  'shar_pei': BreedProfile('Shar Pei', _R.molosser, {_T.brachyMild}),
  'dogo_argentino': BreedProfile('Dogo Argentino', _R.molosser),
  'kangal': BreedProfile('Kangal Shepherd Dog', _R.lgd, {_T.giant}),
  'caucasian': BreedProfile('Caucasian Shepherd Dog', _R.lgd, {_T.giant, _T.heavy, _T.heatSensitive}),
  'central_asian': BreedProfile('Central Asia Shepherd Dog', _R.lgd, {_T.giant, _T.heavy}),
  'hovawart': BreedProfile('Hovawart', _R.working),
  'entlebucher': BreedProfile('Entlebuch Cattle Dog', _R.mountain),
  'appenzeller': BreedProfile('Appenzell Cattle Dog', _R.mountain),
  'swiss_mountain': BreedProfile('Great Swiss Mountain Dog', _R.mountain, {_T.giant, _T.heavy}),
  'black_russian': BreedProfile('Black Russian Terrier', _R.working),
  // Grupa III
  'amstaff': BreedProfile('American Staffordshire Terrier', _R.bully),
  'staffie': BreedProfile('Staffordshire Bull Terrier', _R.bully),
  'bull_terrier': BreedProfile('Bull Terrier', _R.bully, {_T.cardiac}),
  'jack_russell': BreedProfile('Jack Russell Terrier', _R.terrier, {_T.agile}),
  'parson_russell': BreedProfile('Parson Russell Terrier', _R.terrier, {_T.agile}),
  'yorkshire': BreedProfile('Yorkshire Terrier', _R.companion, {_T.toy, _T.patella}),
  'westie': BreedProfile('West Highland White Terrier', _R.terrier),
  'fox_terrier': BreedProfile('Fox Terrier (Smooth / Wire)', _R.terrier),
  'airedale': BreedProfile('Airedale Terrier', _R.terrier),
  'scottish_terrier': BreedProfile('Scottish Terrier', _R.terrier),
  'cairn': BreedProfile('Cairn Terrier', _R.terrier),
  'border_terrier': BreedProfile('Border Terrier', _R.terrier),
  'german_hunting_terrier': BreedProfile('German Hunting Terrier', _R.terrier),
  // Grupa IV
  'dachshund': BreedProfile('Dachshund', _R.dachshund, {_T.longBack, _T.ivdd}),
  // Grupa V
  'husky': BreedProfile('Siberian Husky', _R.sled, {_T.endurance, _T.heatSensitive}),
  'malamute': BreedProfile('Alaskan Malamute', _R.sled, {_T.heatSensitive}),
  'samoyed': BreedProfile('Samoyed', _R.sled, {_T.heatSensitive}),
  'akita': BreedProfile('Akita', _R.spitz, {_T.independent, _T.heatSensitive}),
  'american_akita': BreedProfile('American Akita', _R.spitz, {_T.independent, _T.heatSensitive}),
  'shiba': BreedProfile('Shiba', _R.spitz, {_T.independent, _T.patella}),
  'pomeranian': BreedProfile('German Spitz – Pomeranian (Zwergspitz)', _R.companion, {_T.toy, _T.patella}),
  'german_spitz': BreedProfile('German Spitz', _R.spitz, {_T.patella}),
  'keeshond': BreedProfile('German Spitz – Keeshond (Wolfspitz)', _R.spitz, {_T.heatSensitive}),
  'chow': BreedProfile('Chow Chow', _R.spitz, {_T.heatSensitive, _T.independent}),
  'basenji': BreedProfile('Basenji', _R.primitive, {_T.independent}),
  'eurasier': BreedProfile('Eurasier', _R.spitz),
  'pharaoh': BreedProfile('Pharaoh Hound', _R.primitive, {_T.sprinter}),
  'xolo': BreedProfile('Xoloitzcuintle', _R.primitive),
  // Grupa VI
  'beagle': BreedProfile('Beagle', _R.scentHound),
  'basset': BreedProfile('Basset Hound', _R.scentHound, {_T.longBack, _T.heavy}),
  'dalmatian': BreedProfile('Dalmatian', _R.carriage, {_T.endurance}),
  'rhodesian': BreedProfile('Rhodesian Ridgeback', _R.ridgeback, {_T.endurance}),
  'ogar': BreedProfile('Polish Hound', _R.scentHound, {_T.endurance}),
  'gonczy_polski': BreedProfile('Polish Hunting Dog', _R.scentHound, {_T.endurance}),
  'bloodhound': BreedProfile('Bloodhound', _R.scentHound, {_T.heavy, _T.deepChest}),
  'hanover_hound': BreedProfile('Hanoverian Scent Hound', _R.scentHound),
  'bavarian_hound': BreedProfile('Bavarian Mountain Scent Hound', _R.scentHound),
  // Grupa VII
  'gsp': BreedProfile('German Short-haired Pointing Dog', _R.pointer, {_T.endurance}),
  'gwp': BreedProfile('German Wire-haired Pointing Dog', _R.pointer, {_T.endurance}),
  'vizsla': BreedProfile('Hungarian Short-haired Pointer (Vizsla)', _R.pointer, {_T.endurance}),
  'wire_vizsla': BreedProfile('Hungarian Wire-haired Pointer', _R.pointer, {_T.endurance}),
  'weimaraner': BreedProfile('Weimaraner', _R.pointer, {_T.endurance, _T.deepChest}),
  'pointer': BreedProfile('English Pointer', _R.pointer, {_T.endurance}),
  'irish_setter': BreedProfile('Irish Red Setter', _R.pointer, {_T.endurance, _T.deepChest}),
  'english_setter': BreedProfile('English Setter', _R.pointer, {_T.endurance}),
  'gordon_setter': BreedProfile('Gordon Setter', _R.pointer),
  'brittany': BreedProfile('Brittany Spaniel (Epagneul Breton)', _R.pointer, {_T.endurance}),
  'wyzel_polski': BreedProfile('Polish Pointer (Wyżeł polski)', _R.pointer),
  'munsterlander': BreedProfile('Münsterländer (Large / Small)', _R.pointer),
  // Grupa VIII
  'labrador': BreedProfile('Labrador Retriever', _R.retriever),
  'golden': BreedProfile('Golden Retriever', _R.retriever),
  'flatcoat': BreedProfile('Flat Coated Retriever', _R.retriever),
  'toller': BreedProfile('Nova Scotia Duck Tolling Retriever', _R.retriever, {_T.agile}),
  'chesapeake': BreedProfile('Chesapeake Bay Retriever', _R.retriever),
  'cocker': BreedProfile('English Cocker Spaniel', _R.spaniel),
  'american_cocker': BreedProfile('American Cocker Spaniel', _R.spaniel),
  'springer': BreedProfile('English Springer Spaniel', _R.spaniel, {_T.endurance}),
  'wachtel': BreedProfile('German Spaniel (Wachtelhund)', _R.spaniel),
  'lagotto': BreedProfile('Romagna Water Dog (Lagotto Romagnolo)', _R.water),
  'portuguese_water': BreedProfile('Portuguese Water Dog', _R.water, {_T.cardiac}),
  // Grupa IX
  'poodle': BreedProfile('Poodle', _R.companion, {_T.agile}),
  'chihuahua': BreedProfile('Chihuahua', _R.companion, {_T.toy, _T.patella, _T.cardiac}),
  'maltese': BreedProfile('Maltese', _R.companion, {_T.toy, _T.patella}),
  'shih_tzu': BreedProfile('Shih Tzu', _R.companion, {_T.brachy, _T.ivdd}),
  'french_bulldog': BreedProfile('French Bulldog', _R.companion, {_T.brachy, _T.ivdd}),
  'pug': BreedProfile('Pug', _R.companion, {_T.brachy}),
  'cavalier': BreedProfile('Cavalier King Charles Spaniel', _R.companion, {_T.brachyMild, _T.cardiac}),
  'papillon': BreedProfile('Continental Toy Spaniel (Papillon)', _R.companion, {_T.agile, _T.patella}),
  'havanese': BreedProfile('Havanese', _R.companion, {_T.patella}),
  'bichon': BreedProfile('Bichon Frise', _R.companion, {_T.patella}),
  'boston': BreedProfile('Boston Terrier', _R.companion, {_T.brachyMild}),
  'lhasa': BreedProfile('Lhasa Apso', _R.companion),
  'pekingese': BreedProfile('Pekingese', _R.companion, {_T.brachy, _T.ivdd}),
  'coton': BreedProfile('Coton de Tuléar', _R.companion),
  'prague_ratter': BreedProfile('Prague Ratter (Pražský krysařík)', _R.companion, {_T.toy, _T.patella}),
  // Grupa X
  'greyhound': BreedProfile('Greyhound', _R.sighthound, {_T.sprinter}),
  'whippet': BreedProfile('Whippet', _R.sighthound, {_T.sprinter}),
  'saluki': BreedProfile('Saluki', _R.sighthound, {_T.sprinter, _T.endurance}),
  'borzoi': BreedProfile('Borzoi – Russian Hunting Sighthound', _R.sighthound, {_T.sprinter, _T.deepChest}),
  'afghan': BreedProfile('Afghan Hound', _R.sighthound, {_T.sprinter}),
  'chart_polski': BreedProfile('Polish Greyhound (Chart Polski)', _R.sighthound, {_T.sprinter}),
  'italian_greyhound': BreedProfile('Italian Sighthound', _R.sighthound, {_T.sprinter}),
  'irish_wolfhound': BreedProfile('Irish Wolfhound', _R.sighthound, {_T.sprinter, _T.giant, _T.cardiac, _T.deepChest}),
};

BreedProfile? breedProfileFor(String? id) => id == null ? null : breedProfiles[id];
