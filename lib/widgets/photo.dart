import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../files/file_store.dart';
import '../theme.dart';
import 'common.dart';

/// Pyta: aparat czy galeria, zapisuje zdjęcie i zwraca jego identyfikator.
Future<String?> pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(c).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListRow(
            icon: Icons.photo_camera_rounded,
            color: K9.orange,
            title: 'Zrób zdjęcie',
            onTap: () => Navigator.pop(c, ImageSource.camera)),
        ListRow(
            icon: Icons.photo_library_rounded,
            color: K9.blue,
            title: 'Wybierz z galerii',
            onTap: () => Navigator.pop(c, ImageSource.gallery)),
      ]),
    ),
  );
  if (source == null) return null;
  try {
    final img = await ImagePicker().pickImage(source: source, maxWidth: 2000, maxHeight: 2000, imageQuality: 80);
    if (img == null) return null;
    return await FileStore.save(await img.readAsBytes());
  } catch (_) {
    if (context.mounted) toast(context, 'Nie udało się dodać zdjęcia');
    return null;
  }
}

void openPhotoViewer(BuildContext context, List<String> refs, int index) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, _, _) => _Viewer(refs: refs, index: index),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _Viewer extends StatelessWidget {
  final List<String> refs;
  final int index;
  const _Viewer({required this.refs, required this.index});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: PageView(
        controller: PageController(initialPage: index),
        children: [
          for (final r in refs)
            InteractiveViewer(maxScale: 6, child: Center(child: FileStore.image(r, fit: BoxFit.contain))),
        ],
      ),
    );
  }
}
