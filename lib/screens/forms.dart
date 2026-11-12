import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'documents.dart';
import 'gear.dart';
import 'shows.dart';

final _store = AppStore.instance;

// ---------------------------------------------------------------------------
// Trening
// ---------------------------------------------------------------------------

Future<void> openTrainingForm(BuildContext context,
    {TrainingSession? existing, Discipline? discipline, DateTime? date, bool? planned}) {
  return showFormSheet(
      context,
      _TrainingForm(
          existing: existing, discipline: discipline, date: date, planned: planned ?? false));
}

class _TrainingForm extends StatefulWidget {
  final TrainingSession? existing;
  final Discipline? discipline;
  final DateTime? date;
  final bool planned;
  const _TrainingForm({this.existing, this.discipline, this.date, required this.planned});

  @override
  State<_TrainingForm> createState() => _TrainingFormState();
}

class _TrainingFormState extends State<_TrainingForm> {
  late Discipline disc;
  late DateTime date;
  late bool done;
  late double rpe;
  final duration = TextEditingController();
  final distance = TextEditingController();
  final notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    disc = e?.discipline ?? widget.discipline ?? Discipline.igp;
    final now = DateTime.now();
    date = e?.date ?? widget.date ?? DateTime(now.year, now.month, now.day, now.hour, 0);
    done = e?.done ?? !widget.planned;
    rpe = (e?.rpe ?? 5).toDouble();
    duration.text = '${e?.durationMin ?? 45}';
    distance.text = e?.distanceKm == null ? '' : fmtNum(e!.distanceKm!);
    notes.text = e?.notes ?? '';
  }

  String get rpeLabel => switch (rpe.round()) {
        <= 2 => 'Bardzo lekko',
        <= 4 => 'Lekko',
        <= 6 => 'Umiarkowanie',
        <= 8 => 'Ciężko',
        _ => 'Maksymalnie',
      };

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(widget.existing == null ? 'Nowy trening' : 'Edytuj trening',
          onDelete: widget.existing == null
              ? null
              : () async {
                  if (await confirmDelete(context, 'trening')) {
                    await _store.deleteTraining(widget.existing!);
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final d in Discipline.values)
          ChoiceChip(
            label: Text(d.label),
            avatar: Icon(d.icon, size: 18, color: d == disc ? Colors.black : d.color),
            selected: d == disc,
            showCheckmark: false,
            selectedColor: K9.orange,
            backgroundColor: K9.cardHi,
            side: BorderSide.none,
            labelStyle: TextStyle(
                color: d == disc ? Colors.black : K9.text, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (_) => setState(() => disc = d),
          ),
      ]),
      gap16,
      Segmented(
          items: const ['Wykonany', 'Zaplanowany'],
          index: done ? 0 : 1,
          onChanged: (i) => setState(() => done = i == 0)),
      gap12,
      DateField(
          label: 'Data i godzina', value: date, withTime: true, onChanged: (d) => setState(() => date = d!)),
      gap12,
      Row(children: [
        Expanded(
          child: TextField(
            controller: duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Czas (min)'),
          ),
        ),
        if (disc.hasDistance) ...[
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: distance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Dystans (km)'),
            ),
          ),
        ],
      ]),
      gap16,
      Row(children: [
        const Text('Intensywność', style: TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('${rpe.round()}/10 · $rpeLabel', style: const TextStyle(color: K9.orange, fontWeight: FontWeight.w700)),
      ]),
      Slider(
        value: rpe,
        min: 1,
        max: 10,
        divisions: 9,
        activeColor: K9.orange,
        inactiveColor: K9.cardHi,
        onChanged: (v) => setState(() => rpe = v),
      ),
      TextField(
        controller: notes,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(labelText: 'Notatki (ćwiczenia, odczucia)'),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          final t = TrainingSession(
            id: widget.existing?.id ?? newId(),
            discipline: disc,
            date: date,
            durationMin: int.tryParse(duration.text.trim()) ?? 0,
            distanceKm: disc.hasDistance ? parseNum(distance.text) : null,
            rpe: rpe.round(),
            notes: notes.text.trim(),
            done: done,
          );
          await _store.upsertTraining(t);
          if (context.mounted) {
            Navigator.pop(context);
            toast(context, done ? 'Trening zapisany' : 'Trening zaplanowany');
          }
        },
        child: const Text('Zapisz'),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Zdrowie
// ---------------------------------------------------------------------------

const _suggestions = {
  HealthCategory.vaccination: ['Wścieklizna', 'DHPPi + L4', 'Kaszel kenelowy'],
  HealthCategory.deworming: ['Milbemax', 'Drontal', 'Cestal'],
  HealthCategory.ticks: ['Bravecto', 'NexGard', 'Simparica', 'Obroża Seresto'],
  HealthCategory.tests: ['HD/ED', 'DNA', 'Badanie oczu', 'Morfologia', 'Biochemia'],
  HealthCategory.vet: ['Kontrola ogólna', 'Fizjoterapia', 'Kardiolog'],
  HealthCategory.supplements: ['Antiflexi', 'Imunodol', 'Biotyna', 'Omega-3'],
};

/// Typowe odstępy do następnego terminu (w dniach).
const _defaultInterval = {
  HealthCategory.vaccination: 365,
  HealthCategory.deworming: 90,
  HealthCategory.ticks: 90,
  HealthCategory.tests: 0,
  HealthCategory.vet: 0,
  HealthCategory.supplements: 30,
};

Future<void> openHealthForm(BuildContext context, {HealthRecord? existing, HealthCategory? category}) {
  return showFormSheet(context, _HealthForm(existing: existing, category: category));
}

class _HealthForm extends StatefulWidget {
  final HealthRecord? existing;
  final HealthCategory? category;
  const _HealthForm({this.existing, this.category});

  @override
  State<_HealthForm> createState() => _HealthFormState();
}

class _HealthFormState extends State<_HealthForm> {
  late HealthCategory cat;
  late DateTime date;
  DateTime? nextDue;
  late bool remind;
  final title = TextEditingController();
  final notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    cat = e?.category ?? widget.category ?? HealthCategory.vaccination;
    date = e?.date ?? dayOnly(DateTime.now());
    nextDue = e?.nextDue ?? _suggestNext();
    remind = e?.remind ?? true;
    title.text = e?.title ?? '';
    notes.text = e?.notes ?? '';
  }

  DateTime? _suggestNext() {
    final days = _defaultInterval[cat] ?? 0;
    return days == 0 ? null : date.add(Duration(days: days));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(widget.existing == null ? 'Nowy wpis zdrowotny' : 'Edytuj wpis',
          onDelete: widget.existing == null
              ? null
              : () async {
                  if (await confirmDelete(context, 'wpis')) {
                    await _store.deleteHealth(widget.existing!);
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
      DropdownButtonFormField<HealthCategory>(
        initialValue: cat,
        dropdownColor: K9.cardHi,
        decoration: const InputDecoration(labelText: 'Kategoria'),
        items: [
          for (final c in HealthCategory.values)
            DropdownMenuItem(
                value: c,
                child: Row(children: [
                  Icon(c.icon, color: c.color, size: 20),
                  const SizedBox(width: 10),
                  Text(c.label),
                ])),
        ],
        onChanged: (c) => setState(() {
          cat = c!;
          if (widget.existing == null) nextDue = _suggestNext();
        }),
      ),
      gap12,
      TextField(
        controller: title,
        decoration: const InputDecoration(labelText: 'Nazwa / preparat'),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final s in _suggestions[cat]!)
          ActionChip(
            label: Text(s, style: const TextStyle(fontSize: 12.5)),
            backgroundColor: K9.cardHi,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onPressed: () => setState(() => title.text = s),
          ),
      ]),
      gap12,
      DateField(
          label: 'Data wykonania',
          value: date,
          onChanged: (d) => setState(() {
                date = d!;
                if (widget.existing == null) nextDue = _suggestNext();
              })),
      gap12,
      DateField(
          label: 'Następny termin',
          value: nextDue,
          clearable: true,
          onChanged: (d) => setState(() => nextDue = d)),
      const SizedBox(height: 4),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Przypomnij mi'),
        subtitle: const Text('7 dni przed i w dniu terminu, o 9:00',
            style: TextStyle(color: K9.muted, fontSize: 12.5)),
        value: remind,
        onChanged: nextDue == null ? null : (v) => setState(() => remind = v),
      ),
      TextField(
        controller: notes,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(labelText: 'Notatki / wynik'),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          if (title.text.trim().isEmpty) {
            toast(context, 'Wpisz nazwę lub preparat');
            return;
          }
          await _store.upsertHealth(HealthRecord(
            id: widget.existing?.id ?? newId(),
            category: cat,
            title: title.text.trim(),
            date: date,
            nextDue: nextDue,
            notes: notes.text.trim(),
            remind: remind,
          ));
          if (context.mounted) {
            Navigator.pop(context);
            toast(context, 'Zapisano');
          }
        },
        child: const Text('Zapisz'),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Wydarzenie w kalendarzu
// ---------------------------------------------------------------------------

Future<void> openEventForm(BuildContext context, {CalendarEvent? existing, DateTime? date}) {
  return showFormSheet(context, _EventForm(existing: existing, date: date));
}

class _EventForm extends StatefulWidget {
  final CalendarEvent? existing;
  final DateTime? date;
  const _EventForm({this.existing, this.date});

  @override
  State<_EventForm> createState() => _EventFormState();
}

class _EventFormState extends State<_EventForm> {
  late EventType type;
  late DateTime date;
  late bool remind;
  final title = TextEditingController();
  final notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    type = e?.type ?? EventType.competition;
    final d = widget.date ?? DateTime.now().add(const Duration(days: 1));
    date = e?.date ?? DateTime(d.year, d.month, d.day, 10);
    remind = e?.remind ?? true;
    title.text = e?.title ?? '';
    notes.text = e?.notes ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(widget.existing == null ? 'Nowe wydarzenie' : 'Edytuj wydarzenie',
          onDelete: widget.existing == null
              ? null
              : () async {
                  if (await confirmDelete(context, 'wydarzenie')) {
                    await _store.deleteEvent(widget.existing!);
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in EventType.values)
          ChoiceChip(
            label: Text(t.label),
            avatar: Icon(t.icon, size: 18, color: t == type ? Colors.black : t.color),
            selected: t == type,
            showCheckmark: false,
            selectedColor: K9.orange,
            backgroundColor: K9.cardHi,
            side: BorderSide.none,
            labelStyle:
                TextStyle(color: t == type ? Colors.black : K9.text, fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (_) => setState(() => type = t),
          ),
      ]),
      gap16,
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Tytuł')),
      gap12,
      DateField(
          label: 'Data i godzina', value: date, withTime: true, onChanged: (d) => setState(() => date = d!)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Przypomnij dzień wcześniej'),
        value: remind,
        onChanged: (v) => setState(() => remind = v),
      ),
      TextField(
          controller: notes,
          maxLines: 3,
          minLines: 1,
          decoration: const InputDecoration(labelText: 'Notatki (miejsce, sędzia, klasa)')),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          if (title.text.trim().isEmpty) {
            toast(context, 'Wpisz tytuł');
            return;
          }
          await _store.upsertEvent(CalendarEvent(
            id: widget.existing?.id ?? newId(),
            type: type,
            title: title.text.trim(),
            date: date,
            notes: notes.text.trim(),
            remind: remind,
          ));
          if (context.mounted) {
            Navigator.pop(context);
            toast(context, 'Dodano do kalendarza');
          }
        },
        child: const Text('Zapisz'),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Waga
// ---------------------------------------------------------------------------

Future<void> openWeightForm(BuildContext context) {
  return showFormSheet(context, const _WeightForm());
}

class _WeightForm extends StatefulWidget {
  const _WeightForm();
  @override
  State<_WeightForm> createState() => _WeightFormState();
}

class _WeightFormState extends State<_WeightForm> {
  DateTime date = dayOnly(DateTime.now());
  late final kg = TextEditingController(
      text: _store.dog?.weightKg == null ? '' : fmtNum(_store.dog!.weightKg!));

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetTitle('Pomiar wagi'),
      TextField(
        controller: kg,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'Waga (kg)'),
      ),
      gap12,
      DateField(label: 'Data', value: date, onChanged: (d) => setState(() => date = d!)),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          final v = parseNum(kg.text);
          if (v == null || v <= 0) {
            toast(context, 'Podaj poprawną wagę');
            return;
          }
          await _store.addWeight(WeightEntry(id: newId(), date: date, kg: v));
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Zapisz'),
      ),
    ]);
  }
}

/// Szybkie dodawanie (środkowy przycisk „+”).
Future<void> openQuickAdd(BuildContext context) {
  Widget tile(IconData icon, Color color, String label, VoidCallback onTap) => Expanded(
        child: K9Card(
          padding: const EdgeInsets.symmetric(vertical: 18),
          onTap: onTap,
          child: Column(children: [
            IconBadge(icon, color, size: 48),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );
  return showModalBottomSheet(
    context: context,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + MediaQuery.viewPaddingOf(c).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SheetTitle('Dodaj'),
        Row(children: [
          tile(Icons.directions_run_rounded, K9.orange, 'Trening', () {
            Navigator.pop(c);
            openTrainingForm(context);
          }),
          const SizedBox(width: 12),
          tile(Icons.event_available_rounded, K9.blue, 'Plan treningu', () {
            Navigator.pop(c);
            openTrainingForm(context,
                planned: true, date: dayOnly(DateTime.now()).add(const Duration(days: 1, hours: 17)));
          }),
        ]),
        gap12,
        Row(children: [
          tile(Icons.vaccines_rounded, K9.green, 'Zdrowie', () {
            Navigator.pop(c);
            openHealthForm(context);
          }),
          const SizedBox(width: 12),
          tile(Icons.event_rounded, K9.yellow, 'Wydarzenie', () {
            Navigator.pop(c);
            openEventForm(context);
          }),
          const SizedBox(width: 12),
          tile(Icons.monitor_weight_rounded, const Color(0xFFBF5AF2), 'Waga', () {
            Navigator.pop(c);
            openWeightForm(context);
          }),
        ]),
        gap12,
        Row(children: [
          tile(Icons.emoji_events_rounded, const Color(0xFFFFB020), 'Wystawa', () {
            Navigator.pop(c);
            openShowForm(context);
          }),
          const SizedBox(width: 12),
          tile(Icons.description_rounded, K9.red, 'Dokument', () {
            Navigator.pop(c);
            openDocumentForm(context);
          }),
          const SizedBox(width: 12),
          tile(Icons.backpack_rounded, const Color(0xFF30B0C7), 'Sprzęt', () {
            Navigator.pop(c);
            openGearForm(context);
          }),
        ]),
      ]),
    ),
  );
}
