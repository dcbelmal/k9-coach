import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/breeding/breeding_logic.dart';
import 'package:k9_coach/breeding/breeding_models.dart';
import 'package:k9_coach/champ_rules.dart';
import 'package:k9_coach/gps/weather.dart';
import 'package:k9_coach/heat/heat_logic.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/models_ext.dart';
import 'package:k9_coach/nutrition/advisor.dart';
import 'package:k9_coach/nutrition/energy.dart';
import 'package:k9_coach/nutrition/nutrition_models.dart';
import 'package:k9_coach/store.dart';

import 'helpers/fake_prefs.dart';

/// Testy korekty merytorycznej 0.15: wartości graniczne, brakujące dane,
/// realistyczne przykłady i zgodność ze starym formatem zapisu.
void main() {
  final now = DateTime(2026, 11, 19, 12);
  Dog dog({double kg = 20, double? target, int? ageMonths = 36, int? bcs, String? breedId}) => Dog(
    name: 'Test',
    weightKg: kg,
    targetWeightKg: target,
    bcs: bcs,
    breedId: breedId,
    birthDate: ageMonths == null ? null : DateTime(now.year, now.month - ageMonths, 1),
  );
  DailyPlan plan(Dog d, {NutritionSettings? s, List<TrainingSession> t = const [], List<FeedingEntry> e = const []}) =>
      computeDailyPlan(
        dog: d,
        settings: s ?? NutritionSettings(),
        trainingsToday: t,
        entriesToday: e,
        kcalPerGram: 4,
        now: now,
      );

  group('Żywienie', () {
    test('mnożniki MER zależą od kastracji i aktywności (WSAVA/AAHA)', () {
      expect(plan(dog(), s: NutritionSettings(neutered: true)).factor, 1.6);
      expect(plan(dog()).factor, 1.8);
      expect(plan(dog(), s: NutritionSettings(neutered: true, activity: ActivityLevel.low)).factor, 1.2);
      expect(plan(dog(), s: NutritionSettings(activity: ActivityLevel.low)).factor, 1.4);
      expect(plan(dog(), s: NutritionSettings(activity: ActivityLevel.high)).factor, 2.0);
    });

    test('zakres orientacyjny ±20% i brak sztywnego mnożnika seniora', () {
      final p = plan(dog(ageMonths: 130));
      expect(p.factor, 1.8, reason: 'senior liczony jak dorosły, z uwagą o obserwacji masy');
      expect(p.notes.any((n) => n.startsWith('Senior')), isTrue);
      expect(p.lowKcal, closeTo(p.targetKcal * 0.8, 0.01));
      expect(p.highKcal, closeTo(p.targetKcal * 1.2, 0.01));
    });

    test('spacer i trening bez dystansu nie dodają kalorii (brak podwójnego liczenia)', () {
      final walk = TrainingSession(id: 'w', discipline: Discipline.walk, date: now, distanceKm: 6, durationMin: 60);
      final igp = TrainingSession(id: 'i', discipline: Discipline.igp, date: now, durationMin: 90, rpe: 9);
      expect(plan(dog(), t: [walk, igp]).trainingKcal, 0);
      expect(plan(dog(), t: [walk, igp]).targetKcal, closeTo(plan(dog()).targetKcal, 0.001));
    });

    test('koszt biegu netto maleje z masą psa (Taylor 1982)', () {
      expect(Energy.netRunKcalPerKgKm(25), closeTo(0.92, 0.01));
      expect(Energy.netRunKcalPerKgKm(10), greaterThan(Energy.netRunKcalPerKgKm(40)));
      final run = TrainingSession(id: 'r', discipline: Discipline.canicross, date: now, distanceKm: 0, durationMin: 30);
      expect(Energy.trainingKcal(run, 20), 0, reason: 'bez dystansu nic nie zgadujemy');
      final planned = TrainingSession(id: 'p', discipline: Discipline.canicross, date: now, distanceKm: 5, done: false);
      expect(Energy.trainingKcal(planned, 20), 0);
    });

    test('redukcja bez masy docelowej korzysta z BCS, a bez obu – nie zmienia masy', () {
      final p = plan(dog(kg: 33, bcs: 8), s: NutritionSettings(goal: NutritionGoal.lose));
      expect(p.basisKg, closeTo(33 / 1.3, 0.01)); // ok. 10% na punkt powyżej 5
      expect(p.factor, 1.0);
      final noData = plan(dog(kg: 33), s: NutritionSettings(goal: NutritionGoal.lose));
      expect(noData.basisKg, 33);
      expect(noData.notes.any((n) => n.contains('wpisz masę docelową')), isTrue);
    });

    test('zbyt ambitna masa docelowa jest ograniczona do 70% obecnej', () {
      final p = plan(dog(kg: 40, target: 20), s: NutritionSettings(goal: NutritionGoal.lose));
      expect(p.basisKg, 28);
    });

    test('silne ograniczenie kalorii daje ostrzeżenie o składnikach niezbędnych', () {
      final p = plan(dog(kg: 30, target: 22), s: NutritionSettings(goal: NutritionGoal.lose));
      expect(p.restrictionWarning, isTrue); // 1,0 × RER(22) to ok. 45% utrzymania 30 kg
      final ok = plan(dog());
      expect(ok.restrictionWarning, isFalse);
      // Dużo przysmaków też może wyprzeć karmę.
      final treats = [FeedingEntry(id: 't', date: now, kind: FeedKind.treat, grams: 100, kcal: 500)];
      expect(plan(dog(), e: treats).restrictionWarning, isTrue);
    });

    test('szczenię: równanie wzrostu NRC, gdy znana masa dorosła', () {
      // Malinois (20–30 kg) w wieku 5 mies., 15 kg: p = 0,6.
      final d = dog(kg: 15, ageMonths: 5, breedId: 'malinois');
      final p = plan(d);
      final me = 130 * math.pow(15, 0.75) * 3.2 * (math.exp(-0.87 * 0.6) - 0.1);
      expect(p.targetKcal, closeTo(me, 1));
      // Bez rasy: uproszczenie 2,0 × RER.
      expect(plan(dog(kg: 15, ageMonths: 5)).factor, 2.0);
      // Szczenię nie dostaje redukcji.
      expect(plan(d, s: NutritionSettings(goal: NutritionGoal.lose)).basisKg, 15);
    });

    test('rasa duża rośnie do 18. miesiąca', () {
      expect(Energy.isGrowing(14, adultKg: 70), isTrue);
      expect(Energy.isGrowing(14, adultKg: 20), isFalse);
      expect(Energy.isGrowing(null), isFalse);
    });

    test('trend masy: za mało danych → brak propozycji zmiany dawki', () {
      WeightEntry w(int day, double kg) => WeightEntry(
        id: '$day',
        date: now.subtract(Duration(days: day)),
        kg: kg,
      );
      expect(weightTrend([w(14, 30), w(0, 29)]), isNull, reason: '2 ważenia');
      expect(weightTrend([w(14, 30), w(7, 29.6), w(0, 29)]), isNull, reason: 'krócej niż 21 dni');
      final t = weightTrend([w(28, 30), w(14, 29.4), w(0, 28.8)])!;
      expect(t, closeTo(-0.3 / 29.4 * 100, 0.01)); // −0,3 kg/tydz.
    });

    test('brak masy psa i zerowa kaloryczność nie psują obliczeń', () {
      final p = plan(Dog(name: 'X'));
      expect(p.targetKcal, 0);
      expect(p.dailyGrams, 0);
      final q = computeDailyPlan(
        dog: dog(),
        settings: NutritionSettings(),
        trainingsToday: [],
        entriesToday: [],
        kcalPerGram: 0,
        now: now,
      );
      expect(q.kcalPerGram, 3.7);
    });
  });

  group('Cieczka', () {
    final start = DateTime(2026, 11, 1);
    test('bez badań nie ma dni płodnych ani pewnej fazy', () {
      final st = HeatLogic.status([HeatCycle(id: 'a', start: start)], DateTime(2026, 11, 10));
      expect(st.stage, HeatStage.heat);
      expect(st.fertileFrom, isNull);
      expect(st.estimated, isTrue);
      expect(st.current, isNotNull);
    });

    test('owulacja potwierdzona przez lekarza wyznacza fazę i okno płodności', () {
      final c = HeatCycle(id: 'a', start: start, ovulation: DateTime(2026, 11, 14));
      expect(HeatLogic.status([c], DateTime(2026, 11, 8)).stage, HeatStage.proestrus);
      final st = HeatLogic.status([c], DateTime(2026, 11, 15));
      expect(st.stage, HeatStage.estrus);
      expect(st.source, StageSource.ovulation);
      expect(st.fertileFrom, DateTime(2026, 11, 14));
      expect(st.fertileTo, DateTime(2026, 11, 19));
      expect(HeatLogic.status([c], DateTime(2026, 11, 22)).stage, HeatStage.diestrus);
    });

    test('cytologia i obserwacja opiekuna', () {
      final cyto = HeatCycle(
        id: 'a',
        start: start,
        tests: [
          HeatTest(id: 't', date: DateTime(2026, 11, 9), type: HeatTestType.cytology, cytology: CytologyResult.estrus),
        ],
      );
      final s1 = HeatLogic.status([cyto], DateTime(2026, 11, 10));
      expect(s1.stage, HeatStage.estrus);
      expect(s1.source, StageSource.cytology);
      // Badanie z przyszłości (błędna data) jest pomijane.
      expect(HeatLogic.status([cyto], DateTime(2026, 11, 5)).stage, HeatStage.heat);
      final obs = HeatCycle(id: 'b', start: start, standingFrom: DateTime(2026, 11, 11));
      expect(HeatLogic.status([obs], DateTime(2026, 11, 10)).stage, HeatStage.heat);
      expect(HeatLogic.status([obs], DateTime(2026, 11, 12)).source, StageSource.observation);
    });

    test('prognoza ma niepewność zależną od historii', () {
      expect(HeatLogic.status([HeatCycle(id: '1', start: start)], start).nextSpreadDays, 30);
      final regular = [
        HeatCycle(id: '1', start: DateTime(2024, 1, 1), end: DateTime(2024, 1, 19)),
        HeatCycle(id: '2', start: DateTime(2024, 7, 1), end: DateTime(2024, 7, 20)),
        HeatCycle(id: '3', start: DateTime(2025, 1, 1), end: DateTime(2025, 1, 18)),
      ];
      final st = HeatLogic.status(regular, DateTime(2025, 3, 1));
      expect(st.nextSpreadDays, 14);
      expect(st.typicalLengthDays, 19);
      expect(st.gapsUsed, 2);
    });

    test('progesteron: przeliczenie jednostek i opis orientacyjny', () {
      final t = HeatTest(id: 'p', date: start, type: HeatTestType.progesterone, value: 15.9, unit: 'nmol/l');
      expect(t.ngPerMl, closeTo(5, 0.01));
      expect(t.progesteroneHint, contains('owulacji'));
    });

    test('stary zapis cieczki wczytuje się bez zmian, nowe pola przechodzą w obie strony', () {
      final old = HeatCycle.fromJson({'id': 'x', 'start': '2025-01-01T00:00:00.000', 'end': null, 'notes': 'n'});
      expect(old.tests, isEmpty);
      expect(old.ovulation, isNull);
      expect(old.toJson().containsKey('tests'), isFalse);
      final c = HeatCycle(
        id: 'y',
        start: start,
        symptoms: ['Krwawienie'],
        ovulation: DateTime(2026, 11, 12),
        tests: [HeatTest(id: 't', date: start, type: HeatTestType.progesterone, value: 3.2)],
      );
      final back = HeatCycle.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(back.symptoms, ['Krwawienie']);
      expect(back.ovulation, DateTime(2026, 11, 12));
      expect(back.tests.single.value, 3.2);
    });
  });

  group('Ciąża', () {
    test('dzień ciąży i etapy liczone od tego samego punktu', () {
      final m = Mating(id: 'a', dates: [DateTime(2026, 1, 5)], ovulation: DateTime(2026, 1, 3));
      final usg = PregnancyCalc.milestones.firstWhere((x) => x.day == 25);
      final date = PregnancyCalc.milestoneDate(m, usg);
      expect(PregnancyCalc.dayOf(m, date), 25);
      expect(PregnancyCalc.fromOvulation(m), isTrue);
    });

    test('okno porodu: wąskie od owulacji, szerokie od krycia', () {
      final ov = Mating(id: 'a', dates: [DateTime(2026, 1, 5)], ovulation: DateTime(2026, 1, 3));
      final (a, b) = PregnancyCalc.window(ov);
      expect(b.difference(a).inDays, 2);
      final mating = Mating(id: 'b', dates: [DateTime(2026, 1, 5)]);
      final (c, d) = PregnancyCalc.window(mating);
      expect(d.difference(c).inDays, 15);
      expect(PregnancyCalc.daysToWindowEnd(mating, d.add(const Duration(days: 1))), -1);
    });

    test('brak automatycznego zakazu aktywności i +50% karmy', () {
      final first = PregnancyCalc.milestones.first.text;
      expect(first.contains('bez forsownego treningu i skoków'), isFalse);
      expect(PregnancyCalc.milestones.any((m) => m.text.contains('+50%')), isFalse);
      expect(PregnancyCalc.urgentSigns, isNotEmpty);
    });

    test('przyrost szczeniąt: fizjologiczny spadek pierwszej doby i alarm później', () {
      final born = DateTime(2026, 1, 1);
      Puppy p(List<(int, int)> w) => Puppy(
        id: 'p',
        name: 'A',
        weights: [for (final (d, g) in w) PuppyWeight(born.add(Duration(days: d)), g)],
      );
      expect(PuppyGrowth.alert(p([(0, 400), (1, 380)]), born), 1, reason: '5% w 1. dobie – obserwuj');
      expect(PuppyGrowth.alert(p([(0, 400), (1, 340)]), born), 2, reason: '15% – lekarz');
      expect(PuppyGrowth.alert(p([(0, 400), (4, 520), (5, 500)]), born), 2);
      expect(PuppyGrowth.alert(p([(0, 400), (4, 520), (5, 520)]), born), 1);
      expect(PuppyGrowth.alert(p([(0, 400), (4, 520), (5, 560)]), born), 0);
      expect(PuppyGrowth.alert(p([(0, 400)]), born), 0);
    });
  });

  group('Monitor obciążenia', () {
    late Directory dir;
    setUp(() async {
      installFakeDisk();
      dir = await useTempFiles();
      await restartApp();
      await AppStore.instance.saveDog(Dog(name: 'Belg', weightKg: 30));
    });
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('krótka historia nie jest „ryzykiem przetrenowania”', () async {
      await AppStore.instance.upsertTraining(
        TrainingSession(
          id: 'a',
          discipline: Discipline.canicross,
          date: now.subtract(const Duration(days: 2)),
          durationMin: 60,
          rpe: 8,
        ),
      );
      final r = AppStore.instance.readinessAt(now);
      expect(r.level, 0);
      expect(r.label, 'Za krótka historia');
    });

    test('regularny trening = obciążenie jak zwykle; sygnały psa zmieniają zalecenie', () async {
      for (var d = 0; d < 35; d += 2) {
        await AppStore.instance.upsertTraining(
          TrainingSession(
            id: 'd$d',
            discipline: Discipline.obedience,
            date: now.subtract(Duration(days: d)),
            durationMin: 30,
            rpe: 5,
            concerns: d == 0 ? ['Sztywność, kulawizna lub dyskomfort'] : null,
          ),
        );
      }
      final r = AppStore.instance.readinessAt(now);
      expect(r.level, 1);
      expect(r.ratio, closeTo(1.0, 0.2));
      expect(r.concerns, ['Sztywność, kulawizna lub dyskomfort']);
      expect(r.advice, contains('lżejszy dzień'));
    });

    test('ocena samopoczucia zapisuje się i stary trening się wczytuje', () {
      final t = TrainingSession(id: 'x', discipline: Discipline.walk, date: now, concerns: ['Słabszy apetyt']);
      expect(TrainingSession.fromJson(jsonDecode(jsonEncode(t.toJson()))).concerns, ['Słabszy apetyt']);
      final old = TrainingSession.fromJson({'id': 'o', 'discipline': 'walk', 'date': now.toIso8601String()});
      expect(old.concerns, isEmpty);
      expect(old.toJson().containsKey('concerns'), isFalse);
    });
  });

  group('Championaty', () {
    ShowEntry e(
      String id,
      DateTime d,
      ShowTitle t, {
      String judge = '',
      ShowType type = ShowType.national,
      String country = 'Polska',
      ShowClass cls = ShowClass.open,
    }) => ShowEntry(id: id, name: id, date: d, titles: {t}, judge: judge, type: type, country: country, showClass: cls);
    ChampStatus pl(List<ShowEntry> l) =>
        evaluate(Championship.pl, l, workingTrialBreed: false, workingTrialPassed: false);

    test('brak nazwiska sędziego nie jest kolejnym sędzią → „nie można zweryfikować”', () {
      final st = pl([
        e('1', DateTime(2025, 1, 1), ShowTitle.cwc, judge: 'Kowalski', type: ShowType.international),
        e('2', DateTime(2025, 4, 1), ShowTitle.cwc),
        e('3', DateTime(2025, 9, 1), ShowTitle.cwc),
      ]);
      expect(st.achieved, isFalse);
      expect(st.cannotVerify, isTrue);
    });

    test('ten sam sędzia dwa razy – niespełnione', () {
      final st = pl([
        e('1', DateTime(2025, 1, 1), ShowTitle.cwc, judge: 'Kowalski', type: ShowType.international),
        e('2', DateTime(2025, 4, 1), ShowTitle.cwc, judge: 'kowalski '),
        e('3', DateTime(2025, 9, 1), ShowTitle.cwc, judge: 'Nowak'),
      ]);
      expect(st.achieved, isFalse);
      expect(st.cannotVerify, isFalse);
    });

    test('warunki muszą spełniać te same certyfikaty', () {
      // 3 różnych sędziów w 3 miesiące + 4. CWC po 6 mies., ale od sędziego, który już był.
      final st = pl([
        e('1', DateTime(2025, 1, 1), ShowTitle.cwc, judge: 'A', type: ShowType.club),
        e('2', DateTime(2025, 2, 1), ShowTitle.cwc, judge: 'B'),
        e('3', DateTime(2025, 3, 1), ShowTitle.cwc, judge: 'C'),
        e('4', DateTime(2025, 8, 1), ShowTitle.cwc, judge: 'B'),
      ]);
      // Zestaw A(1.01) + C(3.01) + B(1.08) spełnia wszystko – tytuł OK.
      expect(st.achieved, isTrue);
      final bad = pl([
        e('1', DateTime(2025, 1, 1), ShowTitle.cwc, judge: 'A', type: ShowType.club),
        e('2', DateTime(2025, 2, 1), ShowTitle.cwc, judge: 'B'),
        e('3', DateTime(2025, 3, 1), ShowTitle.cwc, judge: 'C'),
        e('4', DateTime(2025, 8, 1), ShowTitle.cwc, judge: 'A'),
      ]);
      // A(1.01)–A(1.08) to jeden sędzia; B/C/A(1.08) bez wystawy klubowej – 6 mies. tylko z A(1.01).
      expect(bad.achieved, isFalse);
    });

    test('CWC z klasy młodzieży nie liczy się do Championa Polski', () {
      final st = pl([
        e('1', DateTime(2025, 1, 1), ShowTitle.cwc, judge: 'A', type: ShowType.club),
        e('2', DateTime(2025, 4, 1), ShowTitle.cwc, judge: 'B', cls: ShowClass.junior),
        e('3', DateTime(2025, 9, 1), ShowTitle.cwc, judge: 'C'),
      ]);
      expect(st.reqs.first.ok, isFalse);
    });

    test('C.I.B.: rasa nieustawiona → nie można zweryfikować; próba pracy liczona tylko, gdy ustawiona', () {
      final l = [
        e('1', DateTime(2024, 1, 1), ShowTitle.cacib, judge: 'A', country: 'Polska'),
        e('2', DateTime(2025, 2, 1), ShowTitle.cacib, judge: 'B', country: 'Czechy'),
      ];
      final unknown = evaluate(Championship.inter, l, workingTrialBreed: null, workingTrialPassed: true);
      expect(unknown.achieved, isFalse);
      expect(unknown.reqs.first.unknown, isTrue);
      final wt = evaluate(Championship.inter, l, workingTrialBreed: true, workingTrialPassed: true);
      expect(wt.achieved, isTrue);
      expect(evaluate(Championship.inter, l, workingTrialBreed: true, workingTrialPassed: false).achieved, isFalse);
      expect(isWorkingTrialBreed(Dog(name: 'x', fciGroup: 1)), isNull, reason: 'grupa FCI nie przesądza o próbach');
    });

    test('C.I.B. bez próby: 4 CACIB, 3 sędziów (jeden może się powtórzyć), 3 kraje', () {
      final l = [
        e('1', DateTime(2024, 1, 1), ShowTitle.cacib, judge: 'A', country: 'Polska'),
        e('2', DateTime(2024, 6, 1), ShowTitle.cacib, judge: 'B', country: 'Czechy'),
        e('3', DateTime(2024, 9, 1), ShowTitle.cacib, judge: 'A', country: 'Polska'),
        e('4', DateTime(2025, 2, 1), ShowTitle.cacib, judge: 'C', country: 'Niemcy'),
      ];
      expect(evaluate(Championship.inter, l, workingTrialBreed: false, workingTrialPassed: false).achieved, isTrue);
    });
  });

  group('Pogoda', () {
    test('wilgotność, słońce, długi trening i cechy psa podnoszą ryzyko', () {
      expect(const Weather(8, 7, 60).assess().level, 0);
      expect(const Weather(14, 14, 50).assess().level, 0);
      expect(const Weather(14, 14, 85).assess().level, 1);
      expect(const Weather(14, 14, 85, radiation: 700, isDay: true).assess(plannedMin: 45).level, 2);
      expect(const Weather(16, 16, 50).assess().level, 1);
      expect(const Weather(16, 16, 50).assess(dog: const HeatDogFactors(['krótka kufa'])).level, 1);
      expect(const Weather(16, 16, 80).assess(dog: const HeatDogFactors(['krótka kufa'])).level, 2);
      expect(const Weather(22, 23, 40).assess().level, 1);
      expect(const Weather(22, 23, 75).assess().level, 2);
    });

    test('spokojny spacer ma niższe ryzyko niż bieg', () {
      const w = Weather(22, 23, 75);
      expect(w.assess(highIntensity: false).level, lessThan(w.assess().level));
    });

    test('odczyt Open-Meteo z brakującymi polami', () {
      expect(parseWeather({}), isNull);
      expect(
        parseWeather({
          'current': {'temperature_2m': 10},
        }),
        isNull,
      );
      final w = parseWeather({
        'current': {
          'temperature_2m': 18.2,
          'apparent_temperature': 17.9,
          'relative_humidity_2m': 66,
          'is_day': 1,
          'shortwave_radiation': 650,
        },
      })!;
      expect(w.strongSun, isTrue);
      expect(w.humidity, 66);
    });
  });
}
