import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'module_routes.dart';
import 'module_store.dart';
import 'modules.dart';
import 'premium_screen.dart';
import '../l10n/l10n.dart';

Listenable get modulesListenable => Listenable.merge([AppStore.instance, ModuleStore.instance]);

/// Kafelki aktywnych modułów na ekranie Start, pogrupowane w sekcje.
class ModulesGrid extends StatelessWidget {
  const ModulesGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: modulesListenable,
      builder: (context, _) {
        final dog = AppStore.instance.dog!;
        final on = ModuleStore.instance.enabled(dog).where((m) => m != AppModule.profile).toList();
        final children = <Widget>[];
        for (final sec in ModuleSection.values) {
          final list = on.where((m) => m.section == sec).toList();
          if (list.isEmpty) continue;
          if (children.isNotEmpty) children.add(const SizedBox(height: 14));
          final title = sec == ModuleSection.training && dog.purpose != null
              ? tr('Trening · {0}', [dog.purpose!.label])
              : sec.label;
          children.add(
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(color: K9.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1),
              ),
            ),
          );
          children.add(
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.7,
              padding: EdgeInsets.zero,
              children: [for (final m in list) ModuleTile(module: m)],
            ),
          );
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }
}

/// Moduły, które mają własną zakładkę na dolnym pasku, więc nie dublujemy ich w listach.
const _inBottomBar = {AppModule.profile, AppModule.training, AppModule.healthCalendar, AppModule.stats};

/// Kolejność, w jakiej moduły trafiają do skrótów na ekranie Start.
const _shortcutOrder = [
  AppModule.calendar,
  AppModule.walks,
  AppModule.documents,
  AppModule.goals,
  AppModule.gear,
  AppModule.shows,
  AppModule.gallery,
  AppModule.notes,
  AppModule.foodStock,
];

/// Ekran Start: 4 najważniejsze skróty i przycisk „Wszystkie” (lista wszystkich funkcji).
class ShortcutsRow extends StatelessWidget {
  const ShortcutsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: modulesListenable,
      builder: (context, _) {
        final ms = ModuleStore.instance;
        final list = _shortcutOrder.where((m) => ms.isEnabled(m)).take(4).toList();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in list) ...[Expanded(child: ModuleTile(module: m)), const SizedBox(width: 10)],
            Expanded(
              child: LabeledTile(
                icon: Icons.apps_rounded,
                label: tr('Wszystkie'),
                onTap: () => openAllModules(context),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Osobny ekran z listą wszystkich włączonych funkcji (skrót „Wszystkie” na Start).
void openAllModules(BuildContext context) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: Text(tr('Wszystkie funkcje'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: const [AllModulesCard(expanded: true)],
      ),
    ),
  ),
);

/// Zakładka Pies: wszystkie włączone funkcje, zwinięte w sekcje.
class AllModulesCard extends StatefulWidget {
  /// true = wszystkie sekcje rozwinięte (osobny ekran „Wszystkie funkcje”).
  final bool expanded;
  const AllModulesCard({super.key, this.expanded = false});

  @override
  State<AllModulesCard> createState() => _AllModulesCardState();
}

class _AllModulesCardState extends State<AllModulesCard> {
  late final _open = <ModuleSection>{if (widget.expanded) ...ModuleSection.values};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: modulesListenable,
      builder: (context, _) {
        final dog = AppStore.instance.dog!;
        final on = ModuleStore.instance.enabled(dog).where((m) => !_inBottomBar.contains(m)).toList();
        final rows = <Widget>[];
        for (final sec in ModuleSection.values) {
          final list = on.where((m) => m.section == sec).toList();
          if (list.isEmpty) continue;
          final open = _open.contains(sec);
          final title = sec == ModuleSection.training && dog.purpose != null
              ? tr('Trening · {0}', [dog.purpose!.label])
              : sec.label;
          if (rows.isNotEmpty) rows.add(const Divider(height: 1, color: K9.border));
          rows.add(InkWell(
            onTap: () => setState(() => open ? _open.remove(sec) : _open.add(sec)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [
                Expanded(
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5))),
                Text('${list.length}', style: const TextStyle(color: K9.muted)),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.expand_more_rounded, color: K9.muted),
                ),
              ]),
            ),
          ));
          rows.add(AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: open
                ? Column(children: [
                    for (final m in list)
                      ListRow(
                        icon: m.icon,
                        color: K9.orange,
                        title: m.label,
                        trailing: const Icon(Icons.chevron_right_rounded, color: K9.faint),
                        onTap: () => openModule(context, m),
                      ),
                    const SizedBox(height: 6),
                  ])
                : const SizedBox(width: double.infinity),
          ));
        }
        return K9Card(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionTitle(tr('Wszystkie funkcje'), icon: Icons.apps_rounded),
            ...rows,
          ]),
        );
      },
    );
  }
}

/// Kafelek: ikona w kwadratowej karcie, podpis POD kartą (do 2 linii),
/// więc nazwa nie ucina się na wąskich telefonach.
class LabeledTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const LabeledTile({super.key, required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: K9Card(
                padding: EdgeInsets.zero,
                onTap: onTap,
                child: Center(child: Icon(icon, color: K9.orange, size: 28)),
              ),
            ),
            const SizedBox(height: 6),
            // Słowa nie łamią się w środku: gdy najdłuższe słowo się nie mieści, zmniejszamy tekst.
            LayoutBuilder(builder: (context, c) {
              var style = DefaultTextStyle.of(context)
                  .style
                  .merge(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2));
              var widest = 0.0;
              for (final w in label.split(' ')) {
                final tp = TextPainter(
                  text: TextSpan(text: w, style: style),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                if (tp.width > widest) widest = tp.width;
              }
              if (c.maxWidth.isFinite && widest > c.maxWidth) {
                style = style.copyWith(fontSize: (12 * c.maxWidth / widest).clamp(8.5, 12.0) - 0.1);
              }
              return Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              );
            }),
          ],
        ),
      ),
    );
  }
}

class ModuleTile extends StatelessWidget {
  final AppModule module;
  const ModuleTile({super.key, required this.module});

  @override
  Widget build(BuildContext context) =>
      LabeledTile(icon: module.icon, label: module.label, onTap: () => openModule(context, module));
}

/// Zachęta do uzupełnienia profilu (starsze profile bez celu i aktywności).
class CompleteProfileCard extends StatelessWidget {
  final VoidCallback onTap;
  const CompleteProfileCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return K9Card(
      onTap: onTap,
      color: const Color(0xFF221509),
      child: Row(children: [
        IconBadge(Icons.tune_rounded, K9.orange),
        SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Dopasuj aplikację do psa'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            SizedBox(height: 2),
            Text(tr('Podaj cel, aktywność i status rozrodczy, a pokażę tylko potrzebne moduły.'),
                style: TextStyle(color: K9.muted, fontSize: 13)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: K9.orange),
      ]),
    );
  }
}

/// Ustawienia: ręczne włączanie i wyłączanie modułów.
class ModulesSettingsScreen extends StatelessWidget {
  const ModulesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ms = ModuleStore.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Moduły'))),
      body: ListenableBuilder(
        listenable: modulesListenable,
        builder: (context, _) {
          final dog = AppStore.instance.dog!;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
            Text(
              tr('Moduły włączają się same na podstawie profilu psa ({0}). Możesz je tu włączyć lub wyłączyć ręcznie.', [[dog.sexLabel, dog.reproLabel.toLowerCase(), if (dog.purpose != null) dog.purpose!.label.toLowerCase()].join(', ')]),
              style: const TextStyle(color: K9.muted, fontSize: 13.5),
            ),
            gap12,
            K9Card(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
              child: Row(children: [
                const Icon(Icons.workspace_premium_rounded, color: K9.gold),
                const SizedBox(width: 12),
                Expanded(child: Text(tr('Premium'), style: TextStyle(fontWeight: FontWeight.w700))),
                Text(ms.premium ? tr('Aktywne') : tr('Nieaktywne'), style: const TextStyle(color: K9.muted)),
                const Icon(Icons.chevron_right_rounded, color: K9.faint),
              ]),
            ),
            for (final sec in ModuleSection.values) ...[
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text(sec.label.toUpperCase(),
                    style: const TextStyle(color: K9.muted, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
              K9Card(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(children: [
                  for (final m in AppModule.values.where((m) => m.section == sec && m != AppModule.profile))
                    _ModuleSwitch(module: m, dog: dog),
                ]),
              ),
            ],
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: ms.overrides.isEmpty
                  ? null
                  : () async {
                      await ms.resetOverrides();
                      if (context.mounted) toast(context, tr('Przywrócono ustawienia automatyczne'));
                    },
              icon: const Icon(Icons.auto_mode_rounded),
              label: Text(tr('Przywróć ustawienia automatyczne')),
            ),
          ]);
        },
      ),
    );
  }
}

class _ModuleSwitch extends StatelessWidget {
  final AppModule module;
  final Dog dog;
  const _ModuleSwitch({required this.module, required this.dog});

  @override
  Widget build(BuildContext context) {
    final ms = ModuleStore.instance;
    final applicable = module.applicable(dog, premium: ms.premium);
    final on = ms.isEnabled(module, dog);
    final sub = !applicable
        ? module.ruleLabel(dog)
        : ms.isAuto(module)
            ? tr('{0} · automatycznie', [module.ruleLabel(dog)])
            : tr('Ustawione ręcznie');
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(module.icon, color: applicable ? K9.orange : K9.faint),
      title: Text(module.label, style: TextStyle(color: applicable ? K9.text : K9.faint)),
      subtitle: Text(sub, style: const TextStyle(color: K9.muted, fontSize: 12)),
      value: on,
      onChanged: applicable ? (v) => ms.setEnabled(module, v) : null,
    );
  }
}
