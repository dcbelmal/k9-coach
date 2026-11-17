import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'forms.dart';
import 'health.dart';
import 'home.dart';
import 'profile.dart';
import 'training.dart';

/// Zakładki dolnego paska: 0 Start, 1 Trening, 2 Zdrowie, 3 Pies.
final tabIndex = ValueNotifier<int>(0);
void goToTab(int i) => tabIndex.value = i;

/// Otwiera zakładkę Trening na wybranym segmencie (3 = statystyki).
void openTrainingTab(int segment) {
  trainingTab.value = segment;
  goToTab(1);
}

class Shell extends StatelessWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tabIndex,
      builder: (context, i, _) => Scaffold(
        extendBody: true,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a), child: child),
          ),
          child: KeyedSubtree(
            key: ValueKey(i),
            child: switch (i) {
              0 => const HomeScreen(),
              1 => const TrainingScreen(inTab: true),
              2 => const HealthScreen(inTab: true),
              _ => const ProfileScreen(),
            },
          ),
        ),
        bottomNavigationBar: _BottomBar(index: i),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  const _BottomBar({required this.index});

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, IconData active, String label) => Expanded(
          child: InkResponse(
            onTap: () => goToTab(i),
            radius: 36,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedScale(
                scale: index == i ? 1.12 : 1,
                duration: const Duration(milliseconds: 200),
                child: Icon(index == i ? active : icon, color: index == i ? K9.orange : K9.muted, size: 25),
              ),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: index == i ? K9.orange : K9.muted)),
            ]),
          ),
        );
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101012),
        border: Border(top: BorderSide(color: K9.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(children: [
            item(0, Icons.home_outlined, Icons.home_rounded, 'Start'),
            item(1, Icons.directions_run, Icons.directions_run_rounded, 'Trening'),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () => openQuickAdd(context),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: K9.orangeGradient,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: K9.orange.withValues(alpha: 0.45), blurRadius: 18)],
                    ),
                    child: const Icon(Icons.add_rounded, color: Colors.black, size: 32),
                  ),
                ),
              ),
            ),
            item(2, Icons.favorite_border_rounded, Icons.favorite_rounded, 'Zdrowie'),
            item(3, Icons.pets_outlined, Icons.pets_rounded, 'Pies'),
          ]),
        ),
      ),
    );
  }
}
