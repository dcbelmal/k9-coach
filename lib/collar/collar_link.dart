import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import '../dogs/dog_profiles.dart';
import '../models.dart' show jsonInt;
import '../storage/safe_prefs.dart';
import '../l10n/l10n.dart';
import 'fix_filter.dart';
import 'mesh_proto.dart';

export 'fix_filter.dart' show CollarFix, FixReject, CollarDiagnostics;

/// UUID usługi i charakterystyk Bluetooth urządzeń Meshtastic.
class MeshBle {
  static const service = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
  static const toRadio = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
  static const fromRadio = '2c55e69e-4993-11ed-b878-0242ac120002';
  static const fromNum = 'ed9da18b-2c40-4c4b-b812-07c1b2e1ef10';
}

enum CollarState { off, connecting, connected, lost }

/// Urządzenie w sieci Meshtastic widziane przez telefon.
class CollarNode {
  final int num;
  String? longName, shortName;
  int? hwModel;
  MeshPosition? position;
  DateTime? positionAt; // kiedy telefon dostał pozycję
  int? battery;
  DateTime? lastHeard;
  int? rssi;

  /// Ostatni przyjęty (sprawdzony) pomiar GPS.
  CollarFix? fix;
  final FixFilter filter;
  CollarNode(this.num) : filter = FixFilter(num);

  /// Dwa ostatnie pomiary z ruchem – do kierunku i prędkości.
  CollarFix? lastMoved, prevMoved;

  /// Prędkość (m/s): z trackera, a gdy jej nie podaje – z dwóch ostatnich
  /// pomiarów (najwyżej 2 min odstępu). Postój = 0. null = brak danych.
  double? get speedMs {
    final f = fix;
    if (f == null) return null;
    if (f.speedMs != null) return f.speedMs;
    if (!f.moved) return 0;
    final a = prevMoved, b = lastMoved;
    if (a == null || b == null) return null;
    final dt = b.fixAt.difference(a.fixAt).inMilliseconds / 1000;
    if (dt <= 0 || dt > 120) return null;
    return const Distance()(a.ll, b.ll) / dt;
  }

  /// Kierunek ruchu (stopnie od północy) z dwóch ostatnich pomiarów z ruchem.
  double? get courseDeg {
    final a = prevMoved, b = lastMoved;
    if (a == null || b == null) return null;
    if (b.fixAt.difference(a.fixAt).inSeconds > 120) return null;
    if (const Distance()(a.ll, b.ll) < 5) return null;
    return (const Distance().bearing(a.ll, b.ll) + 360) % 360;
  }

  String get name => (longName?.isNotEmpty ?? false) ? longName! : (shortName ?? meshNodeId(num));
  bool get isT1000E => hwModel == hwT1000E;
}

/// Tryb pracy Valkor Track: jak często aplikacja prosi tracker o pozycję
/// (tylko przy połączeniu bezpośrednim przez Bluetooth). Tracker i tak nie
/// poda pozycji częściej, niż pozwala jego ustawienie GPS w Meshtastic –
/// rzeczywisty odstęp pokazujemy osobno ([CollarDiagnostics.medianInterval]).
enum TrackMode {
  sport('Sportowy', '1–5 s', 3, 5),
  walk('Spacerowy', '10–15 s', 12, 15),
  saver('Oszczędny', '30–60 s', 45, 60),
  search('Poszukiwanie', 'najczęściej', 2, 5);

  final String _label;
  final String range;

  /// Co ile sekund prosimy o pozycję.
  final int requestSec;

  /// Najdłuższy odstęp zgodny z trybem (do ostrzeżenia, że tracker wysyła rzadziej).
  final int targetSec;
  const TrackMode(this._label, this.range, this.requestSec, this.targetSec);
  String get label => tr(_label);
  String get rangeLabel => tr(range);
}

/// Stan łączności z psem – rozróżnia Bluetooth, LoRa i GPS.
enum DogLink {
  /// Nie dodano trackera.
  none,

  /// Telefon nie jest połączony z urządzeniem Meshtastic (Bluetooth).
  bluetoothOff,

  /// Trwa łączenie albo ponowne łączenie przez Bluetooth.
  connecting,

  /// Bluetooth działa, ale tracker na psie nie odzywa się radiem LoRa.
  loraSilent,

  /// Tracker odpowiada, ale nie ma jeszcze pozycji GPS.
  waitingGps,

  /// Jest tylko ostatnia znana pozycja – brak świeżego pomiaru GPS.
  stale,

  /// Pozycja na żywo.
  live,
}

/// Połączenie z obrożą GPS SenseCAP T1000-E (oprogramowanie Meshtastic)
/// przez Bluetooth.
///
/// Dwa sposoby użycia:
/// * jedna obroża – telefon łączy się bezpośrednio z obrożą na psie
///   (zasięg Bluetooth, kilkadziesiąt metrów);
/// * obroża + drugie urządzenie Meshtastic w kieszeni – telefon łączy się
///   z urządzeniem w kieszeni, a pozycje psa przychodzą radiem LoRa (km).
class CollarLink extends ChangeNotifier {
  CollarLink._();
  static final CollarLink instance = CollarLink._();
  static const _key = 'valkor_collar_v1';

  CollarState state = CollarState.off;
  String? error;

  /// Zapamiętane urządzenie Bluetooth (łączymy się z nim automatycznie).
  String? deviceId;
  String? deviceName;

  /// Numer urządzenia, z którym połączony jest telefon.
  int? myNode;

  /// Urządzenie na psie wybrane przez użytkownika (null = wybór automatyczny).
  /// Starszy, wspólny wybór – nowsze wersje przypisują tracker do profilu psa.
  int? dogNodeChoice;

  /// Tryb pracy (częstotliwość próśb o pozycję).
  TrackMode mode = TrackMode.walk;

  /// Tryb sprzed włączenia poszukiwania (przywracany po jego wyłączeniu).
  TrackMode? _beforeSearch;

  Future<void> setMode(TrackMode m) async {
    if (m == mode) return;
    if (m == TrackMode.search && mode != TrackMode.search) _beforeSearch = mode;
    mode = m;
    _lastRequest = null;
    notifyListeners();
    await _save();
  }

  /// Wyłącza poszukiwanie i wraca do poprzedniego trybu.
  Future<void> endSearch() async {
    if (mode != TrackMode.search) return;
    await setMode(_beforeSearch ?? TrackMode.walk);
    _beforeSearch = null;
  }

  /// Tracker wysyła wyraźnie rzadziej, niż zakłada tryb.
  bool get slowerThanMode {
    final m = diag.medianInterval;
    return m != null && m > mode.targetSec * 1.5;
  }

  /// Przypisanie trackerów do profili psów: numer urządzenia → id psa.
  final Map<int, String> assigned = {};

  /// Id aktualnie wybranego psa (podmieniane w testach).
  static String Function() activeDog = () => DogProfiles.instance.activeId;

  final Map<int, CollarNode> nodes = {};
  final _fixes = StreamController<CollarFix>.broadcast();

  /// Sprawdzone pomiary GPS ze wszystkich urządzeń w sieci. Odbiorca wybiera
  /// urządzenie po [CollarFix.node] – trening blokuje je na starcie.
  Stream<CollarFix> get fixes => _fixes.stream;

  /// Liczniki do ekranu diagnostyki.
  final diag = CollarDiagnostics();

  /// Po tylu sekundach bez wiadomości od trackera w sieci LoRa uznajemy go za niesłyszalnego.
  static const loraSilentSec = 180;

  bool _loaded = false;
  bool _wanted = false;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Uint8List>? _notifySub;
  Timer? _poll;
  Timer? _retry;
  bool _opening = false;
  int _retrySec = 5;
  bool _draining = false;
  bool _drainAgain = false;
  int _configId = 0;
  DateTime? _lastRequest;

  bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  bool get connected => state == CollarState.connected;
  bool get paired => deviceId != null;

  /// Urządzenie, którego pozycje traktujemy jako pozycje psa.
  ///
  /// Gdy użytkownik nie wybrał: jedyna inna obroża T1000-E w sieci,
  /// a gdy jej nie ma – urządzenie połączone z telefonem (obroża na psie).
  int? get dogNode => nodeForDog(activeDog());

  /// Tracker psa [dogId]: przypisany do jego profilu, a gdy go nie ma –
  /// wcześniejszy wspólny wybór albo wybór automatyczny (z pominięciem
  /// trackerów przypisanych innym psom).
  int? nodeForDog(String dogId) {
    for (final e in assigned.entries) {
      if (e.value == dogId) return e.key;
    }
    bool free(int? n) => n != null && !assigned.containsKey(n);
    if (free(dogNodeChoice)) return dogNodeChoice;
    final others = nodes.values.where((n) => n.num != myNode && n.isT1000E && free(n.num)).toList();
    if (others.length == 1) return others.first.num;
    return free(myNode) ? myNode : null;
  }

  /// Id psa, do którego przypisano tracker [node] (null = nieprzypisany).
  String? dogFor(int node) => assigned[node];

  /// Przypisuje tracker do psa (jeden tracker na psa). [dogId] null = odpina.
  Future<void> assign(int node, String? dogId) async {
    if (dogId == null) {
      assigned.remove(node);
    } else {
      assigned.removeWhere((_, d) => d == dogId);
      assigned[node] = dogId;
    }
    notifyListeners();
    await _save();
  }

  /// true = telefon połączony bezpośrednio z obrożą na psie.
  bool get direct => dogNode != null && dogNode == myNode;

  CollarNode? get dog => dogNode == null ? null : nodes[dogNode];

  /// Inne urządzenia w sieci (do wyboru, które jest na psie).
  List<CollarNode> get otherNodes => nodes.values.where((n) => n.num != myNode).toList()
    ..sort((a, b) => (b.lastHeard ?? DateTime(2000)).compareTo(a.lastHeard ?? DateTime(2000)));

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      deviceId = j['id'] as String?;
      deviceName = j['name'] as String?;
      dogNodeChoice = jsonInt(j['dog']);
      mode = TrackMode.values.asNameMap()[j['mode']] ?? TrackMode.walk;
      if (mode == TrackMode.search) mode = TrackMode.walk; // poszukiwanie nie przetrwa restartu
      final a = j['assign'];
      if (a is Map) {
        for (final e in a.entries) {
          final n = int.tryParse('${e.key}');
          if (n != null && e.value is String) assigned[n] = e.value as String;
        }
      }
    } catch (e) {
      logError('Obroża GPS', e);
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await SafePrefs.setString(p, _key, jsonEncode({
        'id': deviceId,
        'name': deviceName,
        'dog': dogNodeChoice,
        'assign': {for (final e in assigned.entries) '${e.key}': e.value},
        'mode': (mode == TrackMode.search ? (_beforeSearch ?? TrackMode.walk) : mode).name,
      }));
    } catch (e) {
      logError('Obroża GPS', e);
    }
  }

  /// Wybór urządzenia na psie – przypisuje je do aktualnego psa.
  Future<void> chooseDog(int? node) async {
    if (node == null) {
      assigned.removeWhere((_, d) => d == activeDog());
      dogNodeChoice = null;
      notifyListeners();
      await _save();
      return;
    }
    await assign(node, activeDog());
  }

  /// Uprawnienia i włączony Bluetooth. Zwraca komunikat błędu albo null.
  Future<String?> prepare() async {
    if (!supported) return tr('Obroża GPS działa tylko w aplikacji na telefonie.');
    try {
      await UniversalBle.requestPermissions(withAndroidFineLocation: false);
    } catch (_) {
      return tr('Bez zgody na Bluetooth aplikacja nie połączy się z obrożą. Włącz ją w ustawieniach telefonu.');
    }
    try {
      final s = await UniversalBle.getBluetoothAvailabilityState();
      if (s == AvailabilityState.poweredOff) return tr('Włącz Bluetooth w telefonie.');
      if (s == AvailabilityState.unsupported) return tr('Ten telefon nie obsługuje Bluetooth LE.');
    } catch (_) {}
    return null;
  }

  /// Wyszukiwanie urządzeń Meshtastic w pobliżu.
  Stream<BleDevice> scan() {
    final out = StreamController<BleDevice>();
    final sub = UniversalBle.scanStream.listen(out.add);
    UniversalBle.startScan(scanFilter: ScanFilter(withServices: [MeshBle.service])).catchError((Object e) {
      out.addError(e);
    });
    out.onCancel = () async {
      await sub.cancel();
      try {
        await UniversalBle.stopScan();
      } catch (_) {}
    };
    return out.stream;
  }

  /// Łączy z zapamiętanym urządzeniem, jeśli jest i nie jest już połączone.
  Future<void> reconnectSaved() async {
    await load();
    if (!supported || deviceId == null || state != CollarState.off) return;
    if (await prepare() != null) return;
    unawaited(connect(deviceId!, name: deviceName));
  }

  Future<void> connect(String id, {String? name}) async {
    if (deviceId != id) {
      nodes.clear();
      myNode = null;
      dogNodeChoice = null;
    }
    deviceId = id;
    deviceName = name ?? deviceName;
    _wanted = true;
    await _save();
    await _open();
  }

  Future<void> _open() async {
    final id = deviceId;
    // Nigdy dwie próby łączenia naraz (np. ręczne „Połącz” w trakcie ponawiania).
    if (id == null || !_wanted || _opening || state == CollarState.connected) return;
    _opening = true;
    try {
      await _openInner(id);
    } finally {
      _opening = false;
    }
  }

  Future<void> _openInner(String id) async {
    _retry?.cancel();
    state = CollarState.connecting;
    error = null;
    notifyListeners();
    try {
      await _connSub?.cancel();
      await UniversalBle.connect(id, timeout: const Duration(seconds: 20));
      _connSub = UniversalBle.connectionStream(id).listen((up) {
        if (!up) _onLost();
      });
      final services = await UniversalBle.discoverServices(id);
      if (!services.any((s) => s.uuid.toLowerCase() == MeshBle.service)) {
        throw Exception(tr('To urządzenie nie ma oprogramowania Meshtastic.'));
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          if (await UniversalBle.isPaired(id) != true) await UniversalBle.pair(id);
        } catch (_) {
          // Część urządzeń paruje się dopiero przy pierwszym odczycie.
        }
        try {
          await UniversalBle.requestMtu(id, 512);
        } catch (_) {}
      }
      await _notifySub?.cancel();
      _notifySub = UniversalBle.characteristicValueStream(id, MeshBle.fromNum).listen((_) => _drain());
      try {
        await UniversalBle.subscribeNotifications(id, MeshBle.service, MeshBle.fromNum);
      } catch (_) {
        // Bez powiadomień i tak odpytujemy urządzenie co kilka sekund.
      }
      _configId = meshRandomId();
      await _write(encodeWantConfig(_configId));
      await _drain();
      state = CollarState.connected;
      _retrySec = 5;
      diag.connectedAt = DateTime.now();
      notifyListeners();
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _tickPoll());
    } catch (e) {
      error = _message(e);
      diag.lastError = e.toString();
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
      _onLost();
    }
  }

  String _message(Object e) {
    final s = e.toString();
    if (s.contains('Meshtastic')) return s.replaceFirst('Exception: ', '');
    return tr('Nie udało się połączyć z obrożą. Sprawdź, czy jest włączona i blisko telefonu, a aplikacja Meshtastic jest z nią rozłączona.');
  }

  void _onLost() {
    _poll?.cancel();
    _poll = null;
    if (!_wanted) {
      state = CollarState.off;
      notifyListeners();
      return;
    }
    state = CollarState.lost;
    diag.reconnects++;
    notifyListeners();
    // Ponawianie z rosnącą przerwą (5, 10, 20, 30 s) – oszczędza baterię telefonu.
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _retrySec), _open);
    _retrySec = (_retrySec * 2).clamp(5, 30);
  }

  Future<void> disconnect({bool forget = false}) async {
    _wanted = false;
    _poll?.cancel();
    _retry?.cancel();
    _retrySec = 5;
    await _notifySub?.cancel();
    await _connSub?.cancel();
    _notifySub = null;
    _connSub = null;
    final id = deviceId;
    if (id != null && supported) {
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
    state = CollarState.off;
    if (forget) {
      deviceId = null;
      deviceName = null;
      dogNodeChoice = null;
      myNode = null;
      nodes.clear();
      await _save();
    }
    notifyListeners();
  }

  Future<void> _write(Uint8List data) async {
    final id = deviceId;
    if (id == null) return;
    await UniversalBle.write(id, MeshBle.service, MeshBle.toRadio, data);
  }

  int _tick = 0;

  void _tickPoll() {
    if (state != CollarState.connected) return;
    // Odczyt co 5 s (powiadomienia i tak budzą odczyt od razu), w poszukiwaniu co 1 s.
    if (mode == TrackMode.search || _tick++ % 5 == 0) _drain();
    // Obroża połączona bezpośrednio: prosimy o świeżą pozycję tylko wtedy,
    // gdy ostatni pomiar jest starszy niż odstęp trybu (oszczędza baterię trackera).
    final me = myNode;
    final now = DateTime.now();
    final f = dog?.fix;
    final every = mode.requestSec;
    final fresh = f != null && f.ageSec(now) < every;
    if (direct && me != null && !fresh && (_lastRequest == null || now.difference(_lastRequest!).inSeconds >= every)) {
      _lastRequest = now;
      _write(encodePositionRequest(me)).catchError((_) {});
    }
  }

  /// Odczyt wszystkich oczekujących wiadomości z urządzenia.
  Future<void> _drain() async {
    final id = deviceId;
    if (id == null) return;
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        for (var i = 0; i < 200; i++) {
          final bytes = await UniversalBle.read(id, MeshBle.service, MeshBle.fromRadio);
          if (bytes.isEmpty) break;
          diag.packets++;
          diag.lastPacketAt = DateTime.now();
          try {
            handleEvents(decodeFromRadio(bytes));
          } on FormatException catch (e) {
            logError('Obroża GPS', e);
          }
        }
      } while (_drainAgain);
    } catch (e) {
      logError('Obroża GPS', e);
    } finally {
      _draining = false;
    }
  }

  /// Aktualizacja stanu na podstawie zdarzeń z urządzenia.
  @visibleForTesting
  void handleEvents(List<MeshEvent> events, {DateTime? now}) {
    if (events.isEmpty) return;
    final t = now ?? DateTime.now();
    for (final e in events) {
      switch (e) {
        case MeshMyInfo(:final myNode):
          this.myNode = myNode;
        case MeshNodeInfo():
          final n = nodes.putIfAbsent(e.node, () => CollarNode(e.node));
          n.longName = e.longName ?? n.longName;
          n.shortName = e.shortName ?? n.shortName;
          n.hwModel = e.hwModel ?? n.hwModel;
          n.battery = e.battery ?? n.battery;
          if (e.lastHeard != null) n.lastHeard = e.lastHeard;
          // Pozycja z bazy urządzenia bywa stara – nie trafia do trasy.
          if (e.position != null && n.position == null) n.position = e.position;
        case MeshPositionEvent():
          final n = nodes.putIfAbsent(e.node, () => CollarNode(e.node));
          n.lastHeard = t;
          n.rssi = e.rssi ?? n.rssi;
          diag.positions++;
          final v = n.filter.check(e.position, t);
          if (!v.accepted) {
            diag.reject(v.reject!);
            // Zaokrąglona pozycja: pokazujemy ostrzeżenie, ale nie traktujemy jej jako pomiaru.
            if (v.reject == FixReject.coarse) n.position = e.position;
            break;
          }
          final f = v.fix!;
          if (e.node == dogNode && n.fix != null) {
            diag.addInterval(f.fixAt.difference(n.fix!.fixAt).inMilliseconds / 1000);
          }
          if (f.moved) {
            n.prevMoved = n.lastMoved;
            n.lastMoved = f;
          }
          n.fix = f;
          n.position = e.position;
          n.positionAt = t;
          diag.accepted++;
          _fixes.add(f);
        case MeshBattery():
          final n = nodes.putIfAbsent(e.node, () => CollarNode(e.node));
          n.battery = e.level;
          n.lastHeard = t;
        case MeshConfigComplete():
        case MeshRebooted():
          break;
      }
    }
    notifyListeners();
  }

  /// Tracker na psie wysyła pozycję zaokrągloną przez ustawienia kanału.
  bool get dogCoarse => dog?.position?.coarse ?? false;

  /// Pies z co najmniej jednym przyjętym pomiarem (może być nieaktualny – patrz [status]).
  CollarNode? get dogWithFix {
    final d = dog;
    return d?.fix == null ? null : d;
  }

  /// Po ilu sekundach pomiar przestaje być „na żywo”: 3 × rzeczywisty odstęp
  /// między pomiarami, co najmniej 45 s.
  double get liveLimitSec {
    final m = diag.medianInterval;
    return m == null ? 45 : (m * 3).clamp(45, 600).toDouble();
  }

  /// Stan łączności z psem: osobno Bluetooth, LoRa i GPS.
  DogLink status({DateTime? now}) {
    final t = now ?? DateTime.now();
    if (deviceId == null) return DogLink.none;
    switch (state) {
      case CollarState.off:
        return DogLink.bluetoothOff;
      case CollarState.connecting:
      case CollarState.lost:
        return DogLink.connecting;
      case CollarState.connected:
        break;
    }
    final d = dog;
    final heardAge = d?.lastHeard == null ? null : t.difference(d!.lastHeard!).inSeconds;
    final loraSilent = !direct && (heardAge == null || heardAge > loraSilentSec);
    final f = d?.fix;
    if (f == null) return loraSilent ? DogLink.loraSilent : DogLink.waitingGps;
    if (f.ageSec(t) <= liveLimitSec) return DogLink.live;
    return loraSilent ? DogLink.loraSilent : DogLink.stale;
  }

  @visibleForTesting
  void resetForTest({bool loaded = true}) {
    state = CollarState.off;
    deviceId = null;
    deviceName = null;
    myNode = null;
    dogNodeChoice = null;
    assigned.clear();
    mode = TrackMode.walk;
    _beforeSearch = null;
    nodes.clear();
    diag.clear();
    _loaded = loaded;
  }
}
