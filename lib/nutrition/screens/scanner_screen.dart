import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme.dart';
import '../../widgets/common.dart';
import '../../l10n/l10n.dart';

/// Skaner kodów EAN / QR. Zwraca odczytany tekst kodu.
Future<String?> scanCode(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerScreen()));

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.qrCode,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool done = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture c) {
    if (done) return;
    for (final b in c.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        done = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  Future<void> _manual() async {
    final ctl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Wpisz kod z opakowania')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: tr('Kod EAN (cyfry pod kreskami)')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Anuluj'))),
          TextButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: Text(tr('OK'))),
        ],
      ),
    );
    if (v != null && v.isNotEmpty && mounted) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(tr('Skanuj kod')),
        actions: [
          IconButton(
            tooltip: tr('Latarka'),
            onPressed: () => controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => EmptyState(
            icon: Icons.no_photography_rounded,
            title: tr('Brak dostępu do aparatu'),
            text: tr('Zezwól aplikacji na użycie aparatu w ustawieniach telefonu albo wpisz kod ręcznie.'),
            action: tr('Wpisz kod'),
            onAction: _manual,
          ),
        ),
        Center(
          child: Container(
            width: 280,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: K9.orange, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          bottom: 24 + MediaQuery.viewPaddingOf(context).bottom,
          child: Column(children: [
            Text(tr('Nakieruj aparat na kod kreskowy lub QR na opakowaniu'),
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _manual,
              icon: const Icon(Icons.keyboard_rounded),
              label: Text(tr('Wpisz kod ręcznie')),
            ),
          ]),
        ),
      ]),
    );
  }
}
