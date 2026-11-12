import 'package:material_ui/material_ui.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'profile.dart';

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
        const DogPhoto(dog: null),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0xCC0B0B0C), K9.bg],
              stops: [0.2, 0.55, 0.8],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Spacer(),
              const FadeSlideIn(
                child: Row(children: [
                  Text('K9', style: TextStyle(color: K9.orange, fontSize: 48, fontWeight: FontWeight.w900)),
                  SizedBox(width: 8),
                  Text('Coach', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(height: 10),
              const FadeSlideIn(
                index: 1,
                child: Text(
                  'Trening, zdrowie i forma Twojego psa sportowego w jednym miejscu.',
                  style: TextStyle(fontSize: 17, color: Color(0xFFCFCFD4), height: 1.35),
                ),
              ),
              const SizedBox(height: 28),
              FadeSlideIn(
                index: 2,
                child: FilledButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const DogEditScreen())),
                  child: const Text('Dodaj swojego psa'),
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
                  child: const Text('Zobacz na przykładzie (Gamora)'),
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
