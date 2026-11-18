import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/models_ext.dart';
import 'package:k9_coach/shows/countries.dart';
import 'package:k9_coach/shows/fci_shows.dart';

String row(int i, String city, String date) => '''
<tr style="height:25px;"><td>&nbsp;<span id="ContentPlaceHolder1_ExpoGridView_Expo2GridView_0_VilleLabel_$i">$city</span></td>
<td align="left"><span><span id="ContentPlaceHolder1_ExpoGridView_Expo2GridView_0_DateLabel_$i">$date</span></span></td></tr>''';

void main() {
  test('daty FCI: M/D/RRRR, zakresy i format europejski', () {
    expect(parseFciDates('5/8/2026'), (DateTime(2026, 5, 8), null));
    expect(parseFciDates('11/6/2026 - 11/7/2026 - 11/8/2026'), (DateTime(2026, 11, 6), DateTime(2026, 11, 8)));
    expect(parseFciDates('01/08/2025 - 03/08/2025'), (DateTime(2025, 8, 1), DateTime(2025, 8, 3)));
    expect(parseFciDates('8/30/2026'), (DateTime(2026, 8, 30), null));
    expect(parseFciDates('xx'), null);
  });

  test('strona FCI → lista wystaw CACIB bez duplikatów', () {
    final html = [
      row(0, 'Dortmund', '11/6/2026 - 11/7/2026 - 11/8/2026'),
      row(1, 'Dortmund', '11/6/2026 - 11/7/2026 - 11/8/2026'),
      row(2, 'Kassel', '1/10/2026'),
      row(3, 'Lingen', 'zła data'),
    ].join();
    final shows = parseFci(html, 'DE');
    expect(shows.length, 2);
    expect(shows.first.city, 'Kassel');
    expect(shows.first.country, 'DE');
    expect(shows.first.type, ShowType.international);
    expect(shows.first.matches(3), true);
    expect(shows.last.endDate, DateTime(2026, 11, 8));
  });

  test('sąsiedzi Polski i flagi', () {
    expect(countryNeighbours['PL'], containsAll(['DE', 'CZ', 'SK', 'UA', 'BY', 'LT', 'RU']));
    expect(countryByCode('DE').flag, '🇩🇪');
    // Każdy sąsiad jest na liście krajów.
    for (final e in countryNeighbours.entries) {
      for (final n in e.value) {
        expect(showCountries.any((c) => c.code == n), true, reason: '${e.key} → $n');
      }
    }
  });
}
