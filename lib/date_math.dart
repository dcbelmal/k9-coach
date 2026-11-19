/// Arytmetyka dni kalendarzowych odporna na zmianę czasu (DST).
///
/// W Polsce doba zmiany czasu ma 23 lub 25 godzin. `add(Duration(days: n))`
/// dodaje n × 24 h, więc od północy potrafi trafić na 23:00 dnia poprzedniego,
/// a `difference(...).inDays` między północami potrafi zgubić dzień (np. marzec
/// liczył się jako 30 dni). Tu liczymy dni kalendarzowe.
library;

extension CalendarDays on Duration {
  /// Liczba dni z zaokrągleniem – między dwiema północami zawsze poprawna,
  /// także przez dobę 23- i 25-godzinną.
  int get inCalDays => (inMinutes / 1440).round();
}

extension DayMath on DateTime {
  /// Ta sama godzina zegarowa [n] dni kalendarzowych później (ujemne – wcześniej).
  DateTime plusDays(int n) => isUtc
      ? add(Duration(days: n))
      : DateTime(year, month, day + n, hour, minute, second, millisecond, microsecond);
}
