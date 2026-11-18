import 'package:material_ui/material_ui.dart';

import '../dogs/dog_profiles.dart';
import '../l10n/l10n.dart';
import '../storage/safe_prefs.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'gps_drafts.dart';
import 'recorder.dart';

bool _checked = false;

/// Po uruchomieniu aplikacji: pyta o treningi GPS przerwane zamknięciem
/// aplikacji. Odzyskany trening trafia do historii psa, dla którego go nagrywano.
Future<void> offerDraftRecovery(BuildContext context) async {
  if (_checked || TrackRecorder.instance.state != RecState.idle) return;
  _checked = true;
  final List<GpsDraft> drafts;
  try {
    drafts = await GpsDrafts.pending();
  } catch (e) {
    logError('Szkice GPS', e);
    return;
  }
  for (final d in drafts) {
    if (!context.mounted) return;
    final known = DogProfiles.instance.ids.contains(d.dogId);
    if (!known) {
      await GpsDrafts.discard(d.sessionId); // pies został usunięty
      continue;
    }
    final name = DogProfiles.instance.peek(d.dogId)?.name ?? '';
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(tr('Niedokończony trening')),
        content: Text(tr('{0}: {1} z {2}, {3} min. Aplikacja została zamknięta przed zapisem. Odzyskać trening?',
            [name, d.discipline.label, fmtDateShort(d.startedAt), (d.seconds / 60).round()])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Odrzuć'), style: TextStyle(color: K9.red))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Odzyskaj'))),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == true) {
      if (await saveGuarded(context, () => GpsDrafts.finalize(d)) && context.mounted) {
        toast(context, tr('Trening odzyskany i zapisany w historii'));
      }
    } else {
      await GpsDrafts.discard(d.sessionId);
    }
  }
}
