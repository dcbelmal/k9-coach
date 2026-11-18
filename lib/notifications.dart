import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'breeding/breeding_store.dart';
import 'dogs/dog_profiles.dart';
import 'storage/safe_prefs.dart';
import 'heat/heat_store.dart';
import 'models_ext.dart';
import 'nutrition/nutrition_store.dart';
import 'store.dart';
import 'l10n/l10n.dart';

/// Lokalne przypomnienia (szczepienia, odrobaczanie, wydarzenia, treningi).
class Notifications {
  Notifications._();
  static final Notifications instance = Notifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!supported) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
    }
    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: AndroidInitializationSettings('@drawable/ic_stat_valkor'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      _ready = true;
    } catch (e) {
      logError('Powiadomienia niedostępne', e);
    }
  }

  Future<void> requestPermission() async {
    if (!_ready) return;
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'k9_reminders',
      'Przypomnienia',
      channelDescription: 'Szczepienia, odrobaczanie, treningi i wydarzenia',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFFF5821F),
      // Na zablokowanym ekranie bez treści (imię psa, nazwa dokumentu).
      visibility: NotificationVisibility.private,
    ),
    iOS: DarwinNotificationDetails(),
  );

  // --- Trening na żywo -------------------------------------------------------
  /// To samo id co powiadomienie usługi GPS, więc zastępujemy je czytelną wersją
  /// (widoczną też na ekranie blokady).
  static const liveId = 75415;
  static const goalId = 75416;

  /// Moduł Żywienie: codzienne przypomnienia (61–69) i zmiana dawki.
  static const dailyBaseId = 61;
  static const doseChangeId = 75417;

  /// Natychmiastowe powiadomienie (np. zmiana dawki karmy).
  Future<void> showNow(int id, String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(id: id, title: title, body: body, notificationDetails: _details);
    } catch (e) {
      logError('Powiadomienie', e);
    }
  }

  static const _liveChannel = AndroidNotificationDetails(
    'k9_training_live',
    'Trening na żywo',
    channelDescription: 'Czas i dystans trwającego treningu',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: false,
    enableVibration: false,
    onlyAlertOnce: true,
    color: Color(0xFFF5821F),
  );

  /// Pokazuje lub odświeża stałe powiadomienie o trwającym treningu.
  Future<void> showLive({required String title, required String body, DateTime? chronoBase}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: liveId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _liveChannel.channelId,
            _liveChannel.channelName,
            channelDescription: _liveChannel.channelDescription,
            importance: _liveChannel.importance,
            priority: _liveChannel.priority,
            playSound: false,
            enableVibration: false,
            onlyAlertOnce: true,
            ongoing: true,
            autoCancel: false,
            visibility: NotificationVisibility.private,
            category: AndroidNotificationCategory.workout,
            showWhen: chronoBase != null,
            usesChronometer: chronoBase != null,
            when: chronoBase?.millisecondsSinceEpoch,
            color: const Color(0xFFF5821F),
            colorized: true,
          ),
        ),
      );
    } catch (e) {
      logError('Powiadomienie treningu', e);
    }
  }

  /// Przypomnienie o osiągnięciu celu czasu (działa też, gdy aplikacja śpi).
  Future<void> scheduleGoal(DateTime at, String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.zonedSchedule(
        id: goalId,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      logError('Cel treningu', e);
    }
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  /// Plan przypomnień każdego psa zapisany osobno (klucz z dopiskiem psa).
  /// Dzięki temu przełączenie psa albo edycja jednego psa nie kasuje
  /// przypomnień pozostałych psów.
  static const planKey = 'valkor_notify_plan_v1';

  /// Limit zaplanowanych powiadomień (iOS pozwala na 64; zostawiamy zapas).
  static const maxScheduled = 60;
  static const maxDaily = 8;

  /// Plan bieżącego psa na podstawie danych w pamięci.
  static ReminderPlan buildPlan(AppStore s) {
    final name = s.dog?.name ?? trc('dog', 'Pies');
    final plan = <(DateTime, String, String)>[];

    for (final h in s.dueItems) {
      if (!h.remind) continue;
      final due = h.nextDue!;
      plan.add((
        DateTime(due.year, due.month, due.day, 9),
        tr('{0}: dziś termin', [h.category.label]),
        '$name – ${h.title}'
      ));
      final before = due.subtract(const Duration(days: 7));
      plan.add((
        DateTime(before.year, before.month, before.day, 9),
        tr('{0} za 7 dni', [h.category.label]),
        '$name – ${h.title} (${due.day}.${due.month.toString().padLeft(2, '0')})'
      ));
    }
    for (final e in s.events) {
      if (!e.remind) continue;
      final dayBefore = e.date.subtract(const Duration(days: 1));
      plan.add((
        DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 18),
        tr('Jutro: {0}', [e.type.label]),
        '$name – ${e.title}'
      ));
    }
    for (final t in s.trainings) {
      if (t.done) continue;
      plan.add((
        t.date.subtract(const Duration(hours: 1)),
        tr('Za godzinę trening {0}', [t.discipline.label]),
        '$name${t.notes.isEmpty ? '' : ' – ${t.notes}'}'
      ));
    }
    for (final sh in s.shows) {
      if (sh.status == ShowStatus.cancelled || sh.status == ShowStatus.done) continue;
      final d = sh.date.subtract(const Duration(days: 1));
      plan.add((DateTime(d.year, d.month, d.day, 18), tr('Jutro wystawa'), '$name – ${sh.name}'));
      if (sh.entryDeadline != null && sh.status == ShowStatus.planned) {
        final dl = sh.entryDeadline!.subtract(const Duration(days: 3));
        plan.add((DateTime(dl.year, dl.month, dl.day, 10), tr('Za 3 dni mija termin zgłoszeń'), '$name – ${sh.name}'));
      }
    }
    for (final doc in s.documents) {
      if (!doc.remind || doc.expires == null) continue;
      final e = doc.expires!;
      final before = e.subtract(const Duration(days: 30));
      plan.add((DateTime(before.year, before.month, before.day, 9), tr('Za 30 dni wygasa dokument'), '$name – ${doc.title}'));
      plan.add((DateTime(e.year, e.month, e.day, 9), tr('Dziś wygasa dokument'), '$name – ${doc.title}'));
    }
    for (final g in s.gear) {
      final r = g.replaceDate;
      if (g.retired || !g.remind || r == null) continue;
      plan.add((DateTime(r.year, r.month, r.day, 10), tr('Czas wymienić sprzęt'), '$name – ${g.name}'));
    }
    final daily = <(int, int, String, String)>[];
    // Moduły dokładamy tylko wtedy, gdy mają w pamięci dane tego samego psa.
    if (NutritionStore.instance.guard.owner == s.ownerId) {
      plan.addAll(NutritionStore.instance.notificationPlan());
      daily.addAll(NutritionStore.instance.dailyReminders());
    }
    if (HeatStore.instance.guard.owner == s.ownerId) plan.addAll(HeatStore.instance.notificationPlan());
    if (BreedingStore.instance.guard.owner == s.ownerId) plan.addAll(BreedingStore.instance.notificationPlan());
    return ReminderPlan(plan, daily);
  }

  /// Łączy plany wszystkich psów: bez duplikatów, najbliższe terminy najpierw,
  /// w granicach limitu systemu.
  static ReminderPlan mergedPlan(SharedPreferences p, List<String> dogIds, String activeId, ReminderPlan active,
      DateTime now) {
    final once = <(DateTime, String, String)>[];
    final daily = <(int, int, String, String)>[];
    final seenOnce = <String>{}, seenDaily = <String>{};
    for (final id in {...dogIds, activeId}) {
      ReminderPlan? plan;
      if (id == activeId) {
        plan = active;
      } else {
        final raw = p.getString('$planKey${DogProfiles.suffixFor(id)}');
        if (raw != null) {
          try {
            plan = ReminderPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          } catch (e) {
            logError('Przypomnienia: odczyt planu', e);
          }
        }
      }
      if (plan == null) continue;
      for (final o in plan.once) {
        if (!o.$1.isAfter(now)) continue;
        if (seenOnce.add('${o.$1.toIso8601String()}|${o.$2}|${o.$3}')) once.add(o);
      }
      for (final d in plan.daily) {
        if (seenDaily.add('${d.$1}:${d.$2}|${d.$3}|${d.$4}')) daily.add(d);
      }
    }
    final dailyCut = daily.take(maxDaily).toList();
    once.sort((a, b) => a.$1.compareTo(b.$1));
    return ReminderPlan(once.take(maxScheduled - dailyCut.length).toList(), dailyCut);
  }

  /// Planuje wszystkie przypomnienia od nowa: wszystkich psów, nie tylko wybranego.
  Future<void> reschedule(AppStore s) async {
    try {
      final p = await SharedPreferences.getInstance();
      final mine = buildPlan(s);
      // Plan zapisujemy tylko dla poprawnie odczytanego psa – zablokowany
      // (nieczytelny) profil zachowuje swój poprzedni plan.
      if (!s.locked && s.dog != null) {
        try {
          await SafePrefs.setString(p, '$planKey${DogProfiles.suffixFor(s.ownerId)}', jsonEncode(mine.toJson()));
        } catch (e) {
          logError('Przypomnienia: zapis planu', e);
        }
      }
      if (!_ready) return;
      final now = DateTime.now();
      final ids = DogProfiles.instance.ids;
      final all = mergedPlan(p, ids, s.ownerId, s.locked ? ReminderPlan.empty : mine, now);

      for (final pending in await _plugin.pendingNotificationRequests()) {
        if (pending.id != goalId && pending.id != liveId) await _plugin.cancel(id: pending.id);
      }
      for (final (i, d) in all.daily.indexed) {
        var at = DateTime(now.year, now.month, now.day, d.$1, d.$2);
        if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
        await _plugin.zonedSchedule(
          id: dailyBaseId + i,
          title: d.$3,
          body: d.$4,
          scheduledDate: tz.TZDateTime.from(at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
      var id = 0;
      for (final o in all.once) {
        await _plugin.zonedSchedule(
          id: id++,
          title: o.$2,
          body: o.$3,
          scheduledDate: tz.TZDateTime.from(o.$1, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      logError('Nie udało się zaplanować przypomnień', e);
    }
  }
}

/// Plan przypomnień jednego psa: jednorazowe (termin, tytuł, treść) i codzienne (godz., min., tytuł, treść).
class ReminderPlan {
  final List<(DateTime, String, String)> once;
  final List<(int, int, String, String)> daily;
  const ReminderPlan(this.once, this.daily);
  static const empty = ReminderPlan([], []);

  Map<String, dynamic> toJson() => {
        'once': [for (final o in once) [o.$1.toIso8601String(), o.$2, o.$3]],
        'daily': [for (final d in daily) [d.$1, d.$2, d.$3, d.$4]],
      };

  factory ReminderPlan.fromJson(Map<String, dynamic> j) => ReminderPlan(
        [for (final o in (j['once'] as List? ?? [])) (DateTime.parse(o[0] as String), o[1] as String, o[2] as String)],
        [for (final d in (j['daily'] as List? ?? [])) (d[0] as int, d[1] as int, d[2] as String, d[3] as String)],
      );
}

