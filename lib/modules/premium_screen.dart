import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'billing.dart';
import 'module_store.dart';
import '../l10n/l10n.dart';

/// Co odblokowuje Premium. `ready` = już działa w aplikacji.
const premiumFeatures = <(IconData, String, String, bool)>[
  (Icons.child_friendly_rounded, 'Moduł hodowlany', 'Krycia, kalkulator ciąży, termin porodu, mioty i ważenie szczeniąt', true),
  (Icons.pets_rounded, 'Kilka psów w aplikacji', '', false),
  (Icons.cloud_sync_rounded, 'Kopia i synchronizacja w chmurze', '', false),
  (Icons.picture_as_pdf_rounded, 'Eksport PDF i Excel', '', false),
  (Icons.insights_rounded, 'Zaawansowane statystyki', '', false),
  (Icons.event_note_rounded, 'Zaawansowane planowanie treningów', '', false),
];

/// Zawsze bezpłatne – żeby nikt nie bał się, że coś zniknie.
const freeForever = 'Trening i GPS, zdrowie, żywienie i zapasy karmy, cieczka, przewodniki treningowe i atlas ras zostają za darmo.';

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final m = ModuleStore.instance;
    final b = Billing.instance;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Valkor Premium'))),
      body: ListenableBuilder(
        listenable: Listenable.merge([m, b]),
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
                Expanded(
                  child: Text(tr('PREMIUM'),
                      style: TextStyle(
                          fontFamily: 'Cinzel', color: K9.goldLight, fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2)),
                ),
                if (m.premium) Pill(icon: Icons.check_rounded, text: tr('Aktywne')),
              ]),
              const SizedBox(height: 10),
              Text(tr('Pełnia możliwości dla hodowców, zawodników i psów pracujących.'),
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
                    Icon(f.$1, color: f.$4 ? K9.orange : K9.faint, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr(f.$2), style: TextStyle(fontSize: 15, color: f.$4 ? K9.text : K9.muted)),
                        if (f.$3.isNotEmpty)
                          Text(tr(f.$3), style: const TextStyle(color: K9.muted, fontSize: 12.5)),
                      ]),
                    ),
                    if (!f.$4) Text(tr('wkrótce'), style: TextStyle(color: K9.faint, fontSize: 12)),
                  ]),
                ),
            ]),
          ),
          gap12,
          if (b.live) ..._storeSection(context, m, b) else ..._testSection(context, m, b),
          gap12,
          Text(tr(freeForever), style: const TextStyle(color: K9.faint, fontSize: 12)),
        ]),
      ),
    );
  }

  List<Widget> _storeSection(BuildContext context, ModuleStore m, Billing b) {
    if (m.premium && m.premiumSource == PremiumSource.play) {
      return [
        K9Card(
          child: Row(children: [
            Icon(Icons.verified_rounded, color: K9.green),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                tr('Subskrypcja aktywna. Zmienisz ją lub anulujesz w Sklepie Google Play → Płatności i subskrypcje.'),
                style: TextStyle(fontSize: 13.5),
              ),
            ),
          ]),
        ),
      ];
    }
    return [
      for (final p in b.plans) ...[
        _PlanCard(plan: p, best: p.yearly && b.plans.length > 1, busy: b.busy, onTap: () => b.buy(p)),
        const SizedBox(height: 10),
      ],
      if (b.message != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(b.message!, style: const TextStyle(color: K9.orange, fontSize: 13)),
        ),
      TextButton(
        onPressed: b.busy ? null : b.restore,
        child: Text(tr('Przywróć zakup')),
      ),
      Text(
        tr('Płatność przez Google Play. Subskrypcja odnawia się automatycznie – możesz ją anulować w każdej chwili w Sklepie Play.'),
        style: TextStyle(color: K9.faint, fontSize: 12),
      ),
    ];
  }

  List<Widget> _testSection(BuildContext context, ModuleStore m, Billing b) => [
        K9Card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.info_outline_rounded, color: K9.blue),
              SizedBox(width: 10),
              Expanded(child: Text(tr('Płatności Google Play'), style: TextStyle(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 8),
            Text(
              b.supported
                  ? tr('Zakup zadziała, gdy aplikacja będzie pobrana ze Sklepu Google Play. Ta wersja jest z GitHuba, więc na razie Premium włączysz testowo poniżej.')
                  : tr('Zakup działa w aplikacji na Androida ze Sklepu Google Play.'),
              style: const TextStyle(color: K9.muted, fontSize: 13),
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
              if (context.mounted) toast(context, v ? tr('Premium włączone') : tr('Premium wyłączone'));
            },
            title: Text(tr('Włącz Premium (wersja testowa)'), style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('Za darmo, tylko do sprawdzenia modułów przed startem płatności.'),
                style: TextStyle(color: K9.muted, fontSize: 12.5)),
          ),
        ),
      ];
}

class _PlanCard extends StatelessWidget {
  final PremiumPlan plan;
  final bool best;
  final bool busy;
  final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.best, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(K9.radius),
        border: Border.all(color: best ? K9.orange : K9.border, width: best ? 1.5 : 1),
      ),
      child: K9Card(
        onTap: busy ? null : onTap,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(plan.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                if (best) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: K9.orange, borderRadius: BorderRadius.circular(8)),
                    child: Text(tr('Najtaniej'),
                        style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ],
              ]),
              if (plan.trial != null)
                Text(plan.trial!, style: const TextStyle(color: K9.green, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
          ),
          Text.rich(TextSpan(children: [
            TextSpan(text: plan.price, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            TextSpan(text: ' ${plan.perLabel}', style: const TextStyle(color: K9.muted, fontSize: 12.5)),
          ])),
        ]),
      ),
    );
  }
}
