import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';

/// Stan podkładu mapy (kafli): czy się wczytują, ile błędów, kiedy kolejna
/// próba. Trasa i znaczniki są rysowane niezależnie od kafli, więc bez
/// internetu trasa nadal jest widoczna – brakuje tylko tła.
///
/// Błędne kafle nie są ponawiane w kółko: po serii błędów kolejna próba
/// za 10 s, potem 20, 40… do 120 s (kontrolowane ponawianie). Udany kafel
/// (także z pamięci podręcznej) zeruje serię.
class TileHealth extends ChangeNotifier {
  TileHealth._();
  static final instance = TileHealth._();

  /// Po ilu błędach z rzędu uznajemy podkład za niedostępny.
  static const failAfter = 3;
  static const firstRetrySec = 10, maxRetrySec = 120;

  int loaded = 0, errors = 0, consecutiveErrors = 0, retries = 0;
  int _backoff = 0;
  DateTime? lastOkAt, lastErrorAt, nextRetryAt;
  String? lastError;
  Timer? _timer;
  final _reset = StreamController<void>.broadcast();
  final _counted = Expando<bool>('tile');

  /// Strumień dla [TileLayer.reset] – przeładowanie kafli przy ponowieniu.
  Stream<void> get resetStream => _reset.stream;

  /// Podkład niedostępny: kilka błędów z rzędu i od tego czasu żaden kafel.
  bool get failing => consecutiveErrors >= failAfter;

  void onError(TileImage? tile, Object error, [StackTrace? st]) {
    errors++;
    consecutiveErrors++;
    lastErrorAt = DateTime.now();
    lastError = shortError(error);
    if (failing && _timer == null) _schedule();
    _notifyLater();
  }

  void onLoaded(TileImage tile) {
    if (tile.loadError || tile.loadFinishedAt == null) return;
    if (_counted[tile] == true) return;
    _counted[tile] = true;
    markLoaded();
  }

  /// Udany kafel (także z pamięci podręcznej) – seria błędów od nowa.
  void markLoaded() {
    loaded++;
    lastOkAt = DateTime.now();
    final wasFailing = failing;
    consecutiveErrors = 0;
    _backoff = 0;
    _timer?.cancel();
    _timer = null;
    nextRetryAt = null;
    if (wasFailing) _notifyLater();
  }

  /// Ponów teraz (przycisk „Ponów” albo licznik).
  void retryNow() {
    _timer?.cancel();
    _timer = null;
    nextRetryAt = null;
    retries++;
    _backoff++;
    // Seria zostaje: jeśli i ta próba się nie uda, następna będzie później.
    _reset.add(null);
    if (failing) _schedule();
    notifyListeners();
  }

  /// Odstęp do następnej próby: 10, 20, 40, 80, 120 s.
  int get retryDelaySec => math.min(maxRetrySec, firstRetrySec * (1 << math.min(_backoff, 4)));

  void _schedule() {
    final s = retryDelaySec;
    nextRetryAt = DateTime.now().add(Duration(seconds: s));
    _timer = Timer(Duration(seconds: s), () {
      _timer = null;
      retryNow();
    });
  }

  bool _pending = false;
  void _notifyLater() {
    if (_pending) return;
    _pending = true;
    scheduleMicrotask(() {
      _pending = false;
      notifyListeners();
    });
  }

  /// Krótki opis błędu do diagnostyki (bez adresów i danych).
  static String shortError(Object e) {
    final s = e.toString();
    final code = RegExp(r'(?:statusCode|status code|HTTP)[^0-9]{0,4}(\d{3})', caseSensitive: false).firstMatch(s);
    if (code != null) return 'HTTP ${code.group(1)}';
    if (s.contains('SocketException') || s.contains('Failed host lookup')) return tr('brak połączenia z internetem');
    if (s.contains('TimeoutException')) return tr('przekroczony czas');
    if (s.contains('HandshakeException') || s.contains('Certificate')) return tr('błąd połączenia szyfrowanego');
    return s.length > 60 ? s.substring(0, 60) : s;
  }

  List<String> csvLines() => [
        'mapa;kafle_wczytane;$loaded',
        'mapa;kafle_bledy;$errors',
        'mapa;bledy_z_rzedu;$consecutiveErrors',
        'mapa;ponowienia;$retries',
        'mapa;ostatni_blad;${lastError ?? ''}',
        'mapa;ostatni_kafel_ok;${lastOkAt?.toIso8601String() ?? ''}',
      ];

  @visibleForTesting
  void resetForTest() {
    _timer?.cancel();
    _timer = null;
    loaded = errors = consecutiveErrors = retries = _backoff = 0;
    lastOkAt = lastErrorAt = nextRetryAt = null;
    lastError = null;
  }
}

/// Komunikat na mapie, gdy podkład jest wyłączony albo niedostępny.
/// [onEnable] – włączenie mapy (gdy brak zgody); null = bez przycisku.
class TileNotice extends StatelessWidget {
  final bool consent;
  final VoidCallback? onEnable;
  const TileNotice({super.key, required this.consent, this.onEnable});

  @override
  Widget build(BuildContext context) {
    final h = TileHealth.instance;
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        if (consent && !h.failing) return const SizedBox.shrink();
        final text = !consent
            ? tr('Podkład mapy wyłączony – trasa jest rysowana bez tła.')
            : tr('Podkład mapy niedostępny ({0}) – trasa nadal jest zapisywana i rysowana. Ponawiam automatycznie.',
                [h.lastError ?? tr('błąd')]);
        return Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Material(
            key: const ValueKey('tile-notice'),
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              child: Row(
                children: [
                  const Icon(Icons.map_outlined, size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12))),
                  if (!consent && onEnable != null)
                    TextButton(onPressed: onEnable, child: Text(tr('Włącz mapę')))
                  else if (consent)
                    TextButton(onPressed: h.retryNow, child: Text(tr('Ponów'))),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
