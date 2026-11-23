import 'track_home_card.dart';
import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../models_ext.dart';
import '../breeding/breeding_screen.dart';
import '../dogs/dog_switcher.dart';
import '../dogs/dog_profiles.dart';
import '../heat/heat_screen.dart';
import '../modules/module_store.dart';
import '../modules/modules.dart';
import '../modules/modules_ui.dart';
import '../nutrition/screens/nutrition_home_card.dart';
import 'calendar.dart';
import 'documents.dart';
import 'gear.dart';
import 'health.dart';
import 'profile.dart';
import 'recovery.dart';
import 'shows.dart';
import 'forms.dart';
import 'shell.dart';
import 'track_detail.dart';
import 'training_start.dart';
import '../ui_prefs.dart';
import '../storage/safe_prefs.dart';
import '../l10n/l10n.dart';

/// Ekran Start: kompaktowy nagłówek psa, główny przycisk treningu i karty
/// w stałej kolejności. Karta bez treści się nie pokazuje; karty można ukryć
/// w „Dostosuj ekran Start” (dane zostają).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([modulesListenable, UiPrefs.instance]),
      builder: (context, _) {
        final dog = s.dog!;
        final ms = ModuleStore.instance;
        final ui = UiPrefs.instance;
        final agenda = s.upcoming(days: 30, limit: 20);
        final reminders = agenda.where(isReminder).take(3).toList();
        final events = agenda.where((i) => !isReminder(i)).take(3).toList();
        final last = s.lastTraining;
        final hasTrainings = last != null;
        final cards = <Widget>[
          if (ui.shows(HomeCard.reminders) && reminders.isNotEmpty) _Reminders(items: reminders),
          if (ui.shows(HomeCard.track)) const TrackHomeCard(),
          if (ui.shows(HomeCard.lastActivity) && last != null) _LastActivity(t: last),
          if (ui.shows(HomeCard.stats) && hasTrainings) _WeekStats(week: s.thisWeek, r: s.readiness),
          if (ui.shows(HomeCard.care)) ...[
            if (ms.isEnabled(AppModule.feeding)) const NutritionHomeCard(),
            if (ms.isEnabled(AppModule.heat)) const HeatHomeCard(),
          ],
          if (ui.shows(HomeCard.events) && events.isNotEmpty) _Upcoming(items: events),
          if (ui.shows(HomeCard.shortcuts)) const ShortcutsRow(),
        ];
        return CustomScrollView(
          key: PageStorageKey('home-${DogProfiles.instance.activeId}'),
          slivers: [
            SliverToBoxAdapter(child: _Header(dog: dog)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              sliver: SliverList.list(children: [
                const DataIssuesCard(),
                if (!dog.profileComplete) ...[
                  CompleteProfileCard(
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => DogEditScreen(existing: dog))),
                  ),
                  gap12,
                ],
                const StartTrainingButton(),
                gap12,
                // Ciąża ma własny odstęp i znika, gdy jej nie ma.
                if (ui.shows(HomeCard.care) && ms.isEnabled(AppModule.breeding) && dog.female)
                  const PregnancyHomeCard(),
                for (final c in cards) ...[c, gap12],
                if (!hasTrainings && reminders.isEmpty && events.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      tr('Tu pojawią się przypomnienia, ostatnie treningi i statystyki, gdy coś zapiszesz.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: K9.muted, fontSize: 13),
                    ),
                  ),
                Center(
                  child: TextButton.icon(
                    onPressed: () => showHomeCustomizer(context),
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    label: Text(tr('Dostosuj ekran Start')),
                  ),
                ),
              ]),
            ),
          ],
        );
      },
    );
  }
}

/// Przypomnienie = termin do dopilnowania (zdrowie, ważność dokumentu,
/// termin zgłoszeń). Wydarzenie = coś, co się odbędzie (trening, wystawa).
bool isReminder(AgendaItem i) {
  final src = i.source;
  if (src is TrainingSession || src is CalendarEvent) return false;
  if (src is ShowEntry) return !isSameDay(i.date, src.date);
  return true;
}

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Kompaktowy nagłówek: zdjęcie w kółku (bez przycinania tekstu i bez
/// nakładania się na zdjęcie), imię, rasa i wiek, najważniejsze pomiary.
class _Header extends StatelessWidget {
  final Dog dog;
  const _Header({required this.dog});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final facts = [
      if (dog.weightKg != null) (Icons.monitor_weight_outlined, tr('{0} kg', [fmtNum(dog.weightKg!)])),
      if (dog.heightCm != null) (Icons.height_rounded, tr('{0} cm', [dog.heightCm!.round()])),
      if (dog.bcs != null) (Icons.shield_outlined, tr('BCS {0}/9', [dog.bcs])),
    ];
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF24160A), K9.bg],
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, top + 8, 8, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const _Logo(),
          const Spacer(),
          DogSwitchButton(dog: dog),
          IconButton(
            onPressed: () => showReminders(context),
            icon: Builder(builder: (_) {
              // Licznik terminów na najbliższe 7 dni.
              final n = AppStore.instance.upcoming(days: 7, limit: 99).length;
              return Badge(
                isLabelVisible: n > 0,
                backgroundColor: K9.orange,
                textColor: Colors.black,
                label: Text('$n'),
                child: const Icon(Icons.notifications_none_rounded, size: 26),
              );
            }),
            tooltip: tr('Przypomnienia'),
          ),
        ]),
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: tr('Profil psa: {0}', [dog.name]),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => goToTab(3),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 8, 4),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: K9.orangeGradient),
                  child: Hero(tag: 'dog-photo', child: DogAvatar(dog: dog, size: 72)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                        child: Text(dog.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.1)),
                      ),
                      const SizedBox(width: 6),
                      Icon(dog.female ? Icons.female_rounded : Icons.male_rounded, color: K9.orange, size: 22),
                    ]),
                    if (dog.breed.isNotEmpty || dog.ageLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        [dog.breed, dog.ageLabel].where((e) => e.isNotEmpty).join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, color: Color(0xFFD7D7DC), height: 1.25),
                      ),
                    ],
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 12, runSpacing: 4, children: [
                        for (final f in facts)
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(f.$1, size: 15, color: K9.orange),
                            const SizedBox(width: 4),
                            Text(f.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ]),
                      ]),
                    ],
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: K9.orange),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Image.asset('assets/brand/valkor_mark.png', width: 40, filterQuality: FilterQuality.medium),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(tr('VALKOR'),
            style: TextStyle(
                fontFamily: 'Cinzel', color: K9.goldLight, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 3, height: 1)),
        SizedBox(height: 2),
        Text(tr('COACH'),
            style: TextStyle(
                fontFamily: 'Cinzel', color: K9.goldSoft, fontSize: 10.5, fontWeight: FontWeight.w400, letterSpacing: 4.5, height: 1.1)),
      ]),
    ]);
  }
}

Color readinessColor(int level) => switch (level) {
      1 => K9.green,
      2 => K9.yellow,
      3 => K9.red,
      _ => K9.blue,
    };

/// Ostatni wykonany trening.
class _LastActivity extends StatelessWidget {
  final TrainingSession t;
  const _LastActivity({required this.t});

  @override
  Widget build(BuildContext context) {
    return K9Card(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(tr('Ostatnia aktywność'),
            icon: Icons.history_rounded, action: tr('Historia'), onAction: () => openTrainingTab(2)),
        ListRow(
          icon: t.discipline.icon,
          color: t.discipline.color,
          title: t.discipline.label,
          subtitle: [
            '${relDays(t.date)}, ${fmtTime(t.date)}',
            fmtDuration(t.durationMin),
            if (t.distanceKm != null) '${fmtKm(t.distanceKm!)} km',
          ].join(' · '),
          trailing: t.hasTrack ? const Icon(Icons.route_rounded, color: K9.orange, size: 20) : null,
          onTap: () => openTraining(context, t),
        ),
      ]),
    );
  }
}

/// Tydzień w liczbach i forma psa w jednej karcie.
class _WeekStats extends StatelessWidget {
  final PeriodStats week;
  final Readiness r;
  const _WeekStats({required this.week, required this.r});

  @override
  Widget build(BuildContext context) {
    final c = readinessColor(r.level);
    return K9Card(
      onTap: () => openTrainingTab(3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(tr('Ten tydzień'), icon: Icons.bar_chart_rounded),
        Row(children: [
          RingGauge(
            value: r.ratio == 0 ? 0 : (r.ratio / 2).clamp(0.0, 1.0),
            size: 64,
            stroke: 7,
            color: c,
            center: Text(r.ratio == 0 ? '—' : fmtNum(r.ratio, 1), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, height: 1)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c)),
              const SizedBox(height: 2),
              Text(r.advice, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 12.5, height: 1.3)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatValue(label: tr('Treningi'), value: '${week.count}')),
          Expanded(child: StatValue(label: tr('Czas'), value: '${week.minutes}', unit: 'min')),
          Expanded(child: StatValue(label: tr('Dystans'), value: fmtKm(week.km), unit: 'km')),
        ]),
      ]),
    );
  }
}

/// Najbliższe terminy do dopilnowania (zdrowie, dokumenty, zgłoszenia).
class _Reminders extends StatelessWidget {
  final List<AgendaItem> items;
  const _Reminders({required this.items});

  @override
  Widget build(BuildContext context) {
    return K9Card(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(tr('Przypomnienia'),
            icon: Icons.notifications_active_outlined, action: tr('Wszystkie'), onAction: () => showReminders(context)),
        for (final i in items)
          ListRow(
            icon: i.icon,
            color: K9.orange,
            title: i.title,
            subtitle: '${fmtDate(i.date)} · ${relDays(i.date)}',
            trailing: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dueColor(i.date), shape: BoxShape.circle),
            ),
            onTap: () => openAgendaItem(context, i),
          ),
      ]),
    );
  }
}

/// Wybór kart ekranu Start. Ukrycie karty niczego nie usuwa.
void showHomeCustomizer(BuildContext context) {
  final ui = UiPrefs.instance;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => ListenableBuilder(
      listenable: ui,
      builder: (c, _) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetTitle(tr('Dostosuj ekran Start')),
          Text(tr('Ukryta karta znika tylko z ekranu Start. Dane zostają bez zmian.'),
              style: const TextStyle(color: K9.muted, fontSize: 13)),
          const SizedBox(height: 8),
          for (final card in HomeCard.values)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr(card.plLabel)),
              value: ui.shows(card),
              onChanged: (v) async {
                try {
                  await ui.setShown(card, v);
                } catch (e) {
                  if (c.mounted) toast(c, storageErrorMessage(e));
                }
              },
            ),
        ]),
      ),
    ),
  );
}

class _Upcoming extends StatelessWidget {
  final List<AgendaItem> items;
  const _Upcoming({required this.items});

  @override
  Widget build(BuildContext context) {
    return K9Card(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(tr('Wydarzenia'),
            icon: Icons.event_note_rounded, action: tr('Kalendarz'), onAction: () => openCalendar(context)),
        for (final i in items)
          ListRow(
            icon: i.icon,
            color: K9.orange,
            title: i.title,
            subtitle: '${fmtDate(i.date)} (${relDays(i.date)})',
            onTap: () => openAgendaItem(context, i),
          ),
      ]),
    );
  }
}

void openAgendaItem(BuildContext context, AgendaItem i) {
  final src = i.source;
  if (src is TrainingSession) openTraining(context, src);
  if (src is HealthRecord) openHealthForm(context, existing: src);
  if (src is CalendarEvent) openEventForm(context, existing: src);
  if (src is ShowEntry) openShowForm(context, existing: src);
  if (src is GearItem) openGearForm(context, existing: src);
  if (src is DogDocument) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DocumentScreen(id: src.id)));
  }
}

void showReminders(BuildContext context) {
  final items = AppStore.instance.upcoming(days: 45, limit: 12);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      child: ListView(shrinkWrap: true, padding: EdgeInsets.fromLTRB(20, 0, 20, 28 + MediaQuery.viewPaddingOf(c).bottom), children: [
        SheetTitle(tr('Przypomnienia')),
        if (items.isEmpty)
          Text(tr('Nic nie czeka w najbliższych 45 dniach.'), style: TextStyle(color: K9.muted)),
        for (final i in items)
          ListRow(
            icon: i.icon,
            color: K9.orange,
            title: i.title,
            subtitle: '${fmtDate(i.date)} · ${relDays(i.date)}',
            onTap: () {
              Navigator.pop(c);
              openAgendaItem(context, i);
            },
          ),
      ]),
    ),
  );
}
