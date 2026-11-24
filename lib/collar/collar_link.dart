import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_ble/universal_ble.dart';

import '../dogs/dog_profiles.dart';
import '../models.dart' show jsonInt;
import '../storage/safe_prefs.dart';
import '../l10n/l10n.dart';
import 'dog_distance.dart';
import 'fix_filter.dart';
import 'mesh_proto.dart';
import 'pos_filter.dart';
import 'tracker_config.dart';

export 'dog_distance.dart';
export 'fix_filter.dart' show CollarFix, FixReject, CollarDiagnostics, FixLogEntry, Spread, BleEvent;
export 'pos_filter.dart';
export 'tracker_config.dart';

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

  /// Ostatni przyjęty (sprawdzony) pomiar GPS. Każdy nowy pomiar – także
  /// z identycznymi współrzędnymi (postój) – odświeża go.
  CollarFix? fix;
  final FixFilter filter;
  CollarNode(this.num) : filter = FixFilter(num);

  /// Kiedy telefon dostał ostatni pakiet od tego urządzenia (dowolny).
  DateTime? lastPacketAt;

  /// Filtr adaptacyjny – pozycja do wyświetlania i odległości (trasa i
  /// dystans liczą się z surowych pomiarów).
  final smooth = PosFilter();

  /// Pozycja do pokazania na mapie: po filtrze, a bez niego surowa.
  LatLng? get displayLl => fix == null ? null : (smooth.position ?? fix!.ll);

  /// Szacowany błąd pozycji do pokazania (m).
  double? get displayAccM {
    final f = fix;
    if (f == null) return null;
    final raw = f.accuracyM ?? DogDistance.unknownDogAccM;
    final a = smooth.accuracyM;
    return a == null ? raw : math.max(a, raw * 0.5);
  }

  /// Chwila ostatniego pomiaru z ruchem (null = brak).
  DateTime? get movedAt => lastMoved?.fixAt;

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

/// Tryb pracy Valkor Track.
///
/// Częstotliwość pozycji ustawia firmware trackera (interwał rozgłaszania,
/// interwał GPS, limit nadawania radia) – zapytania z telefonu jej nie
/// zwiększą: Meshtastic odpowiada na zapytanie o pozycję najwyżej raz na
/// 3 minuty. Dlatego tryb ma swój [profile] ustawień trackera, który
/// użytkownik może zatwierdzić, a rzeczywisty odstęp pokazujemy osobno
/// ([CollarDiagnostics.medianInterval]).
enum TrackMode {
  sport('Sportowy', 'ok. 5 s', 2, 5, TrackerProfile.sport),
  walk('Spacerowy', 'ok. 15 s', 5, 15, TrackerProfile.walk),
  saver('Oszczędny', 'ok. 60 s', 5, 60, TrackerProfile.saver),
  search('Poszukiwanie', 'najczęściej (ok. 5 s)', 1, 5, TrackerProfile.sport);

  final String _label;
  final String range;

  /// Co ile sekund aplikacja odczytuje kolejkę wiadomości przez Bluetooth
  /// (dodatkowo od razu po powiadomieniu z urządzenia).
  final int readSec;

  /// Najdłuższy odstęp zgodny z trybem (do ostrzeżenia, że tracker wysyła rzadziej).
  final int targetSec;

  /// Ustawienia trackera dla tego trybu.
  final TrackerProfile profile;
  const TrackMode(this._label, this.range, this.readSec, this.targetSec, this.profile);
  String get label => tr(_label);
  String get rangeLabel => tr(range);
}

/// Stan zmiany ustawień trackera z aplikacji.
enum ProfileApply { idle, waiting, verified, failed }

/// Ostatnia znana pozycja psa – zapamiętana w telefonie, żeby była
/// widoczna także po zamknięciu aplikacji albo utracie łączności.
class LastSeen {
  final double lat, lng;

  /// Kiedy GPS trackera zmierzył tę pozycję.
  final DateTime at;
  final int? battery;
  final int? node;
  const LastSeen(this.lat, this.lng, this.at, {this.battery, this.node});

  LatLng get ll => LatLng(lat, lng);

  Map<String, dynamic> toJson() => {
        'lat': double.parse(lat.toStringAsFixed(6)),
        'lng': double.parse(lng.toStringAsFixed(6)),
        'at': at.toIso8601String(),
        if (battery != null) 'bat': battery,
        if (node != null) 'node': node,
      };

  static LastSeen? fromJson(Object? j) {
    if (j is! Map) return null;
    final lat = j['lat'], lng = j['lng'], at = DateTime.tryParse('${j['at']}');
    if (lat is! num || lng is! num || at == null) return null;
    if (lat.abs() > 90 || lng.abs() > 180) return null;
    return LastSeen(lat.toDouble(), lng.toDouble(), at,
        battery: j['bat'] is int ? j['bat'] as int : null, node: j['node'] is int ? j['node'] as int : null);
  }
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

  /// Ustawienia urządzenia połączonego przez Bluetooth (odczytane po połączeniu).
  final config = TrackerConfig();

  /// Oczekiwany odstęp pozycji psa wg ustawień trackera (s). Tylko przy
  /// połączeniu bezpośrednim – przy dwóch modułach odczytujemy ustawienia
  /// urządzenia w kieszeni, a nie trackera na psie.
  double? get expectedIntervalSec => direct ? config.expectedIntervalSec : null;

  /// Ustawienia trackera pasują do trybu (null = nie wiadomo).
  bool? get trackerMatchesMode => direct && config.known ? mode.profile.matches(config) : null;

  /// Tryb, którego ustawienia są zapisane w trackerze (odczyt z urządzenia);
  /// null = ustawienia własne albo nieznane.
  TrackMode? get deviceMode {
    if (!direct || !config.known) return null;
    for (final m in const [TrackMode.sport, TrackMode.walk, TrackMode.saver]) {
      if (m.profile.matches(config)) return m;
    }
    return null;
  }

  /// Obserwowany odstęp wyraźnie gorszy niż wynika z ustawień trackera
  /// (mediana ponad 1,5 × albo pojedyncze przerwy ponad 4 × i ponad 30 s).
  bool get intervalMismatch {
    final e = expectedIntervalSec, m = diag.medianInterval, sp = diag.intervalSpread;
    if (e == null || m == null) return false;
    return m > e * 1.5 || (sp != null && sp.max > math.max(30, e * 4));
  }

  /// Zmiana ustawień trackera: stan, profil, błąd.
  ProfileApply applyState = ProfileApply.idle;
  TrackerProfile? pendingProfile;
  String? applyError;
  DateTime? _appliedAt;
  Timer? _verify;

  /// Zapisuje w trackerze ustawienia profilu [p]. Tracker po zmianie
  /// uruchamia się ponownie; po ponownym połączeniu aplikacja odczytuje
  /// ustawienia i sprawdza, czy zmiana się zapisała. Zwraca błąd albo null.
  Future<String?> applyProfile(TrackerProfile p) async {
    final me = myNode;
    if (!connected || me == null || !config.known) return tr('Najpierw połącz tracker i poczekaj na odczyt jego ustawień.');
    if (!direct) {
      return tr('Zmiana ustawień działa, gdy telefon jest połączony bezpośrednio z trackerem na psie.');
    }
    final lora = p.loraBytes(config);
    final pos = p.positionBytes(config);
    pendingProfile = p;
    applyState = ProfileApply.waiting;
    applyError = null;
    _appliedAt = DateTime.now();
    _verifyPending = false;
    _expectReboot = true;
    notifyListeners();
    try {
      // Każda sekcja osobno, przez kolejkę Bluetooth (bez równoległego
      // odczytu). Firmware zapisuje sekcję od razu i po kilku sekundach
      // uruchamia się ponownie – wtedy Android zgłasza zwykle błąd GATT 133
      // albo rozłączenie. To oczekiwane: łączymy się ponownie i sprawdzamy.
      if (lora != null) await _write(encodeSetConfig(me, 6, lora, id: meshRandomId()));
      await _write(encodeSetConfig(me, 2, pos, id: meshRandomId()));
    } catch (e) {
      _expectReboot = false;
      applyState = ProfileApply.failed;
      applyError = gattHint(e) ?? tr('Nie udało się wysłać ustawień: {0}', [e]);
      notifyListeners();
      return applyError;
    }
    // Gdy tracker nie uruchomi się ponownie, sami odczytujemy ustawienia.
    _verify?.cancel();
    _verify = Timer(const Duration(seconds: 25), () async {
      if (applyState != ProfileApply.waiting) return;
      if (connected) {
        try {
          await verifyRead();
          await _drain();
        } catch (_) {}
      }
      _verify = Timer(const Duration(seconds: 35), () {
        if (applyState != ProfileApply.waiting) return;
        applyState = ProfileApply.failed;
        applyError = tr('Tracker nie potwierdził zmiany. Sprawdź ustawienia w aplikacji Meshtastic.');
        notifyListeners();
      });
    });
    return null;
  }

  /// Prosi tracker o pełny odczyt ustawień, który potwierdzi (albo nie)
  /// zapis profilu. Zwraca identyfikator odczytu.
  @visibleForTesting
  Future<int> verifyRead() async {
    _expectReboot = false;
    _configId = meshRandomId();
    _verifyPending = true;
    await _write(encodeWantConfig(_configId));
    return _configId;
  }

  /// Po odczycie ustawień: czy zmiana z aplikacji naprawdę się zapisała.
  /// Liczy się tylko pełny odczyt ustawień rozpoczęty po zapisie (po
  /// ponownym połączeniu albo nasz ponowny odczyt) – nie wcześniejszy.
  void _checkApplied(DateTime t, int completeId) {
    final p = pendingProfile, at = _appliedAt;
    if (applyState != ProfileApply.waiting || p == null || at == null || !t.isAfter(at)) return;
    if (!_verifyPending || completeId != _configId) return;
    _verifyPending = false;
    _verify?.cancel();
    if (p.matches(config)) {
      applyState = ProfileApply.verified;
      applyError = null;
    } else {
      applyState = ProfileApply.failed;
      applyError = tr('Tracker nie przyjął wszystkich zmian: {0}.', [p.diff(config).map((d) => d.$1).join(', ')]);
    }
  }

  /// Ile czasu (s) firmware Meshtastic nie odpowiada na kolejne zapytanie
  /// o pozycję (PositionModule: „Skip Position reply since we sent a reply
  /// <3min ago”). Częstsze zapytania tylko zajmują Bluetooth i radio.
  static const requestThrottleSec = 180;

  /// Identyfikatory wysłanych zapytań o pozycję (do liczenia odpowiedzi).
  final Set<int> _requestIds = {};
  DateTime? _openedAt;

  /// Odczyt ustawień po zapisie – tylko on potwierdza zmianę.
  bool _verifyPending = false;

  /// Tracker uruchomi się ponownie po zapisie ustawień (rozłączenie oczekiwane).
  bool _expectReboot = false;

  /// Czytelny opis błędu Bluetooth GATT (133 i podobne), null = inny błąd.
  static String? gattHint(Object e) {
    final s = e.toString();
    if (s.contains('133') || s.toUpperCase().contains('GATT')) {
      return tr('Błąd Bluetooth (GATT {0}). Zwykle znaczy, że połączenie zerwało się w trakcie operacji – np. tracker uruchamia się ponownie albo jest za daleko. Aplikacja połączy się ponownie i sprawdzi ustawienia.',
          [RegExp(r'133|\d{2,3}').firstMatch(s)?.group(0) ?? '?']);
    }
    return null;
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

  /// Przez tyle sekund po połączeniu opóźnione pakiety traktujemy jako
  /// zaległą kolejkę trackera (pomiary historyczne).
  static const backlogWindowSec = 30;

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

  /// Tracker psa [dogId] do podglądu na ekranie Valkor Track. Aktywny pies –
  /// jak [dogNode] (także wybór automatyczny); inne psy – tylko tracker
  /// przypisany do ich profilu (nie zgadujemy cudzego).
  int? viewNode(String dogId) {
    if (dogId == activeDog()) return dogNode;
    for (final e in assigned.entries) {
      if (e.value == dogId) return e.key;
    }
    return null;
  }

  CollarNode? nodeOf(String dogId) {
    final n = viewNode(dogId);
    return n == null ? null : nodes[n];
  }

  /// Ostatnie znane pozycje psów (id psa → pozycja), zapisywane w telefonie.
  final Map<String, LastSeen> lastSeen = {};
  final Map<String, DateTime> _lastSeenSaved = {};

  /// Najświeższa znana pozycja psa: bieżący pomiar albo zapamiętana.
  LastSeen? lastKnown(String dogId) {
    final n = nodeOf(dogId);
    final f = n?.fix;
    final saved = lastSeen[dogId];
    if (f != null && (saved == null || !f.fixAt.isBefore(saved.at))) {
      return LastSeen(f.lat, f.lng, f.fixAt, battery: n!.battery, node: n.num);
    }
    return saved;
  }

  /// Zapamiętuje pozycję psa, do którego należy tracker [node] (co najwyżej
  /// raz na [_lastSeenEverySec] s, żeby nie zapisywać przy każdym pomiarze).
  static const _lastSeenEverySec = 30;
  void _rememberLast(int node, CollarFix f, DateTime now) {
    final ids = <String>{
      for (final e in assigned.entries)
        if (e.key == node) e.value,
      if (node == dogNode) activeDog(),
    };
    var changed = false;
    for (final id in ids) {
      final old = lastSeen[id];
      if (old != null && f.fixAt.isBefore(old.at)) continue;
      lastSeen[id] = LastSeen(f.lat, f.lng, f.fixAt, battery: nodes[node]?.battery, node: node);
      final saved = _lastSeenSaved[id];
      if (saved == null || now.difference(saved).inSeconds >= _lastSeenEverySec) {
        _lastSeenSaved[id] = now;
        changed = true;
      }
    }
    if (changed) unawaited(_save());
  }

  /// Usuwa zapamiętaną pozycję psa (np. po usunięciu profilu).
  Future<void> forgetLastSeen(String dogId) async {
    if (lastSeen.remove(dogId) == null) return;
    notifyListeners();
    await _save();
  }

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
      final l = j['last'];
      if (l is Map) {
        for (final e in l.entries) {
          final v = LastSeen.fromJson(e.value);
          if (v != null) lastSeen['${e.key}'] = v;
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
        if (lastSeen.isNotEmpty) 'last': {for (final e in lastSeen.entries) e.key: e.value.toJson()},
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
        if (!up) _onLost(why: tr('Bluetooth rozłączony'));
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
      _openedAt = DateTime.now();
      config.clear();
      _configId = meshRandomId();
      // Po zapisie ustawień ten odczyt je weryfikuje.
      if (applyState == ProfileApply.waiting) _verifyPending = true;
      _expectReboot = false;
      await _write(encodeWantConfig(_configId));
      await _drain();
      state = CollarState.connected;
      _retrySec = 5;
      diag.connectedAt = DateTime.now();
      final loss = diag.lastLoss;
      diag.addBleEvent(diag.connectedAt!, BleEvent.connected,
          loss == null ? null : tr('po {0} s przerwy', [diag.connectedAt!.difference(loss.at).inSeconds]));
      notifyListeners();
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _tickPoll());
    } catch (e) {
      error = _message(e);
      diag.lastError = CollarDiagnostics.bleErrorText(e);
      diag.addBleEvent(DateTime.now(), BleEvent.failed, CollarDiagnostics.bleErrorText(e));
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

  void _onLost({String? why}) {
    _poll?.cancel();
    _poll = null;
    if (state == CollarState.connected) {
      diag.addBleEvent(DateTime.now(), BleEvent.lost, why ?? error);
    }
    if (!_wanted) {
      state = CollarState.off;
      notifyListeners();
      return;
    }
    // Już czekamy na ponowne łączenie – drugie zgłoszenie utraty nic nie zmienia.
    if (state == CollarState.lost && _retry?.isActive == true) return;
    state = CollarState.lost;
    diag.reconnects++;
    notifyListeners();
    // Po zapisie ustawień tracker uruchamia się ponownie – łączymy po 8 s.
    if (_expectReboot) {
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 8), _open);
      return;
    }
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

  /// Zamiast zapisu przez Bluetooth (testy).
  @visibleForTesting
  Future<void> Function(Uint8List data)? writeOverride;

  Future<void> _write(Uint8List data) async {
    final w = writeOverride;
    final id = deviceId;
    if (w == null && id == null) return;
    await bleOp(() => w != null ? w(data) : UniversalBle.write(id!, MeshBle.service, MeshBle.toRadio, data), retries: 2);
  }

  /// Kolejka operacji Bluetooth: jedna naraz. Android nie obsługuje dwóch
  /// operacji GATT jednocześnie – zapis w trakcie odczytu kończy się często
  /// błędem 133. Nieudana operacja jest ponawiana najwyżej [retries] razy
  /// (po 0,4 s, 0,8 s…), potem błąd idzie dalej.
  Future<void> _bleChain = Future.value();

  @visibleForTesting
  Future<T> bleOp<T>(Future<T> Function() op, {int retries = 1}) {
    final c = Completer<T>();
    _bleChain = _bleChain.then((_) async {
      for (var attempt = 0;; attempt++) {
        try {
          c.complete(await op());
          return;
        } catch (e) {
          // Po zerwaniu połączenia operacje w toku kończą się błędem – to
          // skutek utraty, nie osobny problem: liczymy osobno i nie ponawiamy.
          final down = state == CollarState.off || state == CollarState.lost;
          diag.noteBleError(e, down: down, at: DateTime.now());
          if (attempt >= retries || down || _disconnectError(e)) {
            diag.bleFailures++;
            c.completeError(e);
            return;
          }
          diag.bleRetries++;
          await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
        }
      }
    });
    return c.future;
  }

  static bool _disconnectError(Object e) {
    final c = CollarDiagnostics.bleErrorCode(e);
    return c == 'deviceDisconnected' || c == 'connectionTerminated' || c == 'operationCancelled' || c == 'deviceNotFound';
  }

  int _tick = 0;

  void _tickPoll() {
    if (state != CollarState.connected) return;
    final tick = _tick++;
    // W trakcie zapisu ustawień nie odczytujemy – kolejka i tak by czekała.
    if (_expectReboot) return;
    // Odczyt kolejki co [TrackMode.readSec] s (powiadomienia i tak budzą odczyt od razu).
    if (tick % mode.readSec == 0) _drain();
    final now = DateTime.now();
    // Sygnał Bluetooth co 10 s.
    final id = deviceId;
    // Przez kolejkę – odczyt sygnału równolegle z odczytem danych daje błędy GATT.
    if (id != null && tick % 10 == 0) {
      bleOp(() => UniversalBle.readRssi(id), retries: 0).then((v) {
        diag.bleRssi = v;
        diag.bleRssiAt = DateTime.now();
      }).catchError((_) {});
    }
    final req = positionRequestDue(now);
    if (req != null) {
      final rid = meshRandomId();
      _requestIds.add(rid);
      if (_requestIds.length > 20) _requestIds.remove(_requestIds.first);
      diag.requestsSent++;
      diag.lastRequestAt = now;
      _write(encodePositionRequest(req, id: rid)).catchError((_) {});
    }
  }

  /// Do kogo wysłać zapytanie o pozycję teraz (null = nie wysyłać).
  ///
  /// Firmware odpowiada najwyżej raz na 3 minuty, więc pytamy tylko wtedy,
  /// gdy naprawdę brakuje pozycji: chwilę po połączeniu, jeśli jeszcze jej
  /// nie ma, albo gdy ostatni pomiar psa ma ponad 3 minuty. Pozycje na
  /// bieżąco przychodzą same – co interwał rozgłaszania trackera.
  @visibleForTesting
  int? positionRequestDue(DateTime now) {
    final target = dogNode, me = myNode, opened = _openedAt;
    if (target == null || me == null || opened == null) return null;
    final f = dog?.fix;
    final need = f == null ? now.difference(opened).inSeconds >= 3 : f.ageSec(now) >= requestThrottleSec;
    final last = diag.lastRequestAt;
    if (!need || (last != null && now.difference(last).inSeconds < requestThrottleSec)) return null;
    return target;
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
          final bytes = await bleOp(() => UniversalBle.read(id, MeshBle.service, MeshBle.fromRadio));
          diag.bleReads++;
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
          n.lastPacketAt = t;
          n.rssi = e.rssi ?? n.rssi;
          diag.positions++;
          final isDog = e.node == dogNode;
          final reply = e.requestId != null && _requestIds.remove(e.requestId);
          if (reply) diag.requestReplies++;
          if (isDog) diag.addSeq(e.position.seq);
          if (isDog) diag.addRx(t);
          // Tuż po (ponownym) połączeniu tracker oddaje zaległą kolejkę pakietów.
          final opened = _openedAt;
          final afterConnect = opened != null && t.difference(opened).inSeconds.abs() <= backlogWindowSec;
          final v = n.filter.check(e.position, t, packetId: e.packetId, afterConnect: afterConnect);
          if (v.accepted) n.smooth.update(v.fix!.ll, v.fix!.fixAt, accuracyM: v.fix!.accuracyM, speedMs: v.fix!.speedMs);
          _log(e, t, v, reply, n);
          if (!v.accepted) {
            diag.reject(v.reject!);
            // Zaokrąglona pozycja: pokazujemy ostrzeżenie, ale nie traktujemy jej jako pomiaru.
            if (v.reject == FixReject.coarse) n.position = e.position;
            break;
          }
          final f = v.fix!;
          if (f.historical) diag.historical++;
          if (isDog && f.timeIsFix && !f.historical) diag.addLag(f.lagSec);
          if (isDog && n.fix != null) {
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
          if (!f.moved) diag.still++;
          _rememberLast(e.node, f, t);
          _fixes.add(f);
        case MeshBattery():
          final n = nodes.putIfAbsent(e.node, () => CollarNode(e.node));
          n.battery = e.level;
          n.lastHeard = t;
        case MeshConfigEvent():
          config.set(e.section, e.raw, t);
        case MeshConfigComplete():
          _checkApplied(t, e.id);
        case MeshRoutingEvent():
          // Błąd dostarczenia (np. limit nadawania radia) – do diagnostyki.
          if (e.error != 0) diag.lastError = tr('Błąd Meshtastic nr {0} (pakiet {1})', [e.error, e.requestId]);
        case MeshRebooted():
          break;
      }
    }
    notifyListeners();
  }

  void _log(MeshPositionEvent e, DateTime t, FixVerdict v, bool reply, CollarNode n) {
    final p = e.position;
    final f = v.fix;
    final at = f?.fixAt ?? (p.timeIsFix ? p.time : null);
    final h = at == null ? null : HandlerTrack.instance.at(at);
    final dd = f == null
        ? null
        : DogDistance.of(f, HandlerTrack.instance, now: t, dogFiltered: n.smooth.position, dogFilteredAccM: n.smooth.accuracyM);
    final phone = HandlerTrack.instance.last;
    diag.addLog(FixLogEntry(
      receivedAt: t,
      node: e.node,
      packetId: e.packetId,
      phoneAgeSec: phone == null ? null : t.difference(phone.at).inMilliseconds / 1000,
      compareDtSec: dd?.compareDtSec,
      filteredDistanceM: dd?.matchedM,
      uncertaintyM: dd?.matchedUncertaintyM,
      fixAt: p.timeIsFix ? p.time : null,
      sentAt: p.sentTime,
      lat: p.lat,
      lng: p.lng,
      accuracyM: p.accuracyM,
      hdop: p.hdop,
      speedMs: p.speedMs,
      courseDeg: p.courseDeg,
      sats: p.sats,
      seq: p.seq,
      loraRssi: e.rssi == 0 ? null : e.rssi,
      snr: e.rssi == null || e.rssi == 0 ? null : e.snr,
      bleRssi: diag.bleRssi,
      phoneAccuracyM: h?.accuracyM,
      distanceM: h == null ? null : const Distance()(h.ll, LatLng(p.lat, p.lng)),
      reply: reply,
      verdict: f == null ? v.reject!.name : (f.moved ? 'ok' : 'postoj'),
      historical: f?.historical ?? false,
      noDistanceReason: f == null || dd?.matchedM != null ? null : DogDistance.whyNot(f, HandlerTrack.instance, now: t),
    ));
  }

  /// Odległość psa od przewodnika z dopasowaniem czasu i niepewnością.
  DogDistance? distanceTo(String dogId, {DateTime? now}) {
    final n = nodeOf(dogId);
    return DogDistance.of(n?.fix, HandlerTrack.instance,
        now: now ?? DateTime.now(), dogFiltered: n?.smooth.position, dogFilteredAccM: n?.smooth.accuracyM);
  }

  /// Bieżąca prędkość psa (m/s) – tylko z pomiaru na żywo, nie starszego
  /// niż 2 × rzeczywisty odstęp pomiarów (min. 15 s). Postój = 0. Starej
  /// prędkości nie pokazujemy jako bieżącej (null = „–”).
  double? currentSpeedMs(String dogId, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (status(now: t, dogId: dogId) != DogLink.live) return null;
    final n = nodeOf(dogId);
    final f = n?.fix;
    if (f == null) return null;
    final m = diag.medianInterval;
    final limit = math.max(15.0, (m ?? 7.5) * 2);
    if (f.ageSec(t) > limit) return null;
    return n!.speedMs;
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
  DogLink status({DateTime? now, String? dogId}) {
    final t = now ?? DateTime.now();
    if (deviceId == null) return DogLink.none;
    final other = dogId != null && dogId != activeDog();
    final nodeNum = other ? viewNode(dogId) : dogNode;
    // Inny pies bez przypisanego trackera – nie ma czego śledzić.
    if (other && nodeNum == null) return DogLink.none;
    final d = nodeNum == null ? null : nodes[nodeNum];
    final direct = nodeNum != null && nodeNum == myNode;
    switch (state) {
      case CollarState.off:
        return DogLink.bluetoothOff;
      case CollarState.connecting:
      case CollarState.lost:
        return DogLink.connecting;
      case CollarState.connected:
        break;
    }
    final heardAge = d?.lastHeard == null ? null : t.difference(d!.lastHeard!).inSeconds;
    final loraSilent = !direct && (heardAge == null || heardAge > loraSilentSec);
    final f = d?.fix;
    if (f == null) return loraSilent ? DogLink.loraSilent : DogLink.waitingGps;
    // Pomiar zaległy (z kolejki po połączeniu) nigdy nie jest „na żywo”.
    if (f.ageSec(t) <= liveLimitSec && !f.historical) return DogLink.live;
    return loraSilent ? DogLink.loraSilent : DogLink.stale;
  }

  /// Udaje otwarte połączenie od chwili [t] (testy zapytań o pozycję).
  @visibleForTesting
  void markOpenedForTest(DateTime t) => _openedAt = t;

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
    config.clear();
    applyState = ProfileApply.idle;
    pendingProfile = null;
    applyError = null;
    _appliedAt = null;
    _verify?.cancel();
    _requestIds.clear();
    _openedAt = null;
    writeOverride = null;
    _verifyPending = false;
    _expectReboot = false;
    _bleChain = Future.value();
    lastSeen.clear();
    _lastSeenSaved.clear();
    _loaded = loaded;
  }
}
