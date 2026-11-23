import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import '../models.dart' show jsonInt;
import '../storage/safe_prefs.dart';
import '../l10n/l10n.dart';
import 'mesh_proto.dart';

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
  CollarNode(this.num);

  String get name => (longName?.isNotEmpty ?? false) ? longName! : (shortName ?? meshNodeId(num));
  bool get isT1000E => hwModel == hwT1000E;
}

/// Pozycja psa z obroży.
class CollarFix {
  final int node;
  final double lat, lng;
  final DateTime at;
  final double? speedMs;
  const CollarFix(this.node, this.lat, this.lng, this.at, {this.speedMs});
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
  int? dogNodeChoice;

  final Map<int, CollarNode> nodes = {};
  final _fixes = StreamController<CollarFix>.broadcast();

  /// Nowe pozycje psa.
  Stream<CollarFix> get fixes => _fixes.stream;

  bool _loaded = false;
  bool _wanted = false;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<Uint8List>? _notifySub;
  Timer? _poll;
  Timer? _retry;
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
  int? get dogNode {
    if (dogNodeChoice != null) return dogNodeChoice;
    final others = nodes.values.where((n) => n.num != myNode && n.isT1000E).toList();
    if (others.length == 1) return others.first.num;
    return myNode;
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
    } catch (e) {
      logError('Obroża GPS', e);
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await SafePrefs.setString(p, _key, jsonEncode({'id': deviceId, 'name': deviceName, 'dog': dogNodeChoice}));
    } catch (e) {
      logError('Obroża GPS', e);
    }
  }

  Future<void> chooseDog(int? node) async {
    dogNodeChoice = node;
    notifyListeners();
    await _save();
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
    if (id == null || !_wanted) return;
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
      notifyListeners();
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _tickPoll());
    } catch (e) {
      error = _message(e);
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
    notifyListeners();
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 8), _open);
  }

  Future<void> disconnect({bool forget = false}) async {
    _wanted = false;
    _poll?.cancel();
    _retry?.cancel();
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

  void _tickPoll() {
    if (state != CollarState.connected) return;
    _drain();
    // Obroża połączona bezpośrednio: co 15 s prosimy ją o świeżą pozycję.
    final me = myNode;
    final now = DateTime.now();
    if (direct && me != null && (_lastRequest == null || now.difference(_lastRequest!).inSeconds >= 15)) {
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
          n.position = e.position;
          n.positionAt = t;
          n.lastHeard = t;
          n.rssi = e.rssi ?? n.rssi;
          if (e.node == dogNode) {
            _fixes.add(CollarFix(e.node, e.position.lat, e.position.lng, t, speedMs: e.position.speedMs));
          }
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

  /// Ostatnia pozycja psa i jej wiek.
  CollarNode? get dogWithFix {
    final d = dog;
    return d?.positionAt == null ? null : d;
  }

  @visibleForTesting
  void resetForTest() {
    state = CollarState.off;
    deviceId = null;
    deviceName = null;
    myNode = null;
    dogNodeChoice = null;
    nodes.clear();
    _loaded = true;
  }
}
