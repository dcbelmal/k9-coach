import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'files/file_store.dart';
import 'notifications.dart';
import 'screens/onboarding.dart';
import 'screens/shell.dart';
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
  runApp(const K9CoachApp());
}

class K9CoachApp extends StatelessWidget {
  const K9CoachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K9 Coach',
      debugShowCheckedModeBanner: false,
      theme: K9.theme(),
      darkTheme: K9.theme(),
      themeMode: ThemeMode.dark,
      locale: const Locale('pl'),
      supportedLocales: const [Locale('pl')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ListenableBuilder(
        listenable: AppStore.instance,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: AppStore.instance.dog == null
              ? const OnboardingScreen(key: ValueKey('onb'))
              : const Shell(key: ValueKey('shell')),
        ),
      ),
    );
  }
}
