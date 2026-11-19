import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:mugen_ai/ui/techniques.dart';

void main() {
  test('every technique paints at every moment without throwing', () {
    for (final tech in Technique.values) {
      for (var i = 0; i <= 20; i++) {
        final rec = PictureRecorder();
        final canvas = Canvas(rec);
        TechniquePainter(tech, i / 20).paint(canvas, const Size(360, 260));
        rec.endRecording();
      }
    }
  });
}
