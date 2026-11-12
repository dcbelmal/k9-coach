import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import '../widgets/common.dart';

enum Module {
  shows('Wystawy', Icons.emoji_events_rounded, [
    'Kalendarz wystaw i zgłoszenia',
    'Wyniki i oceny',
    'CAC, CACIB, Championaty',
    'Galeria medali',
  ]),
  documents('Dokumenty', Icons.description_rounded, [
    'Rodowód i książeczka zdrowia',
    'Paszport',
    'Wyniki badań (HD/ED, oczy, DNA)',
    'Licencje sportowe',
  ]),
  gear('Sprzęt', Icons.backpack_rounded, [
    'Szelki, smycze, amortyzatory, rower',
    'Daty zakupu',
    'Przypomnienia o wymianie',
  ]),
  goals('Cele', Icons.track_changes_rounded, [
    'BH-VT, IGP1, IGP2, IGP3',
    'Champion Polski i Międzynarodowy',
    'Cel kilometrów',
    'Docelowa masa psa',
  ]),
  ai('Asystent AI', Icons.auto_awesome_rounded, [
    'Analiza postępów',
    'Plany treningowe',
    'Raporty PDF',
  ]);

  final String label;
  final IconData icon;
  final List<String> features;
  const Module(this.label, this.icon, this.features);
}

class ComingSoonScreen extends StatelessWidget {
  final Module module;
  const ComingSoonScreen({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(module.label)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 20),
        Center(child: IconBadge(module.icon, K9.orange, size: 88)),
        const SizedBox(height: 20),
        const Text('Wkrótce w K9 Coach',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Ten moduł pojawi się w kolejnej wersji aplikacji.',
            textAlign: TextAlign.center, style: TextStyle(color: K9.muted)),
        const SizedBox(height: 28),
        K9Card(
          child: Column(children: [
            for (final f in module.features)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: K9.orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(f, style: const TextStyle(fontSize: 15))),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }
}
