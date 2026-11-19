import '../l10n/l10n.dart';
import 'breed_profile.dart';

/// Lokalna baza ras: nazwa polska i grupa FCI (do wyszukiwarki).
/// Szczegóły: breed_info.dart (wymiary, badania), breed_profile.dart
/// (nazwa międzynarodowa, użytkowość, budowa), breed_sports.dart (sporty).
class Breed {
  final String id;
  final String namePl; // nazwa polska (klucz tłumaczenia)
  final int fciGroup;
  final List<String> aliases;
  const Breed(this.id, this.namePl, this.fciGroup, [this.aliases = const []]);

  /// Nazwa w języku aplikacji.
  String get name => tr(namePl);

  bool matches(String q) {
    final n = _fold(q);
    if (n.isEmpty) return true;
    return _fold(name).contains(n) ||
        _fold(namePl).contains(n) ||
        _fold(breedProfiles[id]?.intlName ?? '').contains(n) ||
        aliases.any((a) => _fold(a).contains(n));
  }
}

String _fold(String s) {
  const from = 'ąćęłńóśźż';
  const to = 'acelnoszz';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().trim().split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString();
}

const mixedBreedLabel = 'Mieszaniec';
String get mixedBreedName => tr(mixedBreedLabel);

/// Dawne identyfikatory ras (zapisane w starszych profilach) → aktualne.
/// „Owczarek tatrzański” to ta sama rasa co polski owczarek podhalański
/// (FCI nr 252, ang. Tatra Shepherd Dog) – był w bazie podwójnie.
const legacyBreedIds = <String, String>{'tatra': 'podhalanski'};

String? canonicalBreedId(String? id) => id == null ? null : (legacyBreedIds[id] ?? id);

Breed? breedById(String? id) {
  final cid = canonicalBreedId(id);
  if (cid == null) return null;
  for (final b in breeds) {
    if (b.id == cid) return b;
  }
  return null;
}

/// Dopasowanie po nazwie (dla starszych profili wpisanych ręcznie).
Breed? breedByName(String name) {
  final n = _fold(name);
  if (n.isEmpty) return null;
  for (final b in breeds) {
    if (_fold(b.name) == n || _fold(b.namePl) == n || b.aliases.any((a) => _fold(a) == n)) return b;
  }
  return null;
}

List<Breed> searchBreeds(String q) {
  final list = breeds.where((b) => b.matches(q)).toList();
  final n = _fold(q);
  list.sort((a, b) {
    final sa = _fold(a.name).startsWith(n) ? 0 : 1, sb = _fold(b.name).startsWith(n) ? 0 : 1;
    return sa != sb ? sa - sb : a.name.compareTo(b.name);
  });
  return list;
}

const breeds = <Breed>[
  // Grupa I
  Breed('malinois', 'Owczarek belgijski Malinois', 1, ['malinois', 'mechelaar']),
  Breed('groenendael', 'Owczarek belgijski Groenendael', 1, ['groenendael']),
  Breed('tervueren', 'Owczarek belgijski Tervueren', 1, ['tervueren']),
  Breed('laekenois', 'Owczarek belgijski Laekenois', 1, ['laekenois']),
  Breed('gsd', 'Owczarek niemiecki', 1, ['owczarek niemiecki długowłosy', 'german shepherd', 'onek']),
  Breed('dutch_shepherd', 'Owczarek holenderski', 1, ['hollandse herder', 'dutch shepherd']),
  Breed('border_collie', 'Border collie', 1, ['border']),
  Breed('aussie', 'Owczarek australijski', 1, ['australian shepherd', 'aussie']),
  Breed('collie_rough', 'Owczarek szkocki długowłosy', 1, ['collie', 'rough collie']),
  Breed('sheltie', 'Owczarek szetlandzki', 1, ['sheltie', 'shetland']),
  Breed('pon', 'Polski owczarek nizinny', 1, ['pon']),
  Breed('podhalanski', 'Polski owczarek podhalański', 1, [
    'podhalan',
    'owczarek podhalański',
    'owczarek tatrzański',
    'polski owczarek tatrzański',
    'tatra shepherd dog',
  ]),
  Breed('white_swiss', 'Biały owczarek szwajcarski', 1, ['bos', 'berger blanc suisse']),
  Breed('corgi_pembroke', 'Welsh corgi pembroke', 1, ['corgi']),
  Breed('kelpie', 'Australijski kelpie', 1, ['kelpie']),
  Breed('mudi', 'Mudi', 1),
  Breed('pumi', 'Pumi', 1),
  Breed('puli', 'Puli', 1),
  Breed('briard', 'Owczarek francuski briard', 1, ['briard']),
  Breed('beauceron', 'Owczarek francuski beauceron', 1, ['beauceron']),
  Breed('cattle_dog', 'Australijski pies pasterski', 1, ['australian cattle dog', 'heeler']),
  // Grupa II
  Breed('dobermann', 'Doberman', 2, ['dobermann']),
  Breed('rottweiler', 'Rottweiler', 2),
  Breed('boxer', 'Bokser', 2, ['boxer']),
  Breed('giant_schnauzer', 'Sznaucer olbrzym', 2, ['sznaucer']),
  Breed('standard_schnauzer', 'Sznaucer średni', 2),
  Breed('mini_schnauzer', 'Sznaucer miniaturowy', 2),
  Breed('pinscher', 'Pinczer średni', 2, ['pinczer']),
  Breed('min_pinscher', 'Pinczer miniaturowy', 2, ['ratlerek']),
  Breed('great_dane', 'Dog niemiecki', 2, ['great dane']),
  Breed('cane_corso', 'Cane corso italiano', 2, ['cane corso']),
  Breed('bernese', 'Berneński pies pasterski', 2, ['berneńczyk', 'berner']),
  Breed('newfoundland', 'Nowofundland', 2),
  Breed('leonberger', 'Leonberger', 2),
  Breed('st_bernard', 'Bernardyn', 2),
  Breed('english_bulldog', 'Buldog angielski', 2),
  Breed('dogue_bordeaux', 'Dog z Bordeaux', 2),
  Breed('mastiff', 'Mastif angielski', 2, ['mastif']),
  Breed('bullmastiff', 'Bullmastif', 2),
  Breed('shar_pei', 'Shar pei', 2),
  Breed('dogo_argentino', 'Dog argentyński', 2, ['dogo argentino']),
  Breed('kangal', 'Owczarek anatolijski', 2, ['kangal']),
  Breed('caucasian', 'Owczarek kaukaski', 2),
  Breed('central_asian', 'Owczarek środkowoazjatycki', 2, ['alabaj']),
  Breed('hovawart', 'Hovawart', 2),
  Breed('entlebucher', 'Entlebucher', 2),
  Breed('appenzeller', 'Appenzeller', 2),
  Breed('swiss_mountain', 'Duży szwajcarski pies pasterski', 2),
  Breed('black_russian', 'Czarny terier rosyjski', 2),
  // Grupa III
  Breed('amstaff', 'Amerykański staffordshire terier', 3, ['amstaff']),
  Breed('staffie', 'Staffordshire bulterier', 3, ['staffik', 'staffie']),
  Breed('bull_terrier', 'Bulterier', 3, ['bull terier']),
  Breed('jack_russell', 'Jack Russell terier', 3, ['jack russell']),
  Breed('parson_russell', 'Parson Russell terier', 3),
  Breed('yorkshire', 'Yorkshire terier', 3, ['york']),
  Breed('westie', 'West highland white terier', 3, ['westie']),
  Breed('fox_terrier', 'Foksterier', 3, ['fox terier']),
  Breed('airedale', 'Airedale terier', 3),
  Breed('scottish_terrier', 'Szkocki terier', 3),
  Breed('cairn', 'Cairn terier', 3),
  Breed('border_terrier', 'Border terier', 3),
  Breed('german_hunting_terrier', 'Niemiecki terier myśliwski', 3, ['jagdterier']),
  // Grupa IV
  Breed('dachshund', 'Jamnik', 4, ['jamnik standardowy', 'jamnik miniaturowy', 'jamnik króliczy']),
  // Grupa V
  Breed('husky', 'Siberian husky', 5, ['husky']),
  Breed('malamute', 'Alaskan malamute', 5, ['malamut']),
  Breed('samoyed', 'Samojed', 5),
  Breed('akita', 'Akita', 5, ['akita inu']),
  Breed('american_akita', 'Akita amerykańska', 5),
  Breed('shiba', 'Shiba', 5, ['shiba inu']),
  Breed('pomeranian', 'Szpic miniaturowy (pomeranian)', 5, ['pomeranian', 'szpic']),
  Breed('german_spitz', 'Szpic niemiecki', 5),
  Breed('keeshond', 'Szpic wilczy (keeshond)', 5),
  Breed('chow', 'Chow chow', 5),
  Breed('basenji', 'Basenji', 5),
  Breed('czech_wolfdog', 'Czechosłowacki wilczak', 1, ['wilczak']),
  Breed('saarloos', 'Wilczak Saarlosa', 1),
  Breed('eurasier', 'Eurasier', 5),
  Breed('pharaoh', 'Pies faraona', 5),
  Breed('xolo', 'Meksykański pies bezwłosy', 5, ['xoloitzcuintle']),
  // Grupa VI
  Breed('beagle', 'Beagle', 6),
  Breed('basset', 'Basset hound', 6),
  Breed('dalmatian', 'Dalmatyńczyk', 6),
  Breed('rhodesian', 'Rhodesian ridgeback', 6, ['ridgeback']),
  Breed('ogar', 'Ogar polski', 6),
  Breed('gonczy_polski', 'Gończy polski', 6),
  Breed('bloodhound', 'Bloodhound', 6, ['posokowiec św. huberta']),
  Breed('hanover_hound', 'Posokowiec hanowerski', 6),
  Breed('bavarian_hound', 'Posokowiec bawarski', 6),
  // Grupa VII
  Breed('gsp', 'Wyżeł niemiecki krótkowłosy', 7, ['kurzhaar']),
  Breed('gwp', 'Wyżeł niemiecki szorstkowłosy', 7, ['drahthaar']),
  Breed('vizsla', 'Wyżeł węgierski krótkowłosy', 7, ['vizsla', 'wyżeł węgierski']),
  Breed('wire_vizsla', 'Wyżeł węgierski szorstkowłosy', 7),
  Breed('weimaraner', 'Wyżeł weimarski', 7, ['weimaraner']),
  Breed('pointer', 'Pointer', 7),
  Breed('irish_setter', 'Seter irlandzki', 7),
  Breed('english_setter', 'Seter angielski', 7),
  Breed('gordon_setter', 'Seter szkocki', 7, ['gordon']),
  Breed('brittany', 'Epagneul breton', 7, ['breton']),
  Breed('wyzel_polski', 'Wyżeł polski', 7),
  Breed('munsterlander', 'Munsterlender', 7),
  // Grupa VIII
  Breed('labrador', 'Labrador retriever', 8, ['labrador']),
  Breed('golden', 'Golden retriever', 8, ['golden']),
  Breed('flatcoat', 'Flat coated retriever', 8, ['flat']),
  Breed('toller', 'Nova scotia duck tolling retriever', 8, ['toller']),
  Breed('chesapeake', 'Chesapeake bay retriever', 8),
  Breed('cocker', 'Cocker spaniel angielski', 8, ['cocker']),
  Breed('american_cocker', 'Cocker spaniel amerykański', 8),
  Breed('springer', 'Springer spaniel angielski', 8, ['springer']),
  Breed('wachtel', 'Płochacz niemiecki', 8, ['wachtelhund']),
  Breed('lagotto', 'Lagotto romagnolo', 8),
  Breed('portuguese_water', 'Portugalski pies dowodny', 8),
  // Grupa IX
  Breed('poodle', 'Pudel', 9, ['pudel duży', 'pudel średni', 'pudel miniaturowy', 'pudel toy']),
  Breed('chihuahua', 'Chihuahua', 9),
  Breed('maltese', 'Maltańczyk', 9),
  Breed('shih_tzu', 'Shih tzu', 9),
  Breed('french_bulldog', 'Buldog francuski', 9, ['frenchie']),
  Breed('pug', 'Mops', 9),
  Breed('cavalier', 'Cavalier King Charles spaniel', 9, ['cavalier']),
  Breed('papillon', 'Papillon', 9, ['kontynentalny spaniel miniaturowy']),
  Breed('havanese', 'Hawańczyk', 9, ['havanese']),
  Breed('bichon', 'Bichon frise', 9),
  Breed('boston', 'Boston terier', 9),
  Breed('lhasa', 'Lhasa apso', 9),
  Breed('pekingese', 'Pekińczyk', 9),
  Breed('coton', 'Coton de Tulear', 9),
  Breed('prague_ratter', 'Pražský krysařík', 9, ['krysarik']),
  // Grupa X
  Breed('greyhound', 'Greyhound', 10),
  Breed('whippet', 'Whippet', 10),
  Breed('saluki', 'Saluki', 10),
  Breed('borzoi', 'Borzoj', 10, ['chart rosyjski']),
  Breed('afghan', 'Chart afgański', 10),
  Breed('chart_polski', 'Chart polski', 10),
  Breed('italian_greyhound', 'Charcik włoski', 10),
  Breed('irish_wolfhound', 'Wilczarz irlandzki', 10),
];
