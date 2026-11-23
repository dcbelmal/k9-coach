import 'package:material_ui/material_ui.dart';

import '../gps/draft_recovery.dart';
import '../theme.dart';
import 'forms.dart';
import 'health.dart';
import 'home.dart';
import 'profile.dart';
import 'training.dart';
import 'valkor_track_screen.dart';
import '../l10n/l10n.dart';

/// Zakładki dolnego paska: 0 Start, 1 Trening, 2 Zdrowie, 3 Pies, 4 Track.
/// (Track ma numer 4, żeby nie zmieniać numerów starszych zakładek.)
final tabIndex = ValueNotifier<int>(0);
void goToTab(int i) => tabIndex.value = i;

/// Otwiera zakładkę Trening na wybranym segmencie (3 = statystyki).
void openTrainingTab(int segment) {
  trainingTab.value = segment;
  goToTab(1);
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) offerDraftRecovery(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final calm = MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<int>(
      valueListenable: tabIndex,
      // Wstecz na innej zakładce wraca na Start, dopiero na Start zamyka aplikację.
      builder: (context, i, _) => PopScope(
        canPop: i == 0,
        onPopInvokedWithResult: (did, _) {
          if (!did) goToTab(0);
        },
        child: Scaffold(
        extendBody: true,
        // Każda zakładka jest budowana od nowa (zawsze aktualne dane psa),
        // a pozycję przewijania przywraca PageStorage (klucze w listach zakładek).
        body: AnimatedSwitcher(
          duration: calm ? Duration.zero : const Duration(milliseconds: 200),
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
              4 => const ValkorTrackScreen(),
              _ => const ProfileScreen(),
            },
          ),
        ),
        bottomNavigationBar: _BottomBar(index: i),
        ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
            item(0, Icons.home_outlined, Icons.home_rounded, tr('Start')),
            item(1, Icons.directions_run, Icons.directions_run_rounded, tr('Trening')),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () => openQuickAdd(context),
                  child: Container(
                    width: 50,
                    height: 50,
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
            item(4, Icons.gps_not_fixed_rounded, Icons.gps_fixed_rounded, tr('Track')),
            item(2, Icons.favorite_border_rounded, Icons.favorite_rounded, tr('Zdrowie')),
            item(3, Icons.pets_outlined, Icons.pets_rounded, trc('dog', 'Pies')),
          ]),
        ),
      ),
    );
  }
}
