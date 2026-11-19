import 'package:material_ui/material_ui.dart';

import '../dogs/dog_profiles.dart';
import '../gps/recorder.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../ui_prefs.dart';
import '../widgets/common.dart';
import 'forms.dart';
import 'gps_screen.dart';
import '../l10n/l10n.dart';

/// Ustawienia do szybkiego startu dla aktywnego psa: zapamiętane przy ostatnim
/// starcie, a jeśli ich nie ma, dyscyplina ostatniego treningu tego psa.
///
/// Gdy po zapamiętanym starcie pies ma nowszy trening innej dyscypliny
/// (np. wpisany ręcznie), podpowiadamy tę nowszą dyscyplinę.
QuickStart? currentQuickStart() {
  final saved = UiPrefs.instance.quickFor(DogProfiles.instance.activeId);
  final last = AppStore.instance.lastTraining;
  if (saved != null) {
    final at = saved.at;
    final newer = last != null && at != null && last.discipline != saved.discipline && last.date.isAfter(at);
    if (!newer) return saved;
  }
  return last == null ? null : QuickStart(last.discipline);
}

/// Wszystkie dyscypliny, ostatnio używane przez aktywnego psa na początku
/// (od najnowszej), pozostałe w stałej kolejności. Nic nie znika z listy.
List<Discipline> disciplinesByRecent() {
  final recent = <Discipline>[];
  final q = currentQuickStart();
  if (q != null) recent.add(q.discipline);
  final done = AppStore.instance.doneTrainings.toList()..sort((a, b) => b.date.compareTo(a.date));
  for (final t in done) {
    if (!recent.contains(t.discipline)) recent.add(t.discipline);
    if (recent.length >= 3) break;
  }
  return [...recent, for (final d in Discipline.values) if (!recent.contains(d)) d];
}

/// Krótki opis ustawień, np. „Canicross · 30 min · GPS”.
String quickStartLabel(QuickStart q) => [
      q.discipline.label,
      if (q.targetMin > 0) tr('{0} min', [q.targetMin]),
      if (q.targetKm != null && q.targetKm! > 0) tr('{0} km', [fmtKm(q.targetKm!)]),
      q.discipline.hasDistance ? tr('GPS') : tr('stoper'),
    ].join(' · ');

/// Start z zapamiętanymi ustawieniami: ekran startu jest już wypełniony,
/// zostaje tylko „Start”. To ten sam ekran i zapis co zwykły trening GPS.
Future<void> startQuick(BuildContext context, QuickStart q) =>
    openGps(context, discipline: q.discipline, targetMin: q.targetMin, targetKm: q.targetKm);

/// Wybór: dyscyplina, potem trening na żywo (GPS albo stoper) lub wpis ręczny.
Future<void> openTrainingStart(BuildContext context) {
  final q = currentQuickStart();
  var disc = q?.discipline ?? Discipline.walk;
  final order = disciplinesByRecent();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        void go(VoidCallback f) {
          Navigator.pop(c);
          f();
        }

        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(c).bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SheetTitle(tr('Rozpocznij trening')),
                if (q != null) ...[
                  K9Card(
                    gradient: K9.orangeGradient,
                    onTap: () => go(() => startQuick(context, q)),
                    child: Row(children: [
                      const Icon(Icons.replay_rounded, color: Colors.black, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(tr('Jak ostatnio'),
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 16)),
                          Text(quickStartLabel(q), style: const TextStyle(color: Colors.black87, fontSize: 13)),
                        ]),
                      ),
                      const Icon(Icons.play_circle_fill_rounded, color: Colors.black, size: 34),
                    ]),
                  ),
                  const SizedBox(height: 18),
                ],
                Text(tr('Dyscyplina'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final d in order)
                    ChoiceChip(
                      label: Text(d.label),
                      avatar: Icon(d.icon, size: 18, color: d == disc ? Colors.black : d.color),
                      selected: d == disc,
                      showCheckmark: false,
                      selectedColor: K9.orange,
                      backgroundColor: K9.cardHi,
                      side: BorderSide.none,
                      labelStyle: TextStyle(color: d == disc ? Colors.black : K9.text, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (_) => setState(() => disc = d),
                    ),
                ]),
                const SizedBox(height: 18),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: () => go(() => openGps(context, discipline: disc)),
                    icon: Icon(disc.hasDistance ? Icons.route_rounded : Icons.timer_outlined),
                    label: Text(disc.hasDistance ? tr('Nagrywaj z GPS') : tr('Mierz czas')),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () => go(() => openTrainingForm(context, discipline: disc)),
                    icon: const Icon(Icons.edit_note_rounded),
                    label: Text(tr('Wpisz ręcznie')),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Ręczny wpis działa bez GPS i bez internetu, także po treningu.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: K9.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Główny przycisk treningu (Start i zakładka Trening).
///
/// * trening trwa → „Trening trwa” i powrót do niego,
/// * są ostatnie ustawienia → start jednym dotknięciem, obok „Zmień”,
/// * brak historii → wybór dyscypliny.
class StartTrainingButton extends StatelessWidget {
  const StartTrainingButton({super.key});

  @override
  Widget build(BuildContext context) {
    final rec = TrackRecorder.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([rec, UiPrefs.instance, AppStore.instance]),
      builder: (context, _) {
        final live = rec.state != RecState.idle;
        final q = live ? null : currentQuickStart();
        final String title;
        final String sub;
        final IconData icon;
        if (live) {
          final paused = rec.state == RecState.paused;
          title = paused ? tr('Trening wstrzymany') : tr('Trening trwa');
          sub = tr('{0} · dotknij, aby wrócić', [rec.discipline.label]);
          icon = paused ? Icons.pause_circle_filled_rounded : Icons.radio_button_checked_rounded;
        } else {
          title = tr('Rozpocznij trening');
          sub = q == null ? tr('Wybierz dyscyplinę i ruszaj') : quickStartLabel(q);
          icon = Icons.play_circle_fill_rounded;
        }
        return Semantics(
          button: true,
          label: '$title. $sub',
          excludeSemantics: true,
          child: K9Card(
            padding: EdgeInsets.zero,
            gradient: K9.orangeGradient,
            child: Row(children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(K9.radius),
                  onTap: () {
                    if (live) {
                      openGps(context);
                    } else if (q != null) {
                      startQuick(context, q);
                    } else {
                      openTrainingStart(context);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                    child: Row(children: [
                      Icon(icon, color: Colors.black, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(title,
                              style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(sub,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
              if (!live)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: IconButton(
                    tooltip: tr('Zmień dyscyplinę lub sposób zapisu'),
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.black,
                      backgroundColor: Colors.black.withValues(alpha: 0.12),
                      minimumSize: const Size(52, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => openTrainingStart(context),
                    icon: const Icon(Icons.tune_rounded, size: 24),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}
