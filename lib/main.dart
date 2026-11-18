import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'breeding/breeding_store.dart';
import 'files/file_store.dart';
import 'guides/guide_store.dart';
import 'modules/billing.dart';
import 'gallery/gallery_store.dart';
import 'heat/heat_store.dart';
import 'modules/module_store.dart';
import 'notifications.dart';
import 'nutrition/nutrition_store.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';
import 'screens/splash.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: K9.bg,
  ));
  await initializeDateFormatting('pl');
  await FileStore.init();
  await Notifications.instance.init();
  await AppStore.instance.load();
  await NutritionStore.instance.load();
  await ModuleStore.instance.load();
  await HeatStore.instance.load();
  await GalleryStore.instance.load();
  await BreedingStore.instance.load();
  await GuideStore.instance.load();
  runApp(const K9CoachApp());
  Billing.instance.init(); // w tle – nie blokuje startu aplikacji
}

class K9CoachApp extends StatelessWidget {
  const K9CoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Valkor Coach',
      debugShowCheckedModeBanner: false,
      theme: K9.theme(),
      darkTheme: K9.theme(),
      themeMode: ThemeMode.dark,
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Boot(),
    );
  }
}

/// Pokazuje ekran startowy z logo przez chwilę, potem aplikację.
class _Boot extends StatefulWidget {
  const _Boot();

  @override
  State<_Boot> createState() => _BootState();
}

class _BootState extends State<_Boot> {
  bool _splash = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _splash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.instance,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _splash
            ? const SplashScreen(key: ValueKey('splash'))
            : AppStore.instance.dog == null
                ? const OnboardingScreen(key: ValueKey('onb'))
                : const Shell(key: ValueKey('shell')),
      ),
    );
  }
}
