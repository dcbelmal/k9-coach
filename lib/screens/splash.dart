import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import '../l10n/l10n.dart';

/// Ekran startowy Valkor Coach: logo Valkor Canis z hasłem na czarnym tle.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: K9.brandBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 0.9,
            colors: [Color(0xFF1A1512), K9.brandBg],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 72, 32, 40),
            child: Column(children: [
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Image.asset('assets/brand/valkor_logo.png', filterQuality: FilterQuality.medium),
              ),
              const SizedBox(height: 34),
              Text(tr('COACH'),
                  style: TextStyle(
                      fontFamily: 'Cinzel', fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: 8, color: K9.goldLight)),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: const SizedBox(
                  width: 160,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    color: K9.gold,
                    backgroundColor: Color(0xFF2A2421),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
