import 'package:material_ui/material_ui.dart';

import '../models.dart';

/// Sekcje, w których moduły są pokazywane na ekranie Start i w ustawieniach.
enum ModuleSection {
  basic('Na co dzień'),
  health('Zdrowie'),
  reproduction('Rozród'),
  training('Trening'),
  more('Więcej');

  final String label;
  const ModuleSection(this.label);
}

/// Dlaczego moduł jest (albo nie jest) dostępny dla danego psa.
enum ModuleRule {
  /// Dla wszystkich psów.
  always,

  /// Tylko suka niesterylizowana.
  intactFemale,

  /// Pasuje do celu użytkowania psa.
  purpose,

  /// Wymaga Premium.
  premium,
}

/// Rejestr wszystkich modułów aplikacji. Każdy moduł ma regułę, która na
/// podstawie profilu psa decyduje, czy włączyć go automatycznie. Użytkownik
/// może to nadpisać w ustawieniach (patrz ModuleStore).
///
/// Nowy moduł (np. AI) dodaje się tutaj jedną linią + ekranem w module_routes.dart.
enum AppModule {
  // --- Dla wszystkich psów -------------------------------------------------
  profile('Profil psa', Icons.pets_rounded, ModuleSection.basic, ModuleRule.always),
  training('Trening', Icons.directions_run_rounded, ModuleSection.basic, ModuleRule.always),
  walks('Spacery', Icons.directions_walk_rounded, ModuleSection.basic, ModuleRule.always),
  feeding('Karmienie', Icons.restaurant_rounded, ModuleSection.basic, ModuleRule.always),
  foodStock('Zapasy karmy', Icons.inventory_2_rounded, ModuleSection.basic, ModuleRule.always),
  calendar('Kalendarz', Icons.calendar_month_rounded, ModuleSection.basic, ModuleRule.always),
  healthCalendar('Kalendarz zdrowia', Icons.favorite_rounded, ModuleSection.health, ModuleRule.always),
  vaccinations('Szczepienia', Icons.vaccines_rounded, ModuleSection.health, ModuleRule.always),
  deworming('Odrobaczenia', Icons.medication_rounded, ModuleSection.health, ModuleRule.always),
  weight('Historia masy', Icons.monitor_weight_rounded, ModuleSection.health, ModuleRule.always),
  notes('Notatki', Icons.sticky_note_2_rounded, ModuleSection.more, ModuleRule.always),
  documents('Dokumenty', Icons.description_rounded, ModuleSection.more, ModuleRule.always),
  gallery('Galeria', Icons.photo_library_rounded, ModuleSection.more, ModuleRule.always),
  stats('Statystyki', Icons.bar_chart_rounded, ModuleSection.more, ModuleRule.always),
  gear('Sprzęt', Icons.backpack_rounded, ModuleSection.more, ModuleRule.always),
  goals('Cele', Icons.track_changes_rounded, ModuleSection.more, ModuleRule.always),

  // --- Suka ------------------------------------------------------------------
  heat('Cykl i cieczka', Icons.water_drop_rounded, ModuleSection.reproduction, ModuleRule.intactFemale),

  // --- Premium ---------------------------------------------------------------
  breeding('Moduł hodowlany', Icons.child_friendly_rounded, ModuleSection.reproduction, ModuleRule.premium),

  // --- Treningowe (wg celu użytkowania) --------------------------------------
  basicCommands('Podstawowe komendy', Icons.record_voice_over_rounded, ModuleSection.training, ModuleRule.purpose,
      [DogPurpose.family, DogPurpose.recreation]),
  socialization('Socjalizacja', Icons.groups_rounded, ModuleSection.training, ModuleRule.purpose, [DogPurpose.family]),
  mindGames('Zabawy umysłowe', Icons.extension_rounded, ModuleSection.training, ModuleRule.purpose,
      [DogPurpose.family, DogPurpose.recreation]),
  recall('Przywołanie', Icons.campaign_rounded, ModuleSection.training, ModuleRule.purpose,
      [DogPurpose.family, DogPurpose.recreation]),
  agility('Agility', Icons.sports_gymnastics_rounded, ModuleSection.training, ModuleRule.purpose, [DogPurpose.sport]),
  canicross('Canicross', Icons.directions_run_rounded, ModuleSection.training, ModuleRule.purpose,
      [DogPurpose.sport, DogPurpose.recreation]),
  bikejoring('Bikejoring', Icons.directions_bike_rounded, ModuleSection.training, ModuleRule.purpose, [DogPurpose.sport]),
  obedience('Obedience', Icons.pets_rounded, ModuleSection.training, ModuleRule.purpose, [DogPurpose.sport]),
  dogtrekking('Dogtrekking', Icons.hiking_rounded, ModuleSection.training, ModuleRule.purpose,
      [DogPurpose.sport, DogPurpose.recreation]),
  bhvt('BH-VT', Icons.emoji_events_rounded, ModuleSection.training, ModuleRule.purpose, [DogPurpose.working]),
  igp('IGP', Icons.sports_martial_arts_rounded, ModuleSection.training, ModuleRule.purpose, [DogPurpose.working]),
  tracking('Tropienie', Icons.travel_explore_rounded, ModuleSection.training, ModuleRule.purpose, [DogPurpose.working]),
  protection('Obrona', Icons.shield_rounded, ModuleSection.training, ModuleRule.purpose, [DogPurpose.working]),
  sportObedience('Posłuszeństwo sportowe', Icons.military_tech_rounded, ModuleSection.training, ModuleRule.purpose,
      [DogPurpose.working]),
  reproduction('Rozród', Icons.favorite_border_rounded, ModuleSection.training, ModuleRule.purpose, [DogPurpose.breeding]),
  shows('Wystawy', Icons.emoji_events_outlined, ModuleSection.training, ModuleRule.purpose, [DogPurpose.breeding]),
  evaluations('Oceny', Icons.grading_rounded, ModuleSection.training, ModuleRule.purpose, [DogPurpose.breeding]),
  breedingDocs('Dokumentacja hodowlana', Icons.folder_shared_rounded, ModuleSection.training, ModuleRule.purpose,
      [DogPurpose.breeding]);

  final String label;
  final IconData icon;
  final ModuleSection section;
  final ModuleRule rule;
  final List<DogPurpose> purposes;
  const AppModule(this.label, this.icon, this.section, this.rule, [this.purposes = const []]);

  /// Czy moduł w ogóle może działać dla tego psa (np. cieczka nie dla psa).
  /// Takiego modułu nie da się włączyć ręcznie.
  bool applicable(Dog dog, {required bool premium}) => switch (rule) {
        ModuleRule.intactFemale => dog.female && !dog.neutered,
        ModuleRule.premium => premium,
        _ => true,
      };

  /// Automatyczna decyzja na podstawie profilu (bez ręcznych ustawień).
  bool autoEnabled(Dog dog, {required bool premium, bool hasData = false}) {
    if (!applicable(dog, premium: premium)) return false;
    if (rule != ModuleRule.purpose) return true;
    // Starsze profile bez celu: aplikacja była dla psów sportowych.
    final p = dog.purpose ?? DogPurpose.sport;
    return purposes.contains(p) || hasData;
  }

  /// Krótki opis reguły do ustawień.
  String ruleLabel(Dog dog) => switch (rule) {
        ModuleRule.always => 'Dla wszystkich psów',
        ModuleRule.intactFemale => dog.female
            ? (dog.neutered ? 'Ukryty: suka wysterylizowana' : 'Dla suk niesterylizowanych')
            : 'Tylko dla suk',
        ModuleRule.premium => 'Premium',
        ModuleRule.purpose => 'Cel: ${purposes.map((p) => p.label).join(', ')}',
      };
}
