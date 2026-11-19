import 'models.dart';
import 'models_ext.dart';
import 'l10n/l10n.dart';

/// Podstawa reguł (sprawdzone 19.11.2026):
/// * Regulamin Wystaw Psów Rasowych ZKwP, rozdz. IV.5 „Championaty krajowe”
///   (wersja obowiązująca od 1.01.2024 z późniejszymi zmianami),
///   https://zkwp.pl/regulaminy/Regulamin_Wystaw_Psow_Rasowych.pdf
/// * FCI Regulations for the FCI International Champion titles (sekcje I.1, I.2;
///   zmiany zatwierdzone w 2024 r.), https://fci.be/EN/FCI-International-Championship-41.html
const champRulesSource =
    'Regulamin Wystaw Psów Rasowych ZKwP (rozdz. IV.5, wersja od 1.01.2024 z późn. zm.) i regulamin tytułów FCI (2024). Sprawdzono 19.11.2026 – przed złożeniem wniosku potwierdź aktualne zasady w ZKwP.';

/// Jeden warunek championatu. [unknown] = nie da się go potwierdzić z zapisanych danych.
class Req {
  final String text;
  final bool ok;
  final bool unknown;
  const Req(this.text, this.ok, {this.unknown = false});
}

class ChampStatus {
  final Championship champ;
  final List<Req> reqs;
  final double progress; // 0..1
  final String summary;
  final String rule; // treść zasady
  const ChampStatus(this.champ, this.reqs, this.progress, this.summary, this.rule);
  bool get achieved => reqs.every((r) => r.ok);

  /// Warunki mogą być spełnione, ale danych jest za mało, by to potwierdzić.
  bool get cannotVerify => !achieved && reqs.any((r) => r.unknown) && reqs.every((r) => r.ok || r.unknown);
}

bool _bigShow(ShowEntry e) =>
    e.type == ShowType.international || e.type == ShowType.club || e.type == ShowType.specialty;

String _judgeKey(ShowEntry e) => e.judge.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
String _countryKey(ShowEntry e) => e.country.trim().toLowerCase();

/// Liczba różnych sędziów potwierdzonych nazwiskiem oraz wpisów bez nazwiska.
/// Wpis bez nazwiska NIE jest liczony jako kolejny sędzia – może to być ten sam.
(int, int) judgeCounts(Iterable<ShowEntry> l) {
  final named = <String>{};
  var unnamed = 0;
  for (final e in l) {
    final j = _judgeKey(e);
    if (j.isEmpty) {
      unnamed++;
    } else {
      named.add(j);
    }
  }
  return (named.length, unnamed);
}

(int, int) _countryCounts(Iterable<ShowEntry> l) {
  final named = <String>{};
  var unnamed = 0;
  for (final e in l) {
    final c = _countryKey(e);
    if (c.isEmpty) {
      unnamed++;
    } else {
      named.add(c);
    }
  }
  return (named.length, unnamed);
}

/// Warunek „N różnych …” z rozróżnieniem: spełniony / nie można zweryfikować / niespełniony.
Req _distinctReq(String text, (int, int) counts, int need, String missingHint) {
  final (named, unnamed) = counts;
  if (named >= need) return Req(text, true);
  if (named + unnamed >= need) return Req('$text$missingHint', false, unknown: true);
  return Req(text, false);
}

int _spanDays(List<ShowEntry> l) {
  if (l.length < 2) return 0;
  final d = l.map((e) => e.date).toList()..sort();
  return d.last.difference(d.first).inDays;
}

bool _sixMonths(List<ShowEntry> l) {
  if (l.length < 2) return false;
  final d = l.map((e) => e.date).toList()..sort();
  final f = d.first;
  return !d.last.isBefore(DateTime(f.year, f.month + 6, f.day));
}

bool _yearAndDay(List<ShowEntry> l) {
  if (l.length < 2) return false;
  final d = l.map((e) => e.date).toList()..sort();
  final f = d.first;
  return d.last.isAfter(DateTime(f.year + 1, f.month, f.day));
}

/// Wynik szukania jednego zestawu certyfikatów spełniającego WSZYSTKIE warunki naraz.
enum _Combo { found, unverified, none }

/// Szuka zestawu [need] wpisów, które razem spełniają warunki (różni sędziowie,
/// kraje, rodzaj wystawy, odstęp czasu). Warunki sprawdzane osobno mogłyby być
/// spełnione przez różne certyfikaty – liczy się jeden wspólny zestaw.
_Combo _findSet(
  List<ShowEntry> all,
  int need, {
  bool needBig = false,
  bool Function(List<ShowEntry>)? span,
  int needCountries = 0,
  int? judges,
}) {
  final needJudges = judges ?? need;
  final l = ([...all]..sort((a, b) => b.date.compareTo(a.date))).take(16).toList();
  if (l.length < need) return _Combo.none;
  var best = _Combo.none;
  void rec(int start, List<ShowEntry> pick) {
    if (best == _Combo.found) return;
    if (pick.length == need) {
      if (needBig && !pick.any(_bigShow)) return;
      if (span != null && !span(pick)) return;
      final (jn, ju) = judgeCounts(pick);
      if (jn + ju < needJudges) return; // za mało różnych sędziów
      var verified = jn >= needJudges;
      if (needCountries > 0) {
        final (cn, cu) = _countryCounts(pick);
        if (cn + cu < needCountries) return;
        if (cn < needCountries) verified = false;
      }
      if (verified) {
        best = _Combo.found;
      } else {
        best = _Combo.unverified;
      }
      return;
    }
    for (var i = start; i < l.length; i++) {
      pick.add(l[i]);
      rec(i + 1, pick);
      pick.removeLast();
    }
  }

  rec(0, []);
  return best;
}

Req? _comboReq(_Combo c, List<Req> parts) {
  // Dodatkowy warunek pokazujemy tylko, gdy osobno wszystko wygląda dobrze,
  // ale żaden jeden zestaw certyfikatów nie spełnia warunków razem.
  if (!parts.every((r) => r.ok || r.unknown)) return null;
  return switch (c) {
    _Combo.found => null,
    _Combo.unverified => Req(tr('jeden zestaw certyfikatów spełnia wszystkie warunki – nie można zweryfikować bez nazwisk sędziów i krajów'), false, unknown: true),
    _Combo.none => Req(tr('te same certyfikaty muszą spełniać wszystkie warunki naraz (sędziowie, rodzaj wystawy, odstęp)'), false),
  };
}

double _frac(List<Req> r) => r.isEmpty ? 0 : r.where((x) => x.ok).length / r.length;

String get _missingJudge => tr(' – nie można zweryfikować: uzupełnij nazwiska sędziów');
String get _missingCountry => tr(' – nie można zweryfikować: uzupełnij kraje wystaw');

/// Klasy, w których przyznaje się CWC (ocena doskonała i 1. lokata), wg regulaminu ZKwP.
const cwcClasses = {ShowClass.intermediate, ShowClass.open, ShowClass.working, ShowClass.champion};

ChampStatus evaluate(Championship c, List<ShowEntry> shows,
    {required bool? workingTrialBreed, required bool workingTrialPassed, bool? plChampion}) {
  List<ShowEntry> withT(ShowTitle t) => shows.where((e) => e.titles.contains(t)).toList();
  switch (c) {
    case Championship.juniorPl:
      final l = withT(ShowTitle.zm);
      final parts = [
        Req(tr('3 × Zwycięzca Młodzieży (masz {0})', [l.length]), l.length >= 3),
        _distinctReq(tr('od 3 różnych sędziów (potwierdzonych: {0})', [judgeCounts(l).$1]), judgeCounts(l), 3, _missingJudge),
        Req(tr('min. 1 na wystawie międzynarodowej, klubowej lub specjalistycznej'), l.any(_bigShow)),
      ];
      final reqs = [...parts, ?_comboReq(_findSet(l, 3, needBig: true), parts)];
      return ChampStatus(c, reqs, (l.length.clamp(0, 3) / 3 + _frac(reqs)) / 2, '${l.length} / 3 × ZM',
          tr('Trzykrotnie tytuł Zwycięzcy Młodzieży od 3 różnych sędziów, co najmniej raz na wystawie specjalistycznej, klubowej lub międzynarodowej. Bez wymaganego odstępu czasu.'));
    case Championship.pl:
      final all = withT(ShowTitle.cwc);
      final l = all.where((e) => cwcClasses.contains(e.showClass)).toList();
      final skipped = all.length - l.length;
      final parts = [
        Req(tr('3 × CWC (masz {0})', [l.length]) + (skipped > 0 ? tr(' – pominięto {0} wpisy z klasy, w której CWC nie jest przyznawane', [skipped]) : ''),
            l.length >= 3),
        _distinctReq(tr('od 3 różnych sędziów (potwierdzonych: {0})', [judgeCounts(l).$1]), judgeCounts(l), 3, _missingJudge),
        Req(tr('min. 1 na wystawie międzynarodowej, klubowej lub specjalistycznej'), l.any(_bigShow)),
        Req(tr('min. 6 miesięcy między pierwszym a ostatnim CWC') + (l.length >= 2 ? tr(' (teraz {0} dni)', [_spanDays(l)]) : ''), _sixMonths(l)),
      ];
      final reqs = [...parts, ?_comboReq(_findSet(l, 3, needBig: true, span: _sixMonths), parts)];
      return ChampStatus(c, reqs, (l.length.clamp(0, 3) / 3 + _frac(reqs)) / 2, '${l.length} / 3 × CWC',
          tr('Trzy CWC od trzech różnych sędziów, co najmniej jedno na wystawie międzynarodowej, klubowej lub specjalistycznej. Między pierwszym a ostatnim CWC co najmniej 6 miesięcy. CWC przyznaje się za ocenę doskonałą z 1. lokatą w klasie pośredniej, otwartej, użytkowej lub championów (pies powyżej 15 miesięcy).'));
    case Championship.grand:
      final l = withT(ShowTitle.cwc).where((e) => e.showClass == ShowClass.champion && e.type == ShowType.international).toList();
      final parts = [
        Req(tr('tytuł Champion Polski'), plChampion ?? false),
        Req(tr('3 × CWC w klasie championów na wystawach międzynarodowych (masz {0})', [l.length]), l.length >= 3),
        _distinctReq(tr('od 3 różnych sędziów (potwierdzonych: {0})', [judgeCounts(l).$1]), judgeCounts(l), 3, _missingJudge),
      ];
      final reqs = [...parts, ?_comboReq(_findSet(l, 3), parts)];
      return ChampStatus(c, reqs, (l.length.clamp(0, 3) / 3 + _frac(reqs)) / 2, '${l.length} / 3 × CWC',
          tr('Pies z zatwierdzonym tytułem Champion Polski po jego otrzymaniu zdobywa 3 CWC w klasie championów od 3 sędziów na wystawach międzynarodowych, championów lub Światowej Wystawie Ras Polskich w Polsce. Odstęp czasu nie jest wymagany. Aplikacja liczy wystawy oznaczone jako międzynarodowe – CWC z wystawy championów lub ŚWRP sprawdź samodzielnie.'));
    case Championship.veteran:
      final l = withT(ShowTitle.zw);
      final parts = [
        Req(tr('3 × Zwycięzca Weteran (masz {0})', [l.length]), l.length >= 3),
        _distinctReq(tr('od 3 różnych sędziów (potwierdzonych: {0})', [judgeCounts(l).$1]), judgeCounts(l), 3, _missingJudge),
        Req(tr('min. 1 na wystawie międzynarodowej, klubowej lub specjalistycznej'), l.any(_bigShow)),
      ];
      final reqs = [...parts, ?_comboReq(_findSet(l, 3, needBig: true), parts)];
      return ChampStatus(c, reqs, (l.length.clamp(0, 3) / 3 + _frac(reqs)) / 2, '${l.length} / 3 × ZW',
          tr('Trzykrotnie tytuł Zwycięzca Weteran od 3 różnych sędziów, co najmniej raz na wystawie specjalistycznej, klubowej lub międzynarodowej. Klasa weteranów – psy, które ukończyły 8 lat.'));
    case Championship.inter:
      final l = withT(ShowTitle.cacib);
      final wt = workingTrialBreed ?? false;
      final need = wt ? 2 : 4;
      final needJ = wt ? 2 : 3;
      final needC = wt ? 2 : 3;
      final parts = [
        if (workingTrialBreed == null)
          Req(tr('ustal, czy rasa podlega próbom pracy wg nomenklatury FCI (profil psa) – liczę jak dla rasy bez próby'), false, unknown: true),
        Req(tr('{0} × CACIB (masz {1})', [need, l.length]), l.length >= need),
        _distinctReq(tr('od {0} różnych sędziów (potwierdzonych: {1})', [needJ, judgeCounts(l).$1]), judgeCounts(l), needJ, _missingJudge),
        _distinctReq(tr('w {0} różnych krajach (potwierdzonych: {1})', [needC, _countryCounts(l).$1]), _countryCounts(l), needC, _missingCountry),
        Req(tr('min. rok i 1 dzień między pierwszym a ostatnim CACIB'), _yearAndDay(l)),
        if (wt) Req(tr('zdana próba pracy z CACT właściwa dla rasy (np. IGP 1 – min. 70% w każdej części)'), workingTrialPassed),
      ];
      final reqs = [...parts, ?_comboReq(_findSet(l, need, span: _yearAndDay, needCountries: needC, judges: needJ), parts)];
      return ChampStatus(c, reqs, (l.length.clamp(0, need) / need + _frac(reqs)) / 2, '${l.length} / $need × CACIB',
          wt
              ? tr('Rasy podlegające próbom pracy: 2 CACIB od 2 sędziów w 2 krajach, min. rok i 1 dzień między pierwszym a ostatnim, oraz zdana próba pracy z CACT właściwa dla rasy (np. gr. I–III: IGP/IPO kl. 1 z min. 70% w każdej części; gr. 7: polowa próba „bardzo dobry”). Data próby nie ma znaczenia.')
              : tr('4 CACIB od 3 różnych sędziów w 3 różnych krajach, min. rok i 1 dzień między pierwszym a ostatnim.'));
  }
}

/// Czy rasa podlega próbom pracy (C.I.B.). Wynika z nomenklatury FCI dla
/// konkretnej rasy – nie z numeru grupy (np. w gr. I–III są rasy bez próby,
/// a próby mają też m.in. jamniki, posokowce, wyżły i retrievery).
/// null = nie ustawiono, nie zgadujemy.
bool? isWorkingTrialBreed(Dog? d) => d?.workingTrial;
