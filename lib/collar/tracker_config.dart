import 'dart:math' as math;
import 'dart:typed_data';

import '../l10n/l10n.dart';
import 'mesh_proto.dart';

/// Ustawienia urządzenia Meshtastic odczytane przez Bluetooth (sekcje
/// device, position i lora z `Config`). Trzymamy surowe bajty, żeby przy
/// zmianie podmienić tylko wybrane pola i nie stracić reszty ustawień.
class TrackerConfig {
  Uint8List? device, position, lora;
  DateTime? readAt;

  bool get known => position != null;

  PbFields? _p(Uint8List? b) => b == null ? null : PbFields.parse(b);
  int _int(Uint8List? b, int f) => _p(b)?.integer(f) ?? 0;

  /// DeviceConfig.role (0 = CLIENT, 5 = TRACKER…).
  int get role => _int(device, 1);

  /// PositionConfig: interwał rozgłaszania (s, 0 = domyślne 15 min),
  /// inteligentne rozgłaszanie, stała pozycja, interwał GPS (s, 0 = 2 min),
  /// flagi pól pozycji, tryb GPS (1 = włączony).
  int get broadcastSecs => _int(position, 1);
  bool get smart => _int(position, 2) != 0;
  bool get fixedPosition => _int(position, 3) != 0;
  int get gpsUpdateSecs => _int(position, 5);
  int get positionFlags => _int(position, 7);
  int get gpsMode => _int(position, 13);

  /// LoRaConfig: preset modemu, region, nadawanie włączone, obejście limitu nadawania.
  bool get usePreset => _int(lora, 1) != 0;
  int get preset => _int(lora, 2);
  int get region => _int(lora, 7);
  bool get txEnabled => _int(lora, 9) != 0;
  bool get overrideDutyCycle => _int(lora, 12) != 0;

  /// Rzeczywiste interwały (firmware zamienia 0 na wartości domyślne).
  int get effectiveBroadcastSecs => broadcastSecs > 0 ? broadcastSecs : 15 * 60;
  int get effectiveGpsUpdateSecs => gpsUpdateSecs > 0 ? gpsUpdateSecs : 2 * 60;

  void set(int section, Uint8List raw, DateTime now) {
    switch (section) {
      case 1:
        device = raw;
      case 2:
        position = raw;
      case 6:
        lora = raw;
      default:
        return;
    }
    readAt = now;
  }

  void clear() {
    device = position = lora = null;
    readAt = null;
  }

  /// Szacowany czas nadawania jednego pakietu z pozycją (s) dla presetu.
  /// Orientacyjnie, dla pakietu ok. 60 bajtów.
  static double airtimeSec(int preset) => switch (preset) {
        0 => 1.0, // LONG_FAST
        1 => 3.0, // LONG_SLOW
        2 => 6.0, // VERY_LONG_SLOW
        3 => 0.45, // MEDIUM_SLOW
        4 => 0.25, // MEDIUM_FAST
        5 => 0.13, // SHORT_SLOW
        6 => 0.07, // SHORT_FAST
        7 => 2.0, // LONG_MODERATE
        8 => 0.04, // SHORT_TURBO
        _ => 1.0,
      };

  static String presetName(int preset) => switch (preset) {
        0 => 'LONG_FAST',
        1 => 'LONG_SLOW',
        2 => 'VERY_LONG_SLOW',
        3 => 'MEDIUM_SLOW',
        4 => 'MEDIUM_FAST',
        5 => 'SHORT_SLOW',
        6 => 'SHORT_FAST',
        7 => 'LONG_MODERATE',
        8 => 'SHORT_TURBO',
        _ => '#$preset',
      };

  static String roleName(int role) => switch (role) {
        0 => 'CLIENT',
        1 => 'CLIENT_MUTE',
        2 => 'ROUTER',
        4 => 'REPEATER',
        5 => 'TRACKER',
        6 => 'SENSOR',
        7 => 'TAK',
        8 => 'CLIENT_HIDDEN',
        9 => 'LOST_AND_FOUND',
        10 => 'TAK_TRACKER',
        11 => 'ROUTER_LATE',
        12 => 'CLIENT_BASE',
        _ => '#$role',
      };

  /// Limit czasu nadawania regionu (część godziny): EU_433 i EU_868 – 10%.
  static double dutyCycle(int region) => region == 2 || region == 3 ? 0.10 : 1.0;

  /// Najkrótszy odstęp między pozycjami, na jaki pozwala radio przy ciągłym
  /// nadawaniu (limit czasu nadawania w UE; poza UE – zajętość kanału 25%).
  double get radioMinSec {
    if (!usePreset && lora != null) return 0; // własne parametry radia – nie szacujemy
    final limit = overrideDutyCycle ? 0.25 : math.min(0.25, dutyCycle(region));
    return airtimeSec(preset) / limit;
  }

  /// Oczekiwany odstęp między nowymi pozycjami w telefonie (s).
  ///
  /// Firmware sprawdza, czy wysłać pozycję, co 5 s; wysyła nie częściej niż
  /// interwał rozgłaszania; nowy pomiar GPS jest co interwał GPS; radio
  /// w UE może nadawać tylko 10% czasu. Telefon dostaje kopię pozycji
  /// dopiero wtedy, gdy tracker wyśle ją radiem – dlatego limit radia działa
  /// także przy połączeniu wyłącznie przez Bluetooth.
  double? get expectedIntervalSec {
    if (!known) return null;
    final raw = [5.0, effectiveBroadcastSecs.toDouble(), effectiveGpsUpdateSecs.toDouble(), radioMinSec].reduce(math.max);
    return (raw / 5).ceil() * 5.0;
  }

  /// Co ogranicza częstotliwość (do wyjaśnienia na ekranie).
  String? get limitReason {
    final e = expectedIntervalSec;
    if (e == null) return null;
    if (smart) return tr('Włączone inteligentne rozgłaszanie pozycji – tracker wysyła pozycję głównie wtedy, gdy przejdzie dalej.');
    if (fixedPosition) return tr('Tracker ma ustawioną stałą pozycję – nie wysyła pomiarów GPS.');
    final r = radioMinSec;
    if (r >= effectiveBroadcastSecs && r >= effectiveGpsUpdateSecs && r > 5) {
      return tr('Limit radia: preset {0} nadaje jedną pozycję ok. {1} s, a w UE radio może nadawać tylko 10% czasu.',
          [presetName(preset), airtimeSec(preset).toStringAsFixed(2).replaceAll('.', ',')]);
    }
    if (effectiveGpsUpdateSecs >= effectiveBroadcastSecs && effectiveGpsUpdateSecs > 5) {
      return tr('Interwał aktualizacji GPS: {0} s.', [effectiveGpsUpdateSecs]);
    }
    if (effectiveBroadcastSecs > 5) return tr('Interwał rozgłaszania pozycji: {0} s.', [effectiveBroadcastSecs]);
    return tr('Firmware sprawdza pozycję co 5 s – szybciej się nie da bez zmiany firmware.');
  }
}

/// Profil ustawień trackera dopasowany do trybu pracy.
class TrackerProfile {
  final String id;
  final int broadcastSecs, gpsUpdateSecs;

  /// Preset radia do ustawienia (null = bez zmiany).
  final int? preset;
  const TrackerProfile(this.id, this.broadcastSecs, this.gpsUpdateSecs, {this.preset});

  static const sport = TrackerProfile('sport', 5, 2, preset: 6);
  static const walk = TrackerProfile('walk', 15, 5);
  static const saver = TrackerProfile('saver', 60, 30);

  /// Zmiany w stosunku do bieżących ustawień: (nazwa, było, będzie).
  List<(String, String, String)> diff(TrackerConfig c) => [
        if (c.broadcastSecs != broadcastSecs)
          (tr('Interwał rozgłaszania pozycji'), '${c.effectiveBroadcastSecs} s', '$broadcastSecs s'),
        if (c.gpsUpdateSecs != gpsUpdateSecs)
          (tr('Interwał aktualizacji GPS'), '${c.effectiveGpsUpdateSecs} s', '$gpsUpdateSecs s'),
        if (c.smart) (tr('Inteligentne rozgłaszanie'), tr('włączone'), tr('wyłączone')),
        if (c.fixedPosition) (tr('Stała pozycja'), tr('włączona'), tr('wyłączona')),
        if (preset != null && (c.preset != preset || !c.usePreset))
          (tr('Preset radia LoRa'), TrackerConfig.presetName(c.preset), TrackerConfig.presetName(preset!)),
      ];

  bool matches(TrackerConfig c) => c.known && diff(c).isEmpty;

  /// Nowa sekcja position (pozostałe pola bez zmian).
  Uint8List positionBytes(TrackerConfig c) =>
      pbWithVarints(c.position ?? Uint8List(0), {1: broadcastSecs, 2: 0, 3: 0, 5: gpsUpdateSecs});

  /// Nowa sekcja lora albo null, gdy preset się nie zmienia.
  Uint8List? loraBytes(TrackerConfig c) {
    final p = preset;
    if (p == null || c.lora == null || (c.preset == p && c.usePreset)) return null;
    return pbWithVarints(c.lora!, {1: 1, 2: p});
  }

  /// Oczekiwany odstęp po zmianie (s).
  double expectedSec(TrackerConfig c) {
    final after = TrackerConfig()
      ..device = c.device
      ..position = positionBytes(c)
      ..lora = loraBytes(c) ?? c.lora;
    return after.expectedIntervalSec ?? broadcastSecs.toDouble();
  }
}
