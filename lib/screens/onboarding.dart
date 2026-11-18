import 'package:material_ui/material_ui.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../modules/dog_wizard.dart';
import '../l10n/l10n.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        // Tło z logo Valkor Canis zamiast pustej łapy.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.45),
              radius: 0.85,
              colors: [Color(0xFF1A1512), K9.brandBg],
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: const Alignment(0, -0.55),
            child: FractionallySizedBox(
              widthFactor: 0.72,
              child: Image.asset('assets/brand/valkor_logo.png', filterQuality: FilterQuality.medium),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x990B0B0C), K9.bg],
              stops: [0.45, 0.68, 0.85],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Spacer(),
              FadeSlideIn(
                child: Text(tr('VALKOR COACH'),
                    style: TextStyle(
                        fontFamily: 'Cinzel', color: K9.goldLight, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 2.5)),
              ),
              const SizedBox(height: 10),
              FadeSlideIn(
                index: 1,
                child: Text(
                  tr('Trening, zdrowie i forma Twojego psa sportowego w jednym miejscu.'),
                  style: TextStyle(fontSize: 17, color: Color(0xFFCFCFD4), height: 1.35),
                ),
              ),
              const SizedBox(height: 28),
              FadeSlideIn(
                index: 2,
                child: FilledButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const DogWizardScreen())),
                  child: Text(tr('Dodaj swojego psa')),
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                index: 3,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: K9.text,
                    side: const BorderSide(color: K9.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: loading
                      ? null
                      : () async {
                          setState(() => loading = true);
                          await AppStore.instance.loadDemo();
                        },
                  child: Text(tr('Zobacz na przykładzie (Gamora)')),
                ),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ),
      ]),
    );
  }
}
