import 'package:material_ui/material_ui.dart';

import '../models.dart';
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
/// Trend masy w % na tydzień z regresji liniowej. Null, gdy danych jest za mało
/// (mniej niż 3 ważenia albo krócej niż 21 dni) – wtedy nie proponujemy zmian dawki.
double? weightTrend(List<WeightEntry> pts) {
  if (pts.length < 3) return null;
  final sorted = [...pts]..sort((a, b) => a.date.compareTo(b.date));
  final t0 = sorted.first.date;
  final span = sorted.last.date.difference(t0).inHours / 24;
  if (span < 21) return null;
  final xs = [for (final p in sorted) p.date.difference(t0).inHours / 24];
  final ys = [for (final p in sorted) p.kg];
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n, my = ys.reduce((a, b) => a + b) / n;
  var num = 0.0, den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) * (xs[i] - mx);
  }
  if (den == 0 || my <= 0) return null;
  return num / den * 7 / my * 100;
}

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
    final recent = app.weights.where((w) => w.date.isAfter(now.subtract(const Duration(days: 42)))).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final lastWeigh = app.weights.isEmpty ? null : app.weights.last.date;
    if (lastWeigh == null || now.difference(lastWeigh).inDays > 14) {
      out.add(Advice(Icons.scale_rounded, K9.blue, tr('Czas na ważenie'),
          tr('Ostatnie ważenie było ponad 2 tygodnie temu. Regularna waga pozwala mi dokładnie korygować dawkę.')));
    }
    final trend = weightTrend(recent);
    if (trend == null && recent.length >= 2) {
      out.add(Advice(Icons.timeline_rounded, K9.blue, tr('Za mało ważeń na ocenę trendu'),
          tr('Do oceny zmiany dawki potrzebuję co najmniej 3 ważeń z okresu min. 3 tygodni. Krótkie wahania (woda, jelita, pora dnia) nie są podstawą do zmiany porcji.')));
    }
    if (trend != null) {
      final weeklyPct = trend;
      final target = dog.targetWeightKg;
      final lastKg = recent.last.kg;
      switch (s.goal) {
        case NutritionGoal.lose:
          if (target != null && lastKg <= target) {
            out.add(Advice(Icons.emoji_events_rounded, K9.green, tr('Cel osiągnięty'),
                tr('Pies osiągnął wagę docelową. Zmień cel na „Utrzymanie wagi”.')));
          } else if (weeklyPct > -0.5) {
            out.add(Advice(Icons.trending_flat_rounded, K9.yellow, tr('Redukcja stoi w miejscu'),
                tr('Przez ostatnie tygodnie waga zmienia się o {0}% tygodniowo (zalecane ok. 1–2%). Najpierw sprawdź, czy wszystkie przysmaki są zapisane. Możesz zmniejszyć dawkę o 5% i ocenić efekt po 2–3 tygodniach.', [fmtNum(weeklyPct, 1)]),
                adjustPct: -5));
          } else if (weeklyPct < -2) {
            out.add(Advice(Icons.warning_amber_rounded, K9.red, tr('Za szybkie chudnięcie'),
                tr('Spadek {0}% tygodniowo to więcej niż zalecane 1–2%. Proponuję zwiększyć dawkę o 5%. Jeśli pies chudnie mimo jedzenia – skontaktuj się z lekarzem weterynarii.', [fmtNum(weeklyPct.abs(), 1)]),
                adjustPct: 5));
          } else {
            out.add(Advice(Icons.check_circle_rounded, K9.green, tr('Redukcja idzie dobrze'),
                tr('Spadek {0}% tygodniowo – bezpieczne tempo. Bez zmian.', [fmtNum(weeklyPct.abs(), 1)])));
          }
        case NutritionGoal.gain:
          if (target != null && lastKg >= target) {
            out.add(Advice(Icons.emoji_events_rounded, K9.green, tr('Masa docelowa osiągnięta'),
                tr('Zmień cel na „Utrzymanie wagi”, żeby pies nie przybierał dalej.')));
          } else if (weeklyPct < 0.25) {
            out.add(Advice(Icons.trending_flat_rounded, K9.yellow, tr('Masa nie rośnie'),
                tr('Przyrost {0}% tygodniowo. Możesz zwiększyć dawkę o 5% i ocenić efekt po 2–3 tygodniach. Niezamierzona utrata masy wymaga wizyty u lekarza weterynarii.', [fmtNum(weeklyPct, 1)]),
                adjustPct: 5));
          } else if (weeklyPct > 1.5) {
            out.add(Advice(Icons.warning_amber_rounded, K9.yellow, tr('Szybki przyrost'),
                tr('Waga rośnie o {0}% tygodniowo. Sprawdź kondycję (BCS) – może wystarczy −5%.', [fmtNum(weeklyPct, 1)]),
                adjustPct: -5));
          } else {
            out.add(Advice(Icons.check_circle_rounded, K9.green, tr('Budowa masy w normie'),
                tr('Tempo przyrostu jest właściwe. Bez zmian.')));
          }
        case NutritionGoal.maintain:
          if (weeklyPct > 0.75) {
            out.add(Advice(Icons.trending_up_rounded, K9.yellow, tr('Waga rośnie'),
                tr('Trend z ostatnich tygodni: +{0}% tygodniowo. Jeśli BCS też rośnie, możesz zmniejszyć dawkę o 5%.', [fmtNum(weeklyPct, 1)]),
                adjustPct: -5));
          } else if (weeklyPct < -0.75) {
            out.add(Advice(Icons.trending_down_rounded, K9.yellow, tr('Waga spada'),
                tr('Trend z ostatnich tygodni: {0}% tygodniowo. Możesz zwiększyć dawkę o 5%. Niewyjaśniony spadek masy skonsultuj z lekarzem weterynarii.', [fmtNum(weeklyPct, 1)]),
                adjustPct: 5));
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
          tr('Ten tydzień jest cięższy niż zwykle. Do dawki doliczam tylko bieg z dystansem{0} – zwykła aktywność jest już w zapotrzebowaniu bazowym. Pilnuj wody i regeneracji.', [plan != null && plan.trainingKcal > 0 ? tr(' (dziś +{0} kcal)', [plan.trainingKcal.round()]) : ''])));
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
