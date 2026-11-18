import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/build_config.dart';
import 'package:k9_coach/models.dart';
import 'package:k9_coach/modules/billing.dart';
import 'package:k9_coach/modules/module_store.dart';
import 'package:k9_coach/modules/premium_screen.dart';
import 'package:k9_coach/nutrition/nutrition_models.dart';
import 'package:k9_coach/nutrition/nutrition_store.dart';
import 'package:k9_coach/screens/forms.dart';
import 'package:k9_coach/storage/safe_prefs.dart';
import 'package:k9_coach/store.dart';
import 'package:k9_coach/theme.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers/fake_prefs.dart';

Widget formHost() => MaterialApp(
      theme: K9.theme(),
      home: Scaffold(
        body: Builder(
          builder: (c) => Center(
            child: TextButton(onPressed: () => openTrainingForm(c, discipline: Discipline.obedience), child: const Text('otwórz')),
          ),
        ),
      ),
    );

Future<void> openForm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(formHost());
  await tester.tap(find.text('otwórz'));
  await tester.pumpAndSettle();
}

/// Daje czas prawdziwym operacjom zapisu (kolejka zapisów działa poza FakeAsync).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
  }
}

/// Kończy zapisy w toku przed końcem testu (inaczej zostałyby w strefie FakeAsync).
Future<void> drain(WidgetTester tester) async {
  await settle(tester);
  await tester.runAsync(() => AppStore.instance.load().timeout(const Duration(seconds: 2)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FakeDisk disk;

  setUpAll(() async => initializeDateFormatting());

  setUp(() async {
    disk = installFakeDisk();
    dir = await useTempFiles();
    await restartApp();
    await AppStore.instance.saveDog(Dog(name: 'A', weightKg: 20));
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('dwa szybkie kliknięcia „Zapisz” dają jeden trening', (tester) async {
    await openForm(tester);
    final hold = Completer<void>();
    disk.holdKeys['k9coach_data_v1'] = hold; // zapis „trwa”
    await tester.tap(find.text('Zapisz'));
    await tester.pump();
    await tester.tap(find.text('Zapisz'), warnIfMissed: false);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.tap(find.text('Zapisz'), warnIfMissed: false);
    await tester.pump();
    hold.complete();
    disk.holdKeys.clear();
    await settle(tester);
    expect(AppStore.instance.trainings.length, 1);
    final saved = jsonDecode(disk.raw('k9coach_data_v1')!) as Map<String, dynamic>;
    expect((saved['trainings'] as List).length, 1);
    await drain(tester);
  });

  testWidgets('błędny czas nie zamienia się po cichu na zero', (tester) async {
    await openForm(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Czas (min)'), 'abc');
    await tester.tap(find.text('Zapisz'));
    await settle(tester);
    expect(AppStore.instance.trainings, isEmpty);
    expect(find.textContaining('Podaj czas w pełnych minutach'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Czas (min)'), '0');
    await tester.tap(find.text('Zapisz'));
    await settle(tester);
    expect(AppStore.instance.trainings, isEmpty);
    await drain(tester);
  });

  testWidgets('błąd zapisu: formularz zostaje, ponowienie zapisuje jeden trening z tym samym ID', (tester) async {
    await openForm(tester);
    disk.full = true;
    await tester.tap(find.text('Zapisz'));
    await settle(tester);
    expect(find.text('Nie zapisano'), findsOneWidget);
    expect(find.text('Trening zapisany'), findsNothing, reason: 'brak komunikatu o sukcesie');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Nowy trening'), findsOneWidget, reason: 'formularz zostaje');
    disk.full = false;
    await tester.tap(find.text('Zapisz'));
    await settle(tester);
    expect(find.text('Nowy trening'), findsNothing, reason: 'po zapisie formularz się zamyka');
    expect(AppStore.instance.trainings.length, 1);
    await drain(tester);
  });

  test('przerwany zapis treningu ze smaczkami i ponowienie: jeden trening, jedna porcja', () async {
    final n = NutritionStore.instance;
    await n.upsertProduct(FoodProduct(id: 'p1', name: 'Kabanosy', type: ProductType.treat, kcalPer100g: 350));
    final t = TrainingSession(id: 'tt1', discipline: Discipline.obedience, date: DateTime.now(), durationMin: 20);

    disk.failKeys.add('k9coach_data_v1'); // proces „zamknięty” przed zapisem treningu w historii
    await expectLater(n.saveTrainingWithTreats(t, {'p1': 10}), throwsA(isA<StorageWriteException>()));
    disk.failKeys.clear();
    final kcal = n.treatsForTraining('tt1').fold(0.0, (a, e) => a + e.kcal);
    expect(kcal, greaterThan(0), reason: 'kalorie nagród nie zginęły');

    // Restart: aplikacja dokańcza zapis treningu z dziennika.
    await restartApp();
    expect(AppStore.instance.trainings.where((e) => e.id == 'tt1').length, 1);
    expect(NutritionStore.instance.treatsForTraining('tt1').length, 1);

    // Użytkownik i tak ponawia zapis – bez duplikatu i bez podwójnych kalorii.
    await NutritionStore.instance.saveTrainingWithTreats(t, {'p1': 10});
    await NutritionStore.instance.saveTrainingWithTreats(t, {'p1': 10});
    await restartApp();
    expect(AppStore.instance.trainings.where((e) => e.id == 'tt1').length, 1);
    final entries = NutritionStore.instance.treatsForTraining('tt1');
    expect(entries.length, 1);
    expect(entries.fold(0.0, (a, e) => a + e.kcal), closeTo(kcal, 0.001));
  });

  group('Premium w wersji produkcyjnej', () {
    test('wariant kompilacji: testy uruchamiają wersję produkcyjną', () {
      expect(appFlavor, 'prod');
      expect(isBetaBuild, isFalse);
      expect(salesEnabled, isFalse, reason: 'sprzedaż wyłączona bez weryfikacji zakupów');
      expect(Billing.instance.supported, isFalse);
    });

    test('stary przełącznik testowy nie daje Premium w produkcji', () async {
      disk.put('valkor_premium_v1', jsonEncode({'premium': true, 'premiumSource': 'test'}));
      await restartApp();
      expect(ModuleStore.instance.premium, isFalse);
      await ModuleStore.instance.setPremium(true);
      expect(ModuleStore.instance.premium, isFalse);
    });

    test('tylko potwierdzony zakup daje Premium', () {
      expect(Billing.isActiveStatus(PurchaseStatus.pending), isFalse);
      expect(Billing.isActiveStatus(PurchaseStatus.canceled), isFalse);
      expect(Billing.isActiveStatus(PurchaseStatus.error), isFalse);
      expect(Billing.isActiveStatus(PurchaseStatus.purchased), isTrue);
      expect(Billing.isActiveStatus(PurchaseStatus.restored), isTrue);
    });

    testWidgets('bez sieci i bez Sklepu Play nie ma przełącznika testowego', (tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: K9.theme(), home: const PremiumScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Włącz Premium (wersja testowa)'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.textContaining('Zakup Premium nie jest jeszcze dostępny'), findsOneWidget);
    });
  });
}
