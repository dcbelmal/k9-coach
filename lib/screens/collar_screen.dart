import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:universal_ble/universal_ble.dart';

import '../collar/collar_link.dart';
import '../collar/mesh_proto.dart';
import '../collar/tracker_driver.dart';
import '../dogs/dog_profiles.dart';
import '../l10n/l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'valkor_track_screen.dart';

void openCollar(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CollarScreen()));

/// „przed 25 s”, „przed 3 min” – wiek ostatniej pozycji.
String collarAge(DateTime? t, {DateTime? now}) {
  if (t == null) return tr('brak pozycji');
  final s = (now ?? DateTime.now()).difference(t).inSeconds;
  if (s < 60) return tr('{0} s temu', [s < 0 ? 0 : s]);
  if (s < 3600) return tr('{0} min temu', [s ~/ 60]);
  if (s < 172800) return tr('{0} godz. temu', [s ~/ 3600]);
  return tr('{0} dni temu', [s ~/ 86400]);
}

String collarBattery(int? b) => b == null ? '' : (b > 100 ? tr('zasilanie z kabla') : tr('bateria {0}%', [b]));

/// Krótki opis stanu obroży (do kart na innych ekranach).
String collarStatusText(CollarLink c) {
  switch (c.state) {
    case CollarState.off:
      return c.paired ? tr('Rozłączona – stuknij, aby połączyć') : tr('Nie połączono – stuknij, aby dodać');
    case CollarState.connecting:
      return tr('Łączę z {0}…', [c.deviceName ?? tr('obrożą')]);
    case CollarState.lost:
      return tr('Utracono połączenie – ponawiam…');
    case CollarState.connected:
      final f = c.dog?.fix;
      final parts = <String>[
        dogLinkText(c),
        if (f != null && c.status() != DogLink.live) tr('ostatnia znana pozycja {0}', [collarAge(f.fixAt)]),
        if (c.dog?.battery != null) collarBattery(c.dog!.battery),
      ];
      return '${tr('Połączona')} · ${parts.join(' · ')}';
  }
}

/// Opis łączności z psem: Bluetooth / LoRa / GPS / na żywo.
String dogLinkText(CollarLink c, {DateTime? now, String? dogId}) {
  final f = (dogId == null ? c.dog : c.nodeOf(dogId))?.fix;
  switch (c.status(now: now, dogId: dogId)) {
    case DogLink.none:
      return tr('brak trackera');
    case DogLink.bluetoothOff:
      return tr('Bluetooth rozłączony');
    case DogLink.connecting:
      return tr('łączę przez Bluetooth…');
    case DogLink.loraSilent:
      return tr('brak sygnału LoRa od psa');
    case DogLink.waitingGps:
      return tr('czekam na GPS psa');
    case DogLink.stale:
      return tr('brak świeżego GPS');
    case DogLink.live:
      final m = c.diag.medianInterval;
      return [
        tr('na żywo {0}', [collarAge(f?.fixAt, now: now)]),
        if (m != null) tr('pomiar co ~{0} s', [m.round()]),
      ].join(' · ');
  }
}

class CollarScreen extends StatefulWidget {
  const CollarScreen({super.key});
  @override
  State<CollarScreen> createState() => _CollarScreenState();
}

class _CollarScreenState extends State<CollarScreen> {
  final c = CollarLink.instance;
  final found = <String, BleDevice>{};
  StreamSubscription<BleDevice>? _scan;
  Timer? _scanStop;
  Timer? _clock;
  bool scanning = false;
  String? problem;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    c.load().then((_) {
      if (mounted) setState(() {});
    });
    // Odświeżanie „x s temu”.
    _clock = Timer.periodic(const Duration(seconds: 5), (_) => _changed());
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _clock?.cancel();
    _stopScan();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _startScan() async {
    final err = await c.prepare();
    if (!mounted) return;
    if (err != null) {
      setState(() => problem = err);
      return;
    }
    setState(() {
      problem = null;
      found.clear();
      scanning = true;
    });
    _scan = c.scan().listen((d) {
      if (mounted) setState(() => found[d.deviceId] = d);
    }, onError: (_) {
      if (mounted) setState(() => problem = tr('Nie udało się wyszukać urządzeń. Sprawdź, czy Bluetooth jest włączony.'));
      _stopScan();
    });
    _scanStop = Timer(const Duration(seconds: 15), _stopScan);
  }

  void _stopScan() {
    _scanStop?.cancel();
    _scan?.cancel();
    _scan = null;
    if (mounted && scanning) setState(() => scanning = false);
  }

  Future<void> _connect(BleDevice d) async {
    _stopScan();
    await c.connect(d.deviceId, name: d.name);
  }

  @override
  Widget build(BuildContext context) {
    final connected = c.connected;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Obroża GPS'))),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 32 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          _statusCard(),
          if (c.paired) ...[
            gap12,
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const ValkorTrackScreen())),
              icon: const Icon(Icons.map_rounded),
              label: Text(tr('Otwórz Valkor Track')),
            ),
          ],
          if (problem != null) ...[
            gap12,
            K9Card(
              color: K9.cardHi,
              child: Row(children: [
                const Icon(Icons.bluetooth_disabled_rounded, color: K9.yellow),
                const SizedBox(width: 10),
                Expanded(child: Text(problem!, style: const TextStyle(fontSize: 13))),
              ]),
            ),
          ],
          if (c.error != null && !connected) ...[
            gap12,
            K9Card(
              color: K9.cardHi,
              child: Row(children: [
                const Icon(Icons.error_outline_rounded, color: K9.yellow),
                const SizedBox(width: 10),
                Expanded(child: Text(c.error!, style: const TextStyle(fontSize: 13))),
              ]),
            ),
          ],
          if (connected && c.dogCoarse) ...[gap12, const CollarCoarseWarning()],
          if (connected) ...[gap16, _dogChoice()],
          if (!connected) ...[gap16, _scanSection()],
          gap16,
          _howTo(),
          if (c.paired) ...[gap16, _diagnostics()],
          gap16,
          _devices(),
        ],
      ),
    );
  }

  /// Obsługiwane urządzenia i ich prawdziwe możliwości.
  Widget _devices() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionTitle(tr('Obsługiwane urządzenia'), icon: Icons.devices_other_rounded),
        for (final m in TrackerModels.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: K9Card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(m.available ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    size: 18, color: m.available ? K9.green : K9.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (!m.available) Text(tr('w przygotowaniu'), style: const TextStyle(color: K9.muted, fontSize: 12)),
              ]),
              if (m.caps.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(m.caps.map((c) => c.label).join(' · '), style: const TextStyle(color: K9.muted, fontSize: 12)),
              ],
              if (m.note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(tr(m.note), style: const TextStyle(color: K9.faint, fontSize: 12)),
              ],
            ]),
          )),
      ]);

  /// Diagnostyka: liczniki pakietów, odrzuconych pomiarów i połączeń.
  Widget _diagnostics() {
    final d = c.diag;
    final m = d.medianInterval;
    String why(FixReject r) => switch (r) {
      FixReject.coarse => tr('zaokrąglona pozycja'),
      FixReject.stale => tr('nieaktualne'),
      FixReject.duplicate => tr('powtórzone'),
      FixReject.outOfOrder => tr('w złej kolejności'),
      FixReject.weak => tr('słaby sygnał GPS'),
      FixReject.jump => tr('niemożliwy skok'),
    };
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(color: K9.muted, fontSize: 12.5))),
            Text(v, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        );
    return K9Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(tr('Diagnostyka'), style: const TextStyle(fontWeight: FontWeight.w600)),
          children: [
            row(tr('Stan psa'), dogLinkText(c)),
            row(tr('Pakiety z urządzenia'), '${d.packets}'),
            row(tr('Pozycje odebrane'), '${d.positions}'),
            row(tr('Pozycje przyjęte'), '${d.accepted}'),
            for (final e in d.rejected.entries) row(tr('Odrzucone: {0}', [why(e.key)]), '${e.value}'),
            row(tr('Rzeczywisty odstęp pomiarów'), m == null ? '–' : tr('~{0} s', [m.round()])),
            row(tr('Ponowne połączenia'), '${d.reconnects}'),
            if (d.lastPacketAt != null) row(tr('Ostatni pakiet'), collarAge(d.lastPacketAt)),
            if (d.lastError != null) row(tr('Ostatni błąd'), d.lastError!),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    final connected = c.connected;
    final color = switch (c.state) {
      CollarState.connected => K9.green,
      CollarState.connecting || CollarState.lost => K9.yellow,
      CollarState.off => K9.muted,
    };
    final dog = c.dogWithFix;
    return K9Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            IconBadge(Icons.share_location_rounded, color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.deviceName ?? tr('SenseCAP T1000-E'), style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(collarStatusText(c), style: const TextStyle(color: K9.muted, fontSize: 12.5)),
              ]),
            ),
          ]),
          if (connected && dog != null) ...[
            const SizedBox(height: 10),
            Text(
              tr('Pies: {0}, {1}', [dog.fix!.lat.toStringAsFixed(5), dog.fix!.lng.toStringAsFixed(5)]),
              style: const TextStyle(color: K9.faint, fontSize: 12),
            ),
          ],
          if (connected) ...[
            const SizedBox(height: 6),
            Text(
              c.direct
                  ? tr('Telefon jest połączony bezpośrednio z obrożą na psie. Zasięg Bluetooth to zwykle 10–50 m.')
                  : tr('Telefon jest połączony z urządzeniem w Twojej kieszeni. Pozycje psa przychodzą radiem LoRa.'),
              style: const TextStyle(color: K9.muted, fontSize: 12.5),
            ),
          ],
          if (c.paired) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (c.state == CollarState.off)
                FilledButton(
                  onPressed: () async {
                    final err = await c.prepare();
                    if (!mounted) return;
                    if (err != null) return setState(() => problem = err);
                    await c.connect(c.deviceId!, name: c.deviceName);
                  },
                  child: Text(tr('Połącz')),
                ),
              if (c.state != CollarState.off)
                OutlinedButton(onPressed: () => c.disconnect(), child: Text(tr('Rozłącz'))),
              TextButton(
                onPressed: () => c.disconnect(forget: true),
                child: Text(tr('Zapomnij urządzenie'), style: const TextStyle(color: K9.red)),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _scanSection() {
    final list = found.values.toList()..sort((a, b) => (b.rssi ?? -200).compareTo(a.rssi ?? -200));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(tr('Urządzenia w pobliżu'), icon: Icons.bluetooth_searching_rounded),
        FilledButton.icon(
          onPressed: scanning ? null : _startScan,
          icon: scanning
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.search_rounded),
          label: Text(scanning ? tr('Szukam…') : tr('Szukaj obroży')),
        ),
        const SizedBox(height: 8),
        if (!scanning && found.isEmpty)
          Text(
            tr('Włącz obrożę i trzymaj ją blisko telefonu. Jeśli jest połączona z aplikacją Meshtastic, najpierw ją tam rozłącz – obroża obsługuje jeden telefon naraz.'),
            style: const TextStyle(color: K9.muted, fontSize: 12.5),
          ),
        for (final d in list)
          ListRow(
            icon: Icons.share_location_rounded,
            color: K9.orange,
            title: (d.name?.isNotEmpty ?? false) ? d.name! : d.deviceId,
            subtitle: d.rssi == null ? null : tr('sygnał {0} dBm', [d.rssi!]),
            onTap: () => _connect(d),
          ),
      ],
    );
  }

  Widget _dogChoice() {
    final others = c.otherNodes;
    final me = c.myNode == null ? null : c.nodes[c.myNode];
    Widget row(int num, String title, String sub) => RadioListTile<int>(
          contentPadding: EdgeInsets.zero,
          value: num,
          activeColor: K9.orange,
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sub, style: const TextStyle(color: K9.muted, fontSize: 12)),
        );
    final active = CollarLink.activeDog();
    String? owner(int num) {
      final id = c.dogFor(num);
      if (id == null || id == active) return null;
      return tr('przypisany: {0}', [DogProfiles.instance.peek(id)?.name ?? id]);
    }

    String sub(CollarNode n) => [
          ?owner(n.num),
          collarAge(n.fix?.fixAt ?? n.lastHeard),
          if (n.battery != null) collarBattery(n.battery),
          if (n.isT1000E) 'T1000-E',
        ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          DogProfiles.instance.peek(active)?.name.isNotEmpty == true
              ? tr('Który tracker nosi {0}?', [DogProfiles.instance.peek(active)!.name])
              : tr('Które urządzenie jest na psie?'),
          icon: Icons.pets_rounded,
        ),
        K9Card(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: RadioGroup<int>(
            groupValue: c.dogNode,
            onChanged: (v) => c.chooseDog(v),
            child: Column(children: [
            if (c.myNode != null)
              row(c.myNode!, tr('To połączone z telefonem ({0})', [me?.name ?? meshNodeId(c.myNode!)]),
                  me == null ? (owner(c.myNode!) ?? tr('jedna obroża, zasięg Bluetooth')) : sub(me)),
            for (final n in others) row(n.num, n.name, sub(n)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            tr('Wybór zapisuje się w profilu tego psa. Przełącz psa w aplikacji, żeby przypisać mu inny tracker. Trening zawsze nagrywa tracker wybrany na starcie.'),
            style: const TextStyle(color: K9.faint, fontSize: 12),
          ),
        ),
        if (others.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              tr('Nie widzę innych urządzeń Meshtastic. Jeśli masz drugie urządzenie na psie, sprawdź, czy oba mają ten sam region (EU_868) i kanał.'),
              style: const TextStyle(color: K9.muted, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  Widget _howTo() {
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 22, child: Text(n, style: const TextStyle(color: K9.orange, fontWeight: FontWeight.w800))),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ]),
        );
    return K9Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Jak przygotować obrożę'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          step('1', tr('Obroża musi mieć oprogramowanie Meshtastic. Sprawdzisz to w aplikacji Meshtastic: jeśli ją widzi, wszystko gra.')),
          step('2', tr('W Meshtastic ustaw region EU_868, nazwę (np. „Pies”) i zostaw rolę „Klient”.')),
          step('3', tr('Pozycja: interwał wysyłania 30 s, inteligentna pozycja wyłączona, GPS włączony.')),
          step('4', tr('Rozłącz obrożę w aplikacji Meshtastic, potem połącz ją tutaj. PIN przy parowaniu: 123456.')),
          step('5', tr('Z drugim urządzeniem w kieszeni połącz telefon z nim, a obrożę na psie wybierz z listy powyżej.')),
        ],
      ),
    );
  }
}

/// Ostrzeżenie: kanał Meshtastic zaokrągla pozycję psa (domyślny kanał publiczny).
class CollarCoarseWarning extends StatelessWidget {
  const CollarCoarseWarning({super.key});

  @override
  Widget build(BuildContext context) => K9Card(
        color: K9.cardHi,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.blur_on_rounded, color: K9.yellow),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Tracker wysyła zaokrągloną pozycję (nawet o ok. 1,5 km), więc trasa psa będzie błędna. W Meshtastic: Ustawienia → Kanały → kanał główny: zmień nazwę, wygeneruj nowy klucz i włącz dokładną lokalizację.'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ]),
      );
}
