// Protokół Valkor BLE v1 – firmware Valkor Track (repozytorium valkor-track-firmware,
// docs/PROTOKOL.md). Ten plik musi zgadzać się z src/protocol/valkor_protocol.* w firmware;
// test/valkor_proto_test.dart sprawdza go na wektorach wygenerowanych przez firmware.
import 'dart:typed_data';

class ValkorBle {
  static const service = '56410001-9136-4498-8cd8-64b60999c24d';
  static const data = '56410002-9136-4498-8cd8-64b60999c24d';
  static const command = '56410003-9136-4498-8cd8-64b60999c24d';

  /// Wymagane MTU (największy pakiet 62 B + 3 B nagłówka ATT).
  static const minMtu = 67;
}

enum ValkorType { position, status, info, diag, ack, perf, buildInfo, unknown }

/// Tryby firmware (bajt trybu w pakietach i komendzie SET_MODE).
enum ValkorMode {
  sport(0, 1),
  walk(1, 5),
  eco(2, 30),
  search(3, 1);

  const ValkorMode(this.code, this.periodSec);
  final int code;

  /// Docelowy okres wysyłki przez Bluetooth (s).
  final int periodSec;

  static ValkorMode? fromCode(int c) {
    for (final m in values) {
      if (m.code == c) return m;
    }
    return null;
  }
}

class ValkorFlags {
  static const fixValid = 1, historical = 2, stationary = 4, timeValid = 8;
  static const accEstimated = 16, charging = 32, lowBattery = 64, insecureLink = 128;
}

enum ValkorGnss { unknown, searching, fix, lost }

class ValkorHeader {
  final int version, flags, deviceId, seq, mode;
  final ValkorType type;
  final String firmware;
  const ValkorHeader(
      {required this.version,
      required this.type,
      required this.flags,
      required this.deviceId,
      required this.seq,
      required this.firmware,
      required this.mode});
  bool has(int flag) => flags & flag != 0;
  bool get historical => has(ValkorFlags.historical);
  bool get insecure => has(ValkorFlags.insecureLink);
}

class ValkorPosition {
  final ValkorHeader h;

  /// Czas pomiaru (UTC z odbiornika GNSS) albo null, gdy odbiornik nie podał czasu.
  final DateTime? fixTime;
  final double lat, lng;
  final double? altM, speedMs, courseDeg, accuracyM;
  final double hdop;
  final int sats, fixQuality;

  /// Od odebrania pomiaru z odbiornika do wysłania (ms); null dla historycznych.
  final int? ageMs;
  final int? batteryMv, batteryPct;

  /// Numer nowego pomiaru GNSS w trackerze (protokół 1.1, firmware 0.1.1+).
  /// null = brak (pakiet historyczny albo firmware 0.1.0).
  final int? fixId;
  const ValkorPosition(this.h,
      {required this.fixTime,
      required this.lat,
      required this.lng,
      this.altM,
      this.speedMs,
      this.courseDeg,
      this.accuracyM,
      required this.hdop,
      required this.sats,
      required this.fixQuality,
      this.ageMs,
      this.batteryMv,
      this.batteryPct,
      this.fixId});

  bool get fixValid => h.has(ValkorFlags.fixValid);
  bool get timeValid => h.has(ValkorFlags.timeValid);
  bool get stationary => h.has(ValkorFlags.stationary);

  /// true = dokładność oszacowana przez tracker (np. z HDOP), nie zmierzona przez odbiornik.
  bool get accuracyEstimated => h.has(ValkorFlags.accEstimated);
}

class ValkorStatus {
  final ValkorHeader h;
  final int? lastFixAgeMs;
  final ValkorGnss gnss;
  final int sats;
  final double hdop;
  final int? batteryMv, batteryPct;
  final int historyCount;
  const ValkorStatus(this.h,
      {this.lastFixAgeMs,
      required this.gnss,
      required this.sats,
      required this.hdop,
      this.batteryMv,
      this.batteryPct,
      required this.historyCount});
}

class ValkorInfo {
  final ValkorHeader h;
  final int hwModel, capabilities, gnssPeriodMs, historyCapacity;
  final String upstream;
  const ValkorInfo(this.h,
      {required this.hwModel,
      required this.capabilities,
      required this.gnssPeriodMs,
      required this.historyCapacity,
      required this.upstream});
  String get hwName => switch (hwModel) { 1 => 'SenseCAP T1000-E', 2 => 'Valkor', _ => '?' };
}

class ValkorDiag {
  final ValkorHeader h;
  final int uptimeS, fixesTotal, fixesRejected, gnssIntervalAvgMs, gnssIntervalMaxMs;
  final int liveSent, historySent, notifyFailed, mtuTooSmall, reconnects;
  final int historyStored, historyDropped, rssi, freeHeapKb, latencyAvgMs, latencyMaxMs;
  const ValkorDiag(this.h,
      {required this.uptimeS,
      required this.fixesTotal,
      required this.fixesRejected,
      required this.gnssIntervalAvgMs,
      required this.gnssIntervalMaxMs,
      required this.liveSent,
      required this.historySent,
      required this.notifyFailed,
      required this.mtuTooSmall,
      required this.reconnects,
      required this.historyStored,
      required this.historyDropped,
      required this.rssi,
      required this.freeHeapKb,
      required this.latencyAvgMs,
      required this.latencyMaxMs});
}

class ValkorAck {
  final ValkorHeader h;
  final int command, result, value;
  const ValkorAck(this.h, {required this.command, required this.result, required this.value});
  bool get ok => result == 0;
}

/// Pomiary czasu i stanu z trackera (typ 6, protokół 1.1). Okno ≈ 10 s.
class ValkorPerf {
  final ValkorHeader h;
  final int nmeaOk, nmeaBad, windowFixes, gnssIntMedianMs, gnssIntMinMs, bleIntMedianMs, bleIntMaxMs;
  final int latencyMedianMs, queueWaitAvgMs, queueWaitMaxMs, fixesSkipped, samePosition, queueFull, notifyErrors;
  final int telemetrySent;
  final bool gnssActive;

  /// null = brak danych (0xFFFF / 0x7FFF w pakiecie).
  final int? lastFixAgeMs, cpuPermille, fsFreeKb;
  final double? tempC;
  const ValkorPerf(this.h,
      {required this.nmeaOk,
      required this.nmeaBad,
      required this.gnssActive,
      required this.windowFixes,
      required this.gnssIntMedianMs,
      required this.gnssIntMinMs,
      required this.bleIntMedianMs,
      required this.bleIntMaxMs,
      required this.latencyMedianMs,
      required this.lastFixAgeMs,
      required this.queueWaitAvgMs,
      required this.queueWaitMaxMs,
      required this.fixesSkipped,
      required this.samePosition,
      required this.queueFull,
      required this.notifyErrors,
      required this.telemetrySent,
      required this.tempC,
      required this.cpuPermille,
      required this.fsFreeKb});
}

/// Identyfikacja firmware (typ 7, protokół 1.1).
class ValkorBuildInfo {
  final ValkorHeader h;
  final int protoMajor, protoMinor, buildId, features;
  final String firmware, commit, name;
  final bool preRelease;

  /// Okres wysyłki BLE (s) dla SPORT, WALK, ECO, SEARCH.
  final List<int> blePeriodS;
  const ValkorBuildInfo(this.h,
      {required this.protoMajor,
      required this.protoMinor,
      required this.firmware,
      required this.preRelease,
      required this.buildId,
      required this.commit,
      required this.features,
      required this.blePeriodS,
      required this.name});
  String get protocol => '$protoMajor.$protoMinor';
}

/// Pakiet z nieznanym typem (nowsze firmware) – ignorowany.
class ValkorUnknown {
  final ValkorHeader h;
  const ValkorUnknown(this.h);
}

class ValkorCmd {
  static const getInfo = 1, setMode = 2, syncHistory = 3, clearHistory = 4, getDiag = 5, stopHistory = 6;
}

int valkorCrc16(List<int> data, [int? len]) {
  var crc = 0xFFFF;
  final n = len ?? data.length;
  for (var i = 0; i < n; i++) {
    crc ^= (data[i] & 0xFF) << 8;
    for (var b = 0; b < 8; b++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc;
}

/// Ramka komendy: 0x56, 0x01, komenda, token, [argument], CRC16 (LE).
Uint8List valkorCommand(int command, {int token = 0, int? arg}) {
  final b = <int>[0x56, 1, command & 0xFF, token & 0xFF, if (arg != null) arg & 0xFF];
  final c = valkorCrc16(b);
  return Uint8List.fromList([...b, c & 0xFF, c >> 8]);
}

/// Dekoduje pakiet. Zwraca null dla uszkodzonej ramki (zły CRC, magic, wersja,
/// za krótki pakiet). Pakiet dłuższy niż znany (nowsze firmware v1) jest
/// przyjmowany – dodatkowe pola na końcu są pomijane.
Object? decodeValkor(List<int> raw) {
  final n = raw.length;
  if (n < 18 || n > 64 || raw[0] != 0x56 || raw[1] != 1) return null;
  final want = raw[n - 2] | (raw[n - 1] << 8);
  if (valkorCrc16(raw, n - 2) != want) return null;
  final d = ByteData.sublistView(Uint8List.fromList(raw));
  int u8(int o) => d.getUint8(o);
  int u16(int o) => d.getUint16(o, Endian.little);
  int u32(int o) => d.getUint32(o, Endian.little);
  int i32(int o) => d.getInt32(o, Endian.little);
  final typeByte = u8(2);
  final type = switch (typeByte) {
    1 => ValkorType.position,
    2 => ValkorType.status,
    3 => ValkorType.info,
    4 => ValkorType.diag,
    5 => ValkorType.ack,
    6 => ValkorType.perf,
    7 => ValkorType.buildInfo,
    _ => ValkorType.unknown,
  };
  final h = ValkorHeader(
      version: u8(1),
      type: type,
      flags: u8(3),
      deviceId: u32(4),
      seq: u32(8),
      firmware: '${u8(12)}.${u8(13)}.${u8(14)}',
      mode: u8(15));
  const p = 16;
  switch (type) {
    case ValkorType.position:
      if (n < 54) return null;
      final t = u32(p), ms = u16(p + 4);
      final alt = i32(p + 14), spd = u16(p + 18), crs = u16(p + 20), acc = u16(p + 22), age = u16(p + 28);
      final mv = u16(p + 30), pct = u8(p + 32), fixId = u16(p + 33);
      return ValkorPosition(h,
          fixTime: h.has(ValkorFlags.timeValid) && t > 0
              ? DateTime.fromMillisecondsSinceEpoch(t * 1000 + ms, isUtc: true)
              : null,
          lat: i32(p + 6) / 1e7,
          lng: i32(p + 10) / 1e7,
          altM: alt == -0x80000000 ? null : alt / 100,
          speedMs: spd == 0xFFFF ? null : spd / 100,
          courseDeg: crs == 0xFFFF ? null : crs / 100,
          accuracyM: acc == 0xFFFF ? null : acc / 100,
          hdop: u16(p + 24) / 100,
          sats: u8(p + 26),
          fixQuality: u8(p + 27),
          ageMs: age == 0xFFFF ? null : age,
          batteryMv: mv == 0 ? null : mv,
          batteryPct: pct == 0xFF ? null : pct,
          fixId: fixId == 0 ? null : fixId);
    case ValkorType.status:
      if (n < 34) return null;
      final age = u32(p), mv = u16(p + 8), pct = u8(p + 10);
      final g = u8(p + 4);
      return ValkorStatus(h,
          lastFixAgeMs: age == 0xFFFFFFFF ? null : age,
          gnss: g < ValkorGnss.values.length ? ValkorGnss.values[g] : ValkorGnss.unknown,
          sats: u8(p + 5),
          hdop: u16(p + 6) / 100,
          batteryMv: mv == 0 ? null : mv,
          batteryPct: pct == 0xFF ? null : pct,
          historyCount: u16(p + 12));
    case ValkorType.info:
      if (n < 42) return null;
      final up = raw.sublist(p + 8, p + 24).takeWhile((c) => c != 0).toList();
      return ValkorInfo(h,
          hwModel: u8(p),
          capabilities: u16(p + 2),
          gnssPeriodMs: u16(p + 4),
          historyCapacity: u16(p + 6),
          upstream: String.fromCharCodes(up));
    case ValkorType.diag:
      if (n < 62) return null;
      return ValkorDiag(h,
          uptimeS: u32(p),
          fixesTotal: u32(p + 4),
          fixesRejected: u32(p + 8),
          gnssIntervalAvgMs: u16(p + 12),
          gnssIntervalMaxMs: u16(p + 14),
          liveSent: u32(p + 16),
          historySent: u32(p + 20),
          notifyFailed: u32(p + 24),
          mtuTooSmall: u16(p + 28),
          reconnects: u16(p + 30),
          historyStored: u16(p + 32),
          historyDropped: u16(p + 34),
          rssi: d.getInt8(p + 36),
          freeHeapKb: u8(p + 37),
          latencyAvgMs: u16(p + 38),
          latencyMaxMs: u16(p + 40));
    case ValkorType.ack:
      if (n < 22) return null;
      return ValkorAck(h, command: u8(p), result: u8(p + 1), value: u8(p + 2));
    case ValkorType.perf:
      if (n < 64) return null;
      final lastAge = u16(p + 18), temp = d.getInt16(p + 40, Endian.little), cpu = u16(p + 42), fs = u16(p + 44);
      return ValkorPerf(h,
          nmeaOk: u32(p),
          nmeaBad: u16(p + 4),
          gnssActive: u8(p + 6) != 0,
          windowFixes: u8(p + 7),
          gnssIntMedianMs: u16(p + 8),
          gnssIntMinMs: u16(p + 10),
          bleIntMedianMs: u16(p + 12),
          bleIntMaxMs: u16(p + 14),
          latencyMedianMs: u16(p + 16),
          lastFixAgeMs: lastAge == 0xFFFF ? null : lastAge,
          queueWaitAvgMs: u16(p + 20),
          queueWaitMaxMs: u16(p + 22),
          fixesSkipped: u32(p + 24),
          samePosition: u32(p + 28),
          queueFull: u16(p + 32),
          notifyErrors: u16(p + 34),
          telemetrySent: u32(p + 36),
          tempC: temp == 0x7FFF ? null : temp / 4,
          cpuPermille: cpu == 0xFFFF ? null : cpu,
          fsFreeKb: fs == 0xFFFF ? null : fs);
    case ValkorType.buildInfo:
      if (n < 64) return null;
      String text(int o, int len) => String.fromCharCodes(raw.sublist(o, o + len).takeWhile((c) => c != 0));
      return ValkorBuildInfo(h,
          protoMajor: u8(p),
          protoMinor: u8(p + 1),
          firmware: '${u8(p + 2)}.${u8(p + 3)}.${u8(p + 4)}',
          preRelease: u8(p + 5) != 0,
          buildId: u32(p + 6),
          commit: text(p + 10, 8),
          features: u16(p + 18),
          blePeriodS: [u8(p + 20), u8(p + 21), u8(p + 22), u8(p + 23)],
          name: text(p + 24, 22));
    case ValkorType.unknown:
      return ValkorUnknown(h);
  }
}

/// Liczniki łącza Valkor po stronie telefonu (utracone / powtórzone pakiety,
/// restart urządzenia, rzeczywiste odstępy odbioru).
class ValkorLinkStats {
  int packets = 0, live = 0, historical = 0, status = 0, lost = 0, duplicates = 0, badFrames = 0, restarts = 0;
  int? _lastSeq;
  DateTime? _lastLiveRx;
  final List<double> liveIntervals = [];

  /// Numer kolejny ostatniego pakietu.
  int? get lastSeq => _lastSeq;

  /// Najdłuższa przerwa między pozycjami na żywo (s) i liczba przerw > 2 s.
  double maxLiveGapSec = 0;
  int liveGapsOver2s = 0;

  /// Odstęp od poprzedniej pozycji na żywo (s), null dla pierwszej.
  double? lastLiveIntervalSec;

  /// Rejestruje numer kolejny pakietu. Zwraca false dla duplikatu.
  bool seq(int s) {
    final last = _lastSeq;
    packets++;
    if (last != null) {
      if (s == last) {
        duplicates++;
        packets--;
        return false;
      }
      if (s < last) {
        // Mniejszy numer = urządzenie uruchomiło się ponownie.
        restarts++;
      } else if (s > last + 1) {
        lost += s - last - 1;
      }
    }
    _lastSeq = s;
    return true;
  }

  void liveRx(DateTime t) {
    final l = _lastLiveRx;
    lastLiveIntervalSec = null;
    if (l != null) {
      final s = t.difference(l).inMilliseconds / 1000;
      lastLiveIntervalSec = s;
      liveIntervals.add(s);
      if (liveIntervals.length > 600) liveIntervals.removeAt(0);
      if (s > maxLiveGapSec) maxLiveGapSec = s;
      if (s > 2) liveGapsOver2s++;
    }
    _lastLiveRx = t;
    live++;
  }

  /// Średni odstęp odbioru pozycji na żywo (s).
  double? get meanLiveInterval =>
      liveIntervals.isEmpty ? null : liveIntervals.reduce((a, b) => a + b) / liveIntervals.length;

  /// Mediana odstępu odbioru pozycji na żywo (s).
  double? get medianLiveInterval {
    if (liveIntervals.isEmpty) return null;
    final s = [...liveIntervals]..sort();
    return s[s.length ~/ 2];
  }

  /// Odsetek utraconych pakietów (0–1).
  double get lossRatio => packets + lost == 0 ? 0 : lost / (packets + lost);

  /// Po zerwaniu połączenia: numeracja i odstępy liczone od nowa (przerwy
  /// w łączności nie są „utraconymi pakietami” ani odstępem odbioru 1 Hz).
  void resetLink() {
    _lastSeq = null;
    _lastLiveRx = null;
  }

  /// Nowa sesja testowa: wszystkie liczniki od zera.
  void resetSession() {
    packets = live = historical = status = lost = duplicates = badFrames = restarts = 0;
    liveIntervals.clear();
    maxLiveGapSec = 0;
    liveGapsOver2s = 0;
    lastLiveIntervalSec = null;
    _lastLiveRx = null;
  }
}
