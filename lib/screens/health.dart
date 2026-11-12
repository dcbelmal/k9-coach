import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'forms.dart';

Color dueColor(DateTime due) {
  final days = dayOnly(due).difference(dayOnly(DateTime.now())).inDays;
  if (days < 0) return K9.red;
  if (days <= 14) return K9.yellow;
  return K9.green;
}

class HealthScreen extends StatelessWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.favorite_border_rounded, color: K9.orange),
          SizedBox(width: 10),
          Text('Zdrowie'),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openHealthForm(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final due = s.dueItems.take(4).toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            FadeSlideIn(
              child: K9Card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionTitle('Najbliższe terminy', icon: Icons.notifications_active_outlined),
                  if (due.isEmpty)
                    const Text('Brak terminów. Dodaj szczepienie lub zabieg z datą następnego terminu.',
                        style: TextStyle(color: K9.muted)),
                  for (final h in due)
                    ListRow(
                      icon: h.category.icon,
                      color: h.category.color,
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
            gap16,
            for (final (i, c) in HealthCategory.values.indexed) ...[
              FadeSlideIn(index: i + 1, child: _CategoryCard(category: c, s: s)),
              const SizedBox(height: 10),
            ],
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
    final upcoming = s.dueItems.where((h) => h.category == category).toList();
    String sub;
    if (upcoming.isNotEmpty) {
      sub = 'Następne: ${fmtDate(upcoming.first.nextDue!)}';
    } else if (latest != null) {
      sub = 'Ostatnio: ${latest.title}, ${fmtDate(latest.date)}';
    } else {
      sub = 'Brak wpisów';
    }
    return K9Card(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => HealthCategoryScreen(category: category))),
      child: ListRow(
        icon: category.icon,
        color: category.color,
        title: category.label,
        subtitle: sub,
      ),
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
        label: const Text('Dodaj wpis', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final list = s.health.where((h) => h.category == category).toList();
          if (list.isEmpty) {
            return EmptyState(
              icon: category.icon,
              title: 'Brak wpisów',
              text: 'Dodaj pierwszy wpis, a przypomnę o kolejnym terminie.',
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
                        Text('Następny termin: ${fmtDate(h.nextDue!)} (${relDays(h.nextDue!)})',
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
