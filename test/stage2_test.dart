import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/breeding/breeding_logic.dart';
import 'package:k9_coach/breeding/breeding_models.dart';
import 'package:k9_coach/breeds/breed_info.dart';
import 'package:k9_coach/breeds/breeds.dart';
import 'package:k9_coach/guides/guides_data.dart';
import 'package:k9_coach/modules/modules.dart';

void main() {
  group('Kalkulator ciąży', () {
    test('termin 63 dni od krycia i okno 58–68', () {
      final m = Mating(id: 'a', dates: [DateTime(2026, 1, 1), DateTime(2026, 1, 3)]);
      expect(PregnancyCalc.due(m), DateTime(2026, 3, 5));
      final (from, to) = PregnancyCalc.window(m);
      expect(from, DateTime(2026, 2, 28));
      expect(to, DateTime(2026, 3, 12)); // 68 dni od ostatniego krycia
      expect(PregnancyCalc.dayOf(m, DateTime(2026, 1, 29, 15)), 28);
    });

    test('owulacja daje dokładniejszy termin', () {
      final m = Mating(id: 'a', dates: [DateTime(2026, 1, 3)], ovulation: DateTime(2026, 1, 1));
      expect(PregnancyCalc.due(m), DateTime(2026, 3, 5));
      final (from, to) = PregnancyCalc.window(m);
      expect(to.difference(from).inDays, 2);
    });

    test('aktywna tylko w trakcie i bez porodu', () {
      final m = Mating(id: 'a', dates: [DateTime(2026, 1, 1)]);
      expect(PregnancyCalc.isActive(m, DateTime(2026, 2, 1)), isTrue);
      expect(PregnancyCalc.isActive(m, DateTime(2026, 4, 1)), isFalse);
      m.status = PregnancyStatus.notPregnant;
      expect(PregnancyCalc.isActive(m, DateTime(2026, 2, 1)), isFalse);
    });

    test('następny etap', () {
      final m = Mating(id: 'a', dates: [DateTime(2026, 1, 1)]);
      expect(PregnancyCalc.next(m, DateTime(2026, 1, 20))!.day, 25);
      expect(PregnancyCalc.next(m, DateTime(2026, 4, 1)), isNull);
    });

    test('zapis i odczyt z miotem', () {
      final m = Mating(id: 'a', dates: [DateTime(2026, 1, 1)], partner: 'Ares', status: PregnancyStatus.whelped)
        ..litter = Litter(born: DateTime(2026, 3, 5), puppies: [
          Puppy(id: 'p', name: 'Bora')..setWeight(DateTime(2026, 3, 5), 400)..setWeight(DateTime(2026, 3, 6), 380),
        ]);
      final back = Mating.fromJson(m.toJson());
      expect(back.partner, 'Ares');
      expect(back.litter!.puppies.single.lastChange, -20);
      expect(back.litter!.puppies.single.losing, isTrue);
    });
  });

  group('Szczenięta', () {
    test('podwojenie masy w terminie', () {
      final born = DateTime(2026, 3, 1);
      final ok = Puppy(id: 'a', name: 'A')..setWeight(born, 400)..setWeight(born.add(const Duration(days: 8)), 820);
      final late = Puppy(id: 'b', name: 'B')..setWeight(born, 400)..setWeight(born.add(const Duration(days: 12)), 700);
      expect(PuppyGrowth.doubledOnTime(ok, born), isTrue);
      expect(PuppyGrowth.doubledOnTime(late, born), isFalse);
    });
  });

  group('Dane ras', () {
    test('każda rasa z bazy ma dane i sensowne zakresy', () {
      expect(breedsWithInfo, breeds.length);
      for (final b in breeds) {
        final i = breedInfos[b.id]!;
        expect(i.heightMin <= i.heightMax, isTrue, reason: b.id);
        expect(i.weightMin <= i.weightMax, isTrue, reason: b.id);
        expect(i.lifeMin <= i.lifeMax, isTrue, reason: b.id);
        expect(i.energy, inInclusiveRange(1, 5), reason: b.id);
        for (final t in i.tests) {
          expect(testDescriptions.containsKey(t), isTrue, reason: '${b.id}: $t');
        }
      }
    });

    test('link do wzorca FCI', () {
      expect(breedInfos['gsd']!.fciUrl(1), 'https://www.fci.be/Nomenclature/Standards/166g01-en.pdf');
      expect(breedInfos['border_collie']!.size, BreedSize.medium);
      expect(breedInfos['chihuahua']!.size, BreedSize.small);
    });
  });

  group('Przewodniki', () {
    test('każdy zaplanowany moduł treningowy ma treść i unikalne ćwiczenia', () {
      final ids = <String>{};
      for (final g in guides.values) {
        expect(g.exercises, isNotEmpty);
        expect(g.statusLabels.length, 3);
        for (final e in g.exercises) {
          expect(ids.add(e.id), isTrue, reason: e.id);
          expect(e.steps, isNotEmpty);
        }
      }
      for (final m in [AppModule.basicCommands, AppModule.recall, AppModule.socialization, AppModule.mindGames,
        AppModule.agility, AppModule.dogtrekking, AppModule.protection]) {
        expect(guides.containsKey(m), isTrue, reason: m.name);
      }
    });
  });
}
