import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/breeds/breeds.dart';
import 'package:k9_coach/heat/heat_logic.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/modules/modules.dart';

void main() {
  group('Reguły modułów', () {
    test('cieczka tylko dla niesterylizowanej suki', () {
      final suka = Dog(name: 'A', female: true);
      expect(AppModule.heat.autoEnabled(suka, premium: false), isTrue);
      suka.neutered = true;
      expect(AppModule.heat.autoEnabled(suka, premium: false), isFalse);
      expect(AppModule.heat.applicable(suka, premium: false), isFalse);
      final pies = Dog(name: 'B', female: false);
      expect(AppModule.heat.applicable(pies, premium: false), isFalse);
    });

    test('moduł hodowlany tylko z Premium', () {
      final d = Dog(name: 'A');
      expect(AppModule.breeding.autoEnabled(d, premium: false), isFalse);
      expect(AppModule.breeding.autoEnabled(d, premium: true), isTrue);
    });

    test('moduły treningowe wg celu', () {
      final d = Dog(name: 'A', purpose: DogPurpose.working);
      expect(AppModule.igp.autoEnabled(d, premium: false), isTrue);
      expect(AppModule.agility.autoEnabled(d, premium: false), isFalse);
      expect(AppModule.agility.autoEnabled(d, premium: false, hasData: true), isTrue);
      d.purpose = DogPurpose.family;
      expect(AppModule.recall.autoEnabled(d, premium: false), isTrue);
      expect(AppModule.igp.autoEnabled(d, premium: false), isFalse);
    });

    test('stare profile bez nowych pól wczytują się', () {
      final d = Dog.fromJson({'name': 'Stary', 'female': true});
      expect(d.neutered, isFalse);
      expect(d.purpose, isNull);
      expect(d.profileComplete, isFalse);
      final back = Dog.fromJson(Dog(name: 'X', purpose: DogPurpose.sport, activity: DogActivity.high).toJson());
      expect(back.purpose, DogPurpose.sport);
      expect(back.activity, DogActivity.high);
    });
  });

  group('Cieczka', () {
    test('brak danych', () {
      final st = HeatLogic.status([], DateTime(2026, 5, 1));
      expect(st.stage, HeatStage.unknown);
      expect(st.nextStart, isNull);
    });

    test('etapy i prognoza z historii', () {
      final cycles = [
        HeatCycle(id: '1', start: DateTime(2025, 1, 1), end: DateTime(2025, 1, 21)),
        HeatCycle(id: '2', start: DateTime(2025, 7, 1), end: DateTime(2025, 7, 20)),
        HeatCycle(id: '3', start: DateTime(2026, 1, 1)),
      ];
      expect(HeatLogic.status(cycles, DateTime(2026, 1, 3)).stage, HeatStage.proestrus);
      expect(HeatLogic.status(cycles, DateTime(2026, 1, 12)).stage, HeatStage.estrus);
      expect(HeatLogic.status(cycles, DateTime(2026, 2, 15)).stage, HeatStage.diestrus);
      final late = HeatLogic.status(cycles, DateTime(2026, 5, 1));
      expect(late.stage, HeatStage.anestrus);
      expect(late.intervalFromHistory, isTrue);
      // średnia z 181 i 184 dni
      expect(late.intervalDays, 183);
      expect(late.nextStart, DateTime(2026, 1, 1).add(const Duration(days: 183)));
    });

    test('jedna cieczka – domyślnie ok. 6 miesięcy', () {
      final st = HeatLogic.status([HeatCycle(id: '1', start: DateTime(2026, 1, 1))], DateTime(2026, 3, 1));
      expect(st.intervalFromHistory, isFalse);
      expect(st.intervalDays, HeatLogic.defaultInterval);
    });
  });

  test('wyszukiwarka ras', () {
    expect(searchBreeds('malin').first.id, 'malinois');
    expect(searchBreeds('wyzel').any((b) => b.id == 'gsp'), isTrue);
    expect(breedByName('Labrador retriever')?.fciGroup, 8);
  });
}
