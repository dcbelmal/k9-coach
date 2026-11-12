import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../files/file_store.dart';
import '../gps/recorder.dart';
import '../gps/records.dart';
import '../gps/track.dart';
import '../gps/weather.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'track_detail.dart';

final _rec = TrackRecorder.instance;

Future<void> openGps(BuildContext context, {Discipline? discipline}) {
  if (discipline != null && discipline.hasDistance && _rec.state == RecState.idle) _rec.discipline = discipline;
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GpsScreen()));
}

/// Mapa OpenStreetMap (bez klucza i opłat).
TileLayer osmTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'pl.k9coach.app',
      maxZoom: 19,
    );

/// Podpis źródła mapy (wymagany przez OpenStreetMap).
class OsmCredit extends StatelessWidget {
  const OsmCredit({super.key});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomRight,
        child: Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
          child: const Text('© OpenStreetMap', style: TextStyle(color: Colors.white70, fontSize: 9.5)),
        ),
      );
}

class GpsScreen extends StatefulWidget {
  const GpsScreen({super.key});
  @override
  State<GpsScreen> createState() => _GpsScreenState();
}

class _GpsScreenState extends State<GpsScreen> {
  final map = MapController();
  bool follow = true;
  bool mapReady = false;
  String? permError;
  bool checking = true;
  LatLng? here;
  Weather? weather;
  bool weatherLoading = true;

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onRec);
    _prepare();
  }

  @override
  void dispose() {
    _rec.removeListener(_onRec);
    super.dispose();
  }

  void _onRec() {
    if (!mounted) return;
    final p = _rec.last;
    if (follow && mapReady && p != null) {
      map.move(LatLng(p.latitude, p.longitude), map.camera.zoom < 14 ? 16 : map.camera.zoom);
    }
  }

  Future<void> _prepare() async {
    final err = await TrackRecorder.ensurePermission();
    if (!mounted) return;
    setState(() {
      permError = err;
      checking = false;
    });
    if (err != null) {
      setState(() => weatherLoading = false);
      return;
    }
    try {
      final p = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)));
      if (!mounted) return;
      setState(() => here = LatLng(p.latitude, p.longitude));
      if (mapReady) map.move(here!, 15);
      final w = await fetchWeather(p.latitude, p.longitude);
      if (mounted) setState(() => weather = w);
    } catch (_) {}
    if (mounted) setState(() => weatherLoading = false);
  }

  Future<void> _start() async {
    final err = await TrackRecorder.ensurePermission();
    if (err != null) {
      setState(() => permError = err);
      return;
    }
    if (!mounted) return;
    if (weather != null && weather!.risk == 2 && _rec.discipline.hasDistance) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Za gorąco'),
          content: Text('${fmtNum(weather!.temp)}°C, odczuwalna ${fmtNum(weather!.feels)}°C.\n\n${weather!.advice}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Rezygnuję')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Startuję mimo to')),
          ],
        ),
      );
      if (go != true) return;
    }
    follow = true;
    await _rec.start();
  }

  Future<void> _stop() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetTitle('Zakończyć trening?'),
          FilledButton(onPressed: () => Navigator.pop(c, 1), child: const Text('Zakończ i zapisz')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => Navigator.pop(c, 0), child: const Text('Wróć do treningu')),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(c, 2),
            child: const Text('Odrzuć bez zapisywania', style: TextStyle(color: K9.red)),
          ),
        ]),
      ),
    );
    if (choice == 2) {
      await _rec.discard();
      if (mounted) Navigator.pop(context);
    }
    if (choice != 1) return;
    final startedAt = _rec.startedAt ?? DateTime.now();
    final disc = _rec.discipline;
    final track = await _rec.stop();
    final secs = _rec.seconds;
    final meters = track.meters;
    final splits = track.splits().where((s) => s.meters >= 1000).toList();
    final best = splits.isEmpty ? null : splits.map((s) => s.seconds).reduce((a, b) => a < b ? a : b);
    String? ref;
    if (track.points.length > 1) ref = await FileStore.saveText(track.encode());
    final t = TrainingSession(
      id: newId(),
      discipline: disc,
      date: startedAt,
      durationMin: (secs / 60).round().clamp(1, 100000),
      distanceKm: double.parse((meters / 1000).toStringAsFixed(2)),
      rpe: 5,
      notes: '',
      trackRef: ref,
      movingSec: secs.round(),
      maxSpeedKmh: double.parse(track.maxSpeedKmh().toStringAsFixed(1)),
      bestKmSec: best?.round(),
    );
    final recs = Records.newRecords(AppStore.instance.trainings, t);
    await AppStore.instance.upsertTraining(t);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TrackDetailScreen(training: t, track: track, newRecords: recs, fresh: true)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _rec,
      builder: (context, _) {
        final idle = _rec.state == RecState.idle;
        return PopScope(
          canPop: idle,
          onPopInvokedWithResult: (did, _) {
            if (!did) toast(context, 'Trening trwa. Zakończ go przyciskiem Stop.');
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(idle ? 'Trening GPS' : _rec.discipline.label),
              automaticallyImplyLeading: idle,
            ),
            body: idle ? _setup() : _live(),
          ),
        );
      },
    );
  }

  Widget _map({double height = 220}) {
    final pts = _rec.allPoints;
    final p = _rec.last;
    final pos = p == null ? here : LatLng(p.latitude, p.longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(K9.radius),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          FlutterMap(
            mapController: map,
            options: MapOptions(
              initialCenter: pos ?? const LatLng(52.07, 19.48),
              initialZoom: pos == null ? 5.5 : 15.5,
              backgroundColor: K9.cardHi,
              onMapReady: () => mapReady = true,
              onPositionChanged: (c, hasGesture) {
                if (hasGesture && follow) setState(() => follow = false);
              },
            ),
            children: [
              osmTiles(),
              PolylineLayer(polylines: [
                for (final s in _rec.segments)
                  if (s.length > 1)
                    Polyline(
                        points: [for (final q in s) q.ll],
                        strokeWidth: 5,
                        color: K9.orange,
                        borderStrokeWidth: 1.5,
                        borderColor: Colors.black54),
              ]),
              if (pts.isNotEmpty) MarkerLayer(markers: [_dot(pts.first, K9.green, 14)]),
              if (pos != null) MarkerLayer(markers: [_dot(pos, K9.orange, 20)]),
              const OsmCredit(),
            ],
          ),
          if (!follow && pos != null)
            Positioned(
              right: 10,
              top: 10,
              child: FloatingActionButton.small(
                heroTag: 'center',
                backgroundColor: K9.card,
                foregroundColor: K9.orange,
                onPressed: () {
                  setState(() => follow = true);
                  map.move(pos, 16);
                },
                child: const Icon(Icons.my_location_rounded),
              ),
            ),
        ]),
      ),
    );
  }

  Marker _dot(LatLng p, Color c, double size) => Marker(
        point: p,
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 10)],
          ),
        ),
      );

  Widget _setup() {
    final discs = Discipline.values.where((d) => d.hasDistance || d == Discipline.condition).toList();
    final rec = Records.of(AppStore.instance.trainings, _rec.discipline);
    Widget chip(String label, bool sel, VoidCallback on) => ChoiceChip(
          label: Text(label),
          selected: sel,
          showCheckmark: false,
          selectedColor: K9.orange,
          backgroundColor: K9.cardHi,
          side: BorderSide.none,
          labelStyle: TextStyle(color: sel ? Colors.black : K9.text, fontWeight: FontWeight.w600, fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (_) => setState(on),
        );
    return ListView(padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.viewPaddingOf(context).bottom), children: [
      if (permError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: K9Card(
            color: K9.cardHi,
            child: Row(children: [
              const Icon(Icons.location_off_rounded, color: K9.yellow),
              const SizedBox(width: 10),
              Expanded(child: Text(permError!, style: const TextStyle(fontSize: 13))),
              if (!checking && !kIsWeb)
                TextButton(
                    onPressed: () async {
                      await Geolocator.openAppSettings();
                    },
                    child: const Text('Ustawienia')),
            ]),
          ),
        ),
      _map(height: 200),
      gap16,
      const SectionTitle('Dyscyplina'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final d in discs) chip(d.label, _rec.discipline == d, () => _rec.discipline = d),
      ]),
      gap16,
      _weatherCard(),
      gap12,
      K9Card(
        child: Column(children: [
          Row(children: [
            const Icon(Icons.record_voice_over_rounded, color: K9.orange),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Głos co kilometr', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Switch(
                value: _rec.voice,
                activeTrackColor: K9.orange,
                onChanged: (v) => setState(() => _rec.voice = v)),
          ]),
          const Divider(color: K9.border, height: 20),
          Row(children: [
            const Icon(Icons.water_drop_rounded, color: K9.blue),
            const SizedBox(width: 12),
            const Expanded(child: Text('Przypomnienie o wodzie', style: TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 10),
          Segmented(
            items: const ['Wył.', '10 min', '15 min', '20 min'],
            index: switch (_rec.waterEveryMin) { 10 => 1, 15 => 2, 20 => 3, _ => 0 },
            onChanged: (i) => setState(() => _rec.waterEveryMin = const [0, 10, 15, 20][i]),
          ),
        ]),
      ),
      if (!rec.isEmpty) ...[gap12, RecordsCard(records: rec)],
      const SizedBox(height: 20),
      SizedBox(
        height: 58,
        child: FilledButton.icon(
          onPressed: permError != null && checking ? null : _start,
          icon: const Icon(Icons.play_arrow_rounded, size: 30),
          label: const Text('Start', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Nagrywanie działa też przy wyłączonym ekranie. W powiadomieniach zobaczysz, że trening trwa.',
        textAlign: TextAlign.center,
        style: TextStyle(color: K9.faint, fontSize: 12),
      ),
    ]);
  }

  Widget _weatherCard() {
    if (weatherLoading) {
      return const K9Card(
        child: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: K9.orange)),
          SizedBox(width: 12),
          Text('Sprawdzam pogodę…', style: TextStyle(color: K9.muted)),
        ]),
      );
    }
    final w = weather;
    if (w == null) {
      return const K9Card(
        child: Row(children: [
          Icon(Icons.cloud_off_rounded, color: K9.muted),
          SizedBox(width: 12),
          Expanded(
            child: Text('Brak danych o pogodzie. Przy ponad 15°C biegnij krócej i zabierz wodę.',
                style: TextStyle(color: K9.muted, fontSize: 13)),
          ),
        ]),
      );
    }
    final c = switch (w.risk) { 2 => K9.red, 1 => K9.yellow, _ => K9.green };
    return K9Card(
      gradient: LinearGradient(colors: [K9.card, c.withValues(alpha: 0.18)]),
      child: Row(children: [
        IconBadge(w.risk == 0 ? Icons.wb_sunny_rounded : Icons.thermostat_rounded, c),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${fmtNum(w.temp)}°C · odczuwalna ${fmtNum(w.feels)}°C · wilg. ${w.humidity}%',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(w.advice, style: TextStyle(color: c, fontSize: 12.5)),
          ]),
        ),
      ]),
    );
  }

  Widget _live() {
    final paused = _rec.state == RecState.paused;
    final speed = _rec.currentSpeedKmh;
    Widget big(String label, String value, {String? unit, bool hero = false}) => Column(children: [
          FittedBox(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: value,
                  style: TextStyle(
                      fontSize: hero ? 54 : 30,
                      fontWeight: FontWeight.w800,
                      color: hero ? K9.orange : K9.text,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              if (unit != null) TextSpan(text: ' $unit', style: const TextStyle(fontSize: 14, color: K9.muted)),
            ])),
          ),
          Text(label, style: const TextStyle(color: K9.muted, fontSize: 12)),
        ]);
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), children: [
          if (paused)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Center(child: Pill(icon: Icons.pause_rounded, text: 'Pauza')),
            ),
          if (_rec.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Center(child: Pill(icon: Icons.gps_off_rounded, text: _rec.error!)),
            ),
          K9Card(
            child: Column(children: [
              big('Dystans', fmtKm(_rec.meters / 1000), unit: 'km', hero: true),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: big('Czas', fmtClock(_rec.seconds))),
                Expanded(child: big('Tempo śr.', fmtPace(_rec.avgPace), unit: '/km')),
                Expanded(child: big('Prędkość', speed == null ? '–' : fmtNum(speed), unit: 'km/h')),
              ]),
              if (_rec.laps.isNotEmpty) ...[
                const Divider(color: K9.border, height: 24),
                Text(
                    'Okrążenie ${_rec.laps.length + 1}: ${fmtClock(_rec.lapSeconds)} · ${fmtKm(_rec.lapMeters / 1000)} km',
                    style: const TextStyle(color: K9.muted, fontWeight: FontWeight.w600)),
              ],
            ]),
          ),
          gap12,
          _map(height: 300),
        ]),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _roundBtn(Icons.flag_rounded, 'Okrążenie', K9.cardHi, K9.text, _rec.lap),
          _roundBtn(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, paused ? 'Wznów' : 'Pauza', K9.orange,
              Colors.black, paused ? _rec.resume : _rec.pause,
              size: 80),
          _roundBtn(Icons.stop_rounded, 'Stop', K9.red, Colors.white, _stop),
        ]),
      ),
    ]);
  }

  Widget _roundBtn(IconData icon, String label, Color bg, Color fg, VoidCallback on, {double size = 62}) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: on,
            child: SizedBox(width: size, height: size, child: Icon(icon, color: fg, size: size * 0.48)),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: K9.muted, fontSize: 12)),
      ]);
}

/// Karta rekordów dyscypliny.
class RecordsCard extends StatelessWidget {
  final Records records;
  const RecordsCard({super.key, required this.records});

  @override
  Widget build(BuildContext context) {
    Widget item(String label, String value, TrainingSession? t) => Expanded(
          child: Column(children: [
            FittedBox(
              child: Text(value,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: K9.yellow)),
            ),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: K9.muted, fontSize: 11.5)),
            if (t != null) Text(fmtDateShort(t.date), style: const TextStyle(color: K9.faint, fontSize: 10.5)),
          ]),
        );
    final r = records;
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.military_tech_rounded, color: K9.yellow, size: 20),
          SizedBox(width: 8),
          Text('Rekordy', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          item('Najszybszy km', r.bestKm == null ? '–' : '${fmtPace(r.bestKm!.bestKmSec!.toDouble())}/km', r.bestKm),
          item('Najdłuższa trasa', r.longest == null ? '–' : '${fmtKm(r.longest!.distanceKm!)} km', r.longest),
          item('Tempo na 5 km+', r.best5k == null ? '–' : '${fmtPace(Records.avgPace(r.best5k!)!)}/km', r.best5k),
        ]),
      ]),
    );
  }
}
