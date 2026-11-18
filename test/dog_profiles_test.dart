import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/dogs/dog_profiles.dart';
import 'package:k9_coach/heat/heat_store.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stary pies przechodzi na listę, kolejne psy mają osobne dane', () async {
    SharedPreferences.setMockInitialValues({
      'k9coach_data_v1': jsonEncode({'dog': Dog(name: 'Belg').toJson(), 'trainings': []}),
      'valkor_heat_v1': jsonEncode({'cycles': [{'id': 'x', 'start': '2026-01-01T00:00:00.000'}], 'remind': true}),
    });
    final p = DogProfiles.instance;
    await p.load();
    await AppStore.instance.load();
    await HeatStore.instance.load();
    expect(p.ids, ['main']);
    expect(AppStore.instance.dog!.name, 'Belg');
    expect(HeatStore.instance.cycles.length, 1);

    await p.startAdding();
    expect(AppStore.instance.dog, isNull);
    expect(HeatStore.instance.cycles, isEmpty);
    await AppStore.instance.saveDog(Dog(name: 'Suka'));
    expect(p.ids.length, 2);
    final second = p.activeId;

    await p.switchTo('main');
    expect(AppStore.instance.dog!.name, 'Belg');
    expect(HeatStore.instance.cycles.length, 1);
    expect([for (final d in p.dogs) d.$2.name], ['Belg', 'Suka']);

    await p.switchTo(second);
    expect(AppStore.instance.dog!.name, 'Suka');
    await p.deleteActive();
    expect(p.ids, ['main']);
    expect(AppStore.instance.dog!.name, 'Belg');

    await p.startAdding();
    await p.cancelAdding();
    expect(p.activeId, 'main');
    expect(AppStore.instance.dog!.name, 'Belg');
  });
}
