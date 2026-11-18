import '../models.dart';
import '../l10n/l10n.dart';

/// Rekordy z treningów GPS w jednej dyscyplinie.
class Records {
  final TrainingSession? bestKm; // najszybszy kilometr
  final TrainingSession? longest; // najdłuższa trasa
  final TrainingSession? best5k; // najlepsze średnie tempo na trasie ≥ 5 km
  const Records(this.bestKm, this.longest, this.best5k);

  bool get isEmpty => bestKm == null && longest == null && best5k == null;

  static double? avgPace(TrainingSession t) {
    final d = t.distanceKm;
    final s = t.movingSec ?? t.durationMin * 60;
    if (d == null || d <= 0 || s <= 0) return null;
    return s / d;
  }

  static Records of(Iterable<TrainingSession> all, Discipline d, {String? exceptId}) {
    final list = all.where((t) => t.done && t.discipline == d && t.hasTrack && t.id != exceptId).toList();
    TrainingSession? bk, lg, b5;
    for (final t in list) {
      if (t.bestKmSec != null && (bk == null || t.bestKmSec! < bk.bestKmSec!)) bk = t;
      if ((t.distanceKm ?? 0) > 0 && (lg == null || t.distanceKm! > lg.distanceKm!)) lg = t;
      final p = avgPace(t);
      if ((t.distanceKm ?? 0) >= 5 && p != null && (b5 == null || p < avgPace(b5)!)) b5 = t;
    }
    return Records(bk, lg, b5);
  }

  /// Które rekordy pobił trening [t] (w porównaniu z wcześniejszymi).
  static List<String> newRecords(Iterable<TrainingSession> all, TrainingSession t) {
    final prev = of(all, t.discipline, exceptId: t.id);
    final out = <String>[];
    if (t.bestKmSec != null && (prev.bestKm == null || t.bestKmSec! < prev.bestKm!.bestKmSec!)) {
      out.add(tr('Najszybszy kilometr'));
    }
    if ((t.distanceKm ?? 0) > 0.5 && (prev.longest == null || t.distanceKm! > prev.longest!.distanceKm!)) {
      out.add(tr('Najdłuższa trasa'));
    }
    final p = avgPace(t);
    if ((t.distanceKm ?? 0) >= 5 && p != null && (prev.best5k == null || p < avgPace(prev.best5k!)!)) {
      out.add(tr('Najlepsze tempo na 5 km+'));
    }
    return out;
  }
}
