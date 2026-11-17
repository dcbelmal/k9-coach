import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../files/file_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'gallery_store.dart';

/// Moduł „Galeria” – zdjęcia psa.
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  Future<void> _add(BuildContext context, ImageSource src) async {
    try {
      final picker = ImagePicker();
      final files = src == ImageSource.gallery
          ? await picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85)
          : [?await picker.pickImage(source: src, maxWidth: 1600, maxHeight: 1600, imageQuality: 85)];
      for (final f in files) {
        await GalleryStore.instance.add(await f.readAsBytes(), date: await f.lastModified());
      }
    } catch (_) {
      if (context.mounted) toast(context, 'Nie udało się dodać zdjęcia');
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = GalleryStore.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Galeria'),
        actions: [
          IconButton(
            tooltip: 'Zrób zdjęcie',
            onPressed: () => _add(context, ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, color: K9.orange),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: K9.orange,
        foregroundColor: Colors.black,
        onPressed: () => _add(context, ImageSource.gallery),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Dodaj zdjęcia', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: g,
        builder: (context, _) {
          if (g.photos.isEmpty) {
            return const EmptyState(
              icon: Icons.photo_library_rounded,
              title: 'Pusta galeria',
              text: 'Dodaj zdjęcia psa: szczeniak, starty, wystawy, wspólne wyprawy.',
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
            itemCount: g.photos.length,
            itemBuilder: (context, i) {
              final p = g.photos[i];
              return GestureDetector(
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => _PhotoScreen(photo: p))),
                child: ClipRRect(borderRadius: BorderRadius.circular(10), child: FileStore.image(p.ref)),
              );
            },
          );
        },
      ),
    );
  }
}

class _PhotoScreen extends StatefulWidget {
  final GalleryPhoto photo;
  const _PhotoScreen({required this.photo});
  @override
  State<_PhotoScreen> createState() => _PhotoScreenState();
}

class _PhotoScreenState extends State<_PhotoScreen> {
  late final caption = TextEditingController(text: widget.photo.caption);

  @override
  Widget build(BuildContext context) {
    final p = widget.photo;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(fmtDate(p.date)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: K9.red),
            onPressed: () async {
              if (await confirmDelete(context, 'to zdjęcie')) {
                await GalleryStore.instance.delete(p);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Column(children: [
        Expanded(child: InteractiveViewer(child: Center(child: FileStore.image(p.ref, fit: BoxFit.contain)))),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: caption,
              decoration: const InputDecoration(hintText: 'Podpis zdjęcia'),
              onSubmitted: (v) {
                p.caption = v.trim();
                GalleryStore.instance.update(p);
              },
              onTapOutside: (_) {
                FocusScope.of(context).unfocus();
                if (caption.text.trim() != p.caption) {
                  p.caption = caption.text.trim();
                  GalleryStore.instance.update(p);
                }
              },
            ),
          ),
        ),
      ]),
    );
  }
}
