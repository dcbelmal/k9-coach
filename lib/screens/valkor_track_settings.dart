import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../collar/collar_link.dart';
import '../collar/dog_alerts.dart';
import '../l10n/l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Ustawienia Valkor Track: tryb pracy i alarmy (smycz, strefy, utrata psa,
/// bateria, sposób powiadamiania). [here] = środek nowej strefy.
Future<void> showTrackSettings(BuildContext context, {LatLng? here}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: K9.card,
      builder: (_) => _TrackSettingsSheet(here: here),
    );

class _TrackSettingsSheet extends StatefulWidget {
  final LatLng? here;
  const _TrackSettingsSheet({this.here});
  @override
  State<_TrackSettingsSheet> createState() => _TrackSettingsSheetState();
}

class _TrackSettingsSheetState extends State<_TrackSettingsSheet> {
  final c = CollarLink.instance;
  final a = DogAlerts.instance;
  late AlertSettings s = AlertSettings.fromJson(a.settings.toJson());

  Future<void> _save() async {
    setState(() {});
    await a.save(AlertSettings.fromJson(s.toJson()));
  }

  Widget _choice<T>(String label, T value, List<(T, String)> items, ValueChanged<T> onChanged) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox.shrink(),
            items: [for (final (v, t) in items) DropdownMenuItem(value: v, child: Text(t))],
            onChanged: (v) {
              if (v != null || null is T) onChanged(v as T);
            },
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final m = c.diag.medianInterval;
    final spread = c.diag.intervalSpread;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListenableBuilder(listenable: c, builder: (context, _) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          SheetTitle(tr('Ustawienia śledzenia')),
          SectionTitle(tr('Tryb pracy'), icon: Icons.speed_rounded),
          RadioGroup<TrackMode>(
            groupValue: c.mode,
            onChanged: (v) async {
              if (v == null) return;
              await c.setMode(v);
              setState(() {});
            },
            child: Column(children: [
              for (final t in TrackMode.values)
                RadioListTile<TrackMode>(
                  contentPadding: EdgeInsets.zero,
                  value: t,
                  activeColor: K9.orange,
                  title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(tr('pomiar {0}', [t.rangeLabel]), style: const TextStyle(color: K9.muted, fontSize: 12)),
                ),
            ]),
          ),
          Text(
            [
              m == null
                  ? tr('Rzeczywisty odstęp pomiarów: jeszcze nie wiem.')
                  : (spread == null
                      ? tr('Rzeczywisty odstęp pomiarów: ~{0} s.', [m.round()])
                      : tr('Rzeczywisty odstęp pomiarów: ~{0} s (min {1}, max {2} s).',
                          [m.round(), spread.min.round(), spread.max.round()])),
              tr('Odstęp ustawia firmware trackera. Zapytania z telefonu go nie skrócą – Meshtastic odpowiada na nie najwyżej raz na 3 minuty.'),
              if (c.slowerThanMode) tr('Tracker wysyła rzadziej, niż zakłada tryb.'),
            ].join(' '),
            style: TextStyle(color: c.slowerThanMode ? K9.yellow : K9.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          TrackerProfileCard(link: c),
          gap16,
          SectionTitle(tr('Alarmy'), icon: Icons.notifications_active_rounded),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: K9.orange,
            title: Text(tr('Alarmy włączone')),
            subtitle: Text(tr('Działają, gdy aplikacja jest otwarta albo trwa trening GPS.'),
                style: const TextStyle(color: K9.muted, fontSize: 12)),
            value: s.enabled,
            onChanged: (v) {
              s.enabled = v;
              _save();
            },
          ),
          _choice<int?>(tr('Wirtualna smycz'), s.leashM, [
            (null, tr('wyłączona')),
            for (final v in const [25, 50, 100, 200, 300, 500]) (v, '$v m'),
          ], (v) {
            s.leashM = v;
            _save();
          }),
          _choice<int>(tr('Utrata sygnału po'), s.lostSec, [
            for (final v in const [60, 90, 180, 300]) (v, v < 120 ? '$v s' : tr('{0} min', [v ~/ 60])),
          ], (v) {
            s.lostSec = v;
            _save();
          }),
          _choice<int?>(tr('Słaba bateria trackera'), s.lowBattery, [
            (null, tr('wyłączona')),
            for (final v in const [10, 20, 30]) (v, '$v%'),
          ], (v) {
            s.lowBattery = v;
            _save();
          }),
          Wrap(spacing: 8, children: [
            FilterChip(
              label: Text(tr('Głos')),
              selected: s.voice,
              onSelected: (v) {
                s.voice = v;
                _save();
              },
            ),
            FilterChip(
              label: Text(tr('Dźwięk')),
              selected: s.sound,
              onSelected: (v) {
                s.sound = v;
                _save();
              },
            ),
            FilterChip(
              label: Text(tr('Wibracja')),
              selected: s.vibrate,
              onSelected: (v) {
                s.vibrate = v;
                _save();
              },
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            tr('Ochrona przed fałszywymi alarmami: liczę tylko pozycje na żywo, dodaję zapas na błąd GPS, czekam na 2 kolejne pomiary i nie powtarzam alarmu częściej niż co minutę.'),
            style: const TextStyle(color: K9.faint, fontSize: 12),
          ),
          gap16,
          SectionTitle(tr('Bezpieczne strefy'), icon: Icons.radio_button_checked_rounded),
          for (final (i, z) in s.zones.indexed)
            ListRow(
              icon: Icons.radio_button_checked_rounded,
              color: K9.green,
              title: z.name.isEmpty ? tr('Strefa {0}', [i + 1]) : z.name,
              subtitle: tr('promień {0} m', [z.radiusM.round()]),
              trailing: IconButton(
                tooltip: tr('Usuń'),
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () {
                  s.zones.removeAt(i);
                  _save();
                },
              ),
            ),
          if (widget.here == null)
            Text(tr('Żeby dodać strefę, potrzebuję Twojej pozycji albo pozycji psa.'),
                style: const TextStyle(color: K9.muted, fontSize: 12.5))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in const [50, 100, 200, 500])
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: () {
                    s.zones.add(SafeZone(tr('Strefa {0}', [s.zones.length + 1]), widget.here!.latitude, widget.here!.longitude, r.toDouble()));
                    _save();
                  },
                  child: Text(tr('+ strefa {0} m tutaj', [r])),
                ),
            ]),
          gap16,
          SectionTitle(tr('Mapa bez zasięgu'), icon: Icons.cloud_off_rounded),
          Text(
            tr('Aplikacja zapamiętuje fragmenty mapy obejrzane online i używa ich przez 30 dni, także bez internetu. Pobieranie całych obszarów nie jest dozwolone przez zasady OpenStreetMap i OpenTopoMap, więc przed wyjazdem obejrzyj teren na mapie przy dobrym zasięgu. Odległość, kierunek, radar i alarmy działają bez mapy i bez internetu.'),
            style: const TextStyle(color: K9.muted, fontSize: 12.5),
          ),
        ],
      )),
    );
  }
}

/// Ustawienia trackera odczytane przez Bluetooth i dopasowanie do trybu:
/// co ogranicza częstotliwość, propozycja zmiany (po zatwierdzeniu) i
/// sprawdzenie, czy tracker ją zapisał.
class TrackerProfileCard extends StatelessWidget {
  final CollarLink link;
  const TrackerProfileCard({super.key, required this.link});

  @override
  Widget build(BuildContext context) {
    final c = link;
    final cfg = c.config;
    const small = TextStyle(color: K9.muted, fontSize: 12.5);
    if (!c.connected) return Text(tr('Połącz tracker, żeby odczytać jego ustawienia.'), style: small);
    if (!c.direct) {
      return Text(
          tr('Telefon jest połączony z urządzeniem w kieszeni – jego ustawienia nie decydują o pomiarach psa. Żeby zmienić ustawienia trackera na psie, połącz z nim telefon bezpośrednio.'),
          style: small);
    }
    if (!cfg.known) return Text(tr('Odczytuję ustawienia trackera…'), style: small);
    final exp = cfg.expectedIntervalSec;
    final profile = c.mode.profile;
    final diff = profile.diff(cfg);
    final state = c.applyState;
    return K9Card(
      color: K9.cardHi,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Ustawienia trackera'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          [
            tr('Rozgłaszanie pozycji co {0} s, GPS co {1} s, radio {2}, rola {3}.', [
              cfg.effectiveBroadcastSecs,
              cfg.effectiveGpsUpdateSecs,
              TrackerConfig.presetName(cfg.preset),
              TrackerConfig.roleName(cfg.role),
            ]),
            if (exp != null) tr('Najczęściej możliwa nowa pozycja: co ~{0} s.', [exp.round()]),
            ?cfg.limitReason,
          ].join(' '),
          style: small,
        ),
        const SizedBox(height: 6),
        Text(
          [
            tr('Wybrany tryb: {0}.', [c.mode.label]),
            tr('Zapisane w trackerze: {0}.', [c.deviceMode?.label ?? tr('własne ustawienia')]),
            if (c.diag.intervalSpread != null)
              tr('Obserwowany odstęp: ~{0} s (max {1} s).',
                  [c.diag.medianInterval!.round(), c.diag.intervalSpread!.max.round()]),
          ].join(' '),
          style: small,
        ),
        if (c.intervalMismatch) ...[
          const SizedBox(height: 4),
          Text(
              tr('Tracker wysyła rzadziej, niż pozwalają jego ustawienia. Najczęstsze przyczyny: limit nadawania radia, słaby sygnał GPS (np. pod drzewami) albo tracker zasłonięty ciałem psa.'),
              style: const TextStyle(color: K9.yellow, fontSize: 12.5)),
        ],
        const SizedBox(height: 8),
        if (state == ProfileApply.waiting)
          Text(tr('Zapisuję ustawienia. Tracker uruchomi się ponownie, a potwierdzenie pojawi się dopiero po odczycie ustawień z trackera (ok. 30 s)…'),
              style: const TextStyle(color: K9.yellow, fontSize: 12.5))
        else if (state == ProfileApply.verified && diff.isEmpty)
          Text(tr('Tracker potwierdził ustawienia trybu {0}.', [c.mode.label]),
              style: const TextStyle(color: K9.green, fontSize: 12.5))
        else if (state == ProfileApply.failed && c.applyError != null)
          Text(c.applyError!, style: const TextStyle(color: K9.red, fontSize: 12.5)),
        if (diff.isEmpty && state != ProfileApply.waiting && state != ProfileApply.verified)
          Text(tr('Tracker jest ustawiony zgodnie z trybem {0}.', [c.mode.label]),
              style: const TextStyle(color: K9.green, fontSize: 12.5)),
        if (diff.isNotEmpty && state != ProfileApply.waiting) ...[
          const SizedBox(height: 4),
          FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            onPressed: () => confirmTrackerProfile(context, c, profile),
            child: Text(tr('Dostosuj tracker do trybu {0}', [c.mode.label])),
          ),
        ],
      ]),
    );
  }
}

/// Pokazuje planowane zmiany i ostrzeżenia; po zatwierdzeniu zapisuje je w trackerze.
Future<void> confirmTrackerProfile(BuildContext context, CollarLink c, TrackerProfile p) async {
  final cfg = c.config;
  final diff = p.diff(cfg);
  final presetChange = p.loraBytes(cfg) != null;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Zmienić ustawienia trackera?')),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          for (final (name, from, to) in diff)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('$name: $from → $to', style: const TextStyle(fontSize: 13.5)),
            ),
          const SizedBox(height: 6),
          Text(tr('Spodziewany odstęp pozycji: ~{0} s.', [p.expectedSec(cfg).round()]),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          const SizedBox(height: 8),
          Text(tr('Tracker zapisze ustawienia i uruchomi się ponownie. Częstsze pomiary szybciej rozładowują baterię.'),
              style: const TextStyle(color: K9.muted, fontSize: 12.5)),
          if (presetChange) ...[
            const SizedBox(height: 6),
            Text(
                tr('Zmiana presetu radia skraca zasięg LoRa (SHORT_FAST: zwykle kilkaset metrów do ok. 1–2 km w terenie). Tracker przestanie słyszeć urządzenia na innym presecie – przy dwóch modułach oba muszą mieć ten sam preset.'),
                style: const TextStyle(color: K9.yellow, fontSize: 12.5)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Anuluj'))),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(tr('Zmień')),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final err = await c.applyProfile(p);
  if (err != null && context.mounted) toast(context, err);
}
