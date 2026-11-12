import 'package:material_ui/material_ui.dart';

import '../files/file_store.dart';
import '../models.dart';
import '../models_ext.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/photo.dart';

final _s = AppStore.instance;

Color _expiryColor(DateTime e) {
  final d = dayOnly(e).difference(dayOnly(DateTime.now())).inDays;
  if (d < 0) return K9.red;
  if (d <= 30) return K9.yellow;
  return K9.green;
}

class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Row(children: [
        Icon(Icons.description_outlined, color: K9.orange),
        SizedBox(width: 10),
        Text('Dokumenty'),
      ])),
      floatingActionButton: FloatingActionButton(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => openDocumentForm(context),
        child: const Icon(Icons.add_rounded, size: 30),
      ),
      body: ListenableBuilder(
        listenable: _s,
        builder: (context, _) {
          if (_s.documents.isEmpty) {
            return EmptyState(
              icon: Icons.folder_copy_rounded,
              title: 'Brak dokumentów',
              text: 'Zrób zdjęcia rodowodu, paszportu czy wyników badań. Będą zawsze pod ręką, także bez internetu.',
              action: 'Dodaj dokument',
              onAction: () => openDocumentForm(context),
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
            for (final (i, d) in _s.documents.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FadeSlideIn(
                  index: i,
                  child: K9Card(
                    padding: const EdgeInsets.all(12),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => DocumentScreen(id: d.id))),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: d.images.isEmpty
                              ? Container(
                                  color: K9.red.withValues(alpha: 0.14),
                                  child: Icon(d.type.icon, color: K9.red, size: 26))
                              : FileStore.image(d.images.first),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                              [d.type.label, if (d.number.isNotEmpty) d.number, if (d.images.isNotEmpty) '${d.images.length} zdj.']
                                  .join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: K9.muted, fontSize: 12.5)),
                          if (d.expires != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text('Ważny do ${fmtDate(d.expires!)}',
                                  style: TextStyle(
                                      color: _expiryColor(d.expires!), fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: K9.faint),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class DocumentScreen extends StatelessWidget {
  final String id;
  const DocumentScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final d = _s.documents.where((e) => e.id == id).firstOrNull;
        if (d == null) return const Scaffold();
        final rows = <(String, String)>[
          ('Rodzaj', d.type.label),
          if (d.number.isNotEmpty) ('Numer', d.number),
          if (d.issued != null) ('Data wydania', fmtDate(d.issued!)),
          if (d.expires != null) ('Ważny do', '${fmtDate(d.expires!)} (${relDays(d.expires!)})'),
        ];
        return Scaffold(
          appBar: AppBar(title: Text(d.title), actions: [
            IconButton(
                onPressed: () => openDocumentForm(context, existing: d),
                icon: const Icon(Icons.edit_outlined, color: K9.orange)),
          ]),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
            if (d.images.isNotEmpty)
              SizedBox(
                height: 300,
                child: PageView(
                  controller: PageController(viewportFraction: 0.88),
                  padEnds: false,
                  children: [
                    for (final (i, r) in d.images.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () => openPhotoViewer(context, d.images, i),
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(K9.radius), child: FileStore.image(r)),
                        ),
                      ),
                  ],
                ),
              ),
            gap12,
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: K9.orange,
                side: const BorderSide(color: K9.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                final r = await pickPhoto(context);
                if (r == null) return;
                d.images.add(r);
                await _s.upsertDocument(d);
              },
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(d.images.isEmpty ? 'Dodaj zdjęcie dokumentu' : 'Dodaj kolejną stronę'),
            ),
            gap12,
            K9Card(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                for (final (i, r) in rows.indexed) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    child: Row(children: [
                      Expanded(child: Text(r.$1, style: const TextStyle(color: Color(0xFFCFCFD4)))),
                      Flexible(child: Text(r.$2, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ]),
                  ),
                  if (i < rows.length - 1) const Divider(height: 1, color: K9.border),
                ],
              ]),
            ),
            if (d.notes.isNotEmpty) ...[
              gap12,
              K9Card(child: Text(d.notes, style: const TextStyle(color: Color(0xFFCFCFD4)))),
            ],
            if (d.images.isNotEmpty) ...[
              gap16,
              const Text('Stuknij zdjęcie, aby je powiększyć.', textAlign: TextAlign.center, style: TextStyle(color: K9.faint, fontSize: 12)),
            ],
          ]),
        );
      },
    );
  }
}

Future<void> openDocumentForm(BuildContext context, {DogDocument? existing}) =>
    showFormSheet(context, _DocForm(existing: existing));

class _DocForm extends StatefulWidget {
  final DogDocument? existing;
  const _DocForm({this.existing});
  @override
  State<_DocForm> createState() => _DocFormState();
}

class _DocFormState extends State<_DocForm> {
  late final d = widget.existing == null
      ? DogDocument(id: newId(), type: DocType.pedigree, title: '')
      : DogDocument.fromJson(widget.existing!.toJson());
  late final title = TextEditingController(text: d.title.isEmpty ? d.type.label : d.title);
  late final number = TextEditingController(text: d.number);
  late final notes = TextEditingController(text: d.notes);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetTitle(widget.existing == null ? 'Nowy dokument' : 'Edytuj dokument',
          onDelete: widget.existing == null
              ? null
              : () async {
                  if (await confirmDelete(context, 'dokument i jego zdjęcia')) {
                    await _s.deleteDocument(widget.existing!);
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in DocType.values)
          ChoiceChip(
            label: Text(t.label),
            avatar: Icon(t.icon, size: 18, color: t == d.type ? Colors.black : K9.orange),
            selected: t == d.type,
            showCheckmark: false,
            selectedColor: K9.orange,
            backgroundColor: K9.cardHi,
            side: BorderSide.none,
            labelStyle: TextStyle(color: t == d.type ? Colors.black : K9.text, fontWeight: FontWeight.w600, fontSize: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (_) => setState(() {
              if (title.text.isEmpty || DocType.values.any((x) => x.label == title.text)) title.text = t.label;
              d.type = t;
            }),
          ),
      ]),
      gap16,
      TextField(controller: title, decoration: const InputDecoration(labelText: 'Nazwa *')),
      gap12,
      TextField(controller: number, decoration: const InputDecoration(labelText: 'Numer dokumentu')),
      gap12,
      Row(children: [
        Expanded(
            child: DateField(
                label: 'Data wydania', value: d.issued, clearable: true, onChanged: (v) => setState(() => d.issued = v))),
        const SizedBox(width: 12),
        Expanded(
            child: DateField(
                label: 'Ważny do', value: d.expires, clearable: true, onChanged: (v) => setState(() => d.expires = v))),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Przypomnij przed wygaśnięciem'),
        subtitle: const Text('30 dni wcześniej i w dniu wygaśnięcia', style: TextStyle(color: K9.muted, fontSize: 12.5)),
        value: d.remind,
        onChanged: d.expires == null ? null : (v) => setState(() => d.remind = v),
      ),
      TextField(controller: notes, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Notatki')),
      if (widget.existing == null) ...[
        gap12,
        Row(children: [
          for (final r in d.images)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(width: 56, height: 56, child: FileStore.image(r))),
            ),
          TextButton.icon(
            onPressed: () async {
              final r = await pickPhoto(context);
              if (r != null) setState(() => d.images.add(r));
            },
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Dodaj zdjęcie'),
          ),
        ]),
      ],
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          if (title.text.trim().isEmpty) {
            toast(context, 'Wpisz nazwę dokumentu');
            return;
          }
          d
            ..title = title.text.trim()
            ..number = number.text.trim()
            ..notes = notes.text.trim();
          await _s.upsertDocument(d);
          if (context.mounted) Navigator.pop(context);
        },
        child: const Text('Zapisz'),
      ),
    ]);
  }
}
