import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mugen_ai/validate.dart';

const goodPubspec = '''
name: todo_app
description: A todo app
version: 1.0.0+1
environment:
  sdk: ">=3.4.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.5.6
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
  uses-material-design: true
''';

const goodMain = '''
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/home.dart';
import 'src/util.dart';

void main() => runApp(const MaterialApp(home: Home()));
''';

Map<String, String> good() => {
      'pubspec.yaml': goodPubspec,
      'lib/main.dart': goodMain,
      'lib/home.dart': "import 'package:flutter/material.dart';\nclass Home extends StatelessWidget { const Home({super.key}); @override Widget build(BuildContext c) => const Scaffold(); }\n",
      'lib/src/util.dart': 'int one() => 1;\n',
    };

List<String> errors(Map<String, String> files, {String? pkg = 'todo_app'}) =>
    validateProject(files, expectedPackage: pkg).where((i) => i.isError).map((i) => i.toString()).toList();

void main() {
  group('pubspec reader', () {
    test('name, sdk, dependencies, dev dependencies', () {
      final ps = parsePubspec(goodPubspec);
      expect(ps.name, 'todo_app');
      expect(ps.sdkConstraint, '>=3.4.0 <4.0.0');
      expect(ps.hasFlutterSdk, true);
      expect(ps.deps.keys, ['flutter', 'shared_preferences']);
      expect(ps.deps['shared_preferences'], '^2.5.6');
      expect(ps.devDeps, {'flutter_test'});
    });

    test('assets, fonts, comments and quotes', () {
      final ps = parsePubspec('''
name: "quoted_name" # trailing comment
environment:
  sdk: '>=3.4.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  # a comment line
  http: ^1.6.0
  local_pkg:
    path: ../local_pkg
flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/data.json
  fonts:
    - family: Mono
      fonts:
        - asset: assets/fonts/Mono.ttf
''');
      expect(ps.name, 'quoted_name');
      expect(ps.sdkConstraint, '>=3.4.0 <4.0.0');
      expect(ps.deps['http'], '^1.6.0');
      expect(ps.deps['local_pkg'], '', reason: 'a path dependency has no version');
      expect(ps.assets, ['assets/images/', 'assets/data.json']);
      expect(ps.fontAssets, ['assets/fonts/Mono.ttf']);
    });

    test('a dependency written on two lines is still found', () {
      final ps = parsePubspec('name: a\ndependencies:\n  flutter:\n    sdk: flutter\n  intl:\n    ^0.20.0\n');
      expect(ps.deps.containsKey('intl'), true);
    });
  });

  group('validateProject', () {
    test('a correct project has no problems', () {
      expect(validateProject(good(), expectedPackage: 'todo_app'), isEmpty);
    });

    test('missing pubspec and main.dart', () {
      final e = errors({'lib/other.dart': 'void x() {}'});
      expect(e, containsAll([contains('pubspec.yaml: missing'), contains('lib/main.dart: missing')]));
    });

    test('pubspec name must equal the project name', () {
      final f = good()..['pubspec.yaml'] = goodPubspec.replaceFirst('todo_app', 'other_name');
      expect(errors(f), anyElement(contains('name is "other_name" but the project is called "todo_app"')));
    });

    test('an invalid package name is caught', () {
      final f = good()..['pubspec.yaml'] = goodPubspec.replaceFirst('todo_app', 'Todo-App');
      expect(errors(f, pkg: null), anyElement(contains('not a valid Dart package name')));
    });

    test('missing sdk constraint or flutter sdk dependency', () {
      final f = good()..['pubspec.yaml'] = 'name: todo_app\ndependencies:\n  shared_preferences: ^2.5.6\n';
      final e = errors(f);
      expect(e, anyElement(contains('environment: sdk:')));
      expect(e, anyElement(contains('"flutter:" with "sdk: flutter"')));
    });

    test('a package import needs a dependency', () {
      final f = good()..['lib/home.dart'] = "import 'package:intl/intl.dart';\nimport 'package:flutter/material.dart';\nclass Home {}\n";
      expect(errors(f), anyElement(allOf(contains('lib/home.dart'), contains('line 1'), contains('no dependency "intl"'))));
    });

    test('flutter_test and dev dependencies cannot be imported by app code', () {
      final f = good()..['lib/home.dart'] = "import 'package:flutter_test/flutter_test.dart';\nclass Home {}\n";
      expect(errors(f), anyElement(contains('only for tests')));
    });

    test('relative and own-package imports must point at files that exist', () {
      final f = good()..['lib/main.dart'] = "${goodMain}import 'missing.dart';\nimport '../lib/src/util.dart';\nimport 'package:todo_app/nope.dart';\n";
      final e = errors(f);
      expect(e, anyElement(contains("imports 'missing.dart' but that file is not in the project")));
      expect(e, anyElement(contains("lib/nope.dart is not in the project")));
      expect(e.where((x) => x.contains('util.dart')), isEmpty, reason: '../lib/src/util.dart resolves to an existing file');
    });

    test('dart: imports, export and part are understood', () {
      final f = good()
        ..['lib/main.dart'] = "import 'dart:async';\nexport 'home.dart';\npart 'src/util.dart';\nimport 'package:flutter/material.dart';\nvoid main() {}\n";
      expect(errors(f), isEmpty);
    });

    test('code generation and too-new plugins are blocked', () {
      final f = good()..['pubspec.yaml'] = goodPubspec.replaceFirst('shared_preferences: ^2.5.6', 'permission_handler: ^12.0.0\n  freezed_annotation: ^3.0.0');
      final e = errors(f);
      expect(e, anyElement(contains('permission_handler')));
      expect(e, anyElement(contains('freezed_annotation')));
    });

    test('native-setup plugins are a warning, not an error', () {
      final f = good()..['pubspec.yaml'] = goodPubspec.replaceFirst('shared_preferences: ^2.5.6', 'firebase_core: ^4.0.0');
      final issues = validateProject(f, expectedPackage: 'todo_app');
      expect(issues.where((i) => !i.isError), anyElement(predicate<Issue>((i) => i.message.contains('firebase_core'))));
      expect(issues.where((i) => i.isError && i.message.contains('firebase_core')), isEmpty);
    });

    test('assets and fonts named in the pubspec must exist', () {
      final f = good()
        ..['pubspec.yaml'] = '$goodPubspec  assets:\n    - assets/images/\n    - assets/data.json\n  fonts:\n    - family: X\n      fonts:\n        - asset: fonts/X.ttf\n';
      final e = errors(f);
      expect(e, anyElement(contains('asset "assets/images/"')));
      expect(e, anyElement(contains('asset "assets/data.json"')));
      expect(e, anyElement(contains('font file "fonts/X.ttf"')));
      f['assets/images/a.png'] = 'x';
      f['assets/data.json'] = '{}';
      f['fonts/X.ttf'] = 'x';
      expect(errors(f), isEmpty);
    });

    test('placeholders are errors, TODO is a warning', () {
      final f = good()..['lib/home.dart'] = "class Home {\n  // ... rest of the code\n}\n";
      expect(errors(f), anyElement(contains('placeholder text')));
      final g = good()..['lib/home.dart'] = "class Home {\n  // TODO: polish\n}\n";
      expect(errors(g), isEmpty);
      expect(validateProject(g, expectedPackage: 'todo_app').any((i) => !i.isError && i.message.contains('TODO')), true);
    });

    test('removed APIs are errors, deprecated ones are warnings', () {
      final f = good()..['lib/home.dart'] = "class Home { void a() { RaisedButton(); } }\n";
      expect(errors(f), anyElement(contains('RaisedButton')));
      final g = good()..['lib/home.dart'] = "class Home { void a() { c.withOpacity(0.5); WillPopScope(); } }\n";
      expect(errors(g), isEmpty);
      final w = validateProject(g, expectedPackage: 'todo_app').where((i) => !i.isError).map((i) => i.message).join('|');
      expect(w, allOf(contains('withOpacity'), contains('PopScope')));
    });

    test('unsafe paths and model-written workflows are reported', () {
      final f = good()
        ..['../evil.dart'] = 'void x() {}'
        ..['.github/workflows/x.yml'] = 'on: push'
        ..['android/app/build.gradle'] = 'x';
      final e = errors(f);
      expect(e, anyElement(contains('unsafe path')));
      expect(e, anyElement(contains('workflow files are written by the app')));
    });

    test('unbalanced brackets are found, with the line', () {
      final f = good()..['lib/home.dart'] = "class Home {\n  void a() {\n    print('x');\n  \n}\n";
      expect(errors(f), anyElement(allOf(contains('lib/home.dart'), contains('unbalanced'), contains('line 1'))));
    });

    test('an empty dart file is an error', () {
      final f = good()..['lib/src/util.dart'] = '   \n';
      expect(errors(f), anyElement(contains('the file is empty')));
    });
  });

  group('bracket lexer', () {
    test('strings, raw strings, triple quotes, interpolation and comments never confuse it', () {
      const ok = r'''
// a comment with ( unbalanced [ brackets {
/* block ( comment /* nested { */ still comment ] */
void main() {
  final a = 'a ) closing in string';
  final b = "b ] \" escaped quote ] ";
  final c = r'raw \\ ) { string';
  final d = """triple "quoted" ( string
  with { brackets over lines""";
  final e = 'value: ${map['k']} and ${call(")", {'x': [1, 2]})} end';
  final f = 'nested ${'inner ${deep('}')} text'} done';
  final g = '$simple and \$escaped { ${'}'}';
  print(a + b + c + d + e + f + g);
}
''';
      expect(firstBracketProblem(ok), isNull);
    });

    test('each kind of mistake is named', () {
      expect(firstBracketProblem('void a() {'), contains("'{' opened on line 1 is never closed"));
      expect(firstBracketProblem('void a() {}}'), contains("extra '}' on line 1"));
      expect(firstBracketProblem('void a() {\n  f(1, 2];\n}'), contains("'(' opened on line 2 is closed with ']'"));
      expect(firstBracketProblem("var s = 'open;\nvar t = 1;"), contains('not closed before the end of the line'));
      expect(firstBracketProblem('/* never closed'), contains('comment that starts on line 1 is never closed'));
      expect(firstBracketProblem(r"var s = 'a ${b';"), isNotNull);
    });

    test('every Dart file of this very app is balanced (the lexer agrees with real code)', () {
      final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();
      expect(files.length, greaterThan(15));
      for (final f in files) {
        expect(firstBracketProblem(f.readAsStringSync()), isNull, reason: f.path);
      }
    });
  });

  group('autoFix', () {
    test('renames the package in pubspec and imports', () {
      final f = good()..['pubspec.yaml'] = goodPubspec.replaceFirst('todo_app', 'wrong')..['lib/main.dart'] = goodMain.replaceAll('package:todo_app/', 'package:wrong/');
      final r = autoFix(f, expectedPackage: 'todo_app');
      expect(parsePubspec(r.files['pubspec.yaml']!).name, 'todo_app');
      expect(r.files['lib/main.dart'], contains('package:todo_app/home.dart'));
      expect(r.notes.single, contains('Renamed the package from "wrong" to "todo_app"'));
      expect(errors(r.files), isEmpty);
    });

    test('deprecated names are replaced, nested calls are left alone', () {
      final r = autoFix({
        'pubspec.yaml': goodPubspec,
        'lib/main.dart': 'void main() {\n  a.withOpacity(0.5);\n  b.withOpacity(f(1));\n  MaterialStateProperty.all(c); MaterialState.pressed;\n  ThemeData(cardTheme: const CardTheme(elevation: 1), dialogTheme: DialogTheme());\n}\n',
      }, expectedPackage: 'todo_app');
      final m = r.files['lib/main.dart']!;
      expect(m, contains('a.withValues(alpha: 0.5)'));
      expect(m, contains('b.withOpacity(f(1))'));
      expect(m, contains('WidgetStateProperty.all(c)'));
      expect(m, contains('WidgetState.pressed'));
      expect(m, contains('cardTheme: const CardThemeData('));
      expect(m, contains('dialogTheme: DialogThemeData('));
      expect(r.notes.length, 3);
    });

    test('generated and unsafe files are left out; nothing else changes', () {
      final f = good()..['.github/workflows/x.yml'] = 'x'..['android/a.gradle'] = 'x'..['../up.dart'] = 'x';
      final r = autoFix(f, expectedPackage: 'todo_app');
      expect(r.files.keys.toSet(), good().keys.toSet());
      expect(r.notes.single, contains('Left out 3'));
      expect(errors(r.files), isEmpty);
    });

    test('a clean project is returned unchanged with no notes, and fixing twice changes nothing', () {
      final r = autoFix(good(), expectedPackage: 'todo_app');
      expect(r.notes, isEmpty);
      expect(r.files, good());
      final bad = {'pubspec.yaml': goodPubspec, 'lib/main.dart': 'void main() { a.withOpacity(1); }\n'};
      final once = autoFix(bad, expectedPackage: 'todo_app');
      expect(autoFix(once.files, expectedPackage: 'todo_app').notes, isEmpty);
    });
  });

  group('pub.dev check', () {
    http.Client pubDev(Map<String, Object> packages, {bool down = false}) => MockClient((req) async {
          if (down) throw http.ClientException('offline');
          final name = req.url.pathSegments.last;
          final p = packages[name];
          if (p == null) return http.Response('{"error":{"code":"NotFound"}}', 404);
          return http.Response(jsonEncode(p), 200);
        });
    Map<String, Object> pkg(List<String> versions) => {
          'name': 'x',
          'latest': {'version': versions.last},
          'versions': [for (final v in versions) {'version': v}],
        };

    test('a package that does not exist is an error', () async {
      final ps = parsePubspec('name: a\ndependencies:\n  flutter:\n    sdk: flutter\n  made_up_pkg: ^1.0.0\n');
      final issues = await checkPackages(ps, clientFactory: () => pubDev({}));
      expect(issues.single.message, contains('package "made_up_pkg" does not exist on pub.dev'));
    });

    test('a version that does not exist is an error with the nearest real one, and a fix', () async {
      final ps = parsePubspec('name: a\ndependencies:\n  flutter:\n    sdk: flutter\n  http: ^1.9.9\n  intl: ^0.20.2\n');
      final fixes = <String, String>{};
      final issues = await checkPackages(ps, fixes: fixes, clientFactory: () => pubDev({
            'http': pkg(['0.13.6', '1.0.0', '1.2.0', '1.6.0', '2.0.0-beta']),
            'intl': pkg(['0.19.0', '0.20.2']),
          }));
      expect(issues.length, 1);
      expect(issues.single.message, allOf(contains('version 1.9.9 of "http"'), contains('latest: 1.6.0')));
      expect(fixes, {'http': '^1.6.0'});
      expect(applyVersionFixes('name: a\ndependencies:\n  flutter:\n    sdk: flutter\n  http: ^1.9.9\n  intl: ^0.20.2\n', fixes), contains('  http: ^1.6.0\n'));
      expect(applyVersionFixes('dependencies:\n  http: ^1.9.9\n  intl: ^0.20.2\n', fixes), contains('  intl: ^0.20.2\n'));
    });

    test('when pub.dev cannot be reached nothing is reported', () async {
      final ps = parsePubspec('name: a\ndependencies:\n  flutter:\n    sdk: flutter\n  http: ^1.6.0\n');
      expect(await checkPackages(ps, clientFactory: () => pubDev({}, down: true)), isEmpty);
    });

    test('the SDK, path and git dependencies are not looked up', () async {
      final ps = parsePubspec('name: a\ndependencies:\n  flutter:\n    sdk: flutter\n  local:\n    path: ../local\n');
      var calls = 0;
      final c = MockClient((req) async {
        calls++;
        return http.Response('{}', 404);
      });
      expect(await checkPackages(ps, clientFactory: () => c), isEmpty);
      expect(calls, 0);
    });
  });

  test('the fix prompt lists every error and asks for only the changed files', () {
    final p = validationFixPrompt([
      const Issue(Severity.error, 'lib/a.dart', 'unbalanced: x'),
      const Issue(Severity.warning, 'lib/b.dart', 'contains a TODO'),
      const Issue(Severity.error, 'pubspec.yaml', 'asset "x" is listed'),
    ]);
    expect(p, allOf(contains('lib/a.dart: unbalanced: x'), contains('pubspec.yaml: asset "x"'), contains('ONLY the files you changed')));
    expect(p.contains('TODO'), false, reason: 'warnings are not sent to the model');
  });
}
