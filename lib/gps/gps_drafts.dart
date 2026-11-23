import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../files/file_store.dart';
import '../models.dart';
import '../storage/safe_prefs.dart';
import '../store.dart';
import 'track.dart';

/// Szkic trwającego treningu GPS, zapisywany co kilkanaście sekund.
/// Po nagłym zamknięciu aplikacji pozwala odzyskać trening u właściwego psa.
class GpsDraft {
  final String sessionId;
  final String dogId;
  Discipline discipline;
  DateTime startedAt;
  double seconds; // czas ruchu
  List<List<TrackPoint>> segments;
  List<double> laps;

  /// Trasa psa z obroży GPS.
  List<TrackPoint> dog;
  bool useGps;
  String? planId;
  int rpe;
  String notes;
  DateTime savedAt;

  /// true = użytkownik zakończył trening, trwa zapis do historii.
  bool finalizing;

  GpsDraft({
    required this.sessionId,
    required this.dogId,
    required this.discipline,
    required this.startedAt,
    this.seconds = 0,
    List<List<TrackPoint>>? segments,
    List<double>? laps,
    List<TrackPoint>? dog,
    this.useGps = true,
    this.planId,
    this.rpe = 5,
    this.notes = '',
    DateTime? savedAt,
    this.finalizing = false,
  })  : segments = segments ?? [],
        laps = laps ?? [],
        dog = dog ?? [],
        savedAt = savedAt ?? DateTime.now();

  /// Stałe ID treningu i pliku trasy – ponowienie zapisu nie tworzy duplikatów.
  String get trainingId => planId ?? 'gps_$sessionId';
  String get trackName => 'trk_$sessionId.json';

  Track get track => Track([for (final s in segments) if (s.length > 1) s], laps, dog);

  /// Czy jest co zapisać jako trasę (człowiek albo pies z obroży).
  bool get hasRoute => track.points.length > 1 || track.hasDog;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'session': sessionId,
        'dog': dogId,
        'discipline': discipline.name,
        'startedAt': startedAt.toIso8601String(),
        'seconds': seconds,
        'segments': [for (final s in segments) [for (final p in s) p.toJson()]],
        'laps': laps,
        if (dog.isNotEmpty) 'dogTrack': [for (final p in dog) p.toJson()],
        'useGps': useGps,
        'plan': planId,
        'rpe': rpe,
        'notes': notes,
        'savedAt': savedAt.toIso8601String(),
        'finalizing': finalizing,
      };

  factory GpsDraft.fromJson(Map<String, dynamic> j) => GpsDraft(
        sessionId: j['session'] as String,
        dogId: j['dog'] as String,
        discipline: Discipline.values.byName(j['discipline'] as String),
        startedAt: DateTime.parse(j['startedAt'] as String),
        seconds: (j['seconds'] as num?)?.toDouble() ?? 0,
        segments: [
          for (final s in (j['segments'] as List? ?? [])) [for (final p in s as List) TrackPoint.fromJson(p as List)]
        ],
        laps: [for (final l in (j['laps'] as List? ?? [])) (l as num).toDouble()],
        dog: [for (final p in (j['dogTrack'] as List? ?? [])) TrackPoint.fromJson(p as List)],
        useGps: j['useGps'] as bool? ?? true,
        planId: j['plan'] as String?,
        rpe: jsonInt(j['rpe']) ?? 5,
        notes: j['notes'] as String? ?? '',
        savedAt: DateTime.tryParse(j['savedAt'] as String? ?? ''),
        finalizing: j['finalizing'] as bool? ?? false,
      );

  /// Trening z danych szkicu.
  TrainingSession toTraining({String? trackRef}) {
    final t = track;
    final splits = t.splits().where((s) => s.meters >= 1000 && s.seconds >= 3600 / Track.maxPlausibleKmh).toList();
    final best = splits.isEmpty ? null : splits.map((s) => s.seconds).reduce(min);
    return TrainingSession(
      id: trainingId,
      discipline: discipline,
      date: startedAt,
      durationMin: (seconds / 60).round().clamp(1, 100000),
      distanceKm: useGps ? double.parse((t.meters / 1000).toStringAsFixed(2)) : null,
      rpe: rpe,
      notes: notes,
      trackRef: trackRef,
      movingSec: seconds.round(),
      maxSpeedKmh: useGps ? double.parse(t.maxSpeedKmh().toStringAsFixed(1)) : null,
      bestKmSec: useGps ? best?.round() : null,
    );
  }
}

/// Przechowywanie szkiców: na telefonie pliki `draft_<sesja>.json` w katalogu
/// aplikacji, w przeglądarce w pamięci strony.
class GpsDrafts {
  static const _webKey = 'valkor_gps_drafts_v1';
  static String _name(String sessionId) => 'draft_$sessionId.json';

  static Future<void> save(GpsDraft d) async {
    d.savedAt = DateTime.now();
    final text = jsonEncode(d.toJson());
    if (FileStore.hasFiles) {
      await FileStore.saveText(text, name: _name(d.sessionId));
    } else {
      final p = await SharedPreferences.getInstance();
      final all = _webAll(p)..[d.sessionId] = d.toJson();
      await SafePrefs.setString(p, _webKey, jsonEncode(all));
    }
  }

  static Map<String, dynamic> _webAll(SharedPreferences p) {
    try {
      return Map<String, dynamic>.from(jsonDecode(p.getString(_webKey) ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }

  /// Wszystkie szkice (najstarsze pierwsze). Nieczytelny plik zostaje na miejscu.
  static Future<List<GpsDraft>> pending() async {
    final out = <GpsDraft>[];
    if (FileStore.hasFiles) {
      for (final (ref, _) in await FileStore.listFiles()) {
        if (!ref.startsWith('file:draft_')) continue;
        try {
          final t = await FileStore.readText(ref);
          if (t != null) out.add(GpsDraft.fromJson(jsonDecode(t) as Map<String, dynamic>));
        } catch (e) {
          logError('Szkic GPS', e);
        }
      }
    } else {
      final p = await SharedPreferences.getInstance();
      for (final v in _webAll(p).values) {
        try {
          out.add(GpsDraft.fromJson(Map<String, dynamic>.from(v as Map)));
        } catch (_) {}
      }
    }
    out.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return out;
  }

  /// Usuwa szkic. Plik trasy usuwamy tylko, jeśli żaden trening go nie używa.
  static Future<void> discard(String sessionId) async {
    if (FileStore.hasFiles) {
      await FileStore.delete('file:${_name(sessionId)}');
      await FileStore.deleteIfUnreferenced('file:trk_$sessionId.json');
    } else {
      final p = await SharedPreferences.getInstance();
      final all = _webAll(p)..remove(sessionId);
      await SafePrefs.setString(p, _webKey, jsonEncode(all));
    }
  }

  static Future<void> discardForDog(String dogId) async {
    for (final d in await pending()) {
      if (d.dogId == dogId) await discard(d.sessionId);
    }
  }

  /// Punkt wstrzyknięcia awarii w testach (np. „proces zakończony po zapisie pliku”).
  @visibleForTesting
  static Future<void> Function(String step)? debugAfterStep;

  /// Zapis treningu do historii psa ze szkicu. Bezpieczne przy wielokrotnym
  /// ponowieniu: stałe ID treningu i nazwa pliku trasy, szkic usuwany dopiero
  /// po potwierdzonym zapisie w historii.
  static Future<TrainingSession> finalize(GpsDraft d) async {
    if (!d.finalizing) {
      d.finalizing = true;
      await save(d);
    }
    String? ref;
    if (d.useGps && d.hasRoute) {
      ref = await FileStore.saveText(d.track.encode(), name: d.trackName);
    }
    await debugAfterStep?.call('track');
    final t = d.toTraining(trackRef: ref);
    await AppStore.instance.upsertTrainingFor(d.dogId, t);
    await debugAfterStep?.call('history');
    if (FileStore.hasFiles) {
      await FileStore.delete('file:${_name(d.sessionId)}');
    } else {
      final p = await SharedPreferences.getInstance();
      final all = _webAll(p)..remove(d.sessionId);
      await SafePrefs.setString(p, _webKey, jsonEncode(all));
    }
    return t;
  }
}
