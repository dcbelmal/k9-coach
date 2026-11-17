import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'module_store.dart';

/// Co odblokowuje Premium. `ready` = już działa w aplikacji.
const premiumFeatures = <(IconData, String, bool)>[
  (Icons.child_friendly_rounded, 'Moduł hodowlany', true),
  (Icons.pets_rounded, 'Nieograniczona liczba psów', false),
  (Icons.cloud_sync_rounded, 'Synchronizacja w chmurze', false),
  (Icons.picture_as_pdf_rounded, 'Eksport PDF', false),
  (Icons.table_chart_rounded, 'Eksport Excel', false),
  (Icons.insights_rounded, 'Zaawansowane statystyki', false),
  (Icons.event_note_rounded, 'Zaawansowane planowanie treningów', false),
  (Icons.notifications_active_rounded, 'Zaawansowane przypomnienia', false),
  (Icons.monitor_weight_rounded, 'Historia zmian masy i kondycji', false),
  (Icons.inventory_2_rounded, 'Śledzenie zapasów karmy i smakołyków', false),
  (Icons.gps_fixed_rounded, 'Integracja z trackerami GPS', false),
  (Icons.watch_rounded, 'Integracja z urządzeniami sportowymi', false),
];

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = ModuleStore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Valkor Premium')),
      body: ListenableBuilder(
        listenable: m,
        builder: (context, _) => ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
          K9Card(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A1A0C), K9.card],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.workspace_premium_rounded, color: K9.gold, size: 30),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('PREMIUM',
                      style: TextStyle(
                          fontFamily: 'Cinzel', color: K9.goldLight, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2)),
                ),
                if (m.premium) const Pill(icon: Icons.check_rounded, text: 'Aktywne'),
              ]),
              const SizedBox(height: 10),
              const Text('Pełnia możliwości dla hodowców, zawodników i psów pracujących.',
                  style: TextStyle(color: Color(0xFFCFCFD4))),
            ]),
          ),
          gap12,
          K9Card(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              for (final f in premiumFeatures)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Icon(f.$1, color: K9.orange, size: 22),
                    const SizedBox(width: 12),
                    Expanded(child: Text(f.$2, style: const TextStyle(fontSize: 15))),
                    if (!f.$3) const Text('wkrótce', style: TextStyle(color: K9.faint, fontSize: 12)),
                  ]),
                ),
            ]),
          ),
          gap12,
          K9Card(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: m.premium,
              onChanged: (v) async {
                await m.setPremium(v);
                if (context.mounted) toast(context, v ? 'Premium włączone' : 'Premium wyłączone');
              },
              title: const Text('Włącz Premium (wersja testowa)', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Płatności jeszcze nie działają. Na razie możesz włączyć Premium za darmo, żeby sprawdzić moduły.',
                  style: TextStyle(color: K9.muted, fontSize: 12.5)),
            ),
          ),
        ]),
      ),
    );
  }
}
