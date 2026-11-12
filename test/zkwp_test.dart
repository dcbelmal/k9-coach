import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/models_ext.dart';
import 'package:k9_coach/zkwp.dart';

const listHtml = '''
<html><body><div class="menu"><a href="wystawy.php?l=&rok=2026">2026</a> <a href="#">12 Kontakt</a></div>
<h4>Terminarz wystaw - 2027</h4>
<ul>
<li><b>Styczeń</b><br/>
09 <b>GDAŃSK (O/Gdynia)</b><br/>
klubowa buldogów angielskich<br/>
09 <b>GDAŃSK (O/Gdynia)</b><br/>
międzynarodowa - CACIB<br/>
<b>DUO CACIB</b><br/>
16-17 <b>GRODZISK MAZOWIECKI</b><br/>
międzynarodowa - CACIB<br/>
31-01 <b>Katowice</b><br/>krajowa<br/>
</li>
<li><b>Luty</b><br/>
13 <b>Bydgoszcz</b><br/>specjalistyczna - IV grupy FCI<br/>
06 <b>Bukowina Tatrzańska (O/Zakopane)</b><br/>krajowa polskich owczarków podhalańskich<br/>
20 <b>Moszczenica</b><br/>krajowa psów myśliwskich
</li>
</ul>
<div class="footer">Copyright © ZKwP</div>
</body></html>''';

const tableHtml = '''
<h3>Terminarz wystaw - 2027</h3><table>
<tr><td colspan=2><strong>Lipiec</strong></td></tr>
<tr><td>09</td><td><strong>Gorzów Wlkp.</strong><br>specjalistyczna - 9 Grupa FCI - TOY STAR</td></tr>
<tr><td>10</td><td><strong>Gorzów Wlkp.</strong><br>krajowa</td></tr>
</table>''';

const realHtml = r'''<div class="pro-info1">
                           <h4 class=f-22>Terminarz wystaw - 2027</h4>                             <ul class="list-unstyled mb-0 mr-0">
                 <table border=0 width=100%>
 <tr id=01><td height=20 < colspan=4></td></tr><tr id=Styczeń height=40><td style=background-color:#e9ecef align=center colspan=4><b><font class=f-18 color=#009846>Styczeń</font></b></td></tr><tr><td height=5 colspan=4></td></tr><tr><td valign=top width=60> 09 </td><td valign=top width=0><b>GDAŃSK (O/Gdynia)</b><br>klubowa buldogów angielskich</b></td><td valign=top align=right width=10>
                 </td></tr>
               </a><tr><td style="background-color:#e9ecef" colspan=4></td></tr>
               <tr><td height=5 colspan=4></td></tr>
     <tr><td valign=top width=60> 09 </td><td valign=top width=0><b>GDAŃSK (O/Gdynia)</b><br>międzynarodowa - CACIB<br><b class="text-danger f-12">DUO CACIB</b></td><td valign=top align=right width=10>
                 </td></tr>
               </a><tr><td style="background-color:#e9ecef" colspan=4></td></tr>
               <tr><td height=5 colspan=4></td></tr>
     <tr><td valign=top width=60> 16-17 </td><td valign=top width=0><b>GRODZISK MAZOWIECKI</b><br>międzynarodowa-CACIB</b></td><td valign=top align=right width=10>
                 </td></tr>
               </a><tr><td style="background-color:#e9ecef" colspan=4></td></tr>
     <tr id=02><td height=20 < colspan=4></td></tr><tr id=Luty height=40><td style=background-color:#e9ecef align=center colspan=4><b><font class=f-18 color=#009846>Luty</font></b></td></tr><tr><td height=5 colspan=4></td></tr><tr><td valign=top width=60> 06 </td><td valign=top width=0><b>Bukowina Tatrzańska (O/Zakopane)</b><br>krajowa polskich owczarków podhalańskich</b></td><td valign=top align=right width=10>
                 </td></tr>
     <tr><td valign=top width=60> 13 </td><td valign=top width=0><b>Bydgoszcz</b><br>specjalistyczna - IV grupy FCI</b></td><td valign=top align=right width=10>
                 </td></tr>
     <tr id=12><td height=20 < colspan=4></td></tr><tr id=Grudzień height=40><td style=background-color:#e9ecef align=center colspan=4><b><font class=f-18 color=#009846>Grudzień</font></b></td></tr><tr><td height=5 colspan=4></td></tr><tr><td valign=top width=60> 04 </td><td valign=top width=0><b>Goraj O/Bydgoszcz)</b><br>krajowa psów myśliwskich</b></td><td valign=top align=right width=10>
                 </td></tr>
     <tr><td valign=top width=60> 04 </td><td valign=top width=0><b>Świebodzice (O/Wałbrzych)</b><br>krajowa </b></td><td valign=top align=right width=10>
                 </td></tr>
     <tr><td valign=top width=60> 11-12 </td><td valign=top width=0><b>LUBLIN</b><br>międzynarodowa - CACIB</b></td><td valign=top align=right width=10>
                 </td></tr>
</table></ul></div>''';

void main() {
  test('prawdziwy fragment zkwp.pl', () {
    final r = parseZkwp(realHtml, 2027);
    for (final z in r) {
      // ignore: avoid_print
      print('${z.date} ${z.endDate} | ${z.place} | ${z.description} | ${z.type} | ${z.groupsLabel}');
    }
    expect(r.length, 8);
    expect(r[1].description, 'międzynarodowa - CACIB · DUO CACIB');
    expect(r[2].type, ShowType.international);
    expect(r[2].endDate, DateTime(2027, 1, 17));
    expect(r[3].groups, {1});
    expect(r[4].groups, {4});
    expect(r[6].groups, <int>{});
    expect(r[7].date, DateTime(2027, 12, 11));
  });

  test('lista', () {
    final r = parseZkwp(listHtml, 2027);
    for (final z in r) {
      // ignore: avoid_print
      print('${z.date} ${z.endDate} | ${z.place} | ${z.description} | ${z.type} | ${z.groupsLabel} | ${z.city}');
    }
    expect(r.length, 7);
    expect(r[1].description, contains('DUO CACIB'));
    expect(r[1].type, ShowType.international);
    expect(r[3].endDate, DateTime(2027, 2, 1));
    expect(r[4].groups, {4});
    expect(r[5].groups, {1});
    expect(r[0].matches(1), false);
    expect(r[1].matches(1), true);
  });
  test('tabela', () {
    final r = parseZkwp(tableHtml, 2027);
    for (final z in r) {
      // ignore: avoid_print
      print('${z.date} | ${z.place} | ${z.description} | ${z.groupsLabel}');
    }
    expect(r.length, 2);
    expect(r[0].groups, {9});
    expect(r[1].groups, <int>{});
  });
}
