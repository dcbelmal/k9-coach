// Sesje testów terenowych (panel deweloperski): osobne okno czasu, liczniki
// od zera, podsumowanie i eksport CSV dla każdego testu.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../app_version.dart';
import '../l10n/l10n.dart';
import 'app_state.dart';
import 'collar_link.dart';

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
      '',
      FixLogEntry.csvHeader,
      for (final e in entries(c.diag, t)) e.toCsv(),
      '',
      'zdarzenie_bluetooth;czas;szczegoly',
      for (final e in events(c.diag, t)) '${e.kind};${e.at.toIso8601String()};${clean(e.detail ?? '')}',
      ...?v?.csvLines(),
    ].join('\n');
  }

  void _freeze(CollarLink c, DateTime t) {
    endedAt = t;
    end = FieldTestSnapshot.of(c, t);
    _packets1 = c.valkor?.stats.packets;
    _lost1 = c.valkor?.stats.lost;
  }

  void _restart(CollarLink c, DateTime t) {
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
