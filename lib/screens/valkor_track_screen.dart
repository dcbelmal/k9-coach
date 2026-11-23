import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../collar/collar_link.dart';
import '../dogs/dog_profiles.dart';
import '../gps/online_services.dart';
import '../gps/recorder.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'collar_screen.dart';

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

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    rec.addListener(_changed);
    OnlineConsent.instance.addListener(_changed);
    c.reconnectSaved();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    _startOwn(ask: false);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    rec.removeListener(_changed);
    OnlineConsent.instance.removeListener(_changed);
    _posSub?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!_fitted && mapReady && _dogLl != null) {
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
        _changed();
      }, onError: (_) {});
    } catch (_) {}
  }

  /// Przewodnik: z nagrywanego treningu, a poza treningiem z własnego odczytu.
  LatLng? get _meLl {
    final p = rec.state != RecState.idle && rec.last != null ? rec.last : _own;
    return p == null ? null : LatLng(p.latitude, p.longitude);
  }

  LatLng? get _dogLl => c.dog?.fix?.ll;

  void _centerDog() {
    final d = _dogLl;
    if (d != null && mapReady) map.move(d, math.max(map.camera.zoom, 16));
  }

  void _fitBoth() {
    if (!mapReady) return;
    final pts = [?_dogLl, ?_meLl];
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
    final active = CollarLink.activeDog();
    return [
      for (final e in c.assigned.entries)
        if (e.value != active && c.nodes[e.key]?.fix != null) (e.value, c.nodes[e.key]!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final dogLl = _dogLl;
    final me = _meLl;
    final live = c.status() == DogLink.live;
    final mapOn = OnlineConsent.instance.map == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Valkor Track')),
        actions: [
          IconButton(
            tooltip: tr('Ustawienia obroży'),
            icon: const Icon(Icons.settings_bluetooth_rounded),
            onPressed: () => openCollar(context),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
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
                if (dogLl != null && me != null)
                  PolylineLayer(polylines: [
                    Polyline(points: [me, dogLl], strokeWidth: 2, color: Colors.white70, pattern: StrokePattern.dashed(segments: const [8, 6])),
                  ]),
                if (rec.dogPoints.length > 1)
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
    final link = c.status(now: now);
    final node = c.dog;
    final f = node?.fix;
    final Dog? dog = DogProfiles.instance.peek(CollarLink.activeDog());
    final dist = me == null || dogLl == null ? null : const Distance()(me, dogLl);
    final bearing = me == null || dogLl == null || dist! < 3 ? null : (const Distance().bearing(me, dogLl) + 360) % 360;
    final speed = link == DogLink.live ? node?.speedMs : null;

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
            Row(children: [
              ClipOval(child: SizedBox(width: 44, height: 44, child: DogPhoto(dog: dog))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(dog?.name.isNotEmpty == true ? dog!.name : tr('Pies'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(
                    [
                      dogLinkText(c, now: now),
                      if (f != null && link != DogLink.live) tr('ostatnia znana pozycja {0}', [collarAge(f.fixAt, now: now)]),
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
              _stat(tr('Bateria'), node?.battery == null ? '–' : (node!.battery! > 100 ? tr('kabel') : '${node.battery}%')),
              _stat(tr('Pomiar'), f == null ? '–' : collarAge(f.fixAt, now: now)),
            ]),
            if (me == null && locError == null) ...[
              const SizedBox(height: 8),
              Text(tr('Twoja pozycja: dotknij „Moja pozycja” na mapie, żeby liczyć odległość i kierunek.'),
                  style: const TextStyle(color: K9.faint, fontSize: 12)),
            ],
            if (locError != null) ...[
              const SizedBox(height: 8),
              Text(locError!, style: const TextStyle(color: K9.yellow, fontSize: 12)),
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
