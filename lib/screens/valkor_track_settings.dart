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
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
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
              m == null ? tr('Rzeczywisty odstęp pomiarów: jeszcze nie wiem.') : tr('Rzeczywisty odstęp pomiarów: ~{0} s.', [m.round()]),
              if (!c.direct) tr('Z odbiornikiem w kieszeni odstęp ustawia tracker (Meshtastic → Pozycja), aplikacja go nie przyspieszy.'),
              if (c.slowerThanMode) tr('Tracker wysyła rzadziej niż zakłada tryb. W Meshtastic skróć „Interwał aktualizacji GPS” i „Interwał rozgłaszania pozycji”. Częstszy pomiar szybciej rozładowuje baterię.'),
            ].join(' '),
            style: TextStyle(color: c.slowerThanMode ? K9.yellow : K9.muted, fontSize: 12.5),
          ),
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
        ],
      ),
    );
  }
}
