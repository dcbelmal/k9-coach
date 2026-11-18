import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../gps/gps_drafts.dart';
import '../gps/online_services.dart';
import '../gps/recorder.dart';
import '../storage/safe_prefs.dart';
import 'forms.dart';
import '../gps/records.dart';
import '../gps/track.dart';
import '../gps/weather.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'track_detail.dart';
import '../l10n/l10n.dart';

final _rec = TrackRecorder.instance;

Future<void> openGps(BuildContext context, {Discipline? discipline, TrainingSession? plan}) =>
    openGpsWith(Navigator.of(context), discipline: discipline, plan: plan);

Future<void> openGpsWith(NavigatorState nav, {Discipline? discipline, TrainingSession? plan}) {
  if (_rec.state == RecState.idle) {
    _rec.plan = plan;
    if (plan != null) {
      _rec.discipline = plan.discipline;
      _rec.targetMin = plan.durationMin;
      _rec.targetKm = plan.discipline.hasDistance ? plan.distanceKm : null;
    } else {
      if (discipline != null) _rec.discipline = discipline;
      _rec.targetMin = 0;
      _rec.targetKm = null;
    }
  }
  return nav.push(MaterialPageRoute(builder: (_) => const GpsScreen()));
}

/// Mapa OpenStreetMap (bez klucza i opłat) – kafle tylko po zgodzie użytkownika.
Widget osmTiles() => mapTiles();

/// Podpis źródła mapy (wymagany przez OpenStreetMap).
class OsmCredit extends StatelessWidget {
  const OsmCredit({super.key});
  @override
  Widget build(BuildContext context) => OnlineConsent.instance.map != true ? const SizedBox.shrink() : Align(
    alignment: Alignment.bottomRight,
    child: Container(
      margin: const EdgeInsets.all(6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
      child: Text(tr('© OpenStreetMap'), style: TextStyle(color: Colors.white70, fontSize: 9.5)),
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
  bool weatherLoading = false;

  /// Użytkownik wybrał trening bez GPS (np. po odmowie dostępu do lokalizacji).
  bool noGps = false;

  @override
  void initState() {
    super.initState();
    _rec.addListener(_onRec);
    OnlineConsent.instance.addListener(_onConsent);
    _prepare();
  }

  @override
  void dispose() {
    _rec.removeListener(_onRec);
    OnlineConsent.instance.removeListener(_onConsent);
    super.dispose();
  }

  void _onConsent() {
    if (mounted) setState(() {});
  }

  void _onRec() {
    if (!mounted) return;
    final p = _rec.last;
    if (follow && mapReady && p != null) {
      map.move(LatLng(p.latitude, p.longitude), map.camera.zoom < 14 ? 16 : map.camera.zoom);
    }
  }

  /// Otwarcie ekranu: tylko sprawdzenie stanu uprawnień – bez pytania o zgodę,
  /// bez pobierania pozycji i bez żadnych żądań do sieci, dopóki użytkownik
  /// nie wybierze pogody lub mapy online albo nie naciśnie Start.
  Future<void> _prepare() async {
    var granted = false;
    try {
      if (!kIsWeb && await GpsServices.serviceEnabled()) {
        final p = await GpsServices.checkPermission();
        granted = p == LocationPermission.whileInUse || p == LocationPermission.always;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => checking = false);
    final c = OnlineConsent.instance;
    if (granted && (c.weather == true || c.map == true)) await _locate();
  }

  /// Pozycja na mapie i pogoda – wyłącznie po zgodzie użytkownika.
  Future<void> _locate() async {
    final c = OnlineConsent.instance;
    if (c.weather == true) setState(() => weatherLoading = true);
    final p = await GpsServices.position();
    if (!mounted) return;
    if (p != null) {
      setState(() => here = LatLng(p.latitude, p.longitude));
      if (mapReady) map.move(here!, 15);
      if (c.weather == true) {
        final w = await GpsServices.weather(p.latitude, p.longitude);
        if (mounted) setState(() => weather = w);
      }
    }
    if (mounted) setState(() => weatherLoading = false);
  }

  Future<void> _setConsent({bool? weatherOn, bool? mapOn}) async {
    try {
      await OnlineConsent.instance.set(weather: weatherOn, map: mapOn);
    } catch (e) {
      if (mounted) toast(context, storageErrorMessage(e));
      return;
    }
    if (weatherOn == false) setState(() => weather = null);
    if (weatherOn == true || mapOn == true) {
      final err = await TrackRecorder.ensurePermission();
      if (!mounted) return;
      setState(() => permError = err);
      if (err == null) await _locate();
    }
  }

  Future<void> _start() async {
    _rec.useGps = _rec.discipline.hasDistance && !noGps;
    if (_rec.useGps) {
      final err = await TrackRecorder.ensurePermission();
      if (err != null) {
        setState(() => permError = err);
        return;
      }
    }
    if (!mounted) return;
    if (weather != null && weather!.risk == 2 && _rec.discipline.hasDistance) {
      final go = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('Za gorąco')),
          content: Text(tr('{0}°C, odczuwalna {1}°C.\n\n{2}', [fmtNum(weather!.temp), fmtNum(weather!.feels), weather!.advice])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Rezygnuję'))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Startuję mimo to'))),
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
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(c).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitle(tr('Zakończyć trening?')),
              FilledButton(onPressed: () => Navigator.pop(c, 1), child: Text(tr('Zakończ i zapisz'))),
              const SizedBox(height: 10),
              OutlinedButton(onPressed: () => Navigator.pop(c, 0), child: Text(tr('Wróć do treningu'))),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(c, 2),
                child: Text(tr('Odrzuć bez zapisywania'), style: TextStyle(color: K9.red)),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == 2) {
      await _rec.discard();
      if (mounted) Navigator.pop(context);
    }
    if (choice != 1) return;
    final gps = _rec.useGps;
    final goalMin = _rec.targetMin;
    final track = await _rec.stop();
    await _rec.flushDrafts();
    final draft = _rec.draft();
    final recs = gps ? Records.newRecords(AppStore.instance.trainings, draft.toTraining()) : <String>[];
    // Zapis do historii psa, dla którego trening rozpoczęto. Ponowienie po błędzie
    // nie tworzy drugiego treningu ani drugiej trasy (stałe ID).
    TrainingSession? t;
    while (t == null) {
      try {
        t = await GpsDrafts.finalize(draft);
      } catch (e) {
        if (!mounted) return;
        final again = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(tr('Nie udało się zapisać treningu')),
            content: Text('${storageErrorMessage(e)}\n\n${tr('Trening jest zachowany w szkicu. Możesz spróbować teraz albo odzyskać go po ponownym uruchomieniu aplikacji.')}'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Później'))),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Spróbuj ponownie'))),
            ],
          ),
        );
        if (again != true) {
          _rec.plan = null;
          if (mounted) Navigator.pop(context);
          return;
        }
      }
    }
    _rec.sessionId = null;
    _rec.plan = null;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TrackDetailScreen(
          training: t!,
          track: gps ? track : null,
          newRecords: recs,
          fresh: true,
          goalMin: goalMin,
        ),
      ),
    );
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
            if (!did) toast(context, tr('Trening trwa. Zakończ go przyciskiem Stop.'));
          },
          child: Scaffold(
            appBar: AppBar(title: Text(idle ? tr('Start treningu') : _rec.discipline.label), automaticallyImplyLeading: idle),
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
        child: Stack(
          children: [
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
                PolylineLayer(
                  polylines: [
                    for (final s in _rec.segments)
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
          ],
        ),
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
    final discs = Discipline.values;
    final gps = _rec.discipline.hasDistance && !noGps;
    final plan = _rec.plan;
    final goals = {0, 15, 20, 30, 45, 60, if (_rec.targetMin > 0) _rec.targetMin}.toList()..sort();
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
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        if (plan != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: K9Card(
              gradient: LinearGradient(colors: [K9.card, plan.discipline.color.withValues(alpha: 0.25)]),
              child: Row(
                children: [
                  IconBadge(Icons.event_available_rounded, plan.discipline.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('Z planu: {0}{1}', [plan.discipline.label, plan.notes.isEmpty ? '' : ' – ${plan.notes}']),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          [
                            'cel ${plan.durationMin} min',
                            if (gps && plan.distanceKm != null) '${fmtKm(plan.distanceKm!)} km',
                          ].join(' · '),
                          style: const TextStyle(color: K9.muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (permError != null && _rec.discipline.hasDistance)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: K9Card(
              color: K9.cardHi,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_off_rounded, color: K9.yellow),
                      const SizedBox(width: 10),
                      Expanded(child: Text(permError!, style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (!checking && !kIsWeb)
                        TextButton(onPressed: () => Geolocator.openAppSettings(), child: Text(tr('Ustawienia'))),
                      TextButton(
                        onPressed: () => setState(() {
                          noGps = true;
                          permError = null;
                        }),
                        child: Text(tr('Trening bez GPS (tylko czas)')),
                      ),
                      TextButton(
                        onPressed: () {
                          final nav = Navigator.of(context);
                          final d = _rec.discipline;
                          nav.pop();
                          openTrainingForm(nav.context, discipline: d);
                        },
                        child: Text(tr('Wpisz trening ręcznie')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (gps) ...[_onlineCard(), gap12],
        if (gps) ...[_map(height: 200), gap16],
        SectionTitle(tr('Dyscyplina')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final d in discs) chip(d.label, _rec.discipline == d, () => _rec.discipline = d)],
        ),
        const SizedBox(height: 10),
        Text(_rec.discipline.description, style: const TextStyle(color: K9.muted, fontSize: 12.5)),
        if (!gps)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              noGps && _rec.discipline.hasDistance
                  ? tr('Trening bez GPS – liczę tylko czas. Trasa nie zostanie zapisana.')
                  : tr('Bez GPS – liczę tylko czas treningu.'),
              style: TextStyle(color: K9.yellow, fontSize: 12.5),
            ),
          ),
        gap16,
        SectionTitle(tr('Cel czasu')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in goals)
              chip(g == 0 ? tr('Bez celu') : tr('{0} min', [g]), _rec.targetMin == g, () => _rec.targetMin = g),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          tr('Gdy minie założony czas, usłyszysz komunikat i dostaniesz powiadomienie.'),
          style: TextStyle(color: K9.faint, fontSize: 12),
        ),
        gap16,
        if (gps && OnlineConsent.instance.weather == true) ...[_weatherCard(), gap12],
        K9Card(
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.record_voice_over_rounded, color: K9.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(tr('Komunikaty głosowe'), style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Switch(
                    value: _rec.voice,
                    activeTrackColor: K9.orange,
                    onChanged: (v) => setState(() => _rec.voice = v),
                  ),
                ],
              ),
              const Divider(color: K9.border, height: 20),
              Row(
                children: [
                  const Icon(Icons.water_drop_rounded, color: K9.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(tr('Przypomnienie o wodzie'), style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Segmented(
                items: [tr('Wył.'), tr('10 min'), tr('15 min'), tr('20 min')],
                index: switch (_rec.waterEveryMin) {
                  10 => 1,
                  15 => 2,
                  20 => 3,
                  _ => 0,
                },
                onChanged: (i) => setState(() => _rec.waterEveryMin = const [0, 10, 15, 20][i]),
              ),
            ],
          ),
        ),
        if (gps && !rec.isEmpty) ...[gap12, RecordsCard(records: rec)],
        const SizedBox(height: 20),
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.play_arrow_rounded, size: 30),
            label: Text(tr('Start'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          tr('Działa też przy wyłączonym ekranie. Na ekranie blokady zobaczysz powiadomienie z czasem treningu.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: K9.faint, fontSize: 12),
        ),
      ],
    );
  }

  /// Wybór usług online. Bez zgody nagrywanie działa lokalnie, a do sieci nie
  /// trafiają współrzędne ani obszar mapy.
  Widget _onlineCard() {
    final c = OnlineConsent.instance;
    return K9Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.privacy_tip_outlined, color: K9.blue),
              const SizedBox(width: 10),
              Expanded(child: Text(tr('Usługi online (opcjonalne)'), style: TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr('Trasa nagrywa się tylko w telefonie. Pogoda i mapa wymagają internetu: serwis pogodowy Open-Meteo otrzyma przybliżone współrzędne (ok. 100 m), a dostawca mapy OpenStreetMap pozna oglądany obszar. Obie usługi widzą też adres IP telefonu.'),
            style: const TextStyle(color: K9.muted, fontSize: 12.5),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: c.weather == true,
            activeTrackColor: K9.orange,
            onChanged: (v) => _setConsent(weatherOn: v),
            title: Text(tr('Pogoda online'), style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr('Ostrzeżenie przed upałem przed biegiem'), style: TextStyle(color: K9.muted, fontSize: 12)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: c.map == true,
            activeTrackColor: K9.orange,
            onChanged: (v) => _setConsent(mapOn: v),
            title: Text(tr('Mapa online'), style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr('Bez mapy trasa jest rysowana na pustym tle'), style: TextStyle(color: K9.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _weatherCard() {
    if (weatherLoading) {
      return K9Card(
        child: Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: K9.orange)),
            SizedBox(width: 12),
            Text(tr('Sprawdzam pogodę…'), style: TextStyle(color: K9.muted)),
          ],
        ),
      );
    }
    final w = weather;
    if (w == null) {
      return K9Card(
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: K9.muted),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                tr('Brak danych o pogodzie. Przy ponad 15°C biegnij krócej i zabierz wodę.'),
                style: TextStyle(color: K9.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    final c = switch (w.risk) {
      2 => K9.red,
      1 => K9.yellow,
      _ => K9.green,
    };
    return K9Card(
      gradient: LinearGradient(colors: [K9.card, c.withValues(alpha: 0.18)]),
      child: Row(
        children: [
          IconBadge(w.risk == 0 ? Icons.wb_sunny_rounded : Icons.thermostat_rounded, c),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('{0}°C · odczuwalna {1}°C · wilg. {2}%', [fmtNum(w.temp), fmtNum(w.feels), w.humidity]),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(w.advice, style: TextStyle(color: c, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _live() {
    final paused = _rec.state == RecState.paused;
    final speed = _rec.currentSpeedKmh;
    final gps = _rec.useGps;
    final goal = _rec.targetMin * 60.0;
    Widget big(String label, String value, {String? unit, bool hero = false}) => Column(
      children: [
        FittedBox(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: hero ? 54 : 30,
                    fontWeight: FontWeight.w800,
                    color: hero ? K9.orange : K9.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(fontSize: 14, color: K9.muted),
                  ),
              ],
            ),
          ),
        ),
        Text(label, style: const TextStyle(color: K9.muted, fontSize: 12)),
      ],
    );
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              if (paused)
                Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Center(
                    child: Pill(icon: Icons.pause_rounded, text: tr('Pauza')),
                  ),
                ),
              if (_rec.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Center(
                    child: Pill(icon: Icons.gps_off_rounded, text: _rec.error!),
                  ),
                ),
              K9Card(
                child: Column(
                  children: [
                    if (gps) ...[
                      big(tr('Dystans'), fmtKm(_rec.meters / 1000), unit: 'km', hero: true),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: big(tr('Czas'), fmtClock(_rec.seconds))),
                          Expanded(child: big(tr('Tempo śr.'), fmtPace(_rec.avgPace), unit: '/km')),
                          Expanded(child: big(tr('Prędkość'), speed == null ? '–' : fmtNum(speed), unit: 'km/h')),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      big(tr('Czas treningu'), fmtClock(_rec.seconds), hero: true),
                      const SizedBox(height: 12),
                    ],
                    if (goal > 0) ...[
                      const Divider(color: K9.border, height: 24),
                      Row(
                        children: [
                          Icon(
                            _rec.targetTimeDone ? Icons.check_circle_rounded : Icons.flag_circle_rounded,
                            color: _rec.targetTimeDone ? K9.green : K9.orange,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _rec.targetTimeDone
                                  ? tr('Cel {0} min osiągnięty!', [_rec.targetMin])
                                  : tr('Cel {0} min · zostało {1}', [_rec.targetMin, fmtClock(goal - _rec.seconds)]),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _rec.targetTimeDone ? K9.green : K9.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (_rec.seconds / goal).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: K9.cardHi,
                          color: _rec.targetTimeDone ? K9.green : K9.orange,
                        ),
                      ),
                    ],
                    if (_rec.laps.isNotEmpty) ...[
                      const Divider(color: K9.border, height: 24),
                      Text(
                        tr('Okrążenie {0}: {1} · {2} km', [_rec.laps.length + 1, fmtClock(_rec.lapSeconds), fmtKm(_rec.lapMeters / 1000)]),
                        style: const TextStyle(color: K9.muted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              if (gps) ...[gap12, _map(height: 300)],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _roundBtn(Icons.flag_rounded, gps ? tr('Okrążenie') : tr('Runda'), K9.cardHi, K9.text, _rec.lap),
              _roundBtn(
                paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                paused ? tr('Wznów') : tr('Pauza'),
                K9.orange,
                Colors.black,
                paused ? _rec.resume : _rec.pause,
                size: 80,
              ),
              _roundBtn(Icons.stop_rounded, tr('Stop'), K9.red, Colors.white, _stop),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roundBtn(IconData icon, String label, Color bg, Color fg, VoidCallback on, {double size = 62}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: on,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: fg, size: size * 0.48),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: K9.muted, fontSize: 12)),
    ],
  );
}

/// Karta rekordów dyscypliny.
class RecordsCard extends StatelessWidget {
  final Records records;
  const RecordsCard({super.key, required this.records});

  @override
  Widget build(BuildContext context) {
    Widget item(String label, String value, TrainingSession? t) => Expanded(
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: K9.yellow),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: K9.muted, fontSize: 11.5),
          ),
          if (t != null) Text(fmtDateShort(t.date), style: const TextStyle(color: K9.faint, fontSize: 10.5)),
        ],
      ),
    );
    final r = records;
    return K9Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.military_tech_rounded, color: K9.yellow, size: 20),
              SizedBox(width: 8),
              Text(tr('Rekordy'), style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              item(
                tr('Najszybszy km'),
                r.bestKm == null ? '–' : tr('{0}/km', [fmtPace(r.bestKm!.bestKmSec!.toDouble())]),
                r.bestKm,
              ),
              item(tr('Najdłuższa trasa'), r.longest == null ? '–' : tr('{0} km', [fmtKm(r.longest!.distanceKm!)]), r.longest),
              item(tr('Tempo na 5 km+'), r.best5k == null ? '–' : tr('{0}/km', [fmtPace(Records.avgPace(r.best5k!)!)]), r.best5k),
            ],
          ),
        ],
      ),
    );
  }
}
