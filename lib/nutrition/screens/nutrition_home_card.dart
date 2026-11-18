import 'package:material_ui/material_ui.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../nutrition_models.dart';
import '../nutrition_store.dart';
import 'nutrition_forms.dart';
import 'nutrition_screen.dart';
import 'products_screen.dart';
import '../../l10n/l10n.dart';

/// Karta „Żywienie dziś” na ekranie Start.
class NutritionHomeCard extends StatelessWidget {
  const NutritionHomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final n = NutritionStore.instance;
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) {
        final plan = n.plan;
        final f = n.mainForecast;
        final low = f?.daysLeft != null && f!.daysLeft! <= n.settings.buyLeadDays;
        return K9Card(
          onTap: () => openNutrition(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionTitle(tr('Żywienie dziś'),
                icon: Icons.restaurant_rounded, action: tr('Otwórz'), onAction: () => openNutrition(context)),
            if (plan == null)
              Text(tr('Uzupełnij wagę psa, a policzę dzienną porcję karmy.'), style: TextStyle(color: K9.muted))
            else
              Row(children: [
                Expanded(
                    child: StatValue(label: tr('Zostało karmy'), value: '${plan.remainingGrams.round()}', unit: 'g')),
                Expanded(
                    child: StatValue(
                        label: plan.balance > 0 ? tr('Ponad cel') : tr('Zostało'),
                        value: '${plan.balance.abs().round()}',
                        unit: 'kcal')),
                Expanded(
                  child: StatValue(
                    label: low ? tr('Kup karmę!') : tr('Worek'),
                    value: f == null ? '–' : fmtGrams(f.remainingGrams).split(' ').first,
                    unit: f == null ? null : fmtGrams(f.remainingGrams).split(' ').last,
                    color: low ? K9.red : K9.orange,
                  ),
                ),
              ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openFeedingForm(context),
                  icon: const Icon(Icons.restaurant_rounded, size: 18),
                  label: Text(tr('Karmienie')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openFeedingForm(context, kind: FeedKind.treat),
                  icon: const Icon(Icons.cookie_rounded, size: 18),
                  label: Text(tr('Przysmak')),
                ),
              ),
            ]),
          ]),
        );
      },
    );
  }
}
