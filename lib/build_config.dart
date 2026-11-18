/// Wariant kompilacji, ustawiany przy budowie:
///   flutter build apk --release --dart-define=VALKOR_FLAVOR=beta
///
/// * `prod` (domyślny) – wersja produkcyjna: bez przełącznika testowego Premium,
///   niezależnie od tego, czy Sklep Google Play jest dostępny.
/// * `beta` – zamknięta beta: Premium można włączyć testowo (za darmo),
///   prawdziwa sprzedaż jest wyłączona.
const appFlavor = String.fromEnvironment('VALKOR_FLAVOR', defaultValue: 'prod');
const isBetaBuild = appFlavor == 'beta';

/// Sprzedaż Premium przez Google Play. Domyślnie WYŁĄCZONA: zanim zostanie
/// włączona (--dart-define=VALKOR_SALES=true), potrzebna jest weryfikacja
/// zakupów po stronie serwera (Google Play Developer API), której projekt
/// jeszcze nie ma. W wersji beta sprzedaż jest zawsze wyłączona.
const salesEnabled = !isBetaBuild && bool.fromEnvironment('VALKOR_SALES', defaultValue: false);
