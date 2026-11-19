import 'package:flutter_test/flutter_test.dart';
import 'package:mugen_ai/parser.dart';

void main() {
  test('plain chat has no project', () {
    final p = parseMessage('Hello **world**');
    expect(p.project, isNull);
    expect(p.before, 'Hello **world**');
  });

  test('streaming project block is parsed incrementally', () {
    const raw = 'Bana raha hoon\n<mugen-project name="todo" title="Todo App">\n<file path="pubspec.yaml">\nname: todo\n</file>\n<file path="lib/main.dart">\nvoid main(){';
    final p = parseMessage(raw);
    expect(p.project, isNotNull);
    expect(p.project!.complete, isFalse);
    expect(p.project!.files.keys, ['pubspec.yaml', 'lib/main.dart']);
    expect(p.project!.openFile, 'lib/main.dart');
    expect(p.before.trim(), 'Bana raha hoon');
  });

  test('complete block with fences and trailing text', () {
    const raw = 'x\n<mugen-project name="a" title="A">\n<file path="lib/main.dart">\n```dart\nvoid main() {}\n```\n</file>\n</mugen-project>\nDone';
    final p = parseMessage(raw);
    expect(p.project!.complete, isTrue);
    expect(p.project!.files['lib/main.dart'], 'void main() {}\n');
    expect(p.after.trim(), 'Done');
  });

  test('half typed tag is hidden', () {
    expect(parseMessage('ok <mugen-proj').before, 'ok ');
  });

  test('names', () {
    expect(sanitizeRepoName('My Cool App!'), 'my-cool-app');
    expect(dartPackageName('3d-game'), 'app_3d_game');
  });
}
