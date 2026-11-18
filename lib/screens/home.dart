import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../models_ext.dart';
import '../breeding/breeding_screen.dart';
import '../dogs/dog_switcher.dart';
import '../heat/heat_screen.dart';
import '../modules/module_store.dart';
import '../modules/modules.dart';
import '../modules/modules_ui.dart';
import '../nutrition/screens/nutrition_home_card.dart';
import 'calendar.dart';
import 'documents.dart';
import 'gear.dart';
import 'profile.dart';
import 'recovery.dart';
import 'shows.dart';
import 'forms.dart';
import 'shell.dart';
import 'track_detail.dart';
import '../l10n/l10n.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: modulesListenable,
      builder: (context, _) {
        final dog = s.dog!;
        final ms = ModuleStore.instance;
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Hero(dog: dog)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
              sliver: SliverList.list(children: [
                const DataIssuesCard(),
                if (!dog.profileComplete) ...[
                  FadeSlideIn(
                    child: CompleteProfileCard(
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => DogEditScreen(existing: dog))),
                    ),
                  ),
                  gap12,
                ],
                FadeSlideIn(index: 1, child: _ReadinessCard(r: s.readiness)),
                gap12,
                if (ms.isEnabled(AppModule.heat)) ...[
                  const FadeSlideIn(index: 2, child: HeatHomeCard()),
                  gap12,
                ],
                if (ms.isEnabled(AppModule.breeding) && dog.female)
                  const FadeSlideIn(index: 2, child: PregnancyHomeCard()),
                if (ms.isEnabled(AppModule.feeding)) ...[
                  const FadeSlideIn(index: 3, child: NutritionHomeCard()),
                  gap12,
                ],
                const FadeSlideIn(index: 4, child: ShortcutsRow()),
                gap12,
                FadeSlideIn(index: 5, child: _Upcoming(items: s.upcoming(limit: 3))),
              ]),
            ),
          ],
        );
      },
    );
  }
}

class _Hero extends StatelessWidget {
  final Dog dog;
  const _Hero({required this.dog});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: 320 + top,
      child: Stack(fit: StackFit.expand, children: [
        Hero(tag: 'dog-photo', child: DogPhoto(dog: dog)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.25, 0.6, 1],
              colors: [Color(0xAA000000), Color(0x00000000), Color(0x55000000), K9.bg],
            ),
          ),
        ),
        Positioned(
          top: top + 12,
          left: 20,
          right: 12,
          child: Row(children: [
            const _Logo(),
            const Spacer(),
            DogSwitchButton(dog: dog),
            IconButton(
              onPressed: () => showReminders(context),
              icon: const Icon(Icons.notifications_none_rounded, size: 26),
              tooltip: tr('Przypomnienia'),
            ),
          ]),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 16,
          child: GestureDetector(
            onTap: () => goToTab(3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(dog.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, height: 1)),
                ),
                const SizedBox(width: 8),
                Icon(dog.female ? Icons.female_rounded : Icons.male_rounded, color: K9.orange, size: 30),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(
                    [dog.breed, dog.ageLabel].where((e) => e.isNotEmpty).join(' • '),
                    style: const TextStyle(fontSize: 16, color: Color(0xFFD7D7DC)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: K9.orange, size: 28),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (dog.weightKg != null) Pill(icon: Icons.monitor_weight_outlined, text: tr('{0} kg', [fmtNum(dog.weightKg!)])),
                if (dog.heightCm != null) Pill(icon: Icons.height_rounded, text: tr('{0} cm', [dog.heightCm!.round()])),
                if (dog.bcs != null) Pill(icon: Icons.shield_outlined, text: tr('BCS {0}/9', [dog.bcs])),
              ]),
            ]),
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

class _ReadinessCard extends StatelessWidget {
  final Readiness r;
  const _ReadinessCard({required this.r});

  @override
  Widget build(BuildContext context) {
    final c = readinessColor(r.level);
    return K9Card(
      onTap: () => openTrainingTab(3),
      child: Row(children: [
        RingGauge(
          value: r.score / 100,
          size: 84,
          stroke: 9,
          color: c,
          center: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${r.score}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
            Text(tr('forma'), style: TextStyle(color: K9.muted, fontSize: 11)),
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Wskaźnik kondycji'), style: TextStyle(color: K9.muted, fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(r.label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
            const SizedBox(height: 4),
            Text(r.advice, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13, height: 1.3)),
          ]),
        ),
      ]),
    );
  }
}

class _Upcoming extends StatelessWidget {
  final List<AgendaItem> items;
  const _Upcoming({required this.items});

  @override
  Widget build(BuildContext context) {
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle(tr('Najbliższe wydarzenia'),
            icon: Icons.event_note_rounded, action: tr('Kalendarz'), onAction: () => openCalendar(context)),
        if (items.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(tr('Brak zaplanowanych wydarzeń. Dodaj je przyciskiem „+”.'),
                style: TextStyle(color: K9.muted)),
          ),
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
