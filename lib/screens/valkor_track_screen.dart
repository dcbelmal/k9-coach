import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../collar/collar_link.dart';
import '../collar/dog_alerts.dart';
import '../dogs/dog_profiles.dart';
import '../gps/online_services.dart';
import '../gps/recorder.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'collar_screen.dart';
import 'dog_radar.dart';
import 'valkor_track_settings.dart';

void openValkorTrack(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ValkorTrackScreen()));

/// Kierunek kompasu po polsku (8 stron świata).
String compassLabel(double deg) {
  const k = ['PN', 'PN-WSCH', 'WSCH', 'PD-WSCH', 'PD', 'PD-ZACH', 'ZACH', 'PN-ZACH'];
  return tr(k[(((deg % 360) + 22.5) ~/ 45) % 8]);
}

/// Rodzaj mapy na ekranie Valkor Track.
enum TrackMapStyle { standard, terrain }

/// Ekran Valkor Track: pies i przewodnik na mapie, odległość, kierunek,
/// prędkość, bateria, wiek pomiaru i stan łączności (Bluetooth / LoRa / GPS).
class ValkorTrackScreen extends StatefulWidget {
  const ValkorTrackScreen({super.key});

  /// Pozycje przewodnika, gdy nie trwa trening (podmieniane w testach).
  @visibleForTesting
  static Stream<Position> Function() handlerPositions = () => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
      );

  @override
  State<ValkorTrackScreen> createState() => _ValkorTrackScreenState();
}

class _ValkorTrackScreenState extends State<ValkorTrackScreen> {
  final c = CollarLink.instance;
  final rec = TrackRecorder.instance;
  final map = MapController();
  bool mapReady = false;
  bool _fitted = false;
  TrackMapStyle style = TrackMapStyle.standard;
  StreamSubscription<Position>? _posSub;
  Position? _own;
  Timer? _clock;
  String? locError;

  /// Tryb poszukiwania: radar zamiast mapy, najczęstsze pomiary.
  bool radar = false;

  /// Pies oglądany na ekranie (domyślnie aktywny profil). Zmiana tutaj nie
  /// przełącza profilu w całej aplikacji – trening i statystyki zostają.
  String _viewId = CollarLink.activeDog();
  bool get _viewingActive => _viewId == CollarLink.activeDog();

  /// Odległości z ostatnich sekund – do „zbliżasz się / oddalasz się”.
  final List<(DateTime, double)> _dists = [];

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    rec.addListener(_changed);
    OnlineConsent.instance.addListener(_changed);
    DogAlerts.instance.addListener(_changed);
    c.reconnectSaved();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    _startOwn(ask: false);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    rec.removeListener(_changed);
    OnlineConsent.instance.removeListener(_changed);
    DogAlerts.instance.removeListener(_changed);
    if (radar) c.endSearch();
    _posSub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!_fitted && mapReady && _anyDogLl != null) {
      _fitted = true;
      _fitBoth();
    }
  }

  /// Pozycja przewodnika z telefonu. Bez pytania o zgodę przy otwarciu –
  /// pytamy dopiero po dotknięciu „Moja pozycja”.
  Future<void> _startOwn({required bool ask}) async {
    if (kIsWeb || _posSub != null) return;
    try {
      if (!await GpsServices.serviceEnabled()) {
        if (ask && mounted) setState(() => locError = tr('Włącz lokalizację (GPS) w telefonie.'));
        return;
      }
      var p = await GpsServices.checkPermission();
      if (ask && p == LocationPermission.denied) p = await GpsServices.requestPermission();
      if (p != LocationPermission.whileInUse && p != LocationPermission.always) {
        if (ask && mounted) setState(() => locError = tr('Bez dostępu do lokalizacji nie pokażę Twojej pozycji.'));
        return;
      }
      if (!mounted) return;
      setState(() => locError = null);
      _posSub = ValkorTrackScreen.handlerPositions().listen((p) {
        _own = p;
        DogAlerts.instance.setHandler(LatLng(p.latitude, p.longitude));
        _changed();
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Przewodnik: z nagrywanego treningu, a poza treningiem z własnego odczytu.
  LatLng? get _meLl {
    final p = rec.state != RecState.idle && rec.last != null ? rec.last : _own;
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  CollarNode? get _node => c.nodeOf(_viewId);

  /// Bieżąca pozycja psa (pomiar z tej sesji).
  LatLng? get _dogLl => _node?.fix?.ll;

  /// Ostatnia znana pozycja – także zapamiętana z poprzednich sesji.
  LastSeen? get _last => c.lastKnown(_viewId);

  /// Pozycja do mapy i odległości: bieżąca, a bez niej ostatnia znana.
  LatLng? get _anyDogLl => _dogLl ?? _last?.ll;

  void _selectDog(String id) {
    if (id == _viewId) return;
    if (radar) {
      c.endSearch();
      radar = false;
    }
    setState(() {
      _viewId = id;
      _dists.clear();
      _fitted = false;
    });
    _changed();
  }

  Future<void> _makeActive() async {
    if (rec.state != RecState.idle) {
      toast(context, tr('Najpierw zakończ trening.'));
      return;
    }
    await DogProfiles.instance.switchTo(_viewId);
  }

  /// Kierunek marszu przewodnika (z GPS telefonu, tylko w ruchu).
  double? get _myCourse {
    final p = rec.state != RecState.idle && rec.last != null ? rec.last : _own;
    if (p == null || p.speed < 0.7 || p.heading < 0) return null;
    return p.heading;
  }

  Future<void> _toggleRadar() async {
    if (radar) {
      await c.endSearch();
    } else {
      await c.setMode(TrackMode.search);
      await _startOwn(ask: true);
    }
    if (mounted) setState(() => radar = !radar);
  }

  /// Zmiana odległości w ostatnich ~20 s: ujemna = zbliżasz się.
  double? _trend(double? dist, DateTime now) {
    if (dist == null) return null;
    _dists.add((now, dist));
    _dists.removeWhere((e) => now.difference(e.$1).inSeconds > 25);
    final old = _dists.first;
    if (now.difference(old.$1).inSeconds < 8) return null;
    return dist - old.$2;
  }

  void _centerDog() {
    final d = _anyDogLl;
    if (d != null && mapReady) map.move(d, math.max(map.camera.zoom, 16));
  }

  void _fitBoth() {
    if (!mapReady) return;
    final pts = [?_anyDogLl, ?_meLl];
    if (pts.isEmpty) return;
    if (pts.length == 1 || const Distance()(pts.first, pts.last) < 20) {
      map.move(pts.first, 17);
      return;
    }
    map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.all(60), maxZoom: 18));
  }

  Future<void> _chooseStyle() async {
    final picked = await showModalBottomSheet<TrackMapStyle>(
      context: context,
      backgroundColor: K9.card,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SheetTitle(tr('Rodzaj mapy')),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: Text(tr('Standardowa (OpenStreetMap)')),
            trailing: style == TrackMapStyle.standard ? const Icon(Icons.check_rounded, color: K9.orange) : null,
            onTap: () => Navigator.pop(ctx, TrackMapStyle.standard),
          ),
          ListTile(
            leading: const Icon(Icons.terrain_rounded),
            title: Text(tr('Terenowa (OpenTopoMap)')),
            subtitle: Text(tr('Poziomice i ścieżki. Kafle z serwisu OpenTopoMap – pozna oglądany obszar i adres IP.'),
                style: const TextStyle(fontSize: 12)),
            trailing: style == TrackMapStyle.terrain ? const Icon(Icons.check_rounded, color: K9.orange) : null,
            onTap: () => Navigator.pop(ctx, TrackMapStyle.terrain),
          ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == TrackMapStyle.terrain && OnlineConsent.instance.topo != true) {
      try {
        await OnlineConsent.instance.set(topo: true);
      } catch (e) {
        if (mounted) toast(context, tr('Nie udało się zapisać ustawienia.'));
        return;
      }
    }
    if (mounted) setState(() => style = picked);
  }

  Widget _tiles() {
    if (style == TrackMapStyle.terrain && OnlineConsent.instance.topo == true) return GpsServices.topoTiles();
    return mapTiles();
  }

  Widget _credit() => Align(
        alignment: Alignment.bottomRight,
        child: Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
          child: Text(
            style == TrackMapStyle.terrain
                ? tr('© OpenStreetMap, SRTM · © OpenTopoMap (CC-BY-SA)')
                : tr('© OpenStreetMap'),
            style: const TextStyle(color: Colors.white70, fontSize: 9.5),
          ),
        ),
      );

  Marker _dogMarker(LatLng p, {required bool live, String? label}) {
    final col = live ? K9.blue : K9.muted;
    return Marker(
      point: p,
      width: label == null ? 34 : 90,
      height: label == null ? 34 : 52,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: col,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [BoxShadow(color: col.withValues(alpha: 0.5), blurRadius: 10)],
          ),
          child: const Icon(Icons.pets_rounded, size: 17, color: Colors.white),
        ),
        if (label != null)
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, shadows: [
                Shadow(blurRadius: 3, color: Colors.black),
              ])),
      ]),
    );
  }

  Marker _meMarker(LatLng p) => Marker(
        point: p,
        width: 22,
        height: 22,
        child: Container(
          decoration: BoxDecoration(
            color: K9.orange,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
        ),
      );

  /// Pozostałe trackery przypisane do innych psów.
  List<(String, CollarNode)> get _otherDogs {
    final shown = _node?.num;
    return [
      for (final e in c.assigned.entries)
        if (e.value != _viewId && e.key != shown && c.nodes[e.key]?.fix != null) (e.value, c.nodes[e.key]!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final dogLl = _anyDogLl;
    final me = _meLl;
    final live = c.status(dogId: _viewId) == DogLink.live;
    final mapOn = OnlineConsent.instance.map == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Valkor Track')),
        actions: [
          IconButton(
            tooltip: tr('Ustawienia śledzenia'),
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showTrackSettings(context, here: _anyDogLl ?? _meLl),
          ),
          IconButton(
            tooltip: tr('Ustawienia obroży'),
            icon: const Icon(Icons.settings_bluetooth_rounded),
            onPressed: () => openCollar(context),
          ),
        ],
      ),
      body: Column(children: [
        if (radar) Expanded(child: _radarView(me, dogLl, live)) else Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: map,
              options: MapOptions(
                initialCenter: dogLl ?? me ?? const LatLng(52.0, 19.0),
                initialZoom: dogLl != null || me != null ? 16 : 6,
                onMapReady: () {
                  mapReady = true;
                  _changed();
                },
              ),
              children: [
                _tiles(),
                if (DogAlerts.instance.settings.zones.isNotEmpty)
                  CircleLayer(circles: [
                    for (final z in DogAlerts.instance.settings.zones)
                      CircleMarker(
                        point: z.ll,
                        radius: z.radiusM,
                        useRadiusInMeter: true,
                        color: K9.green.withValues(alpha: 0.10),
                        borderColor: K9.green,
                        borderStrokeWidth: 2,
                      ),
                  ]),
                if (me != null && DogAlerts.instance.settings.enabled && DogAlerts.instance.settings.leashM != null)
                  CircleLayer(circles: [
                    CircleMarker(
                      point: me,
                      radius: DogAlerts.instance.settings.leashM!.toDouble(),
                      useRadiusInMeter: true,
                      color: Colors.transparent,
                      borderColor: K9.orange.withValues(alpha: 0.7),
                      borderStrokeWidth: 1.5,
                    ),
                  ]),
                if (dogLl != null && me != null)
                  PolylineLayer(polylines: [
                    Polyline(points: [me, dogLl], strokeWidth: 2, color: Colors.white70, pattern: StrokePattern.dashed(segments: const [8, 6])),
                  ]),
                if (_viewingActive && rec.dogPoints.length > 1)
                  PolylineLayer(polylines: [
                    for (final s in rec.dogSegments)
                      if (s.length > 1) Polyline(points: [for (final q in s) q.ll], strokeWidth: 4, color: K9.blue),
                  ]),
                MarkerLayer(markers: [
                  if (me != null) _meMarker(me),
                  for (final (id, n) in _otherDogs)
                    _dogMarker(n.fix!.ll,
                        live: n.fix!.ageSec(DateTime.now()) <= c.liveLimitSec,
                        label: DogProfiles.instance.peek(id)?.name),
                  if (dogLl != null) _dogMarker(dogLl, live: live),
                ]),
                if (mapOn) _credit(),
              ],
            ),
            if (!mapOn)
              Positioned(
                left: 16,
                right: 16,
                top: 16,
                child: K9Card(
                  color: K9.cardHi,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      tr('Mapa online jest wyłączona. Odległość i kierunek do psa działają bez niej. Po włączeniu dostawca mapy OpenStreetMap pozna oglądany obszar i adres IP telefonu.'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => OnlineConsent.instance.set(map: true),
                      child: Text(tr('Włącz mapę')),
                    ),
                  ]),
                ),
              ),
            Positioned(
              right: 10,
              top: mapOn ? 10 : null,
              bottom: mapOn ? null : 10,
              child: Column(children: [
                _mapButton('dog', Icons.pets_rounded, tr('Pokaż psa'), dogLl == null ? null : _centerDog),
                _mapButton('both', Icons.fit_screen_rounded, tr('Pies i ja'), dogLl == null && me == null ? null : _fitBoth),
                _mapButton('me', Icons.my_location_rounded, tr('Moja pozycja'), () async {
                  await _startOwn(ask: true);
                  final m = _meLl;
                  if (m != null && mapReady) map.move(m, math.max(map.camera.zoom, 16));
                }),
                if (mapOn) _mapButton('style', Icons.layers_rounded, tr('Rodzaj mapy'), _chooseStyle),
              ]),
            ),
          ]),
        ),
        _panel(me, dogLl),
      ]),
    );
  }

  Widget _radarView(LatLng? me, LatLng? dogLl, bool live) {
    final now = DateTime.now();
    final dist = me == null || dogLl == null ? null : const Distance()(me, dogLl);
    final bearing = dist == null || dist < 3 ? null : (const Distance().bearing(me!, dogLl!) + 360) % 360;
    final trend = _trend(dist, now);
    final node = _node;
    final dogCourse = live ? node?.courseDeg : null;
    final dogSpeed = live ? node?.speedMs : null;
    return Container(
      color: K9.bg,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(children: [
        Text(
          dist == null
              ? (dogLl == null ? tr('Czekam na pozycję psa…') : tr('Czekam na Twoją pozycję…'))
              : (dist >= 1000 ? '${fmtKm(dist / 1000)} km' : '${dist.round()} m'),
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
        ),
        if (bearing != null)
          Text(tr('Pies jest na {0} ({1}°)', [compassLabel(bearing), bearing.round()]),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        if (trend != null && trend.abs() >= 5)
          Text(trend < 0 ? tr('Zbliżasz się') : tr('Oddalasz się'),
              style: TextStyle(color: trend < 0 ? K9.green : K9.yellow, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Expanded(
          child: DogRadar(
            distM: dist,
            bearingDeg: bearing,
            myCourseDeg: _myCourse,
            dogCourseDeg: dogCourse,
            live: live,
          ),
        ),
        Text(
          [
            if (!live && _last != null) tr('ostatnia znana pozycja {0}', [collarAge(_last!.at, now: now)]),
            if (dogCourse != null && dogSpeed != null && dogSpeed > 0.5)
              tr('pies biegnie na {0}, {1} km/h', [compassLabel(dogCourse), fmtNum(dogSpeed * 3.6)]),
            tr('Góra = północ. Pomarańczowa kreska = Twój kierunek marszu.'),
          ].join(' · '),
          textAlign: TextAlign.center,
          style: const TextStyle(color: K9.muted, fontSize: 12),
        ),
      ]),
    );
  }

  Widget _mapButton(String tag, IconData icon, String tip, VoidCallback? onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FloatingActionButton.small(
          heroTag: 'vt_$tag',
          tooltip: tip,
          backgroundColor: K9.card,
          foregroundColor: onTap == null ? K9.faint : K9.orange,
          onPressed: onTap,
          child: Icon(icon),
        ),
      );

  Widget _chip(String label, Color color) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _stat(String label, String value, {Widget? leading}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: K9.muted, fontSize: 11.5)),
          const SizedBox(height: 2),
          Row(children: [
            if (leading != null) ...[leading, const SizedBox(width: 4)],
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
        ]),
      );

  Widget _panel(LatLng? me, LatLng? dogLl) {
    final now = DateTime.now();
    final link = c.status(now: now, dogId: _viewId);
    final node = _node;
    final f = node?.fix;
    final last = _last;
    final Dog? dog = DogProfiles.instance.peek(_viewId);
    final dogs = DogProfiles.instance.dogs;
    final dist = me == null || dogLl == null ? null : const Distance()(me, dogLl);
    final bearing = me == null || dogLl == null || dist! < 3 ? null : (const Distance().bearing(me, dogLl) + 360) % 360;
    final speed = link == DogLink.live ? node?.speedMs : null;

    final battery = node?.battery ?? last?.battery;
    final ble = c.connected ? K9.green : (c.state == CollarState.off ? K9.red : K9.yellow);
    final heard = node?.lastHeard == null ? null : now.difference(node!.lastHeard!).inSeconds;
    final lora = heard != null && heard <= CollarLink.loraSilentSec ? K9.green : K9.red;
    final gps = switch (link) {
      DogLink.live => K9.green,
      DogLink.stale || DogLink.waitingGps => K9.yellow,
      _ => K9.red,
    };

    return Material(
      color: K9.card,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (dogs.length > 1) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (id, d) in dogs)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        key: ValueKey('vt-dog-$id'),
                        label: Text(d.name.isEmpty ? tr('Pies') : d.name),
                        avatar: c.viewNode(id) == null ? null : const Icon(Icons.gps_fixed_rounded, size: 16),
                        selected: id == _viewId,
                        onSelected: (_) => _selectDog(id),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
            ],
            Row(children: [
              ClipOval(child: SizedBox(width: 44, height: 44, child: DogPhoto(dog: dog))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(dog?.name.isNotEmpty == true ? dog!.name : tr('Pies'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(
                    [
                      dogLinkText(c, now: now, dogId: _viewId),
                      if (last != null && link != DogLink.live) tr('ostatnia znana pozycja {0}', [collarAge(last.at, now: now)]),
                    ].join(' · '),
                    style: const TextStyle(color: K9.muted, fontSize: 12.5),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip(tr('Bluetooth'), ble),
                if (!c.direct && c.paired) _chip(tr('LoRa'), lora),
                _chip(tr('GPS psa'), gps),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _stat(
                link == DogLink.live || dist == null ? tr('Odległość') : tr('Ostatnio'),
                dist == null ? '–' : (dist >= 1000 ? '${fmtKm(dist / 1000)} km' : '${dist.round()} m'),
              ),
              _stat(
                tr('Kierunek do psa'),
                bearing == null ? '–' : '${compassLabel(bearing)} ${bearing.round()}°',
                leading: bearing == null
                    ? null
                    : Transform.rotate(
                        angle: bearing * math.pi / 180,
                        child: const Icon(Icons.navigation_rounded, size: 16, color: K9.orange),
                      ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _stat(tr('Prędkość psa'), speed == null ? '–' : '${fmtNum(speed * 3.6)} km/h'),
              _stat(tr('Bateria'), battery == null ? '–' : (battery > 100 ? tr('kabel') : '$battery%')),
              _stat(tr('Pomiar'), (f?.fixAt ?? last?.at) == null ? '–' : collarAge(f?.fixAt ?? last!.at, now: now)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text(
                  [
                    tr('Tryb: {0}', [c.mode.label]),
                    if (c.diag.medianInterval != null) tr('pomiar co ~{0} s', [c.diag.medianInterval!.round()]),
                    if (DogAlerts.instance.settings.enabled) tr('alarmy włączone'),
                  ].join(' · '),
                  style: TextStyle(color: c.slowerThanMode ? K9.yellow : K9.muted, fontSize: 12),
                ),
              ),
              if (c.paired && c.viewNode(_viewId) != null)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: _toggleRadar,
                  icon: Icon(radar ? Icons.map_rounded : Icons.radar_rounded, size: 18),
                  label: Text(radar ? tr('Mapa') : tr('Szukaj psa')),
                ),
            ]),
            if (DogAlerts.instance.history.isNotEmpty &&
                now.difference(DogAlerts.instance.history.first.at).inMinutes < 10) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.notifications_active_rounded, size: 16, color: K9.yellow),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${DogAlerts.instance.history.first.text} (${collarAge(DogAlerts.instance.history.first.at, now: now)})',
                    style: const TextStyle(color: K9.yellow, fontSize: 12.5),
                  ),
                ),
              ]),
            ],
            if (me == null && locError == null) ...[
              const SizedBox(height: 8),
              Text(tr('Twoja pozycja: dotknij „Moja pozycja” na mapie, żeby liczyć odległość i kierunek.'),
                  style: const TextStyle(color: K9.faint, fontSize: 12)),
            ],
            if (locError != null) ...[
              const SizedBox(height: 8),
              Text(locError!, style: const TextStyle(color: K9.yellow, fontSize: 12)),
            ],
            if (c.paired && !_viewingActive && c.viewNode(_viewId) == null) ...[
              const SizedBox(height: 10),
              Text(tr('Ten pies nie ma przypisanego trackera. Przełącz się na jego profil i wybierz tracker w ustawieniach obroży.'),
                  style: const TextStyle(color: K9.muted, fontSize: 12.5)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _makeActive,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: Text(tr('Przełącz na tego psa')),
              ),
            ],
            if (!c.paired) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => openCollar(context),
                icon: const Icon(Icons.bluetooth_searching_rounded),
                label: Text(tr('Dodaj tracker')),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
