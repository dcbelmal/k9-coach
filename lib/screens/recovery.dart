import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../dogs/dog_profiles.dart';
import '../l10n/l10n.dart';
import '../storage/safe_prefs.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Karta na ekranie Start, gdy części danych nie udało się odczytać.
class DataIssuesCard extends StatelessWidget {
  const DataIssuesCard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: DataHealth.instance,
        builder: (context, _) {
          final list = DataHealth.instance.forSuffix(DogProfiles.instance.suffix);
          if (list.isEmpty) return const SizedBox.shrink();
          final n = list.fold(0, (a, i) => a + i.unreadable);
          final locked = list.any((i) => i.locked);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: K9Card(
              color: K9.cardHi,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecoveryScreen())),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: K9.yellow),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    locked
                        ? tr('Części danych nie udało się odczytać. Oryginał jest zachowany, zapis w tym miejscu jest wstrzymany. Stuknij, aby odzyskać.')
                        : tr('Nie udało się odczytać {0} wpisów. Są zachowane bez zmian. Stuknij, aby zobaczyć szczegóły.', [n]),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: K9.muted),
              ]),
            ),
          );
        },
      );
}

/// Odzyskiwanie danych, których nie udało się odczytać.
///
/// Nic nie jest kasowane bez wyraźnej decyzji: oryginalne bajty są zawsze
/// zachowane w osobnej kopii w pamięci aplikacji.
class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key, this.standalone = false});

  /// true = ekran zamiast aplikacji (profil psa zablokowany).
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([DataHealth.instance, AppStore.instance, DogProfiles.instance]),
      builder: (context, _) {
        final issues = DataHealth.instance.forSuffix(DogProfiles.instance.suffix);
        final others = [for (final d in DogProfiles.instance.dogs) if (d.$1 != DogProfiles.instance.activeId) d];
        return Scaffold(
          appBar: AppBar(title: Text(tr('Odzyskiwanie danych')), automaticallyImplyLeading: !standalone),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              Text(
                tr('Aplikacja nie potrafiła odczytać części zapisanych danych. Nic nie zostało usunięte: oryginał jest zachowany w osobnej kopii, a miejsca z błędem nie są nadpisywane.'),
                style: const TextStyle(color: K9.muted, fontSize: 13.5),
              ),
              gap16,
              if (issues.isEmpty)
                K9Card(child: Text(tr('Wszystkie dane tego psa są czytelne.'))),
              for (final i in issues) ...[_IssueCard(issue: i), gap12],
              if (others.isNotEmpty) ...[
                SectionTitle(tr('Inne psy')),
                for (final d in others)
                  K9Card(
                    onTap: () => DogProfiles.instance.switchTo(d.$1),
                    child: Row(children: [
                      const Icon(Icons.pets_rounded, color: K9.orange),
                      const SizedBox(width: 12),
                      Expanded(child: Text(tr('Przełącz na: {0}', [d.$2.name]))),
                    ]),
                  ),
              ],
              gap16,
              Text(
                tr('Jeśli błąd pojawił się po aktualizacji, kolejna wersja aplikacji może odczytać te dane – do tego czasu nic nie wybieraj albo skopiuj dane i wyślij je twórcy aplikacji.'),
                style: const TextStyle(color: K9.faint, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.issue});
  final StoreIssue issue;

  bool get _main => issue.key == AppStore.keyForDog(DogProfiles.instance.activeId);

  Future<void> _copy(BuildContext context) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(issue.key) ?? (issue.backupKey == null ? null : p.getString(issue.backupKey!));
    if (raw == null) return;
    await Clipboard.setData(ClipboardData(text: raw));
    if (context.mounted) toast(context, tr('Skopiowano oryginalne dane do schowka'));
  }

  Future<void> _salvage(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Odzyskać poprawne wpisy?')),
        content: Text(_main
            ? tr('Aplikacja zapisze wszystko, co da się odczytać. Wpisy nieczytelne zostaną zachowane bez zmian, a oryginał całości zostaje w kopii.')
            : tr('Ten moduł zacznie od pustego stanu. Oryginał zostaje w kopii i można go skopiować w każdej chwili.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Anuluj'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Odzyskaj'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await saveGuarded(context, () async {
      if (_main) {
        if (!await AppStore.instance.salvage()) {
          throw StorageWriteException(issue.key);
        }
      } else {
        final p = await SharedPreferences.getInstance();
        final raw = p.getString(issue.key);
        if (raw != null && await SafePrefs.preserve(p, issue.key, raw) == null) throw StorageWriteException(issue.key);
        await SafePrefs.remove(p, issue.key);
        DataHealth.instance.clear(issue.key);
      }
      await DogProfiles.instance.reloadAll();
    });
  }

  @override
  Widget build(BuildContext context) => K9Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr(issue.store), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            issue.locked
                ? tr('Nie udało się odczytać zapisu. Zapis w tym miejscu jest wstrzymany, żeby nie nadpisać danych.')
                : tr('{0} wpisów nie udało się odczytać. Są zachowane i wracają do zapisu bez zmian.', [issue.unreadable]),
            style: const TextStyle(color: K9.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            OutlinedButton(onPressed: () => _copy(context), child: Text(tr('Skopiuj oryginał'))),
            if (issue.locked) FilledButton(onPressed: () => _salvage(context), child: Text(tr('Odzyskaj poprawne wpisy'))),
          ]),
        ]),
      );
}
