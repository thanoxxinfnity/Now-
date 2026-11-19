// Prints the shell scaffold + workflow used for generated apps (used by CI to
// verify the template really builds an APK).
import 'dart:io';
import '../lib/github.dart';

void main(List<String> a) {
  if (a.first == 'scaffold') {
    stdout.writeln(scaffoldScript(a[1], a[2]));
  } else {
    stdout.writeln(apkWorkflow(a[1], a[2]));
  }
}
