import 'package:material_ui/material_ui.dart';

import '../gallery/gallery_screen.dart';
import '../heat/heat_screen.dart';
import '../models.dart';
import '../nutrition/screens/nutrition_screen.dart';
import '../screens/calendar.dart';
import '../screens/documents.dart';
import '../screens/forms.dart';
import '../screens/gear.dart';
import '../screens/goals.dart';
import '../screens/health.dart';
import '../screens/profile.dart';
import '../screens/shell.dart';
import '../screens/shows.dart';
import '../screens/training.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'module_store.dart';
import 'modules.dart';
import 'premium_screen.dart';

/// Otwiera ekran danego modułu.
void openModule(BuildContext context, AppModule m) {
  void push(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
  switch (m) {
    case AppModule.profile:
      goToTab(3);
    case AppModule.training:
      openTrainingTab(0);
    case AppModule.walks:
      push(const DisciplineScreen(discipline: Discipline.walk));
    case AppModule.feeding:
      openNutrition(context);
    case AppModule.foodStock:
      push(const StockScreen());
    case AppModule.calendar:
      openCalendar(context);
    case AppModule.healthCalendar:
      goToTab(2);
    case AppModule.vaccinations:
      push(const HealthCategoryScreen(category: HealthCategory.vaccination));
    case AppModule.deworming:
      push(const HealthCategoryScreen(category: HealthCategory.deworming));
    case AppModule.weight:
      push(const _WeightScreen());
    case AppModule.notes:
      push(const _NotesScreen());
    case AppModule.documents || AppModule.breedingDocs:
      push(const DocumentsScreen());
    case AppModule.gallery:
      push(const GalleryScreen());
    case AppModule.stats:
      openTrainingTab(3);
    case AppModule.gear:
      push(const GearScreen());
    case AppModule.goals:
      push(const GoalsScreen());
    case AppModule.heat:
      openHeat(context);
    case AppModule.breeding:
      push(const PlannedModuleScreen(module: AppModule.breeding));
    case AppModule.reproduction:
      if (ModuleStore.instance.isEnabled(AppModule.heat)) {
        openHeat(context);
      } else if (ModuleStore.instance.premium) {
        push(const PlannedModuleScreen(module: AppModule.breeding));
      } else {
        push(const PremiumScreen());
      }
    case AppModule.shows:
      push(const ShowsScreen());
    case AppModule.evaluations:
      push(const ShowsScreen(initialTab: 2));
    case AppModule.canicross:
      push(const DisciplineScreen(discipline: Discipline.canicross));
    case AppModule.bikejoring:
      push(const DisciplineScreen(discipline: Discipline.bikejoring));
    case AppModule.obedience || AppModule.sportObedience:
      push(const DisciplineScreen(discipline: Discipline.obedience));
    case AppModule.bhvt:
      push(const DisciplineScreen(discipline: Discipline.bhvt));
    case AppModule.igp:
      push(const DisciplineScreen(discipline: Discipline.igp));
    case AppModule.tracking:
      push(const DisciplineScreen(discipline: Discipline.nosework));
    case AppModule.basicCommands ||
          AppModule.socialization ||
          AppModule.mindGames ||
          AppModule.recall ||
          AppModule.agility ||
          AppModule.dogtrekking ||
          AppModule.protection:
      push(PlannedModuleScreen(module: m));
  }
}

/// Co znajdzie się w modułach, które dopiero powstają (kolejne etapy).
const plannedFeatures = <AppModule, List<String>>{
  AppModule.breeding: [
    'Rejestr krycia',
    'Kalkulator ciąży i licznik dni',
    'Przewidywany termin porodu',
    'Dziennik ciąży',
    'Rejestr szczeniąt i wykres ich masy',
    'Dokumentacja miotu',
  ],
  AppModule.basicCommands: ['Siad, waruj, zostań, noga', 'Postępy każdej komendy', 'Plan krótkich sesji na co dzień'],
  AppModule.socialization: ['Lista miejsc, ludzi i bodźców do oswojenia', 'Ocena reakcji psa', 'Przypomnienia o nowych wyzwaniach'],
  AppModule.mindGames: ['Węszenie, maty, zabawki na smakołyki', 'Pomysły na zabawy w domu', 'Dziennik zabaw'],
  AppModule.recall: ['Etapy nauki przywołania', 'Trening na lince i bez', 'Skuteczność w różnych miejscach'],
  AppModule.agility: ['Przeszkody i sekwencje', 'Czasy przebiegów i błędy', 'Kalendarz zawodów'],
  AppModule.dogtrekking: ['Trasy z GPS i przewyższeniem', 'Dystans tygodniowy', 'Lista sprzętu na trasę'],
  AppModule.protection: ['Ćwiczenia działu C', 'Ocena chwytu i kontroli', 'Przygotowanie do egzaminu'],
};

class PlannedModuleScreen extends StatelessWidget {
  final AppModule module;
  const PlannedModuleScreen({super.key, required this.module});

  @override
  Widget build(BuildContext context) {
    final feats = plannedFeatures[module] ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: Text(module.label)),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 12),
        Center(child: IconBadge(module.icon, K9.orange, size: 80)),
        const SizedBox(height: 18),
        const Text('Moduł w przygotowaniu',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Pojawi się w kolejnej aktualizacji. Na razie możesz zapisywać treningi w module Trening.',
            textAlign: TextAlign.center, style: TextStyle(color: K9.muted)),
        const SizedBox(height: 24),
        if (feats.isNotEmpty)
          K9Card(
            child: Column(children: [
              for (final f in feats)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded, color: K9.orange, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(f, style: const TextStyle(fontSize: 15))),
                  ]),
                ),
            ]),
          ),
        if (module.section == ModuleSection.training) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => openTrainingForm(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Zapisz trening'),
          ),
        ],
      ]),
    );
  }
}

class _WeightScreen extends StatelessWidget {
  const _WeightScreen();
  @override
  Widget build(BuildContext context) {
    final s = AppStore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Historia masy')),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) =>
            ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [WeightHistory(s: s)]),
      ),
    );
  }
}

class _NotesScreen extends StatelessWidget {
  const _NotesScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notatki')),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [DogNotesEditor(dog: AppStore.instance.dog!)]),
    );
  }
}
