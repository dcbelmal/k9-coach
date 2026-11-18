import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../models_ext.dart';
import '../shows/countries.dart';
import '../shows/fci_shows.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../zkwp.dart';
import '../l10n/l10n.dart';

final _s = AppStore.instance;

/// Terminarz wystaw: kraj zamieszkania (+ kraje sąsiednie) z filtrem po grupie FCI psa.
/// Polska – pełny terminarz ZKwP, pozostałe kraje – wystawy CACIB z kalendarza FCI.
class ZkwpCalendar extends StatefulWidget {
  const ZkwpCalendar({super.key});
  @override
  State<ZkwpCalendar> createState() => _ZkwpCalendarState();
}

class _ZkwpCalendarState extends State<ZkwpCalendar> {
  late int year = DateTime.now().month >= 11 ? DateTime.now().year + 1 : DateTime.now().year;
  bool mine = true;
  bool cacibOnly = false;
  bool loading = true;
  String? error;
  DateTime? fetchedAt;
  List<ZkwpShow> shows = [];
  String home = 'PL';
  bool withNeighbours = true;
  /// null = wszystkie kraje, inaczej kod kraju.
  String? onlyCountry;
  /// Kraje, z których udało się coś pobrać lub które sprawdzono.
  List<String> loadedCountries = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final (c, nb) = await HomeCountry.load();
    home = c;
    withNeighbours = nb;
    await _load();
  }

  List<String> get _countries => [
        home,
        if (withNeighbours) ...[for (final n in neighboursOf(home)) if (n.inFci) n.code],
      ];

  Future<void> _load({bool refresh = false}) async {
    setState(() => loading = true);
    final codes = _countries;
    final results = await Future.wait([
      for (final c in codes)
        c == 'PL' ? ZkwpService.load(year, refresh: refresh) : FciService.load(c, refresh: refresh),
    ]);
    if (!mounted) return;
    final all = <ZkwpShow>[];
    final errs = <String>[];
    DateTime? at;
    for (final (i, (list, got, err)) in results.indexed) {
      all.addAll(list.where((z) => z.date.year == year));
      if (err != null) errs.add('${countryByCode(codes[i]).flag} $err');
      if (got != null && (at == null || got.isBefore(at))) at = got;
    }
    all.sort((a, b) => a.date.compareTo(b.date));
    setState(() {
      shows = all;
      fetchedAt = at;
      error = errs.isEmpty ? null : errs.join('\n');
      loadedCountries = codes;
      if (onlyCountry != null && !codes.contains(onlyCountry)) onlyCountry = null;
      loading = false;
    });
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(12, 0, 12, 20 + MediaQuery.viewPaddingOf(c).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: SheetTitle(tr('Kraj zamieszkania'))),
          for (final k in showCountries.where((e) => e.inFci))
            ListTile(
              title: Text(k.label),
              subtitle: (countryNeighbours[k.code] ?? const []).isEmpty
                  ? null
                  : Text(tr('Sąsiedzi: {0}', [neighboursOf(k.code).map((n) => n.flag).join(' ')]),
                      style: const TextStyle(color: K9.muted, fontSize: 12.5)),
              trailing: k.code == home ? const Icon(Icons.check_rounded, color: K9.orange) : null,
              onTap: () => Navigator.pop(c, k.code),
            ),
        ]),
      ),
    );
    if (picked == null || picked == home) return;
    setState(() {
      home = picked;
      onlyCountry = null;
    });
    await HomeCountry.save(home, withNeighbours);
    await _load();
  }

  Future<void> _toggleNeighbours() async {
    setState(() {
      withNeighbours = !withNeighbours;
      onlyCountry = null;
    });
    await HomeCountry.save(home, withNeighbours);
    await _load();
  }

  /// Miejsce zapisywane w "Moich wystawach": dla wystaw z zagranicy z nazwą kraju.
  String _placeOf(ZkwpShow z) => z.fromFci ? '${z.city}, ${countryByCode(z.country).localName}' : z.city;

  ShowEntry? _added(ZkwpShow z) => _s.shows
      .where((e) => sameDay(e.date, z.date) && e.place.toLowerCase() == _placeOf(z).toLowerCase() && e.type == z.type)
      .firstOrNull;

  Future<void> _add(ZkwpShow z) async {
    final e = ShowEntry(
      id: newId(),
      name: z.title,
      place: _placeOf(z),
      date: DateTime(z.date.year, z.date.month, z.date.day, 9),
      type: z.type,
      showClass: _defaultClass(),
      notes: z.fromFci
          ? tr('Z kalendarza FCI: {0}, {1} – wystawa międzynarodowa CACIB', [countryByCode(z.country).label, z.city])
          : tr('Z terminarza ZKwP: {0} – {1}', [z.place, z.description]),
    );
    if (!context.mounted) return;
    if (!await saveGuarded(context, () => _s.upsertShow(e))) return;
    if (mounted) toast(context, tr('Dodano do moich wystaw. Uzupełnij termin zgłoszeń, a przypomnę o nim.'));
  }

  ShowClass _defaultClass() {
    final b = _s.dog?.birthDate;
    if (b == null) return ShowClass.open;
    final m = (DateTime.now().year - b.year) * 12 + DateTime.now().month - b.month;
    if (m < 9) return ShowClass.puppy;
    if (m < 18) return ShowClass.junior;
    if (m < 24) return ShowClass.intermediate;
    if (m >= 96) return ShowClass.veteran;
    return ShowClass.open;
  }

  @override
  Widget build(BuildContext context) {
    final g = _s.dog?.fciGroup;
    final today = dayOnly(DateTime.now());
    final list = shows
        .where((z) => !(z.endDate ?? z.date).isBefore(today))
        .where((z) => !mine || z.matches(g))
        .where((z) => !cacibOnly || z.type == ShowType.international)
        .where((z) => onlyCountry == null || z.country == onlyCountry)
        .toList();
    final countriesWithShows = [
      for (final c in loadedCountries)
        if (shows.any((z) => z.country == c && !(z.endDate ?? z.date).isBefore(today))) c
    ];
    final byMonth = <int, List<ZkwpShow>>{};
    for (final z in list) {
      byMonth.putIfAbsent(z.date.month, () => []).add(z);
    }

    Widget chip(String label, bool sel, VoidCallback on) => ChoiceChip(
          label: Text(label),
          selected: sel,
          showCheckmark: false,
          selectedColor: K9.orange,
          backgroundColor: K9.cardHi,
          side: BorderSide.none,
          labelStyle: TextStyle(color: sel ? Colors.black : K9.text, fontWeight: FontWeight.w600, fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (_) => setState(on),
        );

    final now = DateTime.now().year;
    return RefreshIndicator(
      color: K9.orange,
      onRefresh: () => _load(refresh: true),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 100), children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ActionChip(
            avatar: const Icon(Icons.home_rounded, size: 18, color: K9.orange),
            label: Text(tr('Mieszkam: {0}', [countryByCode(home).label])),
            backgroundColor: K9.cardHi,
            side: BorderSide.none,
            labelStyle: const TextStyle(color: K9.text, fontWeight: FontWeight.w600, fontSize: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onPressed: _pickCountry,
          ),
          if (neighboursOf(home).isNotEmpty) chip(tr('+ kraje sąsiednie'), withNeighbours, () {
            _toggleNeighbours();
          }),
        ]),
        if (withNeighbours && countriesWithShows.length > 1) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              chip(tr('Wszystkie kraje'), onlyCountry == null, () => onlyCountry = null),
              for (final c in countriesWithShows) ...[
                const SizedBox(width: 8),
                chip(countryByCode(c).flag, onlyCountry == c, () => onlyCountry = onlyCountry == c ? null : c),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final y in [now, now + 1])
            chip('$y', year == y, () {
              year = y;
              _load();
            }),
          const SizedBox(width: 4),
          chip(g == null ? tr('Dla mojego psa') : tr('Dla mojego psa (gr. {0})', [romanNumerals[g - 1]]), mine, () => mine = true),
          chip(tr('Wszystkie'), !mine, () => mine = false),
          chip(tr('Tylko CACIB'), cacibOnly, () => cacibOnly = !cacibOnly),
        ]),
        if (mine && g == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr('Ustaw grupę FCI w profilu psa, aby widzieć też wystawy klubowe i specjalistyczne swojej grupy.'),
                style: TextStyle(color: K9.yellow.withValues(alpha: 0.9), fontSize: 12.5)),
          ),
        gap12,
        if (loading)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator(color: K9.orange)),
          )
        else ...[
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: K9Card(
                color: K9.cardHi,
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.wifi_off_rounded, color: K9.yellow),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        shows.isEmpty
                            ? tr('{0}\nSprawdź internet i pociągnij listę w dół.', [error])
                            : tr('{0}\nPokazuję to, co udało się pobrać lub zapisaną wersję.', [error]),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
            ),
          if (!loading && shows.isNotEmpty && list.isEmpty)
            K9Card(child: Text(tr('Brak nadchodzących wystaw dla tego filtra.'), style: TextStyle(color: K9.muted))),
          for (final m in byMonth.keys) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
              child: Text(fmtMonthYear(DateTime(year, m)),
                  style: const TextStyle(color: K9.muted, fontWeight: FontWeight.w700)),
            ),
            for (final (i, z) in byMonth[m]!.indexed)
              FadeSlideIn(
                  index: i < 8 ? i : 0,
                  child: _ZCard(z: z, foreign: z.country != home, added: _added(z), onAdd: () => _add(z))),
          ],
          if (fetchedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                  tr('Źródła: {0}{1}pobrano {2}, {3}. Grupy przypisuję według rodzaju wystawy: międzynarodowe i krajowe są dla wszystkich ras, klubowe i specjalistyczne według nazwy. Sprawdź szczegóły u organizatora.{4}', [loadedCountries.contains('PL') ? tr('Polska – terminarz ZKwP (zkwp.pl); ') : '', loadedCountries.any((c) => c != 'PL') ? tr('inne kraje – kalendarz wystaw międzynarodowych FCI (fci.be), tylko CACIB; ') : '', fmtDate(fetchedAt!), fmtTime(fetchedAt!), withNeighbours && neighboursOf(home).any((n) => !n.inFci) ? tr(' {0}: brak wystaw w kalendarzu FCI.', [neighboursOf(home).where((n) => !n.inFci).map((n) => n.label).join(', ')]) : '']),
                  style: const TextStyle(color: K9.faint, fontSize: 11.5)),
            ),
        ],
      ]),
    );
  }
}

class _ZCard extends StatelessWidget {
  final ZkwpShow z;
  final bool foreign;
  final ShowEntry? added;
  final VoidCallback onAdd;
  const _ZCard({required this.z, required this.foreign, required this.added, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final intl = z.type == ShowType.international;
    final days = z.endDate == null ? '${z.date.day}' : '${z.date.day}–${z.endDate!.day}';
    final c = countryByCode(z.country);
    final placeText = z.fromFci || foreign ? '${c.flag} ${z.fromFci ? z.city : z.place}, ${c.localName}' : z.place;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: K9Card(
        padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
        child: Row(children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: (intl ? K9.yellow : K9.orange).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              FittedBox(
                child: Text(days,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: intl ? K9.yellow : K9.orange)),
              ),
              Text(fmtWeekday(z.date), style: TextStyle(fontSize: 11, color: intl ? K9.yellow : K9.orange)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(placeText, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(tr(z.description), style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13)),
              const SizedBox(height: 6),
              Text(z.groupsLabel, style: const TextStyle(color: K9.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          added != null
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.check_circle_rounded, color: K9.green),
                )
              : IconButton(
                  tooltip: tr('Dodaj do moich wystaw'),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline_rounded, color: K9.orange, size: 28),
                ),
        ]),
      ),
    );
  }
}
