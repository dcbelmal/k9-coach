import 'dart:async';

import '../l10n/l10n.dart';
import 'collar_link.dart';

/// Co tracker naprawdę potrafi. Ekrany pokazują tylko funkcje z tej listy –
/// niczego nie udajemy dla urządzeń, które tego nie mają.
enum TrackerCapability {
  /// Połączenie z telefonem przez Bluetooth.
  bluetooth('Bluetooth'),

  /// Pozycje przez radio LoRa (sieć Meshtastic, drugie urządzenie w kieszeni).
  lora('radio LoRa'),

  /// Aplikacja może poprosić o świeżą pozycję.
  positionRequest('pozycja na żądanie'),

  /// Stan baterii trackera.
  battery('bateria'),

  /// Szacowana dokładność pozycji (HDOP, satelity).
  accuracy('dokładność GPS'),

  /// Pobranie historii tras zapisanej w trackerze.
  historySync('historia tras'),

  /// Pozycje przez sieć komórkową (karta SIM).
  cellular('sieć komórkowa'),

  /// Zmiana ustawień trackera z aplikacji (profil trybu – tylko przy
  /// połączeniu bezpośrednim przez Bluetooth).
  remoteConfig('ustawienia z aplikacji');

  final String _label;
  const TrackerCapability(this._label);
  String get label => tr(_label);
}

/// Model trackera znany aplikacji.
class TrackerModel {
  final String id, name;

  /// false = w przygotowaniu, nie da się go jeszcze połączyć.
  final bool available;
  final Set<TrackerCapability> caps;
  final String note;
  const TrackerModel(this.id, this.name, {required this.available, required this.caps, this.note = ''});
}

/// Interfejs sterownika trackera – wspólny dla wszystkich urządzeń.
/// Nowe urządzenie = nowy sterownik; ekrany i nagrywanie korzystają tylko
/// z tego interfejsu i z [TrackerModel.caps].
abstract class TrackerDriver {
  TrackerModel get model;

  /// Sprawdzone pomiary GPS (wszystkich trackerów tego sterownika).
  Stream<CollarFix> get fixes;

  /// Tracker psa wybranego w aplikacji (null = brak).
  int? get dogNode;
  DogLink status({DateTime? now});
  int? get battery;
  bool get paired;
  Future<void> reconnect();
  Future<void> disconnect();
  bool has(TrackerCapability c) => model.caps.contains(c);
}

/// Sterownik urządzeń Meshtastic (SenseCAP T1000-E i inne) – przez [CollarLink].
class MeshtasticDriver extends TrackerDriver {
  final CollarLink link;
  MeshtasticDriver(this.link);

  @override
  TrackerModel get model => TrackerModels.t1000e;
  @override
  Stream<CollarFix> get fixes => link.fixes;
  @override
  int? get dogNode => link.dogNode;
  @override
  DogLink status({DateTime? now}) => link.status(now: now);
  @override
  int? get battery => link.dog?.battery;
  @override
  bool get paired => link.paired;
  @override
  Future<void> reconnect() => link.reconnectSaved();
  @override
  Future<void> disconnect() => link.disconnect();
}

/// Lista urządzeń: dostępne i w przygotowaniu (bez fikcyjnych funkcji).
class TrackerModels {
  static const t1000e = TrackerModel(
    'meshtastic_t1000e',
    'SenseCAP T1000-E (Meshtastic)',
    available: true,
    caps: {
      TrackerCapability.bluetooth,
      TrackerCapability.lora,
      TrackerCapability.positionRequest,
      TrackerCapability.battery,
      TrackerCapability.accuracy,
      TrackerCapability.remoteConfig,
    },
    note: 'Bez historii tras w urządzeniu: trasa zapisuje się w telefonie, gdy tracker jest w zasięgu.',
  );

  static const meshtastic = TrackerModel(
    'meshtastic',
    'Inne urządzenia Meshtastic',
    available: true,
    caps: {TrackerCapability.bluetooth, TrackerCapability.lora, TrackerCapability.positionRequest, TrackerCapability.battery},
    note: 'Działa jak T1000-E, jeśli urządzenie ma GPS. Dokładność zależy od modelu.',
  );

  static const bleGeneric = TrackerModel('ble', 'Inne trackery Bluetooth',
      available: false, caps: {}, note: 'W przygotowaniu – każdy producent ma własny protokół.');

  static const cellular = TrackerModel('lte', 'Trackery GPS z kartą SIM (LTE)',
      available: false, caps: {}, note: 'W przygotowaniu – wymagają serwera producenta i abonamentu.');

  static const valkorCanis = TrackerModel('valkor_canis', 'Valkor Canis',
      available: false, caps: {}, note: 'Własna obroża Valkor – w przygotowaniu.');

  static const all = [t1000e, meshtastic, bleGeneric, cellular, valkorCanis];
}

/// Aktywny sterownik (dziś jedyny działający: Meshtastic).
class TrackerDrivers {
  static TrackerDriver active = MeshtasticDriver(CollarLink.instance);
}
