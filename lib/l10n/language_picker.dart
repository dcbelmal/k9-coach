import 'package:material_ui/material_ui.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'l10n.dart';

/// Wiersz ustawień „Język”. Podpis po angielsku pomaga znaleźć go,
/// gdy aplikacja jest w nieznanym języku.
class LanguageRow extends StatelessWidget {
  const LanguageRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.instance;
    final title = tr('Język');
    return ListRow(
      icon: Icons.translate_rounded,
      color: K9.orange,
      title: l.code == 'en' ? title : '$title · Language',
      subtitle: l.chosen == null ? '${tr('Jak w telefonie')} · ${l.language.name}' : l.language.name,
      onTap: () => openLanguagePicker(context),
    );
  }
}

Future<void> openLanguagePicker(BuildContext context) async {
  final l = L10n.instance;
  final picked = await showFormSheet<String>(
    context,
    Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(tr('Język')),
        _option(context, tr('Jak w telefonie'), l.chosen == null, ''),
        const Divider(height: 8),
        for (final a in appLanguages) _option(context, a.name, l.chosen == a.code, a.code),
      ],
    ),
  );
  if (picked == null) return;
  await l.set(picked.isEmpty ? null : picked);
}

Widget _option(BuildContext context, String name, bool selected, String value) => ListTile(
  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
  title: Text(name, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
  trailing: selected ? const Icon(Icons.check_rounded, color: K9.orange) : null,
  onTap: () => Navigator.pop(context, value),
);
