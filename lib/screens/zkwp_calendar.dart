import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../models_ext.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../zkwp.dart';

final _s = AppStore.instance;

const _monthNames = [
  'Styczeń', 'Luty', 'Marzec', 'Kwiecień', 'Maj', 'Czerwiec',
  'Lipiec', 'Sierpień', 'Wrzesień', 'Październik', 'Listopad', 'Grudzień',
];

/// Terminarz wystaw ZKwP z filtrem po grupie FCI psa.
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => loading = true);
    final (list, at, err) = await ZkwpService.load(year, refresh: refresh);
    if (!mounted) return;
    setState(() {
      shows = list;
      fetchedAt = at;
      error = err;
      loading = false;
    });
  }

  ShowEntry? _added(ZkwpShow z) => _s.shows
      .where((e) => sameDay(e.date, z.date) && e.place.toLowerCase() == z.city.toLowerCase() && e.type == z.type)
      .firstOrNull;

  Future<void> _add(ZkwpShow z) async {
    final e = ShowEntry(
      id: newId(),
      name: z.title,
      place: z.city,
      date: DateTime(z.date.year, z.date.month, z.date.day, 9),
      type: z.type,
      showClass: _defaultClass(),
      notes: 'Z terminarza ZKwP: ${z.place} – ${z.description}',
    );
    await _s.upsertShow(e);
    if (mounted) toast(context, 'Dodano do moich wystaw. Uzupełnij termin zgłoszeń, a przypomnę o nim.');
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
        .toList();
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
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final y in [now, now + 1])
            chip('$y', year == y, () {
              year = y;
              _load();
            }),
          const SizedBox(width: 4),
          chip(g == null ? 'Dla mojego psa' : 'Dla mojego psa (gr. ${romanNumerals[g - 1]})', mine, () => mine = true),
          chip('Wszystkie', !mine, () => mine = false),
          chip('Tylko CACIB', cacibOnly, () => cacibOnly = !cacibOnly),
        ]),
        if (mine && g == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Ustaw grupę FCI w profilu psa, aby widzieć też wystawy klubowe i specjalistyczne swojej grupy.',
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
                child: Row(children: [
                  const Icon(Icons.wifi_off_rounded, color: K9.yellow),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        shows.isEmpty ? '$error Sprawdź internet i pociągnij listę w dół.' : '$error Pokazuję zapisaną wersję.',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
            ),
          if (!loading && shows.isNotEmpty && list.isEmpty)
            const K9Card(child: Text('Brak nadchodzących wystaw dla tego filtra.', style: TextStyle(color: K9.muted))),
          for (final m in byMonth.keys) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
              child: Text('${_monthNames[m - 1]} $year',
                  style: const TextStyle(color: K9.muted, fontWeight: FontWeight.w700)),
            ),
            for (final (i, z) in byMonth[m]!.indexed)
              FadeSlideIn(index: i < 8 ? i : 0, child: _ZCard(z: z, added: _added(z), onAdd: () => _add(z))),
          ],
          if (fetchedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                  'Źródło: terminarz ZKwP (zkwp.pl), pobrano ${fmtDate(fetchedAt!)}, ${fmtTime(fetchedAt!)}. '
                  'Grupy przypisuję według rodzaju wystawy: międzynarodowe i krajowe są dla wszystkich ras, '
                  'klubowe i specjalistyczne według nazwy. Sprawdź szczegóły u organizatora.',
                  style: const TextStyle(color: K9.faint, fontSize: 11.5)),
            ),
        ],
      ]),
    );
  }
}

class _ZCard extends StatelessWidget {
  final ZkwpShow z;
  final ShowEntry? added;
  final VoidCallback onAdd;
  const _ZCard({required this.z, required this.added, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final intl = z.type == ShowType.international;
    final days = z.endDate == null ? '${z.date.day}' : '${z.date.day}–${z.endDate!.day}';
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
              Text(z.place, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(z.description, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13)),
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
                  tooltip: 'Dodaj do moich wystaw',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline_rounded, color: K9.orange, size: 28),
                ),
        ]),
      ),
    );
  }
}
