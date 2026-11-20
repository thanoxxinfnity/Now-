import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mugen_ai/engine.dart';
import 'package:mugen_ai/models.dart';
import 'package:mugen_ai/store.dart';

const pubspec = '''
name: todo_app
description: Todo
environment:
  sdk: ">=3.4.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.5.6
flutter:
  uses-material-design: true
''';

const goodMain = "import 'package:flutter/material.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\nvoid main() => runApp(const MaterialApp());\n";
const badMain = "import 'package:flutter/material.dart';\nimport 'package:intl/intl.dart';\nvoid main() => runApp(const MaterialApp());\n";

String reply(Map<String, String> files) =>
    'Fixed it.\n<mugen-project name="todo_app" title="Todo">\n${files.entries.map((e) => '<file path="${e.key}">\n${e.value}</file>\n').join()}</mugen-project>\nDone.';

/// One fake world: the model, pub.dev and GitHub, all answered from memory.
class World {
  final List<String> modelReplies;
  final List<Map<String, dynamic>> modelRequests = [];
  final List<Map<String, String>> pushed = []; // files of each commit
  final Map<String, String> _blobs = {};
  final List<String> pubLookups = [];
  World(this.modelReplies);

  http.StreamedResponse _json(Object body, [int code = 200]) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), code, headers: {'content-type': 'application/json'});

  http.Client client() => MockClient.streaming((req, bodyStream) async {
        final body = await bodyStream.bytesToString();
        final path = req.url.path;
        if (req.url.host == 'model.test') {
          modelRequests.add(jsonDecode(body) as Map<String, dynamic>);
          final text = modelReplies[(modelRequests.length - 1).clamp(0, modelReplies.length - 1)];
          final sse = 'data: ${jsonEncode({'choices': [{'delta': {'content': text}}]})}\n\ndata: [DONE]\n\n';
          return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200, headers: {'content-type': 'text/event-stream'});
        }
        if (req.url.host == 'pub.dev') {
          final name = path.split('/').last;
          pubLookups.add(name);
          if (name != 'shared_preferences') return _json({'error': 'nf'}, 404);
          return _json({'latest': {'version': '2.5.6'}, 'versions': [{'version': '2.5.5'}, {'version': '2.5.6'}]});
        }
        if (path == '/user') return _json({'login': 'tester'});
        if (path == '/repos/tester/todo-app-abcd') return _json({'html_url': 'https://github.com/tester/todo-app-abcd', 'default_branch': 'main'});
        if (path.endsWith('/git/ref/heads/main')) return _json({'object': {'sha': 'p1'}});
        if (path.contains('/git/commits/')) return _json({'tree': {'sha': 't0'}});
        if (path.endsWith('/git/blobs')) {
          final sha = 'b${_blobs.length}';
          _blobs[sha] = utf8.decode(base64Decode(jsonDecode(body)['content'] as String));
          return _json({'sha': sha}, 201);
        }
        if (path.endsWith('/git/trees')) {
          pushed.add({for (final t in jsonDecode(body)['tree'] as List) t['path'] as String: _blobs[t['sha']]!});
          return _json({'sha': 't1'}, 201);
        }
        if (path.endsWith('/git/commits')) return _json({'sha': 'c1'}, 201);
        if (path.contains('/git/refs/heads/')) return _json({});
        if (path.endsWith('/actions/runs')) return _json({'workflow_runs': [{'id': 7, 'status': 'completed', 'conclusion': 'success', 'html_url': 'https://github.com/run/7'}]});
        if (path.endsWith('/releases/latest')) return _json({'assets': [{'name': 'todo_app.apk', 'browser_download_url': 'https://dl.test/todo_app.apk'}]});
        return _json({'message': 'unexpected ${req.method} $path'}, 404);
      });
}

class Run {
  final List<Map<String, dynamic>> events = [];
  late final Chat chat;
  late final JobEngine engine;
  final Directory dir = Directory.systemTemp.createTempSync('mugen_engine_');
  Run(Map<String, String> files, {bool autoFix = true, String? pkg = 'todo_app'}) {
    final store = ChatStore(dir.path);
    final c = Chat(id: 'abcd1234', messages: [
      Msg(id: '1', role: 'user', text: 'make a todo app'),
      Msg(id: '2', role: 'assistant', text: 'Building...'),
    ], project: Project(name: 'todo-app-abcd', pkg: pkg, title: 'Todo', files: files));
    store.save(c);
    engine = JobEngine(
      JobSpec(
        chatId: c.id, kind: 'push', modelId: 'm1', research: false, systemExtra: '', temperature: 0.2,
        ghToken: 'ghp_test', publicRepo: true, autoFix: autoFix, docsDir: dir.path,
        provider: ProviderConfig(id: 'x', kind: ProviderKind.custom, name: 'X', baseUrl: 'https://model.test/v1', apiKey: 'k'),
      ),
      events.add,
      (_, _) {},
    );
  }
  ChatStore get store => ChatStore(dir.path);
  Project get project => store.load('abcd1234')!.project!;
  List<Msg> get messages => store.load('abcd1234')!.messages;
}

Future<void> go(Run r, World w) => http.runWithClient(() => r.engine.run(), w.client);

void main() {
  test('a project that fails the checks is repaired by the model BEFORE anything is pushed', () async {
    final w = World([reply({'lib/main.dart': goodMain})]);
    final r = Run({'pubspec.yaml': pubspec, 'lib/main.dart': badMain});
    await go(r, w);

    expect(r.events.where((e) => e['type'] == 'error'), isEmpty, reason: r.events.toString());
    expect(w.modelRequests.length, 1, reason: 'one repair request');
    final asked = jsonEncode(w.modelRequests.single['messages']);
    expect(asked, allOf(contains('Mugen checked your project'), contains('no dependency'), contains('intl')));
    expect(w.pushed.length, 1, reason: 'exactly one commit, and it already has the repaired file');
    expect(w.pushed.single['lib/main.dart'], goodMain);
    expect(w.pushed.single.keys, containsAll(['pubspec.yaml', '.github/workflows/build-apk.yml', '.gitignore', 'README.md']));
    final steps = r.project.steps;
    expect(steps.indexWhere((s) => s.startsWith('Asking the AI to fix 1 problem')), greaterThan(-1));
    expect(steps.indexOf('Project checks passed'), greaterThan(steps.indexWhere((s) => s.startsWith('Asking the AI'))));
    expect(steps.indexOf('Project checks passed'), lessThan(steps.indexOf('Checking GitHub token')), reason: 'checks come first');
    expect(r.project.status, 'success');
    expect(r.project.apkUrl, 'https://dl.test/todo_app.apk');
    expect(r.messages.where((m) => m.text.startsWith(JobEngine.fixMarker)).length, 1);
  });

  test('a clean project goes straight to GitHub without bothering the model', () async {
    final w = World(['unused']);
    final r = Run({'pubspec.yaml': pubspec, 'lib/main.dart': goodMain});
    await go(r, w);
    expect(w.modelRequests, isEmpty);
    expect(w.pubLookups, ['shared_preferences'], reason: 'the dependency was looked up on pub.dev');
    expect(w.pushed.length, 1);
    expect(r.project.steps, contains('Project checks passed'));
    expect(r.project.status, 'success');
  });

  test('what has one obvious answer is fixed without asking: wrong pubspec name and old APIs', () async {
    final w = World(['unused']);
    final r = Run({
      'pubspec.yaml': pubspec.replaceFirst('todo_app', 'whatever'),
      'lib/main.dart': "import 'package:flutter/material.dart';\nimport 'package:shared_preferences/shared_preferences.dart';\nvoid main() { final c = Colors.red.withOpacity(0.5); runApp(const MaterialApp()); }\n",
    });
    await go(r, w);
    expect(w.modelRequests, isEmpty);
    expect(w.pushed.single['pubspec.yaml'], contains('name: todo_app'));
    expect(w.pushed.single['lib/main.dart'], contains('.withValues(alpha: 0.5)'));
    expect(r.project.steps.any((s) => s.startsWith('Renamed the package from "whatever"')), true);
  });

  test('model-written workflow and android files never reach the repository; the real workflow does', () async {
    final w = World(['unused']);
    final r = Run({
      'pubspec.yaml': pubspec,
      'lib/main.dart': goodMain,
      '.github/workflows/evil.yml': 'on: push\njobs: {}\n',
      '.github/workflows/build-apk.yml': 'name: faked\n',
      'android/app/build.gradle': 'x',
    });
    await go(r, w);
    final pushed = w.pushed.single;
    expect(pushed.keys.where((k) => k.startsWith('android/')), isEmpty);
    expect(pushed.keys.where((k) => k.startsWith('.github/')).toList(), ['.github/workflows/build-apk.yml']);
    expect(pushed['.github/workflows/build-apk.yml'], contains('flutter build apk'));
  });

  test('when the model cannot repair it, the build still happens and the chat says what is left', () async {
    final w = World([reply({'lib/main.dart': badMain})]); // the model changes nothing useful
    final r = Run({'pubspec.yaml': pubspec, 'lib/main.dart': badMain});
    await go(r, w);
    expect(w.modelRequests.length, 1, reason: 'the same answer is not asked for again');
    expect(w.pushed.length, 1);
    expect(r.project.steps.any((s) => s.contains('left, building anyway') && s.contains('intl')), true, reason: r.project.steps.toString());
    expect(r.project.status, 'success');
  });

  test('with auto-fix off the model is not asked, the problem is reported and the build still runs', () async {
    final w = World(['unused']);
    final r = Run({'pubspec.yaml': pubspec, 'lib/main.dart': badMain}, autoFix: false);
    await go(r, w);
    expect(w.modelRequests, isEmpty);
    expect(w.pushed.length, 1);
    expect(r.project.steps.any((s) => s.contains('left, building anyway')), true);
  });

  test('a made-up version on pub.dev is corrected in the pubspec before the push', () async {
    final w = World(['unused']);
    final r = Run({'pubspec.yaml': pubspec.replaceFirst('^2.5.6', '^2.9.9'), 'lib/main.dart': goodMain});
    await go(r, w);
    expect(w.modelRequests, isEmpty);
    expect(w.pushed.single['pubspec.yaml'], contains('shared_preferences: ^2.5.6'));
    expect(r.project.steps.any((s) => s.startsWith('Corrected 1 package version')), true);
  });

  test('projects saved before the package name was stored still work (the name comes from the pubspec)', () async {
    final w = World(['unused']);
    final r = Run({'pubspec.yaml': pubspec, 'lib/main.dart': goodMain}, pkg: null);
    await go(r, w);
    expect(r.project.status, 'success');
    expect(Project.fromJson(r.project.toJson()).pkg, r.project.pkg);
  });
}
