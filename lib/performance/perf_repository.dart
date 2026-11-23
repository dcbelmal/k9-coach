import 'package:flutter/foundation.dart';

import '../dogs/dog_profiles.dart';
import '../files/file_store.dart';
import '../gps/track.dart';
import '../models.dart';
import '../store.dart';
import 'perf_model.dart';

/// Wczytuje trasy treningów z plików (bez internetu) i liczy wskaźniki
/// Valkor Performance dla aktywnego psa. Wyniki są trzymane w pamięci –
/// niczego nie zapisujemy, więc dane użytkownika zostają nietknięte.
class PerfRepository {
  PerfRepository._();
  static final PerfRepository instance = PerfRepository._();

  /// Odczyt pliku trasy (podmieniany w testach).
  @visibleForTesting
  static Future<String?> Function(String ref) readTrack = FileStore.readText;

  final Map<String, SessionMetrics> _cache = {};
  final Map<String, Track?> _tracks = {};

  @visibleForTesting
  void clear() {
    _cache.clear();
    _tracks.clear();
  }

  Future<Track?> _track(String ref) async {
    if (_tracks.containsKey(ref)) return _tracks[ref];
    Track? t;
    try {
      final txt = await readTrack(ref);
      if (txt != null) t = Track.decode(txt);
    } catch (_) {
      // Uszkodzony plik trasy – trening liczymy jak bez trasy.
    }
    if (_tracks.length > 400) _tracks.clear();
    return _tracks[ref] = t;
  }

  /// Wskaźniki treningów aktywnego psa.
  Future<List<SessionMetrics>> metricsFor(
    List<TrainingSession> sessions, {
    String? dogId,
    Dog? dog,
    List<WeightEntry>? weights,
  }) async {
    final s = AppStore.instance;
    final d = dog ?? s.dog;
    final w = weights ?? s.weights;
    final id = dogId ?? DogProfiles.instance.activeId;
    final out = <SessionMetrics>[];
    for (final t in sessions) {
      final kg = weightOn(t.date, w, d?.weightKg);
      final key =
          '$id|${t.id}|${t.trackRef}|${t.distanceKm}|${t.durationMin}|${t.movingSec}|${t.rpe}|${t.discipline.name}|'
          '${t.date.toIso8601String()}|$kg|${d?.heightCm}';
      final hit = _cache[key];
      if (hit != null) {
        out.add(hit);
        continue;
      }
      final tr = t.trackRef == null ? null : await _track(t.trackRef!);
      final m = SessionMetrics.of(t, tr, kg: kg, heightCm: d?.heightCm);
      if (_cache.length > 2000) _cache.clear();
      _cache[key] = m;
      out.add(m);
    }
    return out;
  }
}
