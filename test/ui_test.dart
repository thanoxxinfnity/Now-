import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mugen_ai/api.dart';
import 'package:mugen_ai/models.dart';
import 'package:mugen_ai/state.dart';
import 'package:mugen_ai/theme.dart';
import 'package:mugen_ai/ui/model_picker.dart';
import 'package:mugen_ai/ui/scope.dart';
import 'package:mugen_ai/ui/settings.dart';

AppState appWith(ProviderConfig p, {List<ModelInfo> models = const []}) {
  final app = AppState();
  app.settings.providers = [p];
  app.settings.models[p.id] = models;
  return app;
}

Widget host(AppState app, Widget child) => AppScope(state: app, child: MaterialApp(theme: buildTheme(), home: child));

ProviderConfig custom() => ProviderConfig(id: 'p1', kind: ProviderKind.custom, name: 'My Server', baseUrl: 'https://api.test/v1', apiKey: 'k');

void main() {
  tearDown(() => defaultClientFactory = http.Client.new);

  group('Test connection (Settings)', () {
    testWidgets('shows how many models were found', (tester) async {
      defaultClientFactory = () => MockClient((req) async => http.Response(jsonEncode({'data': [{'id': 'a'}, {'id': 'b'}, {'id': 'c'}]}), 200));
      await tester.pumpWidget(host(appWith(custom()), const SettingsScreen()));
      expect(find.text('Test connection'), findsOneWidget);
      await tester.tap(find.text('Test connection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Connected to My Server'), findsOneWidget);
      expect(find.textContaining('3 models found'), findsOneWidget);
    });

    testWidgets('shows the exact error text of a refused key', (tester) async {
      defaultClientFactory = () => MockClient((req) async => http.Response(jsonEncode({'error': {'message': 'Invalid API key provided'}}), 401));
      await tester.pumpWidget(host(appWith(custom()), const SettingsScreen()));
      await tester.tap(find.text('Test connection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // SelectableText builds the text twice (the field and its rich text), so "at least one".
      expect(find.textContaining('the API key was refused (401)'), findsWidgets);
      expect(find.textContaining('Invalid API key provided'), findsWidgets);
      expect(find.text('Copy'), findsOneWidget);
    });
  });

  group('Test model (model picker)', () {
    Future<void> openPicker(WidgetTester tester, AppState app) async {
      await tester.pumpWidget(host(app, Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showModelPicker(c), child: const Text('open')))))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('every model row has a Test action that shows the reply', (tester) async {
      defaultClientFactory = () => MockClient.streaming((req, b) async {
            final body = jsonDecode(await b.bytesToString());
            expect(body['model'], 'model-a');
            final sse = 'data: ${jsonEncode({'choices': [{'delta': {'content': 'pong'}}]})}\n\ndata: [DONE]\n\n';
            return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200, headers: {'content-type': 'text/event-stream'});
          });
      final app = appWith(custom(), models: [ModelInfo(id: 'model-a', name: 'Model A', providerId: 'p1'), ModelInfo(id: 'model-b', name: 'Model B', providerId: 'p1')]);
      await openPicker(tester, app);
      expect(find.text('Test'), findsNWidgets(2));
      await tester.tap(find.text('Test').first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Test model'), findsOneWidget);
      expect(find.textContaining('model-a answered'), findsWidgets);
      expect(find.textContaining('pong'), findsWidgets);
    });

    testWidgets('a failing model shows the exact error, including the server text', (tester) async {
      defaultClientFactory = () => MockClient.streaming((req, b) async {
            await b.drain<void>();
            return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode({'error': {'message': 'model is turned off right now'}}))), 400, headers: {'content-type': 'application/json'});
          });
      final app = appWith(custom(), models: [ModelInfo(id: 'model-a', name: 'Model A', providerId: 'p1')]);
      await openPicker(tester, app);
      await tester.tap(find.text('Test'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('My Server / model-a'), findsWidgets);
      expect(find.textContaining('model is turned off right now'), findsWidgets);
      expect(find.text('Test again'), findsOneWidget);
    });

    testWidgets('a model ID typed by hand can be tested too', (tester) async {
      defaultClientFactory = () => MockClient.streaming((req, b) async {
            final body = jsonDecode(await b.bytesToString());
            final sse = 'data: ${jsonEncode({'choices': [{'delta': {'content': body['model']}}]})}\n\ndata: [DONE]\n\n';
            return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200, headers: {'content-type': 'text/event-stream'});
          });
      final app = appWith(custom());
      await openPicker(tester, app);
      await tester.enterText(find.byType(TextField), 'my/typed-model');
      await tester.pump();
      expect(find.textContaining('Use "my/typed-model" as model ID'), findsOneWidget);
      await tester.tap(find.text('Test'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('my/typed-model answered'), findsWidgets);
    });
  });
}
