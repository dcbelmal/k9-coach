import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../files/file_store.dart';
import '../gps/dog_stats.dart';
import '../gps/track.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'gps_screen.dart' show osmTiles, OsmCredit;

/// Kolory mapy intensywności psa (stęp/postój, kłus, galop, sprint).
const intensityColors = [Color(0xFF4FA3FF), Color(0xFF34C759), Color(0xFFFF9F0A), Color(0xFFFF453A)];

/// Trasa psa pokolorowana według prędkości (mapa intensywności).
List<Polyline> dogIntensityPolylines(Track t) => [
      for (final l in dogLegs(t))
        Polyline(
          points: [l.a.ll, l.b.ll],
          strokeWidth: 4,
          color: intensityColors[intensityBand(l.speedMs)],
          borderStrokeWidth: 1,
          borderColor: Colors.black54,
        ),
    ];

String _m(double? m) => m == null ? '–' : (m >= 1000 ? '${fmtKm(m / 1000)} km' : '${m.round()} m');
String _kmh(double? v) => v == null ? '–' : fmtNum(v * 3.6);

/// Karta „Trasa psa”: dystanse, prędkości, odległość od przewodnika,
/// aktywność, wiarygodność danych i legenda mapy intensywności.
class DogStatsCard extends StatelessWidget {
  final Track track;
  const DogStatsCard({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final s = DogStats.of(track);
    final ratio = s.ratio;
    Widget cell(String label, String value, [String? unit]) => Expanded(
          child: StatValue(label: label, value: value, unit: unit),
        );
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.pets_rounded, color: K9.blue, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Trasa psa z obroży GPS'), style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: StatValue(label: tr('Pies'), value: fmtKm(s.dogMeters / 1000), unit: 'km', color: K9.blue)),
          cell(tr('Ty'), fmtKm(s.handlerMeters / 1000), 'km'),
          cell(tr('Pies / Ty'), ratio == null ? '–' : '× ${fmtNum(ratio)}'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          cell(tr('Śr. prędkość psa'), _kmh(s.avgSpeedMs), 'km/h'),
          cell(tr('Maks. prędkość'), _kmh(s.maxSpeedMs), 'km/h'),
          cell(tr('Aktywność'), s.activeSec + s.restSec <= 0 ? '–' : '${(s.activeSec / (s.activeSec + s.restSec) * 100).round()}%'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          cell(tr('Śr. od Ciebie'), _m(s.avgFromHandlerM)),
          cell(tr('Najdalej'), _m(s.maxFromHandlerM)),
          cell(tr('Ruch / odpoczynek'), '${fmtClock(s.activeSec)} / ${fmtClock(s.restSec)}'),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 4, children: [
          for (final (i, l) in [tr('stęp'), tr('kłus'), tr('galop'), tr('sprint')].indexed)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 14, height: 4, color: intensityColors[i]),
              const SizedBox(width: 4),
              Text(l, style: const TextStyle(color: K9.muted, fontSize: 11.5)),
            ]),
        ]),
        if (!s.reliable) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline_rounded, size: 16, color: K9.yellow),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${tr('Statystyki psa orientacyjne:')} ${s.issues.map(_issue).join(' ')}',
                style: const TextStyle(color: K9.yellow, fontSize: 12),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 8),
        Text(
          s.medianIntervalSec == null
              ? tr('Na mapie: pomarańczowa linia – Twoja trasa, kolorowa – trasa psa według prędkości.')
              : tr('Na mapie: pomarańczowa linia – Twoja trasa, kolorowa – trasa psa według prędkości. Pomiar psa co ~{0} s.',
                  [s.medianIntervalSec!.round()]),
          style: const TextStyle(color: K9.muted, fontSize: 12),
        ),
      ]),
    );
  }

  static String _issue(DogStatsIssue i) => switch (i) {
        DogStatsIssue.fewPoints => tr('mało pomiarów psa.'),
        DogStatsIssue.sparse => tr('pomiar rzadszy niż co 20 s – trasa uproszczona, prędkości zaniżone.'),
        DogStatsIssue.gaps => tr('pomiary obejmują mniej niż 60% treningu.'),
        DogStatsIssue.noHandler => tr('brak Twojej trasy w tych samych chwilach – odległość od Ciebie niepełna.'),
      };
}

/// Prosty wykres liniowy (prędkość psa albo odległość od przewodnika).
class DogLineChart extends StatelessWidget {
  final List<(double, double)> series;
  final Color color;
  final String Function(double y) label;
  const DogLineChart({super.key, required this.series, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(1.0, series.map((e) => e.$2).reduce(math.max));
    final minX = series.first.$1, maxX = math.max(series.last.$1, minX + 1);
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY * 1.15,
        minX: minX,
        maxX: maxX,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: K9.border, strokeWidth: 1, dashArray: [4, 4]),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (v, m) => v == m.max ? const SizedBox() : Text(label(v), style: const TextStyle(color: K9.faint, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: math.max(60, ((maxX - minX) / 4 / 60).ceil() * 60).toDouble(),
              getTitlesWidget: (v, m) => v <= minX || v >= maxX
                  ? const SizedBox()
                  : Text("${(v / 60).round()}'", style: const TextStyle(color: K9.faint, fontSize: 10)),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => K9.cardHi,
            getTooltipItems: (spots) => [
              for (final p in spots)
                LineTooltipItem('${label(p.y)}\n${fmtClock(p.x)}',
                    const TextStyle(color: K9.text, fontWeight: FontWeight.w600, fontSize: 12)),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (final e in series) FlSpot(e.$1, e.$2)],
            isCurved: true,
            preventCurveOverShooting: true,
            barWidth: 2.2,
            color: color,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.15)),
          ),
        ],
      ),
    );
  }
}

/// Wykresy psa: prędkość i odległość od przewodnika.
class DogCharts extends StatelessWidget {
  final Track track;
  const DogCharts({super.key, required this.track});

  @override
  Widget build(BuildContext context) {
    final s = DogStats.of(track);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s.speedSeries.length > 2) ...[
        SectionTitle(tr('Prędkość psa (km/h)'), icon: Icons.speed_rounded),
        K9Card(
          child: SizedBox(
            height: 150,
            child: DogLineChart(
              series: [for (final e in s.speedSeries) (e.$1, e.$2 * 3.6)],
              color: K9.blue,
              label: (y) => fmtNum(y),
            ),
          ),
        ),
      ],
      if (s.distanceSeries.length > 2) ...[
        gap16,
        SectionTitle(tr('Odległość psa od Ciebie (m)'), icon: Icons.social_distance_rounded),
        K9Card(
          child: SizedBox(
            height: 150,
            child: DogLineChart(series: s.distanceSeries, color: K9.green, label: (y) => '${y.round()}'),
          ),
        ),
      ],
    ]);
  }
}

/// Odtwarzanie treningu: pies i przewodnik na mapie w tej samej chwili.
class DogReplayCard extends StatefulWidget {
  final Track track;
  const DogReplayCard({super.key, required this.track});
  @override
  State<DogReplayCard> createState() => _DogReplayCardState();
}

class _DogReplayCardState extends State<DogReplayCard> {
  double t = 0;
  Timer? _play;
  late final double t0, t1;

  @override
  void initState() {
    super.initState();
    final all = [...widget.track.points, ...widget.track.dog].map((p) => p.t).toList();
    t0 = all.reduce(math.min);
    t1 = all.reduce(math.max);
    t = t0;
  }

  @override
  void dispose() {
    _play?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_play != null) {
      _play!.cancel();
      setState(() => _play = null);
      return;
    }
    if (t >= t1) t = t0;
    // Cały trening w ok. 30 s.
    final step = math.max(1.0, (t1 - t0) / 150);
    _play = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {
        t = math.min(t1, t + step);
        if (t >= t1) {
          _play?.cancel();
          _play = null;
        }
      });
    });
    setState(() {});
  }

  Marker _dot(LatLng p, Color c, IconData? icon) => Marker(
        point: p,
        width: 24,
        height: 24,
        child: Container(
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2.5)),
          child: icon == null ? null : Icon(icon, size: 12, color: Colors.white),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tr0 = widget.track;
    final me = positionAt(tr0.segments, t);
    final dog = positionAt(tr0.dogSegments, t, maxGapSec: 60);
    final all = [...tr0.points.map((p) => p.ll), ...tr0.dog.map((p) => p.ll)];
    final d = me == null || dog == null ? null : const Distance()(me, dog);
    return K9Card(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(K9.radius - 4),
          child: SizedBox(
            height: 220,
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: CameraFit.coordinates(coordinates: all, padding: const EdgeInsets.all(24), maxZoom: 17),
                backgroundColor: K9.cardHi,
              ),
              children: [
                osmTiles(),
                PolylineLayer(polylines: [
                  for (final s in tr0.segments)
                    if (s.length > 1) Polyline(points: [for (final q in s) q.ll], strokeWidth: 3, color: K9.orange.withValues(alpha: 0.45)),
                  for (final s in tr0.dogSegments)
                    if (s.length > 1) Polyline(points: [for (final q in s) q.ll], strokeWidth: 3, color: K9.blue.withValues(alpha: 0.45)),
                ]),
                MarkerLayer(markers: [
                  if (me != null) _dot(me, K9.orange, null),
                  if (dog != null) _dot(dog, K9.blue, Icons.pets_rounded),
                ]),
                const OsmCredit(),
              ],
            ),
          ),
        ),
        Row(children: [
          IconButton(
            tooltip: _play == null ? tr('Odtwórz') : tr('Pauza'),
            icon: Icon(_play == null ? Icons.play_arrow_rounded : Icons.pause_rounded, color: K9.orange),
            onPressed: _toggle,
          ),
          Expanded(
            child: Slider(
              value: t.clamp(t0, t1),
              min: t0,
              max: t1 <= t0 ? t0 + 1 : t1,
              activeColor: K9.orange,
              onChanged: (v) => setState(() => t = v),
            ),
          ),
        ]),
        Text(
          [
            fmtClock(t),
            if (d != null) tr('pies {0} od Ciebie', [_m(d)]),
            if (dog == null) tr('brak pomiaru psa w tej chwili'),
          ].join(' · '),
          textAlign: TextAlign.center,
          style: const TextStyle(color: K9.muted, fontSize: 12.5),
        ),
      ]),
    );
  }
}

/// Tropienie IGP: porównanie trasy psa ze śladem założonym wcześniej.
class IgpTrackingCard extends StatefulWidget {
  final TrainingSession training;
  final Track track;
  const IgpTrackingCard({super.key, required this.training, required this.track});
  @override
  State<IgpTrackingCard> createState() => _IgpTrackingCardState();
}

class _IgpTrackingCardState extends State<IgpTrackingCard> {
  TrainingSession? laidFrom;
  Track? laid;
  bool loading = false;

  /// Kandydaci na ślad: treningi z trasą z ostatnich 24 h przed tym.
  List<TrainingSession> get _candidates {
    final me = widget.training;
    return AppStore.instance.trainings
        .where((e) =>
            e.id != me.id &&
            e.hasTrack &&
            !e.date.isAfter(me.date) &&
            me.date.difference(e.date).inHours < 24)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _pick() async {
    final list = _candidates;
    final picked = await showModalBottomSheet<TrainingSession>(
      context: context,
      backgroundColor: K9.card,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          SheetTitle(tr('Który trening to założenie śladu?')),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('Brak treningu z trasą GPS z ostatnich 24 godzin. Najpierw nagraj zakładanie śladu jako osobny trening (przejdź ślad z telefonem).'),
                style: const TextStyle(color: K9.muted),
              ),
            ),
          for (final e in list)
            ListTile(
              leading: Icon(e.discipline.icon, color: K9.orange),
              title: Text(e.discipline.label),
              subtitle: Text('${fmtDate(e.date)}, ${fmtTime(e.date)}'),
              onTap: () => Navigator.pop(ctx, e),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => loading = true);
    Track? t;
    try {
      final txt = await FileStore.readText(picked.trackRef!);
      if (txt != null) t = Track.decode(txt);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      loading = false;
      laidFrom = picked;
      laid = t;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = laid;
    final a = l == null ? null : TrackingAnalysis.compare(l.points.toList(), widget.track.dog);
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.route_rounded, color: K9.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Tropienie IGP – porównanie ze śladem'), style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 8),
        if (a == null)
          Text(
            laidFrom != null && !loading
                ? tr('Nie udało się odczytać trasy śladu.')
                : tr('Wybierz trening, w którym zakładałeś ślad. Porównam go z trasą psa z obroży.'),
            style: const TextStyle(color: K9.muted, fontSize: 12.5),
          )
        else ...[
          Row(children: [
            Expanded(child: StatValue(label: tr('Śr. odchylenie'), value: '${a.avgDevM.round()}', unit: 'm')),
            Expanded(child: StatValue(label: tr('Największe'), value: '${a.maxDevM.round()}', unit: 'm')),
            Expanded(child: StatValue(label: tr('Pomiary ≤ 10 m'), value: '${(a.within10 * 100).round()}', unit: '%')),
          ]),
          const SizedBox(height: 8),
          Text(tr('Pies przeszedł przy {0}% śladu (≤ 10 m).', [(a.covered * 100).round()]),
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(K9.radius - 4),
            child: SizedBox(
              height: 200,
              child: FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.coordinates(
                    coordinates: [...l!.points.map((p) => p.ll), ...widget.track.dog.map((p) => p.ll)],
                    padding: const EdgeInsets.all(24),
                    maxZoom: 19,
                  ),
                  backgroundColor: K9.cardHi,
                ),
                children: [
                  osmTiles(),
                  PolylineLayer(polylines: [
                    for (final s in l.segments)
                      if (s.length > 1)
                        Polyline(points: [for (final q in s) q.ll], strokeWidth: 6, color: K9.yellow.withValues(alpha: 0.7)),
                    for (final s in widget.track.dogSegments)
                      if (s.length > 1) Polyline(points: [for (final q in s) q.ll], strokeWidth: 3, color: K9.blue),
                  ]),
                  const OsmCredit(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(tr('Żółta – ślad, niebieska – pies.'), style: const TextStyle(color: K9.muted, fontSize: 12)),
        ],
        const SizedBox(height: 8),
        Text(
          tr('Wynik orientacyjny: błąd GPS (kilka–kilkanaście metrów) jest podobny do ocenianych odchyleń, więc nie zastępuje oceny sędziego ani przebiegu na próbie.'),
          style: const TextStyle(color: K9.faint, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: loading ? null : _pick,
          icon: const Icon(Icons.history_rounded),
          label: Text(laidFrom == null ? tr('Wybierz założenie śladu') : tr('Zmień ślad')),
        ),
      ]),
    );
  }
}
