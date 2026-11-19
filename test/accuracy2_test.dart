import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/breeding/breeding_logic.dart';
import 'package:k9_coach/breeding/breeding_models.dart';
import 'package:k9_coach/breeds/breed_sports.dart';
import 'package:k9_coach/champ_rules.dart';
import 'package:k9_coach/date_math.dart';
import 'package:k9_coach/gps/track.dart';
import 'package:k9_coach/heat/heat_logic.dart';
import 'package:k9_coach/models_ext.dart';

String _f(DateTime d) => '${d.day}.${d.month}';

void main() {
  group('Daty kalendarzowe (zmiana czasu)', () {
    test('plusDays zachowuje dzień i godzinę przez zmianę czasu', () {
      // 2026: czas letni od 29.03, zimowy od 25.10 (Polska).
      expect(DateTime(2026, 3, 30).plusDays(-1), DateTime(2026, 3, 29));
      expect(DateTime(2026, 10, 25).plusDays(1), DateTime(2026, 10, 26));
      expect(DateTime(2026, 3, 1, 9).plusDays(30), DateTime(2026, 3, 31, 9));
      expect(DateTime(2026, 1, 31).plusDays(1), DateTime(2026, 2, 1));
      expect(DateTime.utc(2026, 1, 1).plusDays(2), DateTime.utc(2026, 1, 3));
    });
    test('inCalDays liczy dni kalendarzowe także dla doby 23 i 25 h', () {
      expect(DateTime(2026, 4, 1).difference(DateTime(2026, 3, 1)).inCalDays, 31);
      expect(DateTime(2026, 11, 1).difference(DateTime(2026, 10, 1)).inCalDays, 31);
      expect(const Duration(hours: 23).inCalDays, 1);
      expect(const Duration(hours: 25).inCalDays, 1);
      expect(const Duration(hours: -23).inCalDays, -1);
    });
    test('ciąża przez zmianę czasu: termin to dokładnie 63 dni kalendarzowe', () {
      final m = Mating(id: 'a', dates: [DateTime(2026, 9, 1)], ovulation: DateTime(2026, 9, 1));
      expect(PregnancyCalc.due(m), DateTime(2026, 11, 3));
      expect(PregnancyCalc.dayOf(m, DateTime(2026, 11, 3, 8)), 63);
    });
  });

  group('Termin porodu', () {
    test('przy samym kryciu pokazujemy tylko przedział', () {
      final m = Mating(id: 'a', dates: [DateTime(2026, 1, 5)]);
      expect(PregnancyCalc.fromOvulation(m), isFalse);
      expect(PregnancyCalc.dueLabel(m, _f), '3.3 – 18.3');
      expect(PregnancyCalc.daysToWindowStart(m, DateTime(2026, 3, 1)), 2);
    });
    test('przy owulacji – dzień orientacyjny z wąskim oknem', () {
      final m = Mating(id: 'a', dates: [DateTime(2026, 1, 5)], ovulation: DateTime(2026, 1, 3));
      expect(PregnancyCalc.dueLabel(m, _f), contains('7.3'));
      expect(PregnancyCalc.dueLabel(m, _f), contains('6.3 – 8.3'));
    });
  });

  group('Seria progesteronu', () {
    HeatTest p(int day, double v) =>
        HeatTest(id: '$day', date: DateTime(2026, 1, day), type: HeatTestType.progesterone, value: v);
    test('jeden wynik nie potwierdza owulacji', () {
      expect(progesteroneSeriesNote([p(5, 6)]), contains('Jeden wynik'));
    });
    test('wzrost w serii – decyzja lekarza, bez automatycznej owulacji', () {
      expect(progesteroneSeriesNote([p(5, 1), p(7, 2.5), p(9, 6)]), contains('lekarz'));
      expect(progesteroneSeriesNote([p(5, 1), p(7, 2.5), p(9, 6)]), contains('wzrost'));
    });
    test('brak wzrostu i brak wyników', () {
      expect(progesteroneSeriesNote([p(5, 2), p(7, 1.5)]), contains('nie widać wzrostu'));
      expect(progesteroneSeriesNote(const []), isNull);
    });
    test('nmol/l przeliczane na ng/ml (÷ 3,18)', () {
      final t = HeatTest(id: 'x', date: DateTime(2026), type: HeatTestType.progesterone, value: 31.8, unit: 'nmol/l');
      expect(t.ngPerMl, closeTo(10, 0.01));
    });
  });

  group('Grand Championat', () {
    test('niepotwierdzony CH.PL = „nie można zweryfikować”, nie zaliczone', () {
      final l = [
        for (var i = 0; i < 3; i++)
          ShowEntry(
              id: '$i',
              name: '$i',
              date: DateTime(2026, 1 + i * 2, 1),
              titles: {ShowTitle.cwc},
              judge: 'J$i',
              type: ShowType.international,
              showClass: ShowClass.champion),
      ];
      final unknown = evaluate(Championship.grand, l, workingTrialBreed: false, workingTrialPassed: false, plChampion: null);
      expect(unknown.achieved, isFalse);
      expect(unknown.cannotVerify, isTrue);
      final ok = evaluate(Championship.grand, l, workingTrialBreed: false, workingTrialPassed: false, plChampion: true);
      expect(ok.achieved, isTrue);
    });
  });

  group('GPS', () {
    test('skok GPS nie staje się prędkością maksymalną', () {
      final pts = <TrackPoint>[
        for (var i = 0; i <= 60; i++) TrackPoint(52.0 + i * 0.00003, 21.0, i * 1.0), // ~3,3 m/s
      ];
      // Skok o ~1 km w 10 s.
      pts.add(TrackPoint(52.0 + 60 * 0.00003 + 0.009, 21.0, 70));
      final t = Track([pts], const []);
      expect(t.maxSpeedKmh(), lessThanOrEqualTo(Track.maxPlausibleKmh));
      expect(t.maxSpeedKmh(), lessThan(20));
    });
  });

  group('Atlas', () {
    test('rasy krótkonożne: canicross i bikejoring = C', () {
      for (final id in ['corgi_pembroke', 'corgi_cardigan', 'dachshund', 'basset']) {
        expect(sportFit(id, 'canicross')?.fit, Fit.c, reason: id);
        expect(sportFit(id, 'bikejoring')?.fit, Fit.c, reason: id);
      }
    });
  });
}
