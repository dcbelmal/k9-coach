import 'models.dart';
import 'models_ext.dart';

/// Jeden warunek championatu.
class Req {
  final String text;
  final bool ok;
  const Req(this.text, this.ok);
}

class ChampStatus {
  final Championship champ;
  final List<Req> reqs;
  final double progress; // 0..1
  final String summary;
  final String rule; // treść zasady
  const ChampStatus(this.champ, this.reqs, this.progress, this.summary, this.rule);
  bool get achieved => reqs.every((r) => r.ok);
}

bool _bigShow(ShowEntry e) =>
    e.type == ShowType.international || e.type == ShowType.club || e.type == ShowType.specialty;

/// Liczba różnych sędziów (brak nazwiska liczony osobno).
int _judges(Iterable<ShowEntry> l) {
  final named = <String>{};
  var unnamed = 0;
  for (final e in l) {
    final j = e.judge.trim().toLowerCase();
    if (j.isEmpty) {
      unnamed++;
    } else {
      named.add(j);
    }
  }
  return named.length + unnamed;
}

int _countries(Iterable<ShowEntry> l) => {for (final e in l) e.country.trim().toLowerCase()}.length;

/// Odstęp między pierwszym a ostatnim certyfikatem w dniach.
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

double _frac(List<Req> r) => r.isEmpty ? 0 : r.where((x) => x.ok).length / r.length;

String _missingJudge(Iterable<ShowEntry> l) =>
    l.any((e) => e.judge.trim().isEmpty) ? ' (uzupełnij nazwiska sędziów)' : '';

ChampStatus evaluate(Championship c, List<ShowEntry> shows, {required bool workingTrialBreed, required bool workingTrialPassed, bool? plChampion}) {
  List<ShowEntry> withT(ShowTitle t) => shows.where((e) => e.titles.contains(t)).toList();
  switch (c) {
    case Championship.juniorPl:
      final l = withT(ShowTitle.zm);
      final j = _judges(l);
      final reqs = [
        Req('3 × Zwycięzca Młodzieży (masz ${l.length})', l.length >= 3),
        Req('od 3 różnych sędziów (masz $j)${_missingJudge(l)}', j >= 3),
        Req('min. 1 na wystawie międzynarodowej, klubowej lub specjalistycznej', l.any(_bigShow)),
      ];
      return ChampStatus(c, reqs, (l.length.clamp(0, 3) / 3 + _frac(reqs)) / 2, '${l.length} / 3 × ZM',
          'Trzykrotnie tytuł Zwycięzcy Młodzieży od 3 różnych sędziów, co najmniej raz na wystawie specjalistycznej, klubowej lub międzynarodowej. Bez określonego przedziału czasu.');
    case Championship.pl:
      final l = withT(ShowTitle.cwc);
      final j = _judges(l);
      final reqs = [
        Req('3 × CWC (masz ${l.length})', l.length >= 3),
        Req('od 3 różnych sędziów (masz $j)${_missingJudge(l)}', j >= 3),
        Req('min. 1 na wystawie międzynarodowej, klubowej lub specjalistycznej', l.any(_bigShow)),
        Req('min. 6 miesięcy między pierwszym a ostatnim CWC${l.length >= 2 ? ' (teraz ${_spanDays(l)} dni)' : ''}', _sixMonths(l)),
      ];
      return ChampStatus(c, reqs, (l.length.clamp(0, 3) / 3 + _frac(reqs)) / 2, '${l.length} / 3 × CWC',
          'Trzy CWC od trzech różnych sędziów, co najmniej jedno na wystawie międzynarodowej, klubowej lub specjalistycznej. Między pierwszym a ostatnim CWC co najmniej 6 miesięcy. CWC może otrzymać pies, który ukończył 15 miesięcy, za ocenę doskonałą i 1. lokatę w klasie pośredniej, otwartej, użytkowej lub championów.');
    case Championship.grand:
      final l = withT(ShowTitle.cwc).where((e) => e.showClass == ShowClass.champion && e.type == ShowType.international).toList();
      final j = _judges(l);
      final reqs = [
        Req('tytuł Champion Polski', plChampion ?? false),
        Req('3 × CWC w klasie championów na wystawach międzynarodowych (masz ${l.length})', l.length >= 3),
        Req('od 3 różnych sędziów (masz $j)${_missingJudge(l)}', j >= 3),
      ];
      return ChampStatus(c, reqs, (l.length.clamp(0, 3) / 3 + _frac(reqs)) / 2, '${l.length} / 3 × CWC',
          'Pies z zatwierdzonym tytułem Champion Polski zdobywa 3 CWC w klasie championów od 3 sędziów na wystawach międzynarodowych, championów lub Światowej Wystawie Ras Polskich. Odstęp czasu nie jest wymagany.');
    case Championship.veteran:
      final l = withT(ShowTitle.zw);
      final j = _judges(l);
      final reqs = [
        Req('3 × Zwycięzca Weteran (masz ${l.length})', l.length >= 3),
        Req('od 3 różnych sędziów (masz $j)${_missingJudge(l)}', j >= 3),
        Req('min. 1 na wystawie międzynarodowej, klubowej lub specjalistycznej', l.any(_bigShow)),
      ];
      return ChampStatus(c, reqs, (l.length.clamp(0, 3) / 3 + _frac(reqs)) / 2, '${l.length} / 3 × ZW',
          'Trzykrotnie tytuł Zwycięzca Weteran od 3 różnych sędziów, co najmniej raz na wystawie specjalistycznej, klubowej lub międzynarodowej. Liczą się wystawy od 1.01.2015.');
    case Championship.inter:
      final l = withT(ShowTitle.cacib);
      final need = workingTrialBreed ? 2 : 4;
      final needJ = workingTrialBreed ? 2 : 3;
      final needC = workingTrialBreed ? 2 : 3;
      final j = _judges(l);
      final k = _countries(l);
      final reqs = [
        Req('$need × CACIB (masz ${l.length})', l.length >= need),
        Req('od $needJ różnych sędziów (masz $j)${_missingJudge(l)}', j >= needJ),
        Req('w $needC różnych krajach (masz $k)', k >= needC),
        Req('min. rok i 1 dzień między pierwszym a ostatnim CACIB', _yearAndDay(l)),
        if (workingTrialBreed) Req('zdana próba pracy z CACT (np. IGP 1, min. 70% w każdej części)', workingTrialPassed),
      ];
      return ChampStatus(c, reqs, (l.length.clamp(0, need) / need + _frac(reqs)) / 2, '${l.length} / $need × CACIB',
          workingTrialBreed
              ? 'Rasy z próbą pracy: 2 CACIB od 2 sędziów w 2 krajach, min. rok i 1 dzień między pierwszym a ostatnim, oraz zdana próba pracy z CACT (gr. I–III: IGP/IPO kl. 1, min. 70% w każdej dyscyplinie). Data próby nie ma znaczenia.'
              : '4 CACIB od 3 różnych sędziów w 3 różnych krajach, min. rok i 1 dzień między pierwszym a ostatnim.');
  }
}

/// Czy rasa podlega próbom pracy (domyślnie gr. I–III; można zmienić w profilu).
bool isWorkingTrialBreed(Dog? d) => d?.workingTrial ?? (d?.fciGroup != null && d!.fciGroup! <= 3);
