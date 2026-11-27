// Sesje testów terenowych (panel deweloperski): osobne okno czasu, liczniki
// od zera, podsumowanie i eksport CSV dla każdego testu.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../app_version.dart';
import '../l10n/l10n.dart';
import 'app_state.dart';
import 'collar_link.dart';
import 'distance_view.dart';

enum FieldTestKind {
  standstill('postoj', 'Test postoju'),
  distance('dokladnosc_odleglosci', 'Test dokładności odległości'),
  walk('spacer', 'Test spaceru'),
  dynamic('dynamiczny', 'Test dynamiczny'),
  bleRange('zasieg_bluetooth', 'Test zasięgu Bluetooth'),
  reconnect('utrata_i_odzyskanie', 'Test utraty i odzyskania połączenia'),
  background('praca_w_tle', 'Test pracy w tle'),
  battery('bateria', 'Test baterii');

  const FieldTestKind(this.code, this._label);
  final String code;
  final String _label;
  String get label => tr(_label);
}

/// Stan w chwili rozpoczęcia albo zakończenia testu.
class FieldTestSnapshot {
  final DateTime at;
  final int? batteryPct, batteryMv;
  final int reconnects, toBackground;
  const FieldTestSnapshot(this.at, {this.batteryPct, this.batteryMv, this.reconnects = 0, this.toBackground = 0});

  static FieldTestSnapshot of(CollarLink c, DateTime t) => FieldTestSnapshot(t,
      batteryPct: c.dog?.battery,
      batteryMv: c.valkor?.batteryMv ?? c.valkor?.status?.batteryMv,
      reconnects: c.diag.reconnects,
      toBackground: AppState.instance.toBackground);
}

/// Podsumowanie testu.
class FieldTestSummary {
  final int freshPositions, rejected, historical;
  final double? meanRxSec, medianRxSec, maxGapSec, lossPct, meanAccuracyM, meanPhoneRssi, meanTrackerRssi;
  final int? batteryStartPct, batteryEndPct, batteryStartMv, batteryEndMv;
  final int reconnects, toBackground;

  /// Czas od ponownego połączenia Bluetooth do pierwszej aktualnej pozycji (s).
  final List<double> recoverySec;
  final int valkorPackets, valkorLost;
  const FieldTestSummary({
    required this.freshPositions,
    required this.rejected,
    required this.historical,
    this.meanRxSec,
    this.medianRxSec,
    this.maxGapSec,
    this.lossPct,
    this.meanAccuracyM,
    this.meanPhoneRssi,
    this.meanTrackerRssi,
    this.batteryStartPct,
    this.batteryEndPct,
    this.batteryStartMv,
    this.batteryEndMv,
    required this.reconnects,
    required this.toBackground,
    required this.recoverySec,
    required this.valkorPackets,
    required this.valkorLost,
  });

  List<(String, String)> rows() {
    String n(double? v, [int d = 2]) => v == null ? '–' : v.toStringAsFixed(d).replaceAll('.', ',');
    return [
      (tr('Świeże pozycje'), '$freshPositions'),
      (tr('Odstęp odbioru: średnia / mediana'), '${n(meanRxSec)} / ${n(medianRxSec)} s'),
      (tr('Najdłuższa przerwa transmisji'), '${n(maxGapSec, 1)} s'),
      (tr('Utracone pakiety Valkor'), lossPct == null ? '–' : '${n(lossPct)} % ($valkorLost / ${valkorPackets + valkorLost})'),
      (tr('Średnia dokładność GNSS'), meanAccuracyM == null ? '–' : '${n(meanAccuracyM)} m'),
      (tr('RSSI telefon / tracker'), '${n(meanPhoneRssi, 0)} / ${n(meanTrackerRssi, 0)} dBm'),
      (tr('Bateria: początek → koniec'),
          '${batteryStartPct ?? '–'}% (${batteryStartMv ?? '–'} mV) → ${batteryEndPct ?? '–'}% (${batteryEndMv ?? '–'} mV)'),
      (tr('Ponowne połączenia'), '$reconnects'),
      (tr('Odzyskanie aktualnej pozycji po połączeniu'),
          recoverySec.isEmpty ? '–' : recoverySec.map((s) => '${n(s, 1)} s').join(', ')),
      (tr('Przejścia aplikacji do tła'), '$toBackground'),
      (tr('Odrzucone pomiary / historyczne'), '$rejected / $historical'),
    ];
  }

  List<String> csvLines() {
    String n(num? v, [int d = 3]) => v == null ? '' : (v is int ? '$v' : v.toStringAsFixed(d));
    return [
      'podsumowanie_testu;swieze_pozycje;$freshPositions',
      'podsumowanie_testu;odstep_odbioru_sredni_s;${n(meanRxSec)}',
      'podsumowanie_testu;odstep_odbioru_mediana_s;${n(medianRxSec)}',
      'podsumowanie_testu;najdluzsza_przerwa_s;${n(maxGapSec)}',
      'podsumowanie_testu;utracone_pakiety_proc;${n(lossPct)}',
      'podsumowanie_testu;pakiety_valkor;$valkorPackets',
      'podsumowanie_testu;pakiety_valkor_utracone;$valkorLost',
      'podsumowanie_testu;dokladnosc_gnss_srednia_m;${n(meanAccuracyM)}',
      'podsumowanie_testu;rssi_telefon_sredni_dbm;${n(meanPhoneRssi, 1)}',
      'podsumowanie_testu;rssi_tracker_sredni_dbm;${n(meanTrackerRssi, 1)}',
      'podsumowanie_testu;bateria_start_proc;${n(batteryStartPct)}',
      'podsumowanie_testu;bateria_koniec_proc;${n(batteryEndPct)}',
      'podsumowanie_testu;bateria_start_mv;${n(batteryStartMv)}',
      'podsumowanie_testu;bateria_koniec_mv;${n(batteryEndMv)}',
      'podsumowanie_testu;ponowne_polaczenia;$reconnects',
      'podsumowanie_testu;czas_odzyskania_pozycji_s;${recoverySec.map((s) => s.toStringAsFixed(1)).join(',')}',
      'podsumowanie_testu;przejscia_do_tla;$toBackground',
      'podsumowanie_testu;pomiary_odrzucone;$rejected',
      'podsumowanie_testu;pomiary_historyczne;$historical',
    ];
  }
}


/// Znacznik odległości referencyjnej (test dokładności): w chwili naciśnięcia
/// przycisku zapisujemy, co pokazywała aplikacja, i medianę odległości
/// z ostatnich [windowSec] s. Wartość referencyjna to pomiar użytkownika
/// (taśma, dalmierz, kroki) – aplikacja niczego nie przelicza.
class ReferenceMark {
  static const windowSec = 10;
  static const presets = [0, 5, 10, 20, 30, 50, 100];

  final DateTime at;
  final double refM;
  final String method;
  final String shownState, shownText;
  final double? shownM, uncertaintyM, medianRawM, medianFilteredM;
  final int samples;
  const ReferenceMark(this.at, this.refM,
      {this.method = '',
      required this.shownState,
      required this.shownText,
      this.shownM,
      this.uncertaintyM,
      this.medianRawM,
      this.medianFilteredM,
      this.samples = 0});

  static const csvHeader =
      'znacznik;czas_utc;odleglosc_referencyjna_m;metoda;wyswietlony_stan;wyswietlono;odleglosc_pokazana_m;niepewnosc_m;'
      'mediana_surowa_10s_m;mediana_filtr_10s_m;pomiary_10s;roznica_filtr_minus_referencja_m';

  String toCsv() {
    String n(double? v) => v == null ? '' : v.toStringAsFixed(2);
    final diff = medianFilteredM == null ? null : medianFilteredM! - refM;
    return 'znacznik;${at.toUtc().toIso8601String()};${n(refM)};${method.replaceAll(';', ',')};$shownState;'
        '${shownText.replaceAll(';', ',')};${n(shownM)};${n(uncertaintyM)};${n(medianRawM)};${n(medianFilteredM)};$samples;${n(diff)}';
  }
}

/// Jedna przerwa w pozycjach na żywo (test zasięgu / utraty połączenia).
class GapInfo {
  final DateTime from, to;

  /// Odległość pies–telefon: ostatnia przed przerwą i pierwsza po niej (m).
  final double? beforeM, afterM;
  const GapInfo(this.from, this.to, this.beforeM, this.afterM);
  double get sec => to.difference(from).inMilliseconds / 1000;
}

double? _median(Iterable<double> xs) {
  final v = xs.toList()..sort();
  return v.isEmpty ? null : v[v.length ~/ 2];
}

double? _maxOf(Iterable<double> xs) => xs.isEmpty ? null : xs.reduce(math.max);
double? _minOf(Iterable<double> xs) => xs.isEmpty ? null : xs.reduce(math.min);
double? _meanOf(Iterable<double> xs) => xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;

/// Droga bez dryfu: odcinek liczy się dopiero, gdy punkt odsunie się od
/// ostatniego zaliczonego o więcej niż jego niepewność (co najmniej 3 m).
double _pathM(Iterable<(LatLng, double?)> pts) {
  const dist = Distance();
  LatLng? anchor;
  var sum = 0.0;
  for (final (ll, acc) in pts) {
    if (anchor == null) {
      anchor = ll;
      continue;
    }
    final d = dist(anchor, ll);
    if (d > math.max(3.0, acc ?? 5)) {
      sum += d;
      anchor = ll;
    }
  }
  return sum;
}

/// Zasięg Bluetooth, przerwy i odzyskiwanie (test zasięgu, utraty połączenia).
class RangeStats {
  final double? currentM, maxWithTransmissionM;
  final double? lastBeforeLossM, firstRecoveredM, atReconnectM;
  final double? phoneRssiNow, phoneRssiMean, phoneRssiMin;
  final double? trackerRssiMean, trackerRssiMin;
  final List<GapInfo> gaps;

  /// Czas bez pozycji na żywo (suma przerw > 2 s) i brakujące pozycje 1 Hz.
  final double noPositionSec;
  final int missingLiveSeconds;
  final String historyState;
  const RangeStats({
    this.currentM,
    this.maxWithTransmissionM,
    this.lastBeforeLossM,
    this.firstRecoveredM,
    this.atReconnectM,
    this.phoneRssiNow,
    this.phoneRssiMean,
    this.phoneRssiMin,
    this.trackerRssiMean,
    this.trackerRssiMin,
    required this.gaps,
    required this.noPositionSec,
    required this.missingLiveSeconds,
    required this.historyState,
  });
}

/// Podsumowanie testu dynamicznego (bieg psa).
class DynamicStats {
  final double dogPathM, phonePathM;
  final double? maxSpeedMs, meanMovingSpeedMs, maxFromPhoneM;
  final double movingSec, stillSec;
  const DynamicStats(
      {required this.dogPathM,
      required this.phonePathM,
      this.maxSpeedMs,
      this.meanMovingSpeedMs,
      this.maxFromPhoneM,
      required this.movingSec,
      required this.stillSec});
}

class FieldTest {
  final FieldTestKind kind;
  String name;
  String notes;
  DateTime startedAt;
  DateTime? endedAt;
  FieldTestSnapshot start;
  FieldTestSnapshot? end;

  /// Liczniki Valkor (telefon) na początku – utracone pakiety liczymy w oknie testu.
  int _packets0, _lost0;
  int? _packets1, _lost1;

  FieldTest(this.kind, this.start, {required this.name, this.notes = '', int packets0 = 0, int lost0 = 0})
      : startedAt = start.at,
        _packets0 = packets0,
        _lost0 = lost0;

  bool get running => endedAt == null;

  /// Znaczniki odległości referencyjnej (test dokładności).
  final List<ReferenceMark> marks = [];

  /// Liczniki firmware na początku testu (pozycje niewysłane na żywo, epoki
  /// GNSS bez fixa) – w teście liczymy przyrost.
  int? _fwSkipped0, _fwNoFix0, _fwOverwritten0, _fwLostInflight0;

  /// Pozycje i zdarzenia z okna testu.
  List<FixLogEntry> entries(CollarDiagnostics d, DateTime now) {
    final to = endedAt ?? now;
    return [for (final e in d.log) if (!e.receivedAt.isBefore(startedAt) && !e.receivedAt.isAfter(to)) e];
  }

  List<BleEvent> events(CollarDiagnostics d, DateTime now) {
    final to = endedAt ?? now;
    return [for (final e in d.bleEvents) if (!e.at.isBefore(startedAt) && !e.at.isAfter(to)) e];
  }

  static bool _fresh(FixLogEntry e) => (e.verdict == 'ok' || e.verdict == 'postoj') && !e.historical;

  FieldTestSummary summary(CollarLink c, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final es = entries(c.diag, t);
    final fresh = [for (final e in es) if (_fresh(e)) e];
    // Odstępy odbioru między świeżymi pozycjami z tego samego źródła.
    final rx = <double>[];
    for (var i = 1; i < fresh.length; i++) {
      if (fresh[i].source != fresh[i - 1].source) continue;
      rx.add(fresh[i].receivedAt.difference(fresh[i - 1].receivedAt).inMilliseconds / 1000);
    }
    final to = endedAt ?? t;
    var maxGap = rx.isEmpty ? null : rx.reduce(math.max);
    // Przerwa od startu do pierwszej pozycji i od ostatniej do końca też się liczy.
    if (fresh.isNotEmpty) {
      final head = fresh.first.receivedAt.difference(startedAt).inMilliseconds / 1000;
      final tail = to.difference(fresh.last.receivedAt).inMilliseconds / 1000;
      maxGap = [maxGap ?? 0, head, tail].reduce(math.max);
    }
    double? mean(Iterable<num> v) => v.isEmpty ? null : v.fold<double>(0, (a, b) => a + b) / v.length;
    double? median(List<double> v) {
      if (v.isEmpty) return null;
      final s = [...v]..sort();
      return s[s.length ~/ 2];
    }

    final v = c.valkor;
    final packets = (_packets1 ?? v?.stats.packets ?? 0) - _packets0;
    final lost = (_lost1 ?? v?.stats.lost ?? 0) - _lost0;
    final recovery = <double>[];
    for (final ev in events(c.diag, t)) {
      if (ev.kind != BleEvent.connected) continue;
      final first = fresh.where((e) => !e.receivedAt.isBefore(ev.at));
      if (first.isNotEmpty) recovery.add(first.first.receivedAt.difference(ev.at).inMilliseconds / 1000);
    }
    final endSnap = end ?? FieldTestSnapshot.of(c, t);
    return FieldTestSummary(
      freshPositions: fresh.length,
      rejected: es.where((e) => e.verdict != 'ok' && e.verdict != 'postoj').length,
      historical: es.where((e) => e.historical).length,
      meanRxSec: mean(rx),
      medianRxSec: median(rx),
      maxGapSec: maxGap,
      lossPct: v == null || packets + lost <= 0 ? null : lost * 100 / (packets + lost),
      meanAccuracyM: mean([for (final e in fresh) if (e.accuracyM != null) e.accuracyM!]),
      meanPhoneRssi: mean([for (final e in fresh) if (e.bleRssi != null) e.bleRssi!]),
      meanTrackerRssi: mean([for (final e in fresh) if (e.trackerRssi != null) e.trackerRssi!]),
      batteryStartPct: start.batteryPct,
      batteryEndPct: endSnap.batteryPct,
      batteryStartMv: start.batteryMv,
      batteryEndMv: endSnap.batteryMv,
      reconnects: endSnap.reconnects - start.reconnects,
      toBackground: endSnap.toBackground - start.toBackground,
      recoverySec: recovery,
      valkorPackets: packets < 0 ? 0 : packets,
      valkorLost: lost < 0 ? 0 : lost,
    );
  }

  /// Przerwy w pozycjach na żywo dłuższe niż [minSec] (z odległością przed i po).
  List<GapInfo> gaps(CollarDiagnostics d, DateTime now, {double minSec = 2}) {
    final fresh = [for (final e in entries(d, now)) if (_fresh(e)) e];
    double? m(FixLogEntry e) => e.filteredDistanceM ?? e.distanceM;
    final out = <GapInfo>[];
    for (var i = 1; i < fresh.length; i++) {
      final a = fresh[i - 1], b = fresh[i];
      if (b.receivedAt.difference(a.receivedAt).inMilliseconds / 1000 > minSec) {
        out.add(GapInfo(a.receivedAt, b.receivedAt, m(a), m(b)));
      }
    }
    final to = endedAt ?? now;
    if (fresh.isNotEmpty && to.difference(fresh.last.receivedAt).inMilliseconds / 1000 > minSec) {
      out.add(GapInfo(fresh.last.receivedAt, to, m(fresh.last), null));
    }
    return out;
  }

  RangeStats range(CollarLink c, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final es = entries(c.diag, t);
    final fresh = [for (final e in es) if (_fresh(e)) e];
    double? m(FixLogEntry e) => e.filteredDistanceM ?? e.distanceM;
    final gs = gaps(c.diag, t);
    // Utrata = przerwa > 5 s; potwierdzone ponowne połączenie = zdarzenie Bluetooth „połączono”.
    final losses = gs.where((g) => g.sec > 5).toList();
    double? atReconnect;
    for (final ev in events(c.diag, t).reversed) {
      if (ev.kind != BleEvent.connected) continue;
      final first = fresh.where((e) => !e.receivedAt.isBefore(ev.at));
      if (first.isNotEmpty) atReconnect = m(first.first);
      break;
    }
    final phone = [for (final e in fresh) if (e.bleRssi != null) e.bleRssi!.toDouble()];
    final tracker = [for (final e in fresh) if (e.trackerRssi != null) e.trackerRssi!.toDouble()];
    final v = c.valkor;
    final hs = v == null
        ? 'brak_kanalu_valkor'
        : '${v.historySync.name}${v.historyExpected == null ? '' : ' ${v.historyReceivedThisSync}/${v.historyExpected}'}'
            '${v.historyComplete == null ? '' : (v.historyComplete! ? ' kompletna' : ' niekompletna')}';
    return RangeStats(
      currentM: fresh.isEmpty ? null : m(fresh.last),
      maxWithTransmissionM: _maxOf([for (final e in fresh) if (m(e) != null) m(e)!]),
      lastBeforeLossM: losses.isEmpty ? null : losses.last.beforeM,
      firstRecoveredM: losses.isEmpty ? null : losses.last.afterM,
      atReconnectM: atReconnect,
      phoneRssiNow: c.diag.bleRssi?.toDouble(),
      phoneRssiMean: _meanOf(phone),
      phoneRssiMin: _minOf(phone),
      trackerRssiMean: _meanOf(tracker),
      trackerRssiMin: _minOf(tracker),
      gaps: gs,
      noPositionSec: gs.fold(0.0, (a, g) => a + g.sec),
      missingLiveSeconds: gs.fold(0, (a, g) => a + math.max(0, g.sec.round() - 1)),
      historyState: hs,
    );
  }

  DynamicStats dynamicStats(CollarLink c, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final fresh = [for (final e in entries(c.diag, t)) if (_fresh(e)) e];
    final to = endedAt ?? t;
    final dog = _pathM([
      for (final e in fresh) (LatLng(e.filteredLat ?? e.lat, e.filteredLng ?? e.lng), e.dogSigmaM ?? e.accuracyM)
    ]);
    final ph = _pathM([
      for (final f in HandlerTrack.instance.fixes)
        if (f.gapSec == 0 && !f.at.isBefore(startedAt) && !f.at.isAfter(to)) (LatLng(f.lat, f.lng), f.accuracyM)
    ]);
    final speeds = [for (final e in fresh) if (e.speedMs != null) e.speedMs!];
    var moving = 0.0, still = 0.0;
    for (var i = 1; i < fresh.length; i++) {
      final dt = fresh[i].receivedAt.difference(fresh[i - 1].receivedAt).inMilliseconds / 1000;
      if (dt > 5) continue; // przerwa – nie wiadomo, co pies robił
      if ((fresh[i].speedMs ?? 0) >= 0.5) {
        moving += dt;
      } else {
        still += dt;
      }
    }
    return DynamicStats(
      dogPathM: dog,
      phonePathM: ph,
      maxSpeedMs: _maxOf(speeds),
      meanMovingSpeedMs: _meanOf(speeds.where((v) => v >= 0.5)),
      maxFromPhoneM: _maxOf([for (final e in fresh) if ((e.filteredDistanceM ?? e.distanceM) != null) e.filteredDistanceM ?? e.distanceM!]),
      movingSec: moving,
      stillSec: still,
    );
  }

  /// Wiersze panelu zależne od rodzaju testu (etykieta, wartość).
  List<(String, String)> extraRows(CollarLink c, {DateTime? now}) {
    final t = now ?? DateTime.now();
    String n(double? v, [int d = 1]) => v == null ? '–' : v.toStringAsFixed(d).replaceAll('.', ',');
    String m(double? v) => v == null ? '–' : '${n(v, 0)} m';
    final r = range(c, now: t);
    final rows = <(String, String)>[
      (tr('Czas bez pozycji na żywo'), '${n(r.noPositionSec)} s'),
      (tr('Brakujące pozycje na żywo (1 Hz)'), '${r.missingLiveSeconds}'),
    ];
    switch (kind) {
      case FieldTestKind.bleRange:
      case FieldTestKind.reconnect:
        rows.addAll([
          (tr('Odległość teraz'), m(r.currentM)),
          (tr('Największa odległość z transmisją'), m(r.maxWithTransmissionM)),
          (tr('Ostatnia odległość przed utratą'), m(r.lastBeforeLossM)),
          (tr('Pierwsza pozycja po utracie'), m(r.firstRecoveredM)),
          (tr('Przy potwierdzonym połączeniu'), m(r.atReconnectM)),
          (tr('RSSI telefon: teraz / śr. / min'),
              '${n(r.phoneRssiNow, 0)} / ${n(r.phoneRssiMean, 0)} / ${n(r.phoneRssiMin, 0)} dBm'),
          (tr('RSSI tracker: śr. / min'),
              r.trackerRssiMean == null ? tr('niedostępne') : '${n(r.trackerRssiMean, 0)} / ${n(r.trackerRssiMin, 0)} dBm'),
          (tr('Przerwy'), r.gaps.isEmpty ? '–' : r.gaps.map((g) => '${n(g.sec)} s').join(', ')),
          (tr('Historia'), r.historyState),
        ]);
      case FieldTestKind.dynamic:
        final d = dynamicStats(c, now: t);
        rows.addAll([
          (tr('Droga psa / telefonu'), '${m(d.dogPathM)} / ${m(d.phonePathM)}'),
          (tr('Prędkość maks. / średnia w ruchu'), '${n(d.maxSpeedMs)} / ${n(d.meanMovingSpeedMs)} m/s'),
          (tr('Największa odległość od telefonu'), m(d.maxFromPhoneM)),
          (tr('Czas ruchu / postoju'), '${n(d.movingSec, 0)} / ${n(d.stillSec, 0)} s'),
        ]);
      case FieldTestKind.distance:
        for (final k in marks.reversed.take(8)) {
          rows.add((
            tr('Ref. {0} m ({1})', [n(k.refM, k.refM % 1 == 0 ? 0 : 1), '${k.at.hour}:${k.at.minute.toString().padLeft(2, '0')}:${k.at.second.toString().padLeft(2, '0')}']),
            '${k.shownText} · ${tr('mediana {0}', [m(k.medianFilteredM)])}'
          ));
        }
      default:
        break;
    }
    return rows;
  }

  /// Zapisuje znacznik odległości referencyjnej [refM] (m) z tym, co aplikacja pokazuje teraz.
  ReferenceMark mark(CollarLink c, double refM, {String method = '', DateTime? now}) {
    final t = now ?? DateTime.now();
    final v = DistanceView.of(c, CollarLink.activeDog(), now: t);
    final from = t.subtract(const Duration(seconds: ReferenceMark.windowSec));
    final recent = [
      for (final e in entries(c.diag, t))
        if (_fresh(e) && !e.receivedAt.isBefore(from)) e
    ];
    final r = ReferenceMark(t, refM,
        method: method,
        shownState: v.csv,
        shownText: v.text,
        shownM: v.m,
        uncertaintyM: v.uncertaintyM,
        medianRawM: _median([for (final e in recent) if (e.distanceM != null) e.distanceM!]),
        medianFilteredM: _median([for (final e in recent) if (e.filteredDistanceM != null) e.filteredDistanceM!]),
        samples: recent.length);
    marks.add(r);
    return r;
  }

  /// Przyrost licznika firmware w oknie testu (null = firmware go nie podaje).
  int? _fwDelta(int? start, int? now) => start == null || now == null ? null : math.max(0, now - start);

  /// CSV tego testu: opis, podsumowanie, pozycje z okna testu, zdarzenia Bluetooth i liczniki Valkor.
  String csv(CollarLink c, {DateTime? now}) {
    final t = now ?? DateTime.now();
    String clean(String s) => s.replaceAll(';', ',').replaceAll('\n', ' ');
    final v = c.valkor;
    return [
      'test;nazwa;${clean(name)}',
      'test;rodzaj;${kind.code}',
      'test;start_utc;${startedAt.toUtc().toIso8601String()}',
      'test;koniec_utc;${(endedAt ?? t).toUtc().toIso8601String()}',
      'test;trwa;${running ? 1 : 0}',
      'test;warunki;${clean(notes)}',
      'aplikacja;wersja;$appVersion',
      'aplikacja;kompilacja;$appBuildId',
      'valkor;firmware;${v?.firmware ?? ''}',
      'valkor;protokol;${v?.protocol ?? ''}',
      'valkor;tryb;${v?.deviceMode?.name ?? ''}',
      'bluetooth;mtu;${c.diag.mtu ?? ''}',
      ...summary(c, now: t).csvLines(),
      ..._extraCsv(c, t),
      '',
      FixLogEntry.csvHeader,
      for (final e in entries(c.diag, t)) e.toCsv(),
      '',
      'zdarzenie_bluetooth;czas;szczegoly',
      for (final e in events(c.diag, t)) '${e.kind};${e.at.toIso8601String()};${clean(e.detail ?? '')}',
      ...?v?.csvLines(),
      ...c.recovery.csvLines(),
    ].join('\n');
  }

  List<String> _extraCsv(CollarLink c, DateTime t) {
    String n(num? v, [int d = 1]) => v == null ? '' : (v is int ? '$v' : v.toStringAsFixed(d));
    final r = range(c, now: t);
    final dy = dynamicStats(c, now: t);
    final v = c.valkor;
    final hist = [for (final e in entries(c.diag, t)) if (e.historical) e];
    return [
      // Osobno: utracone pakiety protokołu (luki w numeracji) i brak pozycji
      // (tracker nic nie wysłał, np. brak fixa albo brak zasięgu Bluetooth).
      'liczniki_testu;utracone_pakiety_protokolu;${summary(c, now: t).valkorLost}',
      'liczniki_testu;czas_bez_pozycji_na_zywo_s;${n(r.noPositionSec)}',
      'liczniki_testu;brakujace_pozycje_na_zywo_1hz;${r.missingLiveSeconds}',
      'liczniki_testu;przerwy_ponad_2s;${r.gaps.length}',
      'liczniki_testu;fw_pomiary_niewyslane_na_zywo;${_fwDelta(_fwSkipped0, v?.perf?.fixesSkipped) ?? 'niedostepne'}',
      'liczniki_testu;fw_epoki_gnss_bez_fixa;${_fwDelta(_fwNoFix0, v?.gnssStats?.epochsNoFix) ?? 'niedostepne'}',
      'liczniki_testu;historia_odebrana;${hist.length}',
      'liczniki_testu;historia_przyjeta;${hist.where((e) => e.verdict == 'ok' || e.verdict == 'postoj').length}',
      'liczniki_testu;historia_odrzucona;${hist.where((e) => e.verdict != 'ok' && e.verdict != 'postoj').length}',
      'liczniki_testu;historia_duplikaty;${hist.where((e) => e.verdict == 'duplicate').length}',
      // Nieodzyskana historia: wpisy nadpisane w pełnym buforze trackera (firmware 0.1.2+).
      'liczniki_testu;fw_historia_nadpisana;${_fwDelta(_fwOverwritten0, v?.gnssStats?.historyOverwritten) ?? 'niedostepne'}',
      'liczniki_testu;fw_historia_w_drodze_nadpisana;${_fwDelta(_fwLostInflight0, v?.trackerLink?.historyLostInflight) ?? 'niedostepne'}',
      'zasieg;odleglosc_teraz_m;${n(r.currentM)}',
      'zasieg;max_odleglosc_z_transmisja_m;${n(r.maxWithTransmissionM)}',
      'zasieg;ostatnia_odleglosc_przed_utrata_m;${n(r.lastBeforeLossM)}',
      'zasieg;odleglosc_pierwszej_pozycji_po_utracie_m;${n(r.firstRecoveredM)}',
      'zasieg;odleglosc_przy_potwierdzonym_polaczeniu_m;${n(r.atReconnectM)}',
      'zasieg;rssi_telefon_teraz_dbm;${n(r.phoneRssiNow, 0)}',
      'zasieg;rssi_telefon_sr_dbm;${n(r.phoneRssiMean)}',
      'zasieg;rssi_telefon_min_dbm;${n(r.phoneRssiMin, 0)}',
      'zasieg;rssi_tracker_sr_dbm;${r.trackerRssiMean == null ? 'niedostepne' : n(r.trackerRssiMean)}',
      'zasieg;rssi_tracker_min_dbm;${r.trackerRssiMin == null ? 'niedostepne' : n(r.trackerRssiMin, 0)}',
      'zasieg;przerwy_s;${r.gaps.map((g) => g.sec.toStringAsFixed(1)).join(',')}',
      'zasieg;historia;${r.historyState}',
      'dynamiczny;droga_psa_m;${n(dy.dogPathM)}',
      'dynamiczny;droga_telefonu_m;${n(dy.phonePathM)}',
      'dynamiczny;max_predkosc_m_s;${n(dy.maxSpeedMs, 2)}',
      'dynamiczny;srednia_predkosc_w_ruchu_m_s;${n(dy.meanMovingSpeedMs, 2)}',
      'dynamiczny;max_odleglosc_od_telefonu_m;${n(dy.maxFromPhoneM)}',
      'dynamiczny;czas_ruchu_s;${n(dy.movingSec)}',
      'dynamiczny;czas_postoju_s;${n(dy.stillSec)}',
      if (marks.isNotEmpty) ...['', ReferenceMark.csvHeader, for (final m in marks) m.toCsv()],
    ];
  }

  void _freeze(CollarLink c, DateTime t) {
    endedAt = t;
    end = FieldTestSnapshot.of(c, t);
    _packets1 = c.valkor?.stats.packets;
    _lost1 = c.valkor?.stats.lost;
  }

  void _fwBaseline(CollarLink c) {
    _fwSkipped0 = c.valkor?.perf?.fixesSkipped;
    _fwNoFix0 = c.valkor?.gnssStats?.epochsNoFix;
    _fwOverwritten0 = c.valkor?.gnssStats?.historyOverwritten;
    _fwLostInflight0 = c.valkor?.trackerLink?.historyLostInflight;
  }

  void _restart(CollarLink c, DateTime t) {
    _fwBaseline(c);
    marks.clear();
    startedAt = t;
    start = FieldTestSnapshot.of(c, t);
    _packets0 = c.valkor?.stats.packets ?? 0;
    _lost0 = c.valkor?.stats.lost ?? 0;
  }
}

/// Testy terenowe tej sesji aplikacji (panel deweloperski).
class FieldTests extends ChangeNotifier {
  FieldTests._();
  static final FieldTests instance = FieldTests._();

  FieldTest? active;
  final List<FieldTest> done = [];

  /// Rozpoczyna test. [resetCounters] zeruje liczniki sesji (telefon) i ustawia
  /// podstawę liczników firmware – liczniki od startu trackera zostają w CSV osobno.
  FieldTest start(FieldTestKind kind, {String notes = '', bool resetCounters = true, DateTime? now, CollarLink? link}) {
    final c = link ?? CollarLink.instance;
    final t = now ?? DateTime.now();
    final a = active;
    if (a != null) stop(now: t, link: c);
    if (resetCounters) c.valkor?.resetSession();
    final test = FieldTest(kind, FieldTestSnapshot.of(c, t),
        name: '${kind.label} ${done.length + 1}',
        notes: notes,
        packets0: c.valkor?.stats.packets ?? 0,
        lost0: c.valkor?.stats.lost ?? 0);
    test._fwBaseline(c);
    active = test;
    notifyListeners();
    return test;
  }

  /// Zeruje liczniki trwającego testu (nowe okno od teraz).
  void resetCounters({DateTime? now, CollarLink? link}) {
    final a = active;
    if (a == null) return;
    final c = link ?? CollarLink.instance;
    c.valkor?.resetSession();
    a._restart(c, now ?? DateTime.now());
    notifyListeners();
  }

  /// Znacznik odległości referencyjnej w trwającym teście (null = brak testu).
  ReferenceMark? mark(double refM, {String method = '', DateTime? now, CollarLink? link}) {
    final a = active;
    if (a == null) return null;
    final r = a.mark(link ?? CollarLink.instance, refM, method: method, now: now);
    notifyListeners();
    return r;
  }

  FieldTest? stop({DateTime? now, CollarLink? link}) {
    final a = active;
    if (a == null) return null;
    a._freeze(link ?? CollarLink.instance, now ?? DateTime.now());
    done.insert(0, a);
    active = null;
    notifyListeners();
    return a;
  }

  @visibleForTesting
  void resetForTest() {
    active = null;
    done.clear();
  }
}
