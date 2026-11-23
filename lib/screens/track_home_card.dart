import 'package:material_ui/material_ui.dart';

import '../collar/collar_link.dart';
import '../l10n/l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'collar_screen.dart';
import 'shell.dart';

/// Karta Valkor Track na ekranie Start: stan trackera aktywnego psa i szybkie
/// przejście do lokalizacji – bez rozpoczynania treningu.
class TrackHomeCard extends StatelessWidget {
  const TrackHomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = CollarLink.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final now = DateTime.now();
        final id = CollarLink.activeDog();
        final link = c.status(now: now, dogId: id);
        final last = c.lastKnown(id);
        final battery = c.nodeOf(id)?.battery ?? last?.battery;
        final color = switch (link) {
          DogLink.live => K9.green,
          DogLink.none => K9.muted,
          DogLink.stale || DogLink.waitingGps || DogLink.connecting => K9.yellow,
          _ => K9.red,
        };
        final lines = <String>[
          if (!c.paired) tr('Dodaj tracker GPS, żeby widzieć psa na mapie.') else dogLinkText(c, now: now, dogId: id),
          if (last != null && link != DogLink.live) tr('ostatnia znana pozycja {0}', [collarAge(last.at, now: now)]),
          if (battery != null) collarBattery(battery),
        ];
        return K9Card(
          key: const ValueKey('home-track'),
          onTap: () => goToTab(4),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: K9.orange.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: const Icon(Icons.gps_fixed_rounded, color: K9.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tr('Valkor Track'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                        const SizedBox(width: 8),
                        Icon(Icons.circle, size: 9, color: color),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(lines.join(' · '), style: const TextStyle(color: K9.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: K9.muted),
            ],
          ),
        );
      },
    );
  }
}
