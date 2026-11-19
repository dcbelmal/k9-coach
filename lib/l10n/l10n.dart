import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lang/ar.dart' as ar;
import 'lang/de.dart' as de;
import 'lang/en.dart' as en;
import 'lang/en_accuracy.dart' as en_acc;
import 'lang/es.dart' as es;
import 'lang/fr.dart' as fr;
import 'lang/hi.dart' as hi;
import 'lang/id.dart' as id;
import 'lang/it.dart' as it;
import 'lang/ja.dart' as ja;
import 'lang/ko.dart' as ko;
import 'lang/pt.dart' as pt;
import 'lang/ru.dart' as ru;
import 'lang/tr.dart' as tr_;
import 'lang/zh.dart' as zh;

/// Język dostępny w aplikacji.
class AppLanguage {
  final String code;
  final String name; // nazwa w tym języku
  final Map<String, String> strings;
  const AppLanguage(this.code, this.name, this.strings);
}

/// Języki aplikacji. Polski jest językiem źródłowym – teksty w kodzie
/// są po polsku i służą jako klucze tłumaczeń.
const appLanguages = <AppLanguage>[
  AppLanguage('pl', 'Polski', {}),
  AppLanguage('en', 'English', en.strings),
  AppLanguage('es', 'Español', es.strings),
  AppLanguage('de', 'Deutsch', de.strings),
  AppLanguage('fr', 'Français', fr.strings),
  AppLanguage('pt', 'Português', pt.strings),
  AppLanguage('it', 'Italiano', it.strings),
  AppLanguage('ru', 'Русский', ru.strings),
  AppLanguage('tr', 'Türkçe', tr_.strings),
  AppLanguage('ar', 'العربية', ar.strings),
  AppLanguage('hi', 'हिन्दी', hi.strings),
  AppLanguage('id', 'Bahasa Indonesia', id.strings),
  AppLanguage('ja', '日本語', ja.strings),
  AppLanguage('ko', '한국어', ko.strings),
  AppLanguage('zh', '中文（简体）', zh.strings),
];

/// Aktualny język aplikacji. `chosen == null` oznacza „jak w telefonie”.
class L10n extends ChangeNotifier {
  L10n._();
  static final instance = L10n._();
  static const _key = 'valkor_lang_v1';

  String? chosen;
  String code = 'pl';
  Map<String, String> _strings = const {};

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      chosen = p.getString(_key);
    } catch (_) {}
    _apply();
  }

  /// Ustawia język (`null` = jak w telefonie).
  Future<void> set(String? lang) async {
    chosen = lang;
    _apply();
    try {
      final p = await SharedPreferences.getInstance();
      if (lang == null) {
        await p.remove(_key);
      } else {
        await p.setString(_key, lang);
      }
    } catch (_) {}
    notifyListeners();
  }

  static String systemCode() {
    for (final l in PlatformDispatcher.instance.locales) {
      if (appLanguages.any((a) => a.code == l.languageCode)) return l.languageCode;
    }
    // Język telefonu nieobsługiwany → angielski.
    return 'en';
  }

  void _apply() {
    code = chosen ?? systemCode();
    _strings = appLanguages.firstWhere((a) => a.code == code, orElse: () => appLanguages.first).strings;
  }

  bool get isPolish => code == 'pl';
  AppLanguage get language => appLanguages.firstWhere((a) => a.code == code);

  /// Przecinek dziesiętny (1,5 km) czy kropka (1.5 km).
  bool get decimalComma => const {'pl', 'de', 'es', 'fr', 'pt', 'it', 'ru', 'tr', 'id'}.contains(code);

  /// Język lektora (komunikaty głosowe w treningu GPS).
  String get ttsLocale =>
      const {
        'pl': 'pl-PL',
        'en': 'en-US',
        'es': 'es-ES',
        'de': 'de-DE',
        'fr': 'fr-FR',
        'pt': 'pt-BR',
        'it': 'it-IT',
        'ru': 'ru-RU',
        'tr': 'tr-TR',
        'ar': 'ar-SA',
        'hi': 'hi-IN',
        'id': 'id-ID',
        'ja': 'ja-JP',
        'ko': 'ko-KR',
        'zh': 'zh-CN',
      }[code] ??
      'en-US';

  String lookup(String pl) {
    if (code == 'pl') return pl;
    return _strings[pl] ?? en.strings[pl] ?? en_acc.strings[pl] ?? pl;
  }
}

/// Tłumaczy polski tekst na język aplikacji. `{0}`, `{1}`… zastępowane są
/// kolejnymi wartościami z [args].
String tr(String pl, [List<Object?> args = const []]) {
  var s = L10n.instance.lookup(pl);
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i] ?? ''}');
  }
  return s;
}

/// Tłumaczenie z kontekstem, gdy ten sam polski tekst ma różne znaczenia
/// (np. „Pies” jako zakładka = Dog, a jako płeć = Male). Klucz: `kontekst|tekst`.
String trc(String context, String pl, [List<Object?> args = const []]) {
  if (L10n.instance.isPolish) return tr(pl, args);
  final key = '$context|$pl';
  final t = tr(key, args);
  return t == key ? tr(pl, args) : t;
}

/// Tłumaczy listę tekstów.
List<String> trList(List<String> l) => [for (final s in l) tr(s)];
