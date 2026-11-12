import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models_ext.dart';
import 'store.dart';

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
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
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

  /// Planuje wszystkie przypomnienia od nowa na podstawie danych.
  Future<void> reschedule(AppStore s) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final now = DateTime.now();
      final name = s.dog?.name ?? 'Pies';
      final plan = <(DateTime, String, String)>[];

      for (final h in s.dueItems) {
        if (!h.remind) continue;
        final due = h.nextDue!;
        plan.add((
          DateTime(due.year, due.month, due.day, 9),
          '${h.category.label}: dziś termin',
          '$name – ${h.title}'
        ));
        final before = due.subtract(const Duration(days: 7));
        plan.add((
          DateTime(before.year, before.month, before.day, 9),
          '${h.category.label} za 7 dni',
          '$name – ${h.title} (${due.day}.${due.month.toString().padLeft(2, '0')})'
        ));
      }
      for (final e in s.events) {
        if (!e.remind) continue;
        final dayBefore = e.date.subtract(const Duration(days: 1));
        plan.add((
          DateTime(dayBefore.year, dayBefore.month, dayBefore.day, 18),
          'Jutro: ${e.type.label}',
          e.title
        ));
      }
      for (final t in s.trainings) {
        if (t.done) continue;
        plan.add((
          t.date.subtract(const Duration(hours: 1)),
          'Za godzinę trening ${t.discipline.label}',
          '$name${t.notes.isEmpty ? '' : ' – ${t.notes}'}'
        ));
      }

      for (final sh in s.shows) {
        if (sh.status == ShowStatus.cancelled || sh.status == ShowStatus.done) continue;
        final d = sh.date.subtract(const Duration(days: 1));
        plan.add((DateTime(d.year, d.month, d.day, 18), 'Jutro wystawa', sh.name));
        if (sh.entryDeadline != null && sh.status == ShowStatus.planned) {
          final dl = sh.entryDeadline!.subtract(const Duration(days: 3));
          plan.add((DateTime(dl.year, dl.month, dl.day, 10), 'Za 3 dni mija termin zgłoszeń', sh.name));
        }
      }
      for (final doc in s.documents) {
        if (!doc.remind || doc.expires == null) continue;
        final e = doc.expires!;
        final before = e.subtract(const Duration(days: 30));
        plan.add((DateTime(before.year, before.month, before.day, 9), 'Za 30 dni wygasa dokument', '$name – ${doc.title}'));
        plan.add((DateTime(e.year, e.month, e.day, 9), 'Dziś wygasa dokument', '$name – ${doc.title}'));
      }
      for (final g in s.gear) {
        final r = g.replaceDate;
        if (g.retired || !g.remind || r == null) continue;
        plan.add((DateTime(r.year, r.month, r.day, 10), 'Czas wymienić sprzęt', g.name));
      }

      plan.sort((a, b) => a.$1.compareTo(b.$1));
      var id = 0;
      for (final p in plan) {
        if (!p.$1.isAfter(now)) continue;
        if (id >= 60) break; // limit iOS: 64 zaplanowane powiadomienia
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

