import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'dog_profiles.dart';

/// Arkusz z listą psów: przełączanie i dodawanie kolejnego psa.
Future<void> showDogSwitcher(BuildContext context) async {
  final p = DogProfiles.instance;
  final picked = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (c) {
      final dogs = p.dogs;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text(tr('Moje psy'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('Każdy pies ma osobne treningi, zdrowie, żywienie i moduły.'),
                style: const TextStyle(color: K9.muted, fontSize: 13)),
            const SizedBox(height: 6),
            Text(tr(oneOwnerNotice), style: const TextStyle(color: K9.faint, fontSize: 12)),
            gap12,
            for (final (id, dog) in dogs) ...[
              _DogTile(dog: dog, active: id == p.activeId, onTap: () => Navigator.pop(c, id)),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: K9.orange,
                side: const BorderSide(color: K9.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.pop(c, '+'),
              icon: const Icon(Icons.add_rounded),
              label: Text(tr('Dodaj kolejnego psa')),
            ),
          ]),
        ),
      );
    },
  );
  if (picked == null) return;
  if (picked == '+') {
    await p.startAdding();
  } else {
    await p.switchTo(picked);
  }
}

class _DogTile extends StatelessWidget {
  final Dog dog;
  final bool active;
  final VoidCallback onTap;
  const _DogTile({required this.dog, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? K9.orange.withValues(alpha: 0.12) : K9.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: active ? K9.orange : K9.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            DogAvatar(dog: dog, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(dog.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  const SizedBox(width: 4),
                  Icon(dog.female ? Icons.female_rounded : Icons.male_rounded, color: K9.orange, size: 18),
                ]),
                Text([dog.breed, dog.ageLabel].where((e) => e.isNotEmpty).join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: K9.muted, fontSize: 13)),
              ]),
            ),
            if (active) const Icon(Icons.check_circle_rounded, color: K9.orange),
          ]),
        ),
      ),
    );
  }
}

/// Okrągłe zdjęcie psa.
class DogAvatar extends StatelessWidget {
  final Dog? dog;
  final double size;
  const DogAvatar({super.key, required this.dog, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = dog?.photoBase64?.isNotEmpty ?? false;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: hasPhoto
            ? DogPhoto(dog: dog)
            : ColoredBox(
                color: K9.cardHi,
                child: Icon(Icons.pets_rounded, color: K9.orange, size: size * 0.5),
              ),
      ),
    );
  }
}

/// Przycisk z avatarem w nagłówku – otwiera listę psów.
class DogSwitchButton extends StatelessWidget {
  final Dog dog;
  const DogSwitchButton({super.key, required this.dog});

  @override
  Widget build(BuildContext context) {
    final count = DogProfiles.instance.ids.length;
    return Material(
      color: Colors.black45,
      shape: const StadiumBorder(side: BorderSide(color: Color(0x33FFFFFF))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDogSwitcher(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            DogAvatar(dog: dog, size: 28),
            const SizedBox(width: 6),
            Text(count > 1 ? tr('Psy ({0})', [count]) : tr('Psy'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const Icon(Icons.unfold_more_rounded, size: 18),
          ]),
        ),
      ),
    );
  }
}

/// Model dostępu w tej wersji (wyświetlany przy liście psów i w ustawieniach).
const oneOwnerNotice =
    'Wersja testowa: jeden opiekun na jednym koncie użytkownika telefonu, z dowolną liczbą psów. Każdy, kto może otworzyć aplikację na tym telefonie, widzi i może zmieniać wszystkie psy. Dane są tylko w tym telefonie, bez konta i bez chmury.';
