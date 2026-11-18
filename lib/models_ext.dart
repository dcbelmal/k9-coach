import 'package:material_ui/material_ui.dart';

import 'models.dart';
import 'l10n/l10n.dart';

DateTime? _d(dynamic v) => v == null ? null : DateTime.parse(v as String);
double? _n(dynamic v) => (v as num?)?.toDouble();

// ---------------------------------------------------------------------------
// Wystawy
// ---------------------------------------------------------------------------

enum ShowType {
  national('Krajowa'),
  international('Międzynarodowa (CACIB)'),
  club('Klubowa'),
  specialty('Specjalistyczna');

  final String _label;
  String get label => tr(_label);
  const ShowType(this._label);
}

enum ShowClass {
  baby('Baby'),
  puppy('Szczeniąt'),
  junior('Młodzieży'),
  intermediate('Pośrednia'),
  open('Otwarta'),
  working('Użytkowa'),
  champion('Championów'),
  veteran('Weteranów');

  final String _label;
  String get label => tr(_label);
  const ShowClass(this._label);
}

enum ShowStatus {
  planned('Planowana', Color(0xFF8E8E93)),
  entered('Zgłoszony', Color(0xFF5E8BFF)),
  paid('Opłacony', Color(0xFF30B0C7)),
  done('Odbyta', Color(0xFF34C759)),
  cancelled('Odwołana', Color(0xFFFF453A));

  final String _label;
  String get label => tr(_label);
  final Color color;
  const ShowStatus(this._label, this.color);
}

enum ShowTitle {
  jcwc('Młodzieżowe CWC', 'mCWC', Color(0xFF5E8BFF)), // dawny wpis, nie służy do championatów
  cwc('CWC / CAC', 'CWC', Color(0xFFF5821F)),
  cacib('CACIB', 'CACIB', Color(0xFFFFC53D)),
  resCacib('Res. CACIB', 'rCACIB', Color(0xFFC0C0C8)),
  zm('Zwycięzca Młodzieży', 'ZM', Color(0xFF30B0C7)),
  zw('Zwycięzca Weteran', 'ZW', Color(0xFF8E8E93)),
  zp('Zwycięzca Polski', 'ZwP', Color(0xFFFF453A)),
  zk('Zwycięzca Klubu', 'ZK', Color(0xFF34C759)),
  boj('Najlepszy Junior (BOJ)', 'BOJ', Color(0xFF30B0C7)),
  bob('Zwycięzca Rasy (BOB)', 'BOB', Color(0xFFFFB020)),
  bos('Najlepszy Przeciwnej Płci (BOS)', 'BOS', Color(0xFFBF5AF2)),
  bog('Lokata w grupie (BOG)', 'BOG', Color(0xFFFF6B3D)),
  bis('Lokata w BIS', 'BIS', Color(0xFFFF453A));

  final String _label;
  String get label => tr(_label);
  final String short;
  final Color color;
  const ShowTitle(this._label, this.short, this.color);
}

const showGrades = ['Doskonała', 'Bardzo dobra', 'Dobra', 'Dostateczna', 'Wybitnie obiecująca', 'Obiecująca', 'Dyskwalifikacja', 'Nie oceniono'];

class ShowEntry {
  final String id;
  String name;
  String place;
  DateTime date;
  ShowType type;
  ShowClass showClass;
  ShowStatus status;
  DateTime? entryDeadline;
  double? fee;
  String judge;
  String country;
  String? grade;
  int? placement;
  Set<ShowTitle> titles;
  String notes;

  ShowEntry({
    required this.id,
    required this.name,
    required this.date,
    this.place = '',
    this.type = ShowType.national,
    this.showClass = ShowClass.open,
    this.status = ShowStatus.planned,
    this.entryDeadline,
    this.fee,
    this.judge = '',
    this.country = 'Polska',
    this.grade,
    this.placement,
    Set<ShowTitle>? titles,
    this.notes = '',
  }) : titles = titles ?? {};

  bool get hasResult => grade != null || placement != null || titles.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'place': place,
        'date': date.toIso8601String(),
        'type': type.name,
        'class': showClass.name,
        'status': status.name,
        'deadline': entryDeadline?.toIso8601String(),
        'fee': fee,
        'judge': judge,
        'country': country,
        'grade': grade,
        'placement': placement,
        'titles': titles.map((e) => e.name).toList(),
        'notes': notes,
      };

  factory ShowEntry.fromJson(Map<String, dynamic> j) => ShowEntry(
        id: j['id'],
        name: j['name'] ?? '',
        place: j['place'] ?? '',
        date: DateTime.parse(j['date']),
        type: ShowType.values.byName(j['type'] ?? 'national'),
        showClass: ShowClass.values.byName(j['class'] ?? 'open'),
        status: ShowStatus.values.byName(j['status'] ?? 'planned'),
        entryDeadline: _d(j['deadline']),
        fee: _n(j['fee']),
        judge: j['judge'] ?? '',
        country: j['country'] ?? 'Polska',
        grade: j['grade'],
        placement: j['placement'],
        titles: {for (final t in (j['titles'] as List? ?? [])) ShowTitle.values.byName(t)},
        notes: j['notes'] ?? '',
      );
}

/// Championaty – zasady w lib/champ_rules.dart (wg ZKwP i FCI).
enum Championship {
  juniorPl('Champion Polski Młodzieży'),
  pl('Champion Polski'),
  grand('Grand Champion Polski'),
  veteran('Champion Polski Weteranów'),
  inter('Champion Międzynarodowy (C.I.B.)');

  final String _label;
  String get label => tr(_label);
  const Championship(this._label);
}

// ---------------------------------------------------------------------------
// Dokumenty
// ---------------------------------------------------------------------------

enum DocType {
  pedigree('Rodowód', Icons.account_tree_rounded),
  healthBook('Książeczka zdrowia', Icons.menu_book_rounded),
  passport('Paszport', Icons.badge_rounded),
  results('Wyniki badań', Icons.biotech_rounded),
  license('Licencja sportowa', Icons.workspace_premium_rounded),
  insurance('Ubezpieczenie', Icons.shield_rounded),
  other('Inny dokument', Icons.description_rounded);

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  const DocType(this._label, this.icon);
}

class DogDocument {
  final String id;
  DocType type;
  String title;
  String number;
  DateTime? issued;
  DateTime? expires;
  bool remind;
  String notes;
  List<String> images;

  DogDocument({
    required this.id,
    required this.type,
    required this.title,
    this.number = '',
    this.issued,
    this.expires,
    this.remind = true,
    this.notes = '',
    List<String>? images,
  }) : images = images ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'number': number,
        'issued': issued?.toIso8601String(),
        'expires': expires?.toIso8601String(),
        'remind': remind,
        'notes': notes,
        'images': images,
      };

  factory DogDocument.fromJson(Map<String, dynamic> j) => DogDocument(
        id: j['id'],
        type: DocType.values.byName(j['type']),
        title: j['title'] ?? '',
        number: j['number'] ?? '',
        issued: _d(j['issued']),
        expires: _d(j['expires']),
        remind: j['remind'] ?? true,
        notes: j['notes'] ?? '',
        images: [for (final i in (j['images'] as List? ?? [])) i as String],
      );
}

// ---------------------------------------------------------------------------
// Sprzęt
// ---------------------------------------------------------------------------

enum GearCategory {
  harness('Szelki', Icons.checkroom_rounded),
  leash('Smycz', Icons.linear_scale_rounded),
  bungee('Amortyzator', Icons.waves_rounded),
  bike('Rower', Icons.directions_bike_rounded),
  collar('Obroża', Icons.circle_outlined),
  booties('Ochraniacze łap', Icons.pets_rounded),
  other('Inne', Icons.inventory_2_rounded);

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  const GearCategory(this._label, this.icon);
}

class GearItem {
  final String id;
  GearCategory category;
  String name;
  String brand;
  DateTime? purchased;
  double? price;
  int? replaceAfterMonths;
  double? maxKm;
  Set<Discipline> disciplines;
  bool remind;
  bool retired;
  String notes;
  String? photo;

  GearItem({
    required this.id,
    required this.category,
    required this.name,
    this.brand = '',
    this.purchased,
    this.price,
    this.replaceAfterMonths,
    this.maxKm,
    Set<Discipline>? disciplines,
    this.remind = true,
    this.retired = false,
    this.notes = '',
    this.photo,
  }) : disciplines = disciplines ?? {};

  DateTime? get replaceDate => purchased == null || replaceAfterMonths == null
      ? null
      : DateTime(purchased!.year, purchased!.month + replaceAfterMonths!, purchased!.day);

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'name': name,
        'brand': brand,
        'purchased': purchased?.toIso8601String(),
        'price': price,
        'months': replaceAfterMonths,
        'maxKm': maxKm,
        'disciplines': disciplines.map((e) => e.name).toList(),
        'remind': remind,
        'retired': retired,
        'notes': notes,
        'photo': photo,
      };

  factory GearItem.fromJson(Map<String, dynamic> j) => GearItem(
        id: j['id'],
        category: GearCategory.values.byName(j['category']),
        name: j['name'] ?? '',
        brand: j['brand'] ?? '',
        purchased: _d(j['purchased']),
        price: _n(j['price']),
        replaceAfterMonths: j['months'],
        maxKm: _n(j['maxKm']),
        disciplines: {for (final d in (j['disciplines'] as List? ?? [])) Discipline.values.byName(d)},
        remind: j['remind'] ?? true,
        retired: j['retired'] ?? false,
        notes: j['notes'] ?? '',
        photo: j['photo'],
      );
}

// ---------------------------------------------------------------------------
// Cele
// ---------------------------------------------------------------------------

enum GoalType {
  exam('Egzamin sportowy', Icons.sports_rounded),
  title('Tytuł wystawowy', Icons.emoji_events_rounded),
  km('Kilometry', Icons.route_rounded),
  weight('Masa ciała', Icons.monitor_weight_rounded),
  custom('Własny cel', Icons.flag_rounded);

  final String _label;
  String get label => tr(_label);
  final IconData icon;
  const GoalType(this._label, this.icon);
}

const examPresets = ['BH-VT', 'IGP 1', 'IGP 2', 'IGP 3', 'IGP-FH', 'Obedience 1', 'Nosework NW1'];

class Goal {
  final String id;
  GoalType type;
  String title;
  Championship? championship;
  DateTime start;
  DateTime? deadline;
  double? target; // km lub kg
  double? startValue; // waga na starcie
  double manualProgress; // 0..1
  bool done;
  DateTime? doneDate;
  String notes;

  Goal({
    required this.id,
    required this.type,
    required this.title,
    required this.start,
    this.championship,
    this.deadline,
    this.target,
    this.startValue,
    this.manualProgress = 0,
    this.done = false,
    this.doneDate,
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'championship': championship?.name,
        'start': start.toIso8601String(),
        'deadline': deadline?.toIso8601String(),
        'target': target,
        'startValue': startValue,
        'manual': manualProgress,
        'done': done,
        'doneDate': doneDate?.toIso8601String(),
        'notes': notes,
      };

  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: j['id'],
        type: GoalType.values.byName(j['type']),
        title: j['title'] ?? '',
        championship: j['championship'] == null ? null : Championship.values.byName(j['championship']),
        start: DateTime.parse(j['start']),
        deadline: _d(j['deadline']),
        target: _n(j['target']),
        startValue: _n(j['startValue']),
        manualProgress: _n(j['manual']) ?? 0,
        done: j['done'] ?? false,
        doneDate: _d(j['doneDate']),
        notes: j['notes'] ?? '',
      );
}
