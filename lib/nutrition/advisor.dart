import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import 'nutrition_models.dart';
import 'nutrition_store.dart';
import '../l10n/l10n.dart';

/// Rekomendacja z panelu AI. [adjustPct] – proponowana zmiana dawki do zatwierdzenia.
class Advice {
  final IconData icon;
  final Color color;
  final String title;
  final String text;
  final double? adjustPct;
  const Advice(this.icon, this.color, this.title, this.text, {this.adjustPct});
}

/// Analiza danych (waga, kalorie, przysmaki, treningi, magazyn) i propozycje zmian.
/// Działa offline na telefonie. Interfejs jest gotowy na podpięcie modelu
/// językowego w chmurze (kolejny etap) – wynik ma tę samą postać.
class NutritionAdvisor {
  static List<Advice> analyze(NutritionStore n) {
    final app = n.app;
    final out = <Advice>[];
    final dog = app.dog;
    if (dog == null) return out;
    final plan = n.plan;
    final s = n.settings;

    if ((dog.weightKg ?? 0) <= 0) {
      return [
        Advice(Icons.monitor_weight_rounded, K9.yellow, tr('Uzupełnij wagę psa'),
            tr('Bez aktualnej masy ciała nie policzę dawki. Dodaj ważenie w profilu lub dzienniku.'))
      ];
    }
    if (n.mainProduct == null) {
      out.add(Advice(Icons.qr_code_scanner_rounded, K9.orange, tr('Dodaj karmę główną'),
          tr('Zeskanuj worek albo wpisz karmę ręcznie, a przeliczę kalorie na gramy.')));
    } else if (n.mainProduct!.kcalPer100g == null) {
      out.add(Advice(Icons.info_outline_rounded, K9.yellow, tr('Brak kaloryczności z etykiety'),
          n.mainProduct!.kcalEstimated
              ? tr('Kaloryczność karmy jest szacowana ze składu. Wpisz kcal/100 g z worka dla dokładniejszej dawki.')
              : tr('Używam średniej wartości 370 kcal/100 g. Wpisz kcal z etykiety karmy.')));
    }

    // --- Trend wagi (ostatnie 4 tygodnie) ---
    final now = DateTime.now();
    final recent = app.weights.where((w) => w.date.isAfter(now.subtract(const Duration(days: 35)))).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final lastWeigh = app.weights.isEmpty ? null : app.weights.last.date;
    if (lastWeigh == null || now.difference(lastWeigh).inDays > 14) {
      out.add(Advice(Icons.scale_rounded, K9.blue, tr('Czas na ważenie'),
          tr('Ostatnie ważenie było ponad 2 tygodnie temu. Regularna waga pozwala mi dokładnie korygować dawkę.')));
    }
    if (recent.length >= 2) {
      final days = recent.last.date.difference(recent.first.date).inDays;
      if (days >= 10) {
        final change = recent.last.kg - recent.first.kg;
        final weeklyPct = change / recent.first.kg / days * 7 * 100;
        final target = dog.targetWeightKg;
        switch (s.goal) {
          case NutritionGoal.lose:
            if (target != null && recent.last.kg <= target) {
              out.add(const Advice(Icons.emoji_events_rounded, K9.green, 'Cel osiągnięty',
                  'Pies osiągnął wagę docelową. Zmień cel na „Utrzymanie wagi”.'));
            } else if (weeklyPct > -0.5) {
              out.add(Advice(Icons.trending_flat_rounded, K9.yellow, 'Redukcja stoi w miejscu',
                  'Waga zmienia się o ${fmtNum(weeklyPct, 1)}% tygodniowo (cel: ok. −1%). Proponuję zmniejszyć dawkę o 10%.',
                  adjustPct: -10));
            } else if (weeklyPct < -2) {
              out.add(Advice(Icons.warning_amber_rounded, K9.red, 'Za szybkie chudnięcie',
                  'Spadek ${fmtNum(weeklyPct.abs(), 1)}% tygodniowo to za dużo (bezpiecznie 1–2%). Proponuję zwiększyć dawkę o 5%.',
                  adjustPct: 5));
            } else {
              out.add(Advice(Icons.check_circle_rounded, K9.green, 'Redukcja idzie dobrze',
                  'Spadek ${fmtNum(weeklyPct.abs(), 1)}% tygodniowo – bezpieczne tempo. Bez zmian.'));
            }
          case NutritionGoal.gain:
            if (target != null && recent.last.kg >= target) {
              out.add(const Advice(Icons.emoji_events_rounded, K9.green, 'Masa docelowa osiągnięta',
                  'Zmień cel na „Utrzymanie wagi”, żeby pies nie przybierał dalej.'));
            } else if (weeklyPct < 0.25) {
              out.add(Advice(Icons.trending_flat_rounded, K9.yellow, 'Masa nie rośnie',
                  'Przyrost ${fmtNum(weeklyPct, 1)}% tygodniowo. Proponuję zwiększyć dawkę o 10%.',
                  adjustPct: 10));
            } else if (weeklyPct > 1.5) {
              out.add(Advice(Icons.warning_amber_rounded, K9.yellow, 'Szybki przyrost',
                  'Waga rośnie o ${fmtNum(weeklyPct, 1)}% tygodniowo. Sprawdź kondycję (BCS) – może wystarczy −5%.',
                  adjustPct: -5));
            } else {
              out.add(const Advice(Icons.check_circle_rounded, K9.green, 'Budowa masy w normie',
                  'Tempo przyrostu jest właściwe. Bez zmian.'));
            }
          case NutritionGoal.maintain:
            final pct = change / recent.first.kg * 100;
            if (pct > 3) {
              out.add(Advice(Icons.trending_up_rounded, K9.yellow, 'Waga rośnie',
                  'Przez ostatnie tygodnie +${fmtNum(pct, 1)}%. Proponuję zmniejszyć dawkę o 5%.',
                  adjustPct: -5));
            } else if (pct < -3) {
              out.add(Advice(Icons.trending_down_rounded, K9.yellow, 'Waga spada',
                  'Przez ostatnie tygodnie ${fmtNum(pct, 1)}%. Proponuję zwiększyć dawkę o 5%.', adjustPct: 5));
            }
        }
      }
    }

    // --- BCS ---
    final bcs = dog.bcs;
    if (bcs != null && s.goal == NutritionGoal.maintain) {
      if (bcs >= 6) {
        out.add(Advice(Icons.shield_outlined, K9.yellow, tr('Kondycja powyżej ideału'),
            tr('BCS 6+ oznacza nadwagę. Rozważ cel „Redukcja” i wpisz wagę docelową w profilu.')));
      } else if (bcs <= 3) {
        out.add(Advice(Icons.shield_outlined, K9.yellow, tr('Pies jest szczupły'),
            tr('BCS 3 lub mniej. Rozważ cel „Budowa masy”.')));
      }
    }

    // --- Przysmaki ---
    final week = n.lastDays(7);
    final kcal7 = week.fold(0.0, (a, d) => a + d.kcal);
    final treats7 = week.fold(0.0, (a, d) => a + d.treatKcal);
    if (kcal7 > 0 && treats7 / kcal7 > 0.15) {
      out.add(Advice(Icons.cookie_rounded, K9.yellow, tr('Dużo przysmaków'),
          tr('Przysmaki to {0}% kalorii z tygodnia (zalecane do 10–15%). Porcja karmy jest już zmniejszana, ale warto użyć mniejszych kawałków lub części karmy jako nagrody.', [(treats7 / kcal7 * 100).round()])));
    }
    if (plan != null && plan.treatsShare > 0.25) {
      out.add(Advice(Icons.warning_amber_rounded, K9.red, tr('Dziś przysmaki to ponad 25% kalorii'),
          tr('Karma zapewnia minerały i witaminy. Postaraj się nie zastępować jej przysmakami.')));
    }

    // --- Obciążenie treningowe ---
    final r = app.readiness;
    if (r.level == 3 || r.level == 2) {
      out.add(Advice(Icons.bolt_rounded, K9.orange, tr('Wyższe obciążenie treningowe'),
          tr('Ten tydzień jest cięższy niż zwykle. Dodatkowe kalorie z treningów są już doliczone do dawki{0}. Pilnuj wody i regeneracji.', [plan != null && plan.trainingKcal > 0 ? tr(' (dziś +{0} kcal)', [plan.trainingKcal.round()]) : ''])));
    }

    // --- Magazyn ---
    final f = n.mainForecast;
    if (f != null && f.daysLeft != null && f.daysLeft! <= n.settings.buyLeadDays + 2) {
      out.add(Advice(Icons.shopping_bag_rounded, K9.red, tr('Kup nowy worek'),
          tr('Karmy wystarczy na ok. {0} dni (do {1}).', [f.daysLeft, fmtDateShort(f.emptyDate!)])));
    }

    // --- Korekta aktywna ---
    if (s.adjustPct != 0) {
      out.add(Advice(Icons.tune_rounded, K9.muted, tr('Aktywna korekta dawki {0}{1}%', [s.adjustPct > 0 ? '+' : '', s.adjustPct.round()]),
          tr('Możesz ją wyzerować, jeśli sytuacja się zmieniła.'),
          adjustPct: -s.adjustPct));
    }

    if (out.isEmpty) {
      out.add(Advice(Icons.check_circle_rounded, K9.green, tr('Wszystko w normie'),
          tr('Dawka pasuje do aktywności i celu. Dodawaj karmienia i ważenia, a będę pilnować bilansu.')));
    }
    return out;
  }
}
