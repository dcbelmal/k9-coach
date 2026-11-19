import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'documents.dart';
import 'gear.dart';
import 'gps_screen.dart';
import '../nutrition/nutrition_models.dart';
import '../nutrition/screens/nutrition_forms.dart';
import '../nutrition/screens/products_screen.dart';
import '../nutrition/screens/treat_training_screen.dart';
import 'shows.dart';
import '../l10n/l10n.dart';
import '../modules/modules_ui.dart';

final _store = AppStore.instance;

// ---------------------------------------------------------------------------
// Trening
// ---------------------------------------------------------------------------

Future<void> openTrainingForm(
  BuildContext context, {
  TrainingSession? existing,
  Discipline? discipline,
  DateTime? date,
  bool? planned,
}) {
  return showFormSheet(
    context,
    _TrainingForm(existing: existing, discipline: discipline, date: date, planned: planned ?? false),
  );
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

  /// Stałe ID wpisu nadane przy otwarciu formularza: ponowienie po błędzie
  /// albo podwójne naciśnięcie „Zapisz” nie tworzy drugiego treningu.
  late final String _id = widget.existing?.id ?? newId();
  bool _saving = false;
  String? _durationError, _distanceError;

  /// Zakres czasu (min) i dystansu (km) zależnie od dyscypliny.
  static const maxMinutes = 24 * 60;
  static double maxKm(Discipline d) => switch (d) {
        Discipline.bikejoring => 300,
        Discipline.walk || Discipline.recovery => 80,
        _ => 150,
      };

  /// Sprawdza pola. Zwraca (czas, dystans) albo null, gdy coś jest błędne.
  (int, double?)? _validate() {
    final minutes = int.tryParse(duration.text.trim());
    _durationError = minutes == null || minutes < 1 || minutes > maxMinutes
        ? tr('Podaj czas w pełnych minutach (1–{0})', [maxMinutes])
        : null;
    double? km;
    _distanceError = null;
    if (disc.hasDistance && distance.text.trim().isNotEmpty) {
      km = parseNum(distance.text);
      if (km == null || km <= 0 || km > maxKm(disc)) {
        _distanceError = tr('Podaj dystans od 0,1 do {0} km', [fmtNum(maxKm(disc))]);
      }
    }
    setState(() {});
    if (_durationError != null || _distanceError != null) return null;
    return (minutes!, km);
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    disc = e?.discipline ?? widget.discipline ?? _store.lastDiscipline ?? Discipline.igp;
    final now = DateTime.now();
    date = e?.date ?? widget.date ?? DateTime(now.year, now.month, now.day, now.hour, 0);
    done = e?.done ?? !widget.planned;
    rpe = (e?.rpe ?? 5).toDouble();
    duration.text = '${e?.durationMin ?? 45}';
    distance.text = e?.distanceKm == null ? '' : fmtNum(e!.distanceKm!);
    notes.text = e?.notes ?? '';
  }

  String get rpeLabel => switch (rpe.round()) {
    <= 2 => tr('Bardzo lekko'),
    <= 4 => tr('Lekko'),
    <= 6 => tr('Umiarkowanie'),
    <= 8 => tr('Ciężko'),
    _ => tr('Maksymalnie'),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(
          widget.existing == null ? tr('Nowy trening') : tr('Edytuj trening'),
          onDelete: widget.existing == null
              ? null
              : () async {
                  if (await confirmDelete(context, 'trening')) {
                    if (!context.mounted) return;
                    if (!await saveGuarded(context, () => _store.deleteTraining(widget.existing!), done: tr('Usunięto'))) {
                      return;
                    }
                    if (context.mounted) Navigator.pop(context);
                  }
                },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in Discipline.values)
              ChoiceChip(
                label: Text(d.label),
                avatar: Icon(d.icon, size: 18, color: d == disc ? Colors.black : d.color),
                selected: d == disc,
                showCheckmark: false,
                selectedColor: K9.orange,
                backgroundColor: K9.cardHi,
                side: BorderSide.none,
                labelStyle: TextStyle(color: d == disc ? Colors.black : K9.text, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (_) => setState(() => disc = d),
              ),
          ],
        ),
        gap16,
        Segmented(
          items: [tr('Wykonany'), tr('Zaplanowany')],
          index: done ? 0 : 1,
          onChanged: (i) => setState(() => done = i == 0),
        ),
        gap12,
        DateField(label: tr('Data i godzina'), value: date, withTime: true, onChanged: (d) => setState(() => date = d!)),
        gap12,
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: duration,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Czas (min)'), errorText: _durationError, errorMaxLines: 2),
              ),
            ),
            if (disc.hasDistance) ...[
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: distance,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Dystans (km)'), errorText: _distanceError, errorMaxLines: 2),
                ),
              ),
            ],
          ],
        ),
        gap16,
        Row(
          children: [
            Text(tr('Intensywność'), style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              '${rpe.round()}/10 · $rpeLabel',
              style: const TextStyle(color: K9.orange, fontWeight: FontWeight.w700),
            ),
          ],
        ),
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
          decoration: InputDecoration(labelText: tr('Notatki (ćwiczenia, odczucia)')),
        ),
        const SizedBox(height: 20),
        if (widget.existing != null && !widget.existing!.done) ...[
          OutlinedButton.icon(
            onPressed: () {
              final plan = widget.existing!;
              final nav = Navigator.of(context);
              nav.pop();
              openGpsWith(nav, plan: plan);
            },
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(tr('Rozpocznij teraz')),
          ),
          const SizedBox(height: 10),
        ],
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  final v = _validate();
                  if (v == null) return;
                  final t = TrainingSession(
                    id: _id,
                    discipline: disc,
                    date: date,
                    durationMin: v.$1,
                    distanceKm: disc.hasDistance ? v.$2 : null,
                    rpe: rpe.round(),
                    notes: notes.text.trim(),
                    done: done,
                    trackRef: widget.existing?.trackRef,
                    movingSec: widget.existing?.movingSec,
                    maxSpeedKmh: widget.existing?.maxSpeedKmh,
                    bestKmSec: widget.existing?.bestKmSec,
                  );
                  setState(() => _saving = true);
                  final ok = await saveGuarded(context, () => _store.upsertTraining(t));
                  if (!context.mounted) return;
                  setState(() => _saving = false);
                  if (!ok) return; // formularz zostaje – można ponowić z tym samym ID
                  Navigator.pop(context);
                  toast(context, done ? tr('Trening zapisany') : tr('Trening zaplanowany'));
                },
          child: Text(tr('Zapisz')),
        ),
      ],
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(
          widget.existing == null ? tr('Nowy wpis zdrowotny') : tr('Edytuj wpis'),
          onDelete: widget.existing == null
              ? null
              : () async {
                  if (await confirmDelete(context, 'wpis')) {
                    if (!context.mounted) return;
                    if (!await saveGuarded(context, () => _store.deleteHealth(widget.existing!), done: tr('Usunięto'))) {
                      return;
                    }
                    if (context.mounted) Navigator.pop(context);
                  }
                },
        ),
        DropdownButtonFormField<HealthCategory>(
          initialValue: cat,
          dropdownColor: K9.cardHi,
          decoration: InputDecoration(labelText: tr('Kategoria')),
          items: [
            for (final c in HealthCategory.values)
              DropdownMenuItem(
                value: c,
                child: Row(
                  children: [
                    Icon(c.icon, color: c.color, size: 20),
                    const SizedBox(width: 10),
                    Text(c.label),
                  ],
                ),
              ),
          ],
          onChanged: (c) => setState(() {
            cat = c!;
            if (widget.existing == null) nextDue = _suggestNext();
          }),
        ),
        gap12,
        TextField(
          controller: title,
          decoration: InputDecoration(labelText: tr('Nazwa / preparat')),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final s in _suggestions[cat]!)
              ActionChip(
                label: Text(tr(s), style: const TextStyle(fontSize: 12.5)),
                backgroundColor: K9.cardHi,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onPressed: () => setState(() => title.text = tr(s)),
              ),
          ],
        ),
        gap12,
        DateField(
          label: tr('Data wykonania'),
          value: date,
          onChanged: (d) => setState(() {
            date = d!;
            if (widget.existing == null) nextDue = _suggestNext();
          }),
        ),
        gap12,
        DateField(
          label: tr('Następny termin'),
          value: nextDue,
          clearable: true,
          onChanged: (d) => setState(() => nextDue = d),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Przypomnij mi')),
          subtitle: Text(
            tr('7 dni przed i w dniu terminu, o 9:00'),
            style: TextStyle(color: K9.muted, fontSize: 12.5),
          ),
          value: remind,
          onChanged: nextDue == null ? null : (v) => setState(() => remind = v),
        ),
        TextField(
          controller: notes,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(labelText: tr('Notatki / wynik')),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            if (title.text.trim().isEmpty) {
              toast(context, tr('Wpisz nazwę lub preparat'));
              return;
            }
            if (!context.mounted) return;
            if (!await saveGuarded(context, () => _store.upsertHealth(
              HealthRecord(
                id: widget.existing?.id ?? newId(),
                category: cat,
                title: title.text.trim(),
                date: date,
                nextDue: nextDue,
                notes: notes.text.trim(),
                remind: remind,
              ),
            ))) {
              return;
            }
            if (context.mounted) {
              Navigator.pop(context);
              toast(context, tr('Zapisano'));
            }
          },
          child: Text(tr('Zapisz')),
        ),
      ],
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(
          widget.existing == null ? tr('Nowe wydarzenie') : tr('Edytuj wydarzenie'),
          onDelete: widget.existing == null
              ? null
              : () async {
                  if (await confirmDelete(context, 'wydarzenie')) {
                    if (!context.mounted) return;
                    if (!await saveGuarded(context, () => _store.deleteEvent(widget.existing!), done: tr('Usunięto'))) {
                      return;
                    }
                    if (context.mounted) Navigator.pop(context);
                  }
                },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in EventType.values)
              ChoiceChip(
                label: Text(t.label),
                avatar: Icon(t.icon, size: 18, color: t == type ? Colors.black : t.color),
                selected: t == type,
                showCheckmark: false,
                selectedColor: K9.orange,
                backgroundColor: K9.cardHi,
                side: BorderSide.none,
                labelStyle: TextStyle(color: t == type ? Colors.black : K9.text, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (_) => setState(() => type = t),
              ),
          ],
        ),
        gap16,
        TextField(
          controller: title,
          decoration: InputDecoration(labelText: tr('Tytuł')),
        ),
        gap12,
        DateField(label: tr('Data i godzina'), value: date, withTime: true, onChanged: (d) => setState(() => date = d!)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Przypomnij dzień wcześniej')),
          value: remind,
          onChanged: (v) => setState(() => remind = v),
        ),
        TextField(
          controller: notes,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(labelText: tr('Notatki (miejsce, sędzia, klasa)')),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            if (title.text.trim().isEmpty) {
              toast(context, tr('Wpisz tytuł'));
              return;
            }
            if (!context.mounted) return;
            if (!await saveGuarded(context, () => _store.upsertEvent(
              CalendarEvent(
                id: widget.existing?.id ?? newId(),
                type: type,
                title: title.text.trim(),
                date: date,
                notes: notes.text.trim(),
                remind: remind,
              ),
            ))) {
              return;
            }
            if (context.mounted) {
              Navigator.pop(context);
              toast(context, tr('Dodano do kalendarza'));
            }
          },
          child: Text(tr('Zapisz')),
        ),
      ],
    );
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
  late final kg = TextEditingController(text: _store.dog?.weightKg == null ? '' : fmtNum(_store.dog!.weightKg!));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(tr('Pomiar wagi')),
        TextField(
          controller: kg,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('Waga (kg)')),
        ),
        gap12,
        DateField(label: tr('Data'), value: date, onChanged: (d) => setState(() => date = d!)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            final v = parseNum(kg.text);
            if (v == null || v <= 0) {
              toast(context, tr('Podaj poprawną wagę'));
              return;
            }
            if (!context.mounted) return;
            if (!await saveGuarded(context, () => _store.addWeight(WeightEntry(id: newId(), date: date, kg: v)))) {
              return;
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: Text(tr('Zapisz')),
        ),
      ],
    );
  }
}

/// Szybkie dodawanie (środkowy przycisk „+”).
/// Wszystko widoczne od razu, w grupach. Trening na górze jako duże przyciski.
Future<void> openQuickAdd(BuildContext context) {
  final groups = <(String, List<(IconData, String, VoidCallback)>)>[
    (
      tr('Codziennie'),
      [
        (Icons.restaurant_rounded, tr('Karmienie'), () => openFeedingForm(context)),
        (Icons.cookie_rounded, tr('Przysmak'), () => openFeedingForm(context, kind: FeedKind.treat)),
        (Icons.monitor_weight_rounded, tr('Waga'), () => openWeightForm(context)),
        (
          Icons.event_available_rounded,
          tr('Plan treningu'),
          () => openTrainingForm(context,
              planned: true, date: dayOnly(DateTime.now()).add(const Duration(days: 1, hours: 17)))
        ),
      ]
    ),
    (
      tr('Zdrowie i dokumenty'),
      [
        (Icons.vaccines_rounded, tr('Zdrowie'), () => openHealthForm(context)),
        (Icons.description_rounded, tr('Dokument'), () => openDocumentForm(context)),
        (Icons.event_rounded, tr('Wydarzenie'), () => openEventForm(context)),
        (Icons.qr_code_scanner_rounded, tr('Skanuj karmę'), () => addProductFlow(context)),
      ]
    ),
    (
      tr('Sport i wystawy'),
      [
        (Icons.emoji_events_rounded, tr('Wystawa'), () => openShowForm(context)),
        (Icons.backpack_rounded, tr('Sprzęt'), () => openGearForm(context)),
        (Icons.sports_rounded, tr('Trening z nagrodami'), () => openTreatTraining(context)),
      ]
    ),
  ];
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) {
      void go(VoidCallback f) {
        Navigator.pop(c);
        f();
      }

      Widget groupGrid(List<(IconData, String, VoidCallback)> items) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: i < items.length
                      ? LabeledTile(icon: items[i].$1, label: items[i].$2, onTap: () => go(items[i].$3))
                      : const SizedBox(),
                ),
              ],
            ],
          );
      Widget label(String t) => Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 10),
            child: Text(t.toUpperCase(),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: K9.muted)),
          );
      return SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + MediaQuery.viewPaddingOf(c).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitle(tr('Dodaj')),
              label(tr('Trening')),
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: () => go(() => openGps(context)),
                      icon: const Icon(Icons.route_rounded),
                      label: Text(tr('Z GPS'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: () => go(() => openTrainingForm(context)),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: Text(tr('Ręcznie'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ]),
              for (final g in groups) ...[label(g.$1), groupGrid(g.$2)],
            ],
          ),
        ),
      );
    },
  );
}
