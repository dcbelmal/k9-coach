import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Minimalna obsługa protokołu Meshtastic (protobuf) – tylko to, czego
/// potrzebuje obroża GPS: pozycje, nazwy urządzeń i bateria.
///
/// Bez generowanego kodu protobuf: czytamy pola po numerach z plików
/// `meshtastic/*.proto` (FromRadio, MeshPacket, Data, Position, NodeInfo,
/// User, MyNodeInfo, Telemetry). Nieznane pola są pomijane, więc nowsze
/// wersje oprogramowania urządzenia nie psują odczytu.

/// Pola jednej wiadomości protobuf: numer pola → wartości (w kolejności).
/// Varint i fixed32/64 → `int`, pola długości → `Uint8List`.
class PbFields {
  final Map<int, List<Object>> _f;
  PbFields._(this._f);

  static PbFields parse(List<int> bytes) {
    final f = <int, List<Object>>{};
    final r = _Reader(bytes);
    while (!r.done) {
      final key = r.varint();
      final field = key >> 3;
      final type = key & 7;
      final Object v;
      switch (type) {
        case 0:
          v = r.varint();
        case 1:
          v = r.fixed64();
        case 2:
          v = r.bytes(r.varint());
        case 5:
          v = r.fixed32();
        default:
          throw const FormatException('Nieobsługiwany typ pola protobuf');
      }
      (f[field] ??= []).add(v);
    }
    return PbFields._(f);
  }

  bool has(int field) => _f.containsKey(field);
  int? integer(int field) => _f[field]?.whereType<int>().lastOrNull;

  /// sfixed32 / int32 ze znakiem.
  int? signed32(int field) => integer(field)?.toSigned(32);

  Uint8List? raw(int field) => _f[field]?.whereType<Uint8List>().lastOrNull;
  PbFields? message(int field) {
    final b = raw(field);
    return b == null ? null : PbFields.parse(b);
  }

  String? string(int field) {
    final b = raw(field);
    if (b == null) return null;
    try {
      return utf8.decode(b, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// float (fixed32) z bitów IEEE 754.
  double? float32(int field) {
    final i = integer(field);
    if (i == null) return null;
    final d = ByteData(4)..setUint32(0, i & 0xffffffff, Endian.little);
    return d.getFloat32(0, Endian.little);
  }
}

class _Reader {
  final List<int> b;
  int i = 0;
  _Reader(this.b);
  bool get done => i >= b.length;

  int _byte() {
    if (i >= b.length) throw const FormatException('Ucięta wiadomość protobuf');
    return b[i++];
  }

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final x = _byte();
      if (shift < 64) result |= (x & 0x7f) << shift;
      if (x & 0x80 == 0) return result;
      shift += 7;
      if (shift > 70) throw const FormatException('Zbyt długi varint');
    }
  }

  int fixed32() {
    var v = 0;
    for (var k = 0; k < 4; k++) {
      v |= _byte() << (8 * k);
    }
    return v;
  }

  int fixed64() {
    var v = 0;
    for (var k = 0; k < 8; k++) {
      v |= _byte() << (8 * k);
    }
    return v;
  }

  Uint8List bytes(int n) {
    if (n < 0 || i + n > b.length) throw const FormatException('Ucięta wiadomość protobuf');
    final out = Uint8List.fromList(b.sublist(i, i + n));
    i += n;
    return out;
  }
}

/// Zapis wiadomości protobuf.
class PbWriter {
  final _out = BytesBuilder();

  void _varint(int v) {
    var x = v;
    // Liczby ujemne zapisujemy jako 64-bitowe (tak jak protobuf dla int32).
    for (var k = 0; k < 10; k++) {
      final low = x & 0x7f;
      x = (x >> 7) & 0x01ffffffffffffff;
      if (x == 0) {
        _out.addByte(low);
        return;
      }
      _out.addByte(low | 0x80);
    }
  }

  void varint(int field, int v) {
    _varint(field << 3);
    _varint(v);
  }

  void boolean(int field, bool v) => varint(field, v ? 1 : 0);

  void fixed32(int field, int v) {
    _varint((field << 3) | 5);
    for (var k = 0; k < 4; k++) {
      _out.addByte((v >> (8 * k)) & 0xff);
    }
  }

  void bytes(int field, List<int> v) {
    _varint((field << 3) | 2);
    _varint(v.length);
    _out.add(v);
  }

  Uint8List toBytes() => _out.toBytes();
}

/// Numery portów (PortNum) używane przez obrożę.
class MeshPort {
  static const position = 3;
  static const nodeInfo = 4;
  static const telemetry = 67;
}

/// Model sprzętu T1000-E w Meshtastic (HardwareModel.TRACKER_T1000_E).
const hwT1000E = 71;

/// Pozycja z urządzenia Meshtastic.
class MeshPosition {
  final double lat, lng;
  final int? altitude;

  /// Czas ustalenia pozycji przez urządzenie (jeśli GPS go podał).
  final DateTime? time;
  final double? speedMs;
  final int? sats;

  /// Precyzja pozycji w bitach (32 = pełna). Mniej = kanał celowo zaokrągla
  /// pozycję (np. ok. 1,5 km na domyślnym publicznym kanale Meshtastic).
  final int? precisionBits;

  /// HDOP (rozmycie poziome, ×1 – już podzielone przez 100), jeśli podane.
  final double? hdop;

  /// Dokładność odbiornika GPS w metrach (gps_accuracy, mm → m), jeśli podana.
  final double? gpsAccuracyM;

  /// Rodzaj fixu z NMEA (2 = 2D, 3 = 3D), jeśli podany.
  final int? fixType;

  /// Numer kolejny pozycji (seq_number), jeśli podany.
  final int? seq;

  const MeshPosition(this.lat, this.lng,
      {this.altitude, this.time, this.speedMs, this.sats, this.precisionBits, this.hdop, this.gpsAccuracyM, this.fixType, this.seq});

  /// Szacowana dokładność pozycji w metrach (null = urządzenie jej nie podaje).
  /// Wzór jak w Meshtastic: HDOP × dokładność odbiornika (domyślnie ok. 5 m).
  double? get accuracyM {
    final h = hdop;
    if (h == null || h <= 0) return null;
    return h * ((gpsAccuracyM ?? 0) > 0 ? gpsAccuracyM! : 5);
  }

  /// Pozycja zaokrąglona przez ustawienia kanału – nie nadaje się do trasy.
  bool get coarse => precisionBits != null && precisionBits! > 0 && precisionBits! < 24;

  /// Odczyt `Position`. Zwraca null, gdy brak współrzędnych (urządzenie
  /// bez fixu wysyła 0,0 albo pomija pola).
  static MeshPosition? parse(PbFields p) {
    final lat = p.signed32(1);
    final lng = p.signed32(2);
    if (lat == null || lng == null || (lat == 0 && lng == 0)) return null;
    final la = lat / 1e7, lo = lng / 1e7;
    if (la.abs() > 90 || lo.abs() > 180) return null;
    final t = p.integer(4) ?? p.integer(7);
    return MeshPosition(
      la,
      lo,
      altitude: p.signed32(3),
      time: t == null || t == 0 ? null : DateTime.fromMillisecondsSinceEpoch(t * 1000, isUtc: true).toLocal(),
      speedMs: p.integer(15)?.toDouble(),
      sats: p.integer(19),
      precisionBits: p.integer(23),
      hdop: p.integer(12) == null || p.integer(12) == 0 ? null : p.integer(12)! / 100,
      gpsAccuracyM: p.integer(14) == null || p.integer(14) == 0 ? null : p.integer(14)! / 1000,
      fixType: p.integer(18),
      seq: p.integer(22),
    );
  }
}

/// Zdarzenia odczytane z FromRadio.
sealed class MeshEvent {
  const MeshEvent();
}

/// Numer urządzenia, z którym połączony jest telefon.
class MeshMyInfo extends MeshEvent {
  final int myNode;
  const MeshMyInfo(this.myNode);
}

/// Informacje o urządzeniu w sieci (z bazy urządzenia lub z pakietu NODEINFO).
class MeshNodeInfo extends MeshEvent {
  final int node;
  final String? longName, shortName;
  final int? hwModel;
  final MeshPosition? position;
  final int? battery;
  final DateTime? lastHeard;
  const MeshNodeInfo(this.node, {this.longName, this.shortName, this.hwModel, this.position, this.battery, this.lastHeard});
}

/// Nowa pozycja urządzenia [node] (pakiet POSITION_APP).
class MeshPositionEvent extends MeshEvent {
  final int node;
  final MeshPosition position;
  final int? rssi;
  final double? snr;
  const MeshPositionEvent(this.node, this.position, {this.rssi, this.snr});
}

/// Poziom baterii urządzenia (0–100, 101 = zasilanie z kabla).
class MeshBattery extends MeshEvent {
  final int node;
  final int level;
  const MeshBattery(this.node, this.level);
}

/// Koniec przesyłania konfiguracji po połączeniu.
class MeshConfigComplete extends MeshEvent {
  final int id;
  const MeshConfigComplete(this.id);
}

class MeshRebooted extends MeshEvent {
  const MeshRebooted();
}

MeshNodeInfo? _user(int node, PbFields? u, {MeshPosition? pos, int? battery, DateTime? heard}) => MeshNodeInfo(
      node,
      longName: u?.string(2),
      shortName: u?.string(3),
      hwModel: u?.integer(5),
      position: pos,
      battery: battery,
      lastHeard: heard,
    );

/// Dekoduje jedną wiadomość FromRadio na listę zdarzeń (zwykle 0 lub 1).
List<MeshEvent> decodeFromRadio(List<int> bytes) {
  if (bytes.isEmpty) return const [];
  final f = PbFields.parse(bytes);
  final out = <MeshEvent>[];
  final my = f.message(3);
  if (my != null) {
    final n = my.integer(1);
    if (n != null) out.add(MeshMyInfo(n));
  }
  final ni = f.message(4);
  if (ni != null) {
    final n = ni.integer(1);
    if (n != null) {
      final pos = ni.message(3);
      final dm = ni.message(6);
      final heard = ni.integer(5);
      out.add(_user(n, ni.message(2),
          pos: pos == null ? null : MeshPosition.parse(pos),
          battery: dm?.integer(1),
          heard: heard == null || heard == 0 ? null : DateTime.fromMillisecondsSinceEpoch(heard * 1000))!);
    }
  }
  if (f.has(7)) out.add(MeshConfigComplete(f.integer(7) ?? 0));
  if (f.has(8)) out.add(const MeshRebooted());
  final pk = f.message(2);
  if (pk != null) out.addAll(_packet(pk));
  return out;
}

List<MeshEvent> _packet(PbFields pk) {
  final from = pk.integer(1);
  final data = pk.message(4);
  if (from == null || data == null) return const []; // zaszyfrowany kanał, którego nie znamy
  final port = data.integer(1);
  final payload = data.raw(2);
  if (payload == null) return const [];
  try {
    switch (port) {
      case MeshPort.position:
        final p = MeshPosition.parse(PbFields.parse(payload));
        if (p == null) return const [];
        return [MeshPositionEvent(from, p, rssi: pk.signed32(12), snr: pk.float32(8))];
      case MeshPort.nodeInfo:
        return [_user(from, PbFields.parse(payload))!];
      case MeshPort.telemetry:
        final dm = PbFields.parse(payload).message(2);
        final lvl = dm?.integer(1);
        return lvl == null ? const [] : [MeshBattery(from, lvl)];
    }
  } on FormatException {
    return const [];
  }
  return const [];
}

final _rnd = Random();

/// Losowy identyfikator (pakietu lub zapytania o konfigurację).
int meshRandomId() => 1 + _rnd.nextInt(0x7ffffffe);

/// ToRadio { want_config_id } – prośba o przesłanie stanu urządzenia.
Uint8List encodeWantConfig(int id) => (PbWriter()..varint(3, id)).toBytes();

/// ToRadio z pakietem: prośba do urządzenia [to] o aktualną pozycję.
Uint8List encodePositionRequest(int to, {int? id, int channel = 0}) {
  final data = PbWriter()
    ..varint(1, MeshPort.position)
    ..bytes(2, const [])
    ..boolean(3, true);
  final pkt = PbWriter()
    ..fixed32(2, to)
    ..varint(3, channel)
    ..bytes(4, data.toBytes())
    ..fixed32(6, id ?? meshRandomId());
  return (PbWriter()..bytes(1, pkt.toBytes())).toBytes();
}

/// ToRadio { heartbeat } – podtrzymanie połączenia.
Uint8List encodeHeartbeat() => (PbWriter()..bytes(7, const [])).toBytes();

/// Krótka nazwa urządzenia jak w Meshtastic: „!a1b2c3d4”.
String meshNodeId(int node) => '!${(node & 0xffffffff).toRadixString(16).padLeft(8, '0')}';
