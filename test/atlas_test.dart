import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/breeds/breed_info.dart';
import 'package:k9_coach/breeds/breed_profile.dart';
import 'package:k9_coach/breeds/breed_sex.dart';
import 'package:k9_coach/breeds/breed_sports.dart';
import 'package:k9_coach/breeds/breed_temperament.dart';
import 'package:k9_coach/breeds/breeds.dart';
import 'package:k9_coach/l10n/l10n.dart';
import 'package:k9_coach/l10n/lang/en.dart' as en;

/// Testy integralności Atlasu ras – pilnują, żeby kolejne zmiany danych
/// nie wprowadziły przypadkowych lub niebezpiecznych przypisań sportów.
void main() {
  Fit? fit(String breed, String activity) => sportFit(breed, activity)?.fit;

  group('Rekordy ras', () {
    test('identyfikatory i nazwy są unikalne, każda rasa ma komplet danych', () {
      final ids = <String>{}, names = <String>{};
      for (final b in breeds) {
        expect(ids.add(b.id), isTrue, reason: 'duplikat id ${b.id}');
        expect(names.add(b.namePl.toLowerCase()), isTrue, reason: 'duplikat nazwy ${b.namePl}');
        expect(b.fciGroup, inInclusiveRange(1, 10), reason: b.id);
        expect(breedInfos.containsKey(b.id), isTrue, reason: 'brak breedInfos: ${b.id}');
        expect(breedProfiles.containsKey(b.id), isTrue, reason: 'brak breedProfiles: ${b.id}');
        expect(breedProfiles[b.id]!.intlName.trim(), isNotEmpty, reason: b.id);
      }
      expect(breedInfos.keys.toSet(), ids, reason: 'breedInfos zawiera rasy spoza bazy');
      expect(breedProfiles.keys.toSet(), ids, reason: 'breedProfiles zawiera rasy spoza bazy');
      expect(breeds.length, 135);
    });

    test('zakresy wymiarów i numery FCI są sensowne', () {
      for (final b in breeds) {
        final i = breedInfos[b.id]!;
        expect(i.heightMin, inInclusiveRange(10, 95), reason: b.id);
        expect(i.heightMax, inInclusiveRange(i.heightMin, 95), reason: b.id);
        expect(i.weightMin, greaterThan(0), reason: b.id);
        expect(i.weightMax, inInclusiveRange(i.weightMin, 100), reason: b.id);
        expect(i.lifeMin, inInclusiveRange(5, 18), reason: b.id);
        expect(i.lifeMax, inInclusiveRange(i.lifeMin, 20), reason: b.id);
        if (i.fciNo != null) expect(i.fciNo, inInclusiveRange(1, 400), reason: b.id);
        for (final t in i.testKeys) {
          expect(testDescriptions.containsKey(t), isTrue, reason: '${b.id}: $t');
        }
        expect(i.testKeys.toSet().length, i.testKeys.length, reason: 'powtórzone badanie: ${b.id}');
      }
    });

    test('wymiary według płci pasują do zakresu ogólnego', () {
      for (final e in breedSexDims.entries) {
        final i = breedInfos[e.key];
        expect(i, isNotNull, reason: 'brak rasy ${e.key}');
        final d = e.value;
        for (final h in [d.maleHeight, d.femaleHeight].whereType<Span>()) {
          expect(h.min, greaterThanOrEqualTo(i!.heightMin - 1), reason: '${e.key} wzrost');
          expect(h.upper, lessThanOrEqualTo(i.heightMax + 1), reason: '${e.key} wzrost');
          if (h.max != null) expect(h.max!, greaterThanOrEqualTo(h.min), reason: e.key);
        }
        for (final w in [d.maleWeight, d.femaleWeight].whereType<Span>()) {
          expect(w.min, greaterThanOrEqualTo(i!.weightMin - 1), reason: '${e.key} masa');
          expect(w.upper, lessThanOrEqualTo(i.weightMax + 1), reason: '${e.key} masa');
        }
        if (d.maleHeight != null && d.femaleHeight != null) {
          expect(d.maleHeight!.min, greaterThanOrEqualTo(d.femaleHeight!.min), reason: '${e.key}: psy niższe od suk');
        }
      }
    });

    test('dawny identyfikator „tatra” wskazuje na polskiego owczarka podhalańskiego', () {
      expect(breedById('tatra')?.id, 'podhalanski');
      expect(breedInfoFor('tatra'), isNotNull);
      expect(canonicalBreedId('malinois'), 'malinois');
      for (final e in legacyBreedIds.entries) {
        expect(breedById(e.value), isNotNull, reason: e.key);
        expect(breeds.any((b) => b.id == e.key), isFalse, reason: 'dawne id nadal na liście: ${e.key}');
      }
    });
  });

  group('Wyszukiwarka i filtr', () {
    test('szuka po nazwie polskiej, aliasie i nazwie międzynarodowej', () {
      expect(searchBreeds('malinois').first.id, 'malinois');
      expect(searchBreeds('tatrzański').map((b) => b.id), contains('podhalanski'));
      expect(searchBreeds('Tatra Shepherd').map((b) => b.id), contains('podhalanski'));
      expect(searchBreeds('Short-haired Pointing').map((b) => b.id), contains('gsp'));
      expect(searchBreeds('zzzz'), isEmpty);
      expect(searchBreeds('').length, breeds.length);
    });

    test('filtr dyscypliny zwraca rasy o danej kategorii', () {
      final canicrossA = breeds.where((b) => fit(b.id, 'canicross') == Fit.a).map((b) => b.id).toSet();
      expect(canicrossA, containsAll(['malinois', 'gsp', 'husky']));
      expect(canicrossA, isNot(contains('pug')));
      expect(canicrossA, isNot(contains('corgi_pembroke')));
    });
  });

  group('Predyspozycje sportowe', () {
    test('każda rasa ma ocenę wszystkich dyscyplin ogólnych z uzasadnieniem', () {
      const restricted = {'coursing', 'racing', 'dummy', 'herding', 'hunting', 'water_rescue', 'lgd'};
      for (final b in breeds) {
        final fits = sportFitsFor(b.id);
        final ids = fits.map((f) => f.activity.id).toList();
        expect(ids.toSet().length, ids.length, reason: 'powtórzona aktywność: ${b.id}');
        for (final a in activities.where((a) => !restricted.contains(a.id))) {
          expect(ids, contains(a.id), reason: '${b.id} bez oceny ${a.id}');
        }
        for (final f in fits) {
          expect(f.reasonPl.trim(), isNotEmpty, reason: '${b.id}/${f.activity.id}');
          if (f.fit == Fit.c || f.fit == Fit.d) expect(f.needsConditioning, isFalse);
        }
      }
    });

    test('każda aktywność ma co najmniej jedną kategorię, a wyjątki dotyczą istniejących ras', () {
      final ids = activities.map((a) => a.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final a in activities) {
        expect(a.categories, isNotEmpty, reason: a.id);
      }
      for (final id in sportOverrideBreedIds) {
        expect(breedInfos.containsKey(id), isTrue, reason: id);
      }
      for (final id in sportOverrideActivityIds) {
        expect(activityById(id), isNotNull, reason: id);
      }
      expect(activityById('therapy')!.categories, isNot(contains(ActivityCategory.sport)));
      expect(activityById('walks')!.categories, isNot(contains(ActivityCategory.sport)));
    });

    test('rasy krótkoczaszkowe nie dostają intensywnych sportów', () {
      const intense = ['canicross', 'bikejoring', 'sled', 'agility', 'flyball', 'frisbee', 'weightpull'];
      for (final id in breedProfiles.keys.where((id) => breedProfiles[id]!.has(BreedTrait.brachy))) {
        for (final a in intense) {
          expect(fit(id, a), Fit.c, reason: '$id/$a');
        }
        expect(fit(id, 'swimming'), Fit.c, reason: id);
        expect(fit(id, 'walks'), Fit.a, reason: id);
      }
    });

    test('rasy z długim kręgosłupem nie mają A w sportach pociągowych i skokowych', () {
      for (final id in breedProfiles.keys.where((id) => breedProfiles[id]!.has(BreedTrait.longBack))) {
        for (final f in sportFitsFor(id)) {
          final load = f.activity.load;
          if (load == ActivityLoad.pulling || load == ActivityLoad.jumping || load == ActivityLoad.strength) {
            expect(f.fit, isNot(Fit.a), reason: '$id/${f.activity.id}');
          }
        }
        expect(fit(id, 'bikejoring'), Fit.c, reason: id);
      }
    });

    test('rasy olbrzymie i z chorobami serca nie mają A w biegu i pracy pociągowej', () {
      for (final e in breedProfiles.entries) {
        final p = e.value;
        if (!p.has(BreedTrait.giant) && !p.has(BreedTrait.cardiac)) continue;
        for (final a in ['canicross', 'bikejoring', 'sled']) {
          expect(fit(e.key, a), isNot(Fit.a), reason: '${e.key}/$a');
        }
        if (p.has(BreedTrait.giant)) expect(fit(e.key, 'agility'), Fit.c, reason: e.key);
      }
    });

    test('dyscypliny specjalistyczne tylko dla właściwych ras', () {
      for (final b in breeds) {
        final p = breedProfiles[b.id]!;
        if (fit(b.id, 'racing') != null) {
          expect(p.role == BreedRole.sighthound || b.id == 'pharaoh', isTrue, reason: b.id);
        }
        if (fit(b.id, 'lgd') != null) expect(p.role, BreedRole.lgd, reason: b.id);
        if (fit(b.id, 'herding') != null) {
          expect({BreedRole.herding, BreedRole.shepherdWorking, BreedRole.mountain}, contains(p.role), reason: b.id);
        }
        if (fit(b.id, 'coursing') != null) {
          expect(
            p.role == BreedRole.sighthound || {'basenji', 'pharaoh', 'rhodesian'}.contains(b.id),
            isTrue,
            reason: b.id,
          );
        }
      }
    });

    test('dogoterapia nigdy nie ma kategorii A (zależy od konkretnego psa)', () {
      for (final b in breeds) {
        expect(fit(b.id, 'therapy'), isNot(Fit.a), reason: b.id);
      }
    });

    test('kluczowe przypadki z audytu', () {
      expect(fit('corgi_pembroke', 'canicross'), Fit.b);
      expect(fit('corgi_pembroke', 'bikejoring'), Fit.c);
      expect(fit('corgi_pembroke', 'herding'), Fit.a);
      expect(fit('corgi_cardigan', 'canicross'), Fit.b);
      expect(fit('corgi_cardigan', 'bikejoring'), Fit.c);
      expect(fit('dachshund', 'canicross'), Fit.c);
      expect(fit('dachshund', 'agility'), Fit.c);
      expect(fit('dachshund', 'tracking'), Fit.a);
      expect(fit('english_bulldog', 'canicross'), Fit.c);
      expect(fit('pug', 'bikejoring'), Fit.c);
      expect(fit('pekingese', 'agility'), Fit.c);
      expect(fit('cavalier', 'bikejoring'), Fit.c);
      expect(sportFit('cavalier', 'canicross')!.limitsPl.join(), contains('kardiolog'));
      expect(fit('great_dane', 'canicross'), Fit.c);
      expect(fit('dobermann', 'canicross'), Fit.b);
      expect(fit('dobermann', 'igp'), Fit.a);
      expect(fit('malinois', 'igp'), Fit.a);
      expect(fit('malinois', 'mondio'), Fit.a);
      expect(fit('husky', 'sled'), Fit.a);
      expect(fit('malamute', 'weightpull'), Fit.a);
      expect(fit('border_collie', 'agility'), Fit.a);
      expect(fit('bloodhound', 'mantrailing'), Fit.a);
      expect(fit('greyhound', 'racing'), Fit.a);
      expect(fit('chihuahua', 'igp'), Fit.c);
      expect(fit('pug', 'nosework'), Fit.b);
    });
  });

  group('Wiek rozpoczęcia treningu', () {
    test('rasy większe zaczynają później, praca pociągowa nie wcześniej niż bieg', () {
      for (final load in [ActivityLoad.running, ActivityLoad.pulling, ActivityLoad.jumping]) {
        var prev = 0;
        for (final g in GrowthClass.values) {
          final s = startAgeFor(g, load);
          expect(s.from, greaterThanOrEqualTo(prev), reason: '$g/$load');
          expect(s.from, greaterThanOrEqualTo(10));
          expect(s.to, greaterThanOrEqualTo(s.from));
          prev = s.from;
        }
      }
      for (final g in GrowthClass.values) {
        expect(
          startAgeFor(g, ActivityLoad.pulling).from,
          greaterThanOrEqualTo(startAgeFor(g, ActivityLoad.running).from),
        );
      }
      expect(growthClassOf(breedInfos['great_dane']!, breedProfiles['great_dane']), GrowthClass.giant);
      expect(growthClassOf(breedInfos['chihuahua']!, breedProfiles['chihuahua']), GrowthClass.small);
      expect(hasRecommended('dachshund', {ActivityLoad.jumping}), isFalse);
      expect(hasRecommended('malinois', {ActivityLoad.pulling}), isTrue);
    });
  });

  group('Badania', () {
    test('każde badanie ma opis i rodzaj', () {
      for (final k in testDescriptions.keys) {
        expect(TestKind.values, contains(testKindOf(k)));
      }
      expect(testKindOf('HD'), TestKind.breeding);
      expect(testKindOf('BOAS'), TestKind.preventive);
      expect(testKindOf('Tarczyca'), TestKind.indication);
    });
  });

  group('Tłumaczenia Atlasu', () {
    test('wszystkie teksty Atlasu mają tłumaczenie angielskie', () {
      final keys = <String>{
        for (final a in activities) a.namePl,
        for (final b in breeds)
          for (final f in sportFitsFor(b.id)) ...[f.reasonPl, ...f.limitsPl],
        ...testDescriptions.values,
      };
      // Międzynarodowe nazwy dyscyplin brzmią tak samo w każdym języku.
      const international = {
        'Canicross',
        'Bikejoring',
        'Dogtrekking',
        'Weight pulling',
        'Agility',
        'Flyball',
        'Dogfrisbee',
        'Obedience',
        'Rally-O',
        'IGP',
        'Mondioring',
        'Coursing',
        'Nosework',
        'Mantrailing',
        'Dummy',
      };
      final missing = keys.where((k) => !international.contains(k) && !en.strings.containsKey(k)).toList();
      expect(missing, isEmpty, reason: missing.join('\n'));
    });

    test('uzasadnienia i ograniczenia sportów są przetłumaczone na wszystkie języki', () {
      final keys = <String>{
        for (final b in breeds)
          for (final f in sportFitsFor(b.id)) ...[f.reasonPl, ...f.limitsPl],
        'Charakter i temperament',
        'Według wzorca FCI',
        'Psy i suki',
        'min. {0} {1}',
        'ok. {0} {1}',
      };
      for (final lang in appLanguages.where((l) => l.code != 'pl')) {
        final missing = keys.where((k) => !lang.strings.containsKey(k)).toList();
        expect(missing, isEmpty, reason: '${lang.code}: ${missing.join('\n')}');
      }
    });

    test('każda rasa ma opis charakteru przetłumaczony na angielski', () {
      final without = breeds.where((b) => !hasTemperament(b.id)).map((b) => b.id).toList();
      expect(without, isEmpty);
      final missing = temperamentKeys.where((k) => !en.strings.containsKey(k)).toList();
      expect(missing, isEmpty, reason: missing.join('\n'));
    });
  });
}
