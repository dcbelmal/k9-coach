import 'dart:async';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_ui/material_ui.dart';

import '../collar/collar_link.dart';
import '../collar/csv_file.dart';
import '../collar/field_test.dart';
import '../gps/phone_location.dart';
import '../l10n/l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';

void openFieldTests(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FieldTestScreen()));

/// Panel deweloperski: niezależne sesje testów terenowych z osobnym
/// podsumowaniem i eksportem CSV. Nie zmienia działania śledzenia.
class FieldTestScreen extends StatefulWidget {
  const FieldTestScreen({super.key});

  @override
  State<FieldTestScreen> createState() => _FieldTestScreenState();
}

class _FieldTestScreenState extends State<FieldTestScreen> {
  final tests = FieldTests.instance;
  final c = CollarLink.instance;
  final notes = TextEditingController();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    notes.dispose();
    super.dispose();
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: Text(k, style: const TextStyle(color: K9.muted, fontSize: 12.5))),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  Future<void> _export(FieldTest t, {bool copy = false}) async {
    final text = t.csv(c);
    if (copy) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) toast(context, tr('Skopiowano CSV testu „{0}”.', [t.name]));
      return;
    }
    final s = t.startedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'valkor-test-${t.kind.code}-${s.year}${two(s.month)}${two(s.day)}-${two(s.hour)}${two(s.minute)}.csv';
    final path = await saveCsvFile(name, text);
    if (!mounted) return;
    toast(context, path == null ? tr('Nie udało się zapisać pliku. Użyj kopiowania do schowka.') : tr('Zapisano: {0}', [path]));
  }

  Widget _indicators() {
    final now = DateTime.now();
    final ind = c.indicators(now: now, phone: PhoneLocation.instance.snapshot(now));
    Color col(IndicatorLevel l) => switch (l) {
          IndicatorLevel.ok => K9.green,
          IndicatorLevel.warn => K9.yellow,
          IndicatorLevel.bad => K9.red,
          IndicatorLevel.na => K9.muted,
        };
    return K9Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Łączność'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        for (final i in ind)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 9, color: col(i.level))),
              const SizedBox(width: 8),
              SizedBox(width: 110, child: Text(i.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
              Expanded(child: Text(i.text, style: const TextStyle(fontSize: 12.5, color: K9.muted))),
            ]),
          ),
        _row(tr('Stan psa'), c.status().name),
      ]),
    );
  }

  Widget _active(FieldTest t) {
    final now = DateTime.now();
    final s = t.summary(c, now: now);
    final el = now.difference(t.startedAt);
    return K9Card(
      key: const ValueKey('ft-active'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        Text(tr('Trwa {0} min {1} s', [el.inMinutes, el.inSeconds % 60]), style: const TextStyle(color: K9.muted)),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('ft-notes'),
          controller: notes,
          decoration: InputDecoration(labelText: tr('Warunki (opcjonalnie)')),
          onChanged: (v) => t.notes = v,
        ),
        const SizedBox(height: 6),
        for (final r in s.rows()) _row(r.$1, r.$2),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          FilledButton(
            key: const ValueKey('ft-stop'),
            onPressed: () => setState(() {
              tests.stop();
              notes.clear();
            }),
            child: Text(tr('Zakończ test')),
          ),
          OutlinedButton(
            key: const ValueKey('ft-reset'),
            onPressed: () => setState(() => tests.resetCounters()),
            child: Text(tr('Wyzeruj liczniki')),
          ),
          OutlinedButton(onPressed: () => _export(t, copy: true), child: Text(tr('Kopiuj CSV'))),
        ]),
      ]),
    );
  }

  Widget _done(FieldTest t) {
    final s = t.summary(c);
    final dur = t.endedAt!.difference(t.startedAt);
    return K9Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(tr('{0} min · {1} świeżych pozycji', [dur.inMinutes, s.freshPositions]),
              style: const TextStyle(color: K9.muted, fontSize: 12)),
          children: [
            if (t.notes.isNotEmpty) _row(tr('Warunki'), t.notes),
            for (final r in s.rows()) _row(r.$1, r.$2),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              FilledButton.tonal(onPressed: () => _export(t), child: Text(tr('Zapisz CSV'))),
              OutlinedButton(onPressed: () => _export(t, copy: true), child: Text(tr('Kopiuj CSV'))),
            ]),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = tests.active;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Testy terenowe (deweloperskie)'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
          tr('Każdy test ma własne okno czasu, liczniki od zera i osobny plik CSV. Liczniki firmware od uruchomienia trackera są w CSV w osobnych wierszach.'),
          style: const TextStyle(color: K9.muted, fontSize: 12.5),
        ),
        const SizedBox(height: 10),
        _indicators(),
        const SizedBox(height: 10),
        if (a != null)
          _active(a)
        else
          K9Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tr('Rozpocznij test'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final k in FieldTestKind.values)
                  OutlinedButton(
                    key: ValueKey('ft-start-${k.code}'),
                    onPressed: () => setState(() => tests.start(k, notes: notes.text)),
                    child: Text(k.label),
                  ),
              ]),
            ]),
          ),
        if (tests.done.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(tr('Zakończone testy'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          for (final t in tests.done) Padding(padding: const EdgeInsets.only(bottom: 8), child: _done(t)),
        ],
      ]),
    );
  }
}
