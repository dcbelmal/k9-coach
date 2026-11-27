// Trasa psa z pomiarów trackera: surowe pomiary → punkty trasy i dystans.
//
// Trzy osobne poziomy:
//  * surowe pomiary GNSS ([DogTrackBuilder.samples]) – każdy przyjęty pomiar,
//    także postój i historia odzyskana z pamięci trackera, w kolejności czasu
//    pomiaru;
//  * pozycje do wyświetlania – filtr adaptacyjny w CollarNode.smooth (mapa na
//    żywo), nie zmienia trasy;
//  * pozycje do dystansu ([segments]) – punkt trasy dopiero, gdy pies
//    przesunął się dalej niż dryf GPS od poprzedniego punktu.
//
// Odcinek kończy się przy przerwie w rzeczywistych pomiarach dłuższej niż
// [gapSec] (zależnie od trybu trackera, SPORT 5 s), na pauzie treningu i przy
// utracie wiarygodności pozycji. Dziur nie łączymy linią ani dystansem.
// Pomiar historyczny wstawiony w środek trasy przebudowuje trasę od nowa
// (kolejność wg czasu pomiaru, duplikaty pomijane).
import 'package:latlong2/latlong.dart';

import '../collar/fix_filter.dart' show FixFilter, FixSource;
import 'track.dart';

const _dist = Distance();

/// Jeden pomiar psa w treningu.
class DogSample {
  /// Czas pomiaru (zegar telefonu po korekcie) i czas treningu (s ruchu);
  /// [t] null = pomiar w czasie pauzy.
  final DateTime at;
  final double? t;

  /// Numer odcinka ruchu treningu (zmienia się po każdej pauzie).
  final int span;
  final double lat, lng;
  final double? speedMs, accuracyM;
  final FixSource source;

  /// false = pozycja jeszcze niewiarygodna (stabilizacja) – przerywa odcinek.
  final bool trusted;

  /// Słaba jakość GNSS: większy promień dryfu, prędkość z odbiornika pomijana.
  final bool weak;

  /// Korekta pozycji GNSS: nowy odcinek, bez łączenia ze starym punktem.
  final bool correction;
  const DogSample(this.at, this.t, this.span, this.lat, this.lng,
      {this.speedMs,
      this.accuracyM,
      this.source = FixSource.valkor,
      this.trusted = true,
      this.weak = false,
      this.correction = false});
  LatLng get ll => LatLng(lat, lng);
}

/// Wynik dodania pomiaru.
enum SampleResult { appended, inserted, duplicate, ignored }

class DogTrackBuilder {
  /// Przerwa w pomiarach (s), po której zaczyna się nowy odcinek.
  double gapSec;
  DogTrackBuilder({this.gapSec = 90});

  final List<DogSample> samples = [];
  final Set<int> _times = {};

  /// Punkty trasy (do dystansu i zapisu) w odcinkach.
  List<List<TrackPoint>> segments = [];
  double meters = 0;

  /// Punkty pominięte jako niemożliwy skok względem poprzedniego punktu trasy.
  int jumps = 0;

  /// Pomiary historyczne wstawione w środek trasy (przebudowy).
  int rebuilds = 0;

  /// Odcinki rozpoczęte od nowa po korekcie / niemożliwym skoku.
  int corrections = 0;

  // Stan przyrostowy (ostatni pomiar i ostatni punkt trasy).
  DogSample? _prev;
  DogSample? _anchor;
  DogSample? _jumpCand; // pomiar po niemożliwym skoku – czeka na potwierdzenie
  bool _break = true;

  void clear() {
    samples.clear();
    _times.clear();
    segments = [];
    meters = 0;
    jumps = 0;
    rebuilds = 0;
    corrections = 0;
    _prev = null;
    _anchor = null;
    _jumpCand = null;
    _break = true;
  }

  /// Dodaje pomiar. Nowszy od ostatniego – dopisanie na końcu; starszy
  /// (historia po ponownym połączeniu) – wstawienie w swoje miejsce
  /// i przebudowa trasy i dystansu.
  SampleResult add(DogSample s) {
    final key = s.at.millisecondsSinceEpoch;
    if (!_times.add(key)) return SampleResult.duplicate;
    if (samples.isEmpty || !s.at.isBefore(samples.last.at)) {
      samples.add(s);
      _step(s);
      return SampleResult.appended;
    }
    var i = samples.length;
    while (i > 0 && samples[i - 1].at.isAfter(s.at)) {
      i--;
    }
    samples.insert(i, s);
    rebuild();
    rebuilds++;
    return SampleResult.inserted;
  }

  /// Przelicza trasę i dystans od nowa ze wszystkich pomiarów.
  void rebuild() {
    segments = [];
    meters = 0;
    jumps = 0;
    corrections = 0;
    _prev = null;
    _anchor = null;
    _jumpCand = null;
    _break = true;
    for (final s in samples) {
      _step(s);
    }
  }

  void _step(DogSample s) {
    final t = s.t;
    // Pauza albo pozycja niewiarygodna: bez punktu, a następny pomiar zaczyna nowy odcinek.
    if (t == null || !s.trusted) {
      _break = true;
      _prev = null;
      _jumpCand = null;
      return;
    }
    // Korekta pozycji GNSS: nigdy nie łączymy błędnej pozycji z poprawną.
    if (s.correction) {
      corrections++;
      _break = true;
    }
    final p = _prev;
    final gap = p != null && s.at.difference(p.at).inMilliseconds / 1000 > gapSec;
    if (_break || p == null || gap || p.span != s.span) {
      _newSegment(s, t);
      return;
    }
    _prev = s;
    final a = _anchor!;
    final d = _dist(a.ll, s.ll);
    final dt = s.at.difference(a.at).inMilliseconds / 1000;
    if (_impossible(d, dt)) {
      // Niemożliwy skok względem punktu trasy. Jeden pomiar – pomijamy (szum).
      // Drugi zgodny z pierwszym – to stary punkt był błędny (korekta GNSS):
      // nowy odcinek od potwierdzonej pozycji, bez dystansu za skok.
      final c = _jumpCand;
      if (c != null && !_impossible(_dist(c.ll, s.ll), s.at.difference(c.at).inMilliseconds / 1000)) {
        corrections++;
        _jumpCand = null;
        _newSegment(c, c.t!);
        _prev = s;
        _stepWithin(s, t);
        return;
      }
      jumps++; // niemożliwy skok – bez punktu i dystansu
      _jumpCand = s;
      return;
    }
    _jumpCand = null;
    _stepWithin(s, t);
  }

  static bool _impossible(double d, double dt) => (dt > 0 && d / dt > FixFilter.maxSpeedMs) || (dt <= 0 && d > 20);

  void _newSegment(DogSample s, double t) {
    if (segments.isEmpty || segments.last.isNotEmpty) segments.add([]);
    _break = false;
    _jumpCand = null;
    _prev = s;
    segments.last.add(TrackPoint(s.lat, s.lng, t, s.speedMs));
    _anchor = s;
  }

  void _stepWithin(DogSample s, double t) {
    final a = _anchor!;
    final d = _dist(a.ll, s.ll);
    // Dryf GPS w miejscu (postój): pomiar świeży, ale bez punktu i dystansu.
    if (FixFilter.isDrift(d, s.accuracyM, s.speedMs, weak: s.weak)) return;
    final at = t < a.t! ? a.t! : t;
    segments.last.add(TrackPoint(s.lat, s.lng, at, s.speedMs));
    meters += d;
    _anchor = s;
  }

  /// Odcinki z co najmniej jednym punktem (kopie – do zapisu szkicu).
  List<List<TrackPoint>> get nonEmpty => [for (final s in segments) if (s.isNotEmpty) [...s]];

  /// Liczba pomiarów wg źródła.
  int count(FixSource src) => samples.where((s) => s.source == src).length;
}
