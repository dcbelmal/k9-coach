import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'breeding/breeding_store.dart';
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
      debugPrint('Powiadomienia niedostępne: $e');
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
      debugPrint('Powiadomienie: $e');
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
            visibility: NotificationVisibility.public,
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
      debugPrint('Powiadomienie treningu: $e');
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
      debugPrint('Cel treningu: $e');
    }
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  /// Planuje wszystkie przypomnienia od nowa na podstawie danych.
  Future<void> reschedule(AppStore s) async {
    if (!_ready) return;
    try {
      for (final p in await _plugin.pendingNotificationRequests()) {
        if (p.id != goalId) await _plugin.cancel(id: p.id);
      }
      final now = DateTime.now();
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
          e.title
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
        plan.add((DateTime(d.year, d.month, d.day, 18), tr('Jutro wystawa'), sh.name));
        if (sh.entryDeadline != null && sh.status == ShowStatus.planned) {
          final dl = sh.entryDeadline!.subtract(const Duration(days: 3));
          plan.add((DateTime(dl.year, dl.month, dl.day, 10), tr('Za 3 dni mija termin zgłoszeń'), sh.name));
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
        plan.add((DateTime(r.year, r.month, r.day, 10), tr('Czas wymienić sprzęt'), g.name));
      }

      plan.addAll(NutritionStore.instance.notificationPlan());
      plan.addAll(HeatStore.instance.notificationPlan());
      plan.addAll(BreedingStore.instance.notificationPlan());

      // Codzienne (powtarzalne) przypomnienia o karmieniu i suplementach.
      final daily = NutritionStore.instance.dailyReminders().take(8).toList();
      for (final (i, d) in daily.indexed) {
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

      plan.sort((a, b) => a.$1.compareTo(b.$1));
      var id = 0;
      final limit = 60 - daily.length; // limit iOS: 64 zaplanowane powiadomienia
      for (final p in plan) {
        if (!p.$1.isAfter(now)) continue;
        if (id >= limit) break;
        await _plugin.zonedSchedule(
          id: id++,
          title: p.$2,
          body: p.$3,
          scheduledDate: tz.TZDateTime.from(p.$1, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (e) {
      debugPrint('Nie udało się zaplanować przypomnień: $e');
    }
  }
}

