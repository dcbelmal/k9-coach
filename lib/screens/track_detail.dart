import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../files/file_store.dart';
import '../gps/records.dart';
import '../gps/track.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'forms.dart';
import 'gps_screen.dart';

/// Otwiera trening: z trasą GPS – podsumowanie, bez trasy – formularz.
void openTraining(BuildContext context, TrainingSession t) {
  if (t.hasTrack) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrackDetailScreen(training: t)));
  } else {
    openTrainingForm(context, existing: t);
  }
}

class TrackDetailScreen extends StatefulWidget {
  final TrainingSession training;
  final Track? track;
  final List<String> newRecords;
  final bool fresh;
  final int goalMin;
  const TrackDetailScreen({
    super.key,
    required this.training,
    this.track,
    this.newRecords = const [],
    this.fresh = false,
    this.goalMin = 0,
  });

  @override
  State<TrackDetailScreen> createState() => _TrackDetailScreenState();
}

class _TrackDetailScreenState extends State<TrackDetailScreen> {
  Track? track;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    track = widget.track;
    if (track != null) {
      loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final ref = widget.training.trackRef;
    Track? t;
    if (ref != null) {
      try {
        final txt = await FileStore.readText(ref);
        if (txt != null) t = Track.decode(txt);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        track = t;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final t = s.trainings.where((e) => e.id == widget.training.id).firstOrNull ?? widget.training;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Icon(t.discipline.icon, color: K9.orange),
                const SizedBox(width: 10),
                Flexible(child: Text(t.discipline.label)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Edytuj',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => openTrainingForm(context, existing: t),
              ),
              IconButton(
                tooltip: 'Usuń',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (await confirmDelete(context, 'ten trening')) {
                    await s.deleteTraining(t);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: _body(t),
        );
      },
    );
  }

  Widget _body(TrainingSession t) {
    final tr = track;
    final splits = tr?.splits() ?? const <KmSplit>[];
    final moving = (t.movingSec ?? t.durationMin * 60).toDouble();
    final km = t.distanceKm ?? 0;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        Text('${fmtDate(t.date)}, ${fmtTime(t.date)}', style: const TextStyle(color: K9.muted)),
        if (t.notes.isNotEmpty) ...[const SizedBox(height: 4), Text(t.notes)],
        gap12,
        if (widget.newRecords.isNotEmpty) ...[
          FadeSlideIn(
            index: 0,
            child: K9Card(
              gradient: LinearGradient(colors: [K9.card, K9.yellow.withValues(alpha: 0.22)]),
              child: Row(
                children: [
                  const IconBadge(Icons.military_tech_rounded, K9.yellow),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Nowy rekord!', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(widget.newRecords.join(' · '), style: const TextStyle(color: K9.yellow, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          gap12,
        ],
        if (widget.fresh && widget.goalMin > 0) ...[
          FadeSlideIn(
            index: 0,
            child: Builder(
              builder: (context) {
                final ok = moving >= widget.goalMin * 60;
                final c = ok ? K9.green : K9.yellow;
                return K9Card(
                  gradient: LinearGradient(colors: [K9.card, c.withValues(alpha: 0.2)]),
                  child: Row(
                    children: [
                      IconBadge(ok ? Icons.check_circle_rounded : Icons.timelapse_rounded, c),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ok ? 'Założenia wykonane!' : 'Prawie się udało',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            Text(
                              ok
                                  ? 'Cel ${widget.goalMin} min – trening trwał ${fmtClock(moving)}.'
                                  : 'Zrobione ${fmtClock(moving)} z ${widget.goalMin} min.',
                              style: TextStyle(color: c, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          gap12,
        ],
        if (!t.hasTrack)
          const SizedBox()
        else if (loading)
          const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator(color: K9.orange)),
          )
        else if (tr != null && tr.points.length > 1)
          _RouteMap(track: tr)
        else
          const K9Card(
            child: Text('Nie udało się wczytać trasy.', style: TextStyle(color: K9.muted)),
          ),
        gap12,
        if (!t.hasTrack)
          K9Card(
            child: Row(
              children: [
                Expanded(
                  child: StatValue(label: 'Czas', value: fmtClock(moving)),
                ),
                Expanded(
                  child: StatValue(label: 'RPE', value: '${t.rpe}'),
                ),
                Expanded(
                  child: StatValue(label: 'Dyscyplina', value: t.discipline.label),
                ),
              ],
            ),
          )
        else
          K9Card(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: StatValue(label: 'Dystans', value: fmtKm(km), unit: 'km'),
                    ),
                    Expanded(
                      child: StatValue(label: 'Czas ruchu', value: fmtClock(moving)),
                    ),
                    Expanded(
                      child: StatValue(label: 'Tempo śr.', value: km > 0 ? fmtPace(moving / km) : '–', unit: '/km'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: StatValue(
                        label: 'Prędkość śr.',
                        value: moving > 0 ? fmtNum(km / moving * 3600) : '–',
                        unit: 'km/h',
                      ),
                    ),
                    Expanded(
                      child: StatValue(
                        label: 'Maks.',
                        value: t.maxSpeedKmh == null ? '–' : fmtNum(t.maxSpeedKmh!),
                        unit: 'km/h',
                      ),
                    ),
                    Expanded(
                      child: StatValue(
                        label: 'Najszybszy km',
                        value: t.bestKmSec == null ? '–' : fmtPace(t.bestKmSec!.toDouble()),
                        unit: '/km',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (widget.fresh) ...[
          gap12,
          K9Card(
            onTap: () => openTrainingForm(context, existing: t),
            child: const Row(
              children: [
                Icon(Icons.tune_rounded, color: K9.orange),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Oceń zmęczenie (RPE) i dodaj notatkę', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right_rounded, color: K9.orange),
              ],
            ),
          ),
        ],
        if (tr != null) ...[
          if (tr.speedSeries().length > 2) ...[
            gap16,
            const SectionTitle('Prędkość', icon: Icons.show_chart_rounded),
            K9Card(
              child: SizedBox(height: 170, child: _SpeedChart(track: tr)),
            ),
          ],
          if (splits.isNotEmpty) ...[
            gap16,
            const SectionTitle('Kilometry', icon: Icons.straighten_rounded),
            K9Card(child: _Splits(splits: splits)),
          ],
          if (tr.laps.isNotEmpty) ...[
            gap16,
            const SectionTitle('Okrążenia', icon: Icons.flag_rounded),
            K9Card(
              child: Column(
                children: [
                  for (var i = 0; i < tr.laps.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            '${i + 1}.',
                            style: const TextStyle(color: K9.muted, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(fmtClock(tr.laps[i] - (i == 0 ? 0 : tr.laps[i - 1])))),
                          Text('po ${fmtClock(tr.laps[i])}', style: const TextStyle(color: K9.faint, fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
        if (t.hasTrack) ...[gap16, RecordsCard(records: Records.of(AppStore.instance.trainings, t.discipline))],
      ],
    );
  }
}

class _RouteMap extends StatelessWidget {
  final Track track;
  const _RouteMap({required this.track});

  @override
  Widget build(BuildContext context) {
    final pts = track.points.map((p) => p.ll).toList();
    Marker dot(LatLng p, Color c) => Marker(
      point: p,
      width: 16,
      height: 16,
      child: Container(
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(K9.radius),
      child: SizedBox(
        height: 260,
        child: FlutterMap(
          options: MapOptions(
            initialCameraFit: CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(28), maxZoom: 17),
            backgroundColor: K9.cardHi,
          ),
          children: [
            osmTiles(),
            PolylineLayer(
              polylines: [
                for (final s in track.segments)
                  if (s.length > 1)
                    Polyline(
                      points: [for (final q in s) q.ll],
                      strokeWidth: 5,
                      color: K9.orange,
                      borderStrokeWidth: 1.5,
                      borderColor: Colors.black54,
                    ),
              ],
            ),
            MarkerLayer(markers: [dot(pts.first, K9.green), dot(pts.last, K9.red)]),
            const OsmCredit(),
          ],
        ),
      ),
    );
  }
}

class _SpeedChart extends StatelessWidget {
  final Track track;
  const _SpeedChart({required this.track});

  @override
  Widget build(BuildContext context) {
    final s = track.speedSeries();
    final maxY = s.map((e) => e.$2).reduce(math.max);
    final maxX = s.last.$1;
    final avg = s.map((e) => e.$2).reduce((a, b) => a + b) / s.length;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: (maxY * 1.15).ceilToDouble(),
        minX: 0,
        maxX: maxX,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: math.max(1, (maxY / 3).roundToDouble()),
          getDrawingHorizontalLine: (_) => const FlLine(color: K9.border, strokeWidth: 1, dashArray: [4, 4]),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: avg,
              color: K9.yellow.withValues(alpha: 0.7),
              strokeWidth: 1.2,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: const TextStyle(color: K9.yellow, fontSize: 10),
                labelResolver: (_) => 'śr. ${fmtNum(avg)}',
              ),
            ),
          ],
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: math.max(1, (maxY / 3).roundToDouble()),
              getTitlesWidget: (v, m) =>
                  Text(v.toInt().toString(), style: const TextStyle(color: K9.faint, fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: math.max(60, (maxX / 4 / 60).ceil() * 60).toDouble(),
              getTitlesWidget: (v, m) => v == 0 || v >= maxX
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
                LineTooltipItem(
                  '${fmtNum(p.y)} km/h\n${fmtClock(p.x)}',
                  const TextStyle(color: K9.text, fontWeight: FontWeight.w600, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (final e in s) FlSpot(e.$1, e.$2)],
            isCurved: true,
            preventCurveOverShooting: true,
            barWidth: 2.5,
            color: K9.orange,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [K9.orange.withValues(alpha: 0.35), K9.orange.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Splits extends StatelessWidget {
  final List<KmSplit> splits;
  const _Splits({required this.splits});

  @override
  Widget build(BuildContext context) {
    final paces = splits.map((s) => s.paceSecPerKm).toList();
    final full = splits.where((s) => s.meters >= 1000).map((s) => s.paceSecPerKm);
    final best = full.isEmpty ? null : full.reduce(math.min);
    final fastest = paces.reduce(math.min);
    return Column(
      children: [
        const Row(
          children: [
            SizedBox(
              width: 34,
              child: Text('km', style: TextStyle(color: K9.faint, fontSize: 11.5)),
            ),
            Expanded(
              child: Text('tempo', style: TextStyle(color: K9.faint, fontSize: 11.5)),
            ),
            Text('czas', style: TextStyle(color: K9.faint, fontSize: 11.5)),
          ],
        ),
        const SizedBox(height: 6),
        for (final (i, s) in splits.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    s.meters >= 1000 ? '${s.km}' : fmtKm(s.meters / 1000),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (c, bc) {
                      // Szybszy km = dłuższy pasek.
                      final f = paces[i] <= 0 ? 0.15 : ((fastest / paces[i] - 0.6) / 0.4).clamp(0.15, 1.0);
                      final isBest = best != null && s.meters >= 1000 && s.paceSecPerKm == best;
                      return Row(
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: f),
                            duration: Duration(milliseconds: 500 + i * 60),
                            curve: Curves.easeOutCubic,
                            builder: (c, v, _) => Container(
                              height: 18,
                              width: (bc.maxWidth - 64) * v,
                              decoration: BoxDecoration(
                                color: isBest ? K9.yellow : K9.orange.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            fmtPace(s.paceSecPerKm),
                            style: TextStyle(fontWeight: FontWeight.w700, color: isBest ? K9.yellow : K9.text),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Text(fmtClock(s.seconds), style: const TextStyle(color: K9.muted)),
              ],
            ),
          ),
      ],
    );
  }
}
