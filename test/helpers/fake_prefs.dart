import 'dart:async';
import 'dart:io';

import 'package:k9_coach/ui_prefs.dart';
import 'package:k9_coach/dogs/dog_profiles.dart';
import 'package:k9_coach/files/file_store.dart';
import 'package:k9_coach/gallery/gallery_store.dart';
import 'package:k9_coach/guides/guide_store.dart';
import 'package:k9_coach/heat/heat_store.dart';
import 'package:k9_coach/breeding/breeding_store.dart';
import 'package:k9_coach/modules/module_store.dart';
import 'package:k9_coach/nutrition/nutrition_store.dart';
import 'package:k9_coach/storage/safe_prefs.dart';
import 'package:k9_coach/store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// Atrapa pamięci telefonu: „dysk” trwa między „uruchomieniami” aplikacji,
/// a zapis można zepsuć (brak miejsca, wyjątek, błąd dla wybranego klucza).
class FakeDisk extends SharedPreferencesStorePlatform {
  final Map<String, Object> disk = {};

  /// true = brak miejsca: każdy zapis zwraca false.
  bool full = false;

  /// true = zapis kończy się wyjątkiem.
  bool throwOnWrite = false;

  /// Klucze (bez prefiksu „flutter.”), których zapis się nie uda.
  final Set<String> failKeys = {};

  /// Zapis tych kluczy czeka na ten Completer (opóźniony zapis).
  final Map<String, Completer<void>> holdKeys = {};

  int writes = 0;

  static String _k(String key) => key.startsWith('flutter.') ? key.substring(8) : key;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final hold = holdKeys[_k(key)];
    if (hold != null) await hold.future;
    if (throwOnWrite) throw const FileSystemException('No space left on device');
    if (full || failKeys.contains(_k(key))) return false;
    writes++;
    disk[key] = value is List<String> ? List<String>.of(value) : value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (full || throwOnWrite) return false;
    disk.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    disk.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map.of(disk);

  @override
  Future<Map<String, Object>> getAllWithParameters(GetAllParameters parameters) async {
    final f = parameters.filter;
    return {
      for (final e in disk.entries)
        if (e.key.startsWith(f.prefix) && (f.allowList == null || f.allowList!.contains(e.key))) e.key: e.value
    };
  }

  /// Wartość tak, jak leży na „dysku”.
  String? raw(String key) => disk['flutter.$key'] as String?;
  void put(String key, String value) => disk['flutter.$key'] = value;
}

FakeDisk? currentDisk;

/// Instaluje atrapę jako pamięć telefonu.
FakeDisk installFakeDisk([Map<String, String> initial = const {}]) {
  final d = FakeDisk();
  for (final e in initial.entries) {
    d.put(e.key, e.value);
  }
  SharedPreferencesStorePlatform.instance = d;
  currentDisk = d;
  SharedPreferences.resetStatic();
  DataHealth.instance.issues.clear();
  return d;
}

/// „Ponowne uruchomienie aplikacji”: pamięć podręczna znika, dane czytane z dysku.
Future<void> restartApp() async {
  SharedPreferences.resetStatic();
  DataHealth.instance.issues.clear();
  await DogProfiles.instance.load();
  await AppStore.instance.load();
  await NutritionStore.instance.load();
  await ModuleStore.instance.load();
  await HeatStore.instance.load();
  await GalleryStore.instance.load();
  await BreedingStore.instance.load();
  await GuideStore.instance.load();
  await UiPrefs.instance.load();
}

/// Katalog plików aplikacji w katalogu tymczasowym.
Future<Directory> useTempFiles() async {
  final dir = await Directory.systemTemp.createTemp('k9_files_test');
  await FileStore.initForTest(dir.path);
  return dir;
}
