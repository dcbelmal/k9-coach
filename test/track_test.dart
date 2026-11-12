import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:k9_coach/gps/demo_track.dart';
import 'package:k9_coach/gps/track.dart';

void main() {
  test('kilometry i zapis trasy', () {
    final t = demoTrack(5.3, 270, Random(1));
    expect(t.meters, closeTo(5300, 400));
    final s = t.splits();
    expect(s.where((e) => e.meters >= 1000).length, t.meters ~/ 1000);
    expect(s.first.paceSecPerKm, inInclusiveRange(200, 340));
    final back = Track.decode(t.encode());
    expect(back.points.length, t.points.length);
    expect(back.meters, closeTo(t.meters, 5));
    expect(fmtPace(272), '4:32');
    expect(fmtClock(3725), '1:02:05');
  });
}
