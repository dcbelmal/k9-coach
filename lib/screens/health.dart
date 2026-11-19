import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../modules/module_routes.dart';
import '../modules/module_store.dart';
import '../modules/modules.dart';
import '../modules/modules_ui.dart';
import 'forms.dart';
import '../l10n/l10n.dart';

Color dueColor(DateTime due) {
  final days = dayOnly(due).difference(dayOnly(DateTime.now())).inDays;
  if (days < 0) return K9.red;
  if (days <= 14) return K9.yellow;
  return K9.green;
}

class HealthScreen extends StatelessWidget {
  /// Pokazywany jako zakładka dolnego paska (bez przycisku wstecz i bez własnego „+”).
  final bool inTab;
  const HealthScreen({super.key, this.inTab = false});

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !inTab,
        title: Row(children: [
          Icon(Icons.favorite_border_rounded, color: K9.orange),
          SizedBox(width: 10),
          Text(tr('Zdrowie')),
        ]),
      ),
      floatingActionButton: inTab
          ? null
          : FloatingActionButton(
              backgroundColor: K9.orange,
              foregroundColor: Colors.black,
              onPressed: () => openHealthForm(context),
              child: const Icon(Icons.add_rounded, size: 30),
            ),
      body: ListenableBuilder(
        listenable: modulesListenable,
        builder: (context, _) {
          final due = s.dueItems.take(4).toList();
          final care = [AppModule.heat, AppModule.feeding, AppModule.foodStock, AppModule.weight]
              .where((m) => ModuleStore.instance.isEnabled(m))
              .toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 120), children: [
            FadeSlideIn(
              child: K9Card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SectionTitle(tr('Najbliższe terminy'), icon: Icons.notifications_active_outlined),
                  if (due.isEmpty)
                    Text(tr('Brak terminów. Dodaj szczepienie lub zabieg z datą następnego terminu.'),
                        style: TextStyle(color: K9.muted)),
                  for (final h in due)
                    ListRow(
                      icon: h.category.icon,
                      color: K9.orange,
                      title: h.title,
                      subtitle: '${fmtDate(h.nextDue!)} · ${relDays(h.nextDue!)}',
                      trailing: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: dueColor(h.nextDue!), shape: BoxShape.circle),
                      ),
                      onTap: () => openHealthForm(context, existing: h),
                    ),
                ]),
              ),
            ),
            if (care.isNotEmpty) ...[
              gap16,
              FadeSlideIn(
                index: 1,
                child: K9Card(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SectionTitle(tr('Codzienna opieka'), icon: Icons.spa_outlined),
                    for (final m in care)
                      ListRow(
                        icon: m.icon,
                        color: K9.orange,
                        title: m.label,
                        trailing: const Icon(Icons.chevron_right_rounded, color: K9.faint),
                        onTap: () => openModule(context, m),
                      ),
                  ]),
                ),
              ),
            ],
            gap16,
            Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8),
              child: Text(tr('WPISY ZDROWOTNE'),
                  style: TextStyle(color: K9.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
            // Jedna lista kategorii. Terminy są tylko w karcie „Najbliższe terminy” wyżej.
            FadeSlideIn(
              index: 2,
              child: K9Card(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  children: [for (final c in HealthCategory.values) _CategoryCard(category: c, s: s)],
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final HealthCategory category;
  final AppStore s;
  const _CategoryCard({required this.category, required this.s});

  @override
  Widget build(BuildContext context) {
    final latest = s.latestFor(category);
    final sub = latest != null ? tr('Ostatnio: {0}, {1}', [latest.title, fmtDate(latest.date)]) : tr('Brak wpisów');
    return ListRow(
      icon: category.icon,
      color: K9.orange,
      title: category.label,
      subtitle: sub,
      trailing: const Icon(Icons.chevron_right_rounded, color: K9.faint),
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => HealthCategoryScreen(category: category))),
    );
  }
}

class HealthCategoryScreen extends StatelessWidget {
  final HealthCategory category;
  const HealthCategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return Scaffold(
      appBar: AppBar(title: Text(category.label)),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openHealthForm(context, category: category),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Dodaj wpis'), style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final list = s.health.where((h) => h.category == category).toList();
          if (list.isEmpty) {
            return EmptyState(
              icon: category.icon,
              title: tr('Brak wpisów'),
              text: tr('Dodaj pierwszy wpis, a przypomnę o kolejnym terminie.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final h = list[i];
              return FadeSlideIn(
                index: i,
                child: K9Card(
                  onTap: () => openHealthForm(context, existing: h),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      IconBadge(category.icon, category.color, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(h.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Text(fmtDate(h.date), style: const TextStyle(color: K9.muted, fontSize: 13)),
                        ]),
                      ),
                      if (h.remind && h.nextDue != null)
                        const Icon(Icons.notifications_active_rounded, color: K9.orange, size: 18),
                    ]),
                    if (h.nextDue != null) ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        Icon(Icons.event_repeat_rounded, size: 16, color: dueColor(h.nextDue!)),
                        const SizedBox(width: 6),
                        Text(tr('Następny termin: {0} ({1})', [fmtDate(h.nextDue!), relDays(h.nextDue!)]),
                            style: TextStyle(color: dueColor(h.nextDue!), fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                    ],
                    if (h.notes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(h.notes, style: const TextStyle(color: Color(0xFFCFCFD4), fontSize: 13.5)),
                    ],
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
