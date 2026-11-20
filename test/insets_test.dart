import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mugen_ai/insets.dart';
import 'package:mugen_ai/models.dart';
import 'package:mugen_ai/state.dart';
import 'package:mugen_ai/theme.dart';
import 'package:mugen_ai/ui/cli_hub.dart';
import 'package:mugen_ai/ui/home.dart';
import 'package:mugen_ai/ui/model_picker.dart';
import 'package:mugen_ai/ui/scope.dart';
import 'package:mugen_ai/ui/settings.dart';
import 'package:mugen_ai/ui/widgets.dart' show Pressable;

/// A phone as Android 15/16 describes it: size and the bars drawn over the app (all in dp, pixel ratio 1).
class Phone {
  final String name;
  final Size size;
  final double top, bottom, left, right, keyboard;
  const Phone(this.name, this.size, {this.top = 0, this.bottom = 0, this.left = 0, this.right = 0, this.keyboard = 0});

  Phone withKeyboard(double k) => Phone('$name + keyboard', size, top: top, bottom: bottom, left: left, right: right, keyboard: k);

  /// What the app must keep its content inside. If nothing at all is reported, the app's own fallback margin applies.
  Rect get safe {
    final t = top < 1 ? fallbackTopInset : top;
    final b = keyboard > 0 ? keyboard : (bottom < 1 ? fallbackBottomInset : bottom);
    return Rect.fromLTRB(left, t, size.width - right, size.height - b);
  }
}

const phones = [
  Phone('gesture navigation, punch-hole camera', Size(412, 915), top: 48, bottom: 24),
  Phone('3-button navigation', Size(392, 800), top: 24, bottom: 48),
  Phone('tall cutout and thick gesture bar', Size(360, 780), top: 59, bottom: 34),
  Phone('landscape with a cutout on the left and the bar on the right', Size(800, 360), top: 24, left: 44, right: 48),
  Phone('the system reports no insets at all', Size(412, 860)),
];

void applyPhone(WidgetTester tester, Phone p) {
  final v = tester.view;
  v.devicePixelRatio = 1;
  v.physicalSize = p.size;
  // On Android the keyboard covers the navigation bar, so padding = viewPadding - viewInsets.
  v.viewPadding = FakeViewPadding(left: p.left, top: p.top, right: p.right, bottom: p.bottom);
  v.padding = FakeViewPadding(left: p.left, top: p.top, right: p.right, bottom: math.max(0, p.bottom - p.keyboard));
  v.viewInsets = FakeViewPadding(bottom: p.keyboard);
  addTearDown(v.reset);
}

AppState appWithModels([int n = 0]) {
  final app = AppState();
  final p = ProviderConfig(id: 'p1', kind: ProviderKind.custom, name: 'My Server', baseUrl: 'https://api.test/v1', apiKey: 'k');
  app.settings.providers = [p];
  app.settings.models[p.id] = [for (var i = 0; i < n; i++) ModelInfo(id: 'model-$i', name: 'Model $i', providerId: 'p1')];
  return app;
}

/// The app as main.dart builds it: same theme and the same insets guard.
Widget appShell(AppState app, Widget home) =>
    AppScope(state: app, child: MaterialApp(theme: buildTheme(), builder: guardInsets, home: home));

/// Scrolls to the real end. A lazily built list keeps growing while it is scrolled, so repeat until it stops.
Future<void> scrollToEnd(WidgetTester tester, ScrollableState list) async {
  for (var i = 0; i < 10; i++) {
    final before = list.position.pixels;
    list.position.jumpTo(list.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 600));
    if ((list.position.pixels - before).abs() < 0.5) break;
  }
}

Rect rectOf(WidgetTester t, Finder f) => t.getRect(f.first);

/// Every piece of text that is on screen at all.
Iterable<Rect> onScreenTexts(WidgetTester t, Rect window) => find
    .byType(Text)
    .evaluate()
    .map((e) => t.getRect(find.byElementPredicate((x) => x == e)))
    .where((r) => r.top < window.bottom && r.bottom > window.top && r.left < window.right && r.right > window.left);

void expectInside(Rect r, Rect safe, String what) {
  expect(r.top, greaterThanOrEqualTo(safe.top - 0.5), reason: '$what starts above the safe area ($r vs $safe)');
  expect(r.bottom, lessThanOrEqualTo(safe.bottom + 0.5), reason: '$what ends below the safe area ($r vs $safe)');
  expect(r.left, greaterThanOrEqualTo(safe.left - 0.5), reason: '$what is left of the safe area ($r vs $safe)');
  expect(r.right, lessThanOrEqualTo(safe.right + 0.5), reason: '$what is right of the safe area ($r vs $safe)');
}

void main() {
  group('resolveInsets', () {
    const none = EdgeInsets.zero;
    test('reported bars are kept as they are', () {
      final r = resolveInsets(padding: const EdgeInsets.only(top: 48, bottom: 24), viewPadding: const EdgeInsets.only(top: 48, bottom: 24), viewInsets: none);
      expect(r.padding, const EdgeInsets.only(top: 48, bottom: 24));
      expect(r.viewPadding, const EdgeInsets.only(top: 48, bottom: 24));
    });
    test('missing insets get a safe margin instead of drawing under the bars', () {
      final r = resolveInsets(padding: none, viewPadding: none, viewInsets: none);
      expect(r.padding.top, fallbackTopInset);
      expect(r.padding.bottom, fallbackBottomInset);
    });
    test('the view\'s own padding is trusted when MediaQuery was zeroed by an ancestor', () {
      final r = resolveInsets(padding: none, viewPadding: none, viewInsets: none, rawViewPadding: const EdgeInsets.only(top: 40, bottom: 20));
      expect(r.padding.top, 40);
      expect(r.padding.bottom, 20);
    });
    test('with the keyboard open the navigation bar height is not added a second time', () {
      final r = resolveInsets(padding: none, viewPadding: const EdgeInsets.only(top: 30, bottom: 48), viewInsets: const EdgeInsets.only(bottom: 300));
      expect(r.padding.bottom, 0);
      expect(r.viewPadding.bottom, 48);
    });
    test('left and right (cutouts in landscape) are never touched', () {
      final r = resolveInsets(padding: const EdgeInsets.only(left: 44, right: 48), viewPadding: const EdgeInsets.only(left: 44, right: 48), viewInsets: none);
      expect(r.padding.left, 44);
      expect(r.padding.right, 48);
    });
  });

  for (final phone in phones) {
    group('on a phone with ${phone.name}', () {
      testWidgets('home: top bar and message box stay inside the bars', (tester) async {
        applyPhone(tester, phone);
        await tester.pumpWidget(appShell(appWithModels(), const HomeScreen()));
        await tester.pump(const Duration(milliseconds: 300));
        expectInside(rectOf(tester, find.byIcon(Icons.menu_rounded)), phone.safe, 'the menu button');
        expectInside(rectOf(tester, find.byIcon(Icons.edit_square)), phone.safe, 'the new chat button');
        expectInside(rectOf(tester, find.byType(TextField)), phone.safe, 'the message box');
      });

      testWidgets('home with the keyboard open: the message box is above the keyboard', (tester) async {
        final kb = phone.withKeyboard(math.min(300, phone.size.height * 0.45));
        applyPhone(tester, kb);
        await tester.pumpWidget(appShell(appWithModels(), const HomeScreen()));
        await tester.pump(const Duration(milliseconds: 300));
        expectInside(rectOf(tester, find.byType(TextField)), kb.safe, 'the message box');
        expectInside(rectOf(tester, find.byIcon(Icons.menu_rounded)), kb.safe, 'the menu button');
      });

      testWidgets('the history drawer: header and bottom entries inside the bars', (tester) async {
        applyPhone(tester, phone);
        await tester.pumpWidget(appShell(appWithModels(), const HomeScreen()));
        await tester.pump(const Duration(milliseconds: 300));
        tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expectInside(rectOf(tester, find.text('Mugen').last), phone.safe, 'the drawer title');
        expectInside(rectOf(tester, find.text('Settings')), phone.safe, 'the Settings entry');
        expectInside(rectOf(tester, find.text('Mugen CLI hub')), phone.safe, 'the CLI hub entry');
        expectInside(rectOf(tester, find.text('New chat')), phone.safe, 'the New chat button');
      });

      testWidgets('settings: title below the status bar, last item above the navigation bar', (tester) async {
        applyPhone(tester, phone);
        await tester.pumpWidget(appShell(appWithModels(), const SettingsScreen()));
        await tester.pump(const Duration(milliseconds: 300));
        expectInside(rectOf(tester, find.text('Settings')), phone.safe, 'the title');
        expectInside(rectOf(tester, find.byIcon(Icons.arrow_back_rounded)), phone.safe, 'the back button');
        await scrollToEnd(tester, tester.state<ScrollableState>(find.byType(Scrollable).first));
        final window = Rect.fromLTWH(0, 0, phone.size.width, phone.size.height);
        final lowest = onScreenTexts(tester, window).map((r) => r.bottom).reduce(math.max);
        expect(lowest, lessThanOrEqualTo(phone.safe.bottom + 0.5), reason: 'at the end of the list the last text ends at $lowest, under the bar that starts at ${phone.safe.bottom}');
      });

      testWidgets('model picker sheet: title below the status bar, last model above the navigation bar', (tester) async {
        applyPhone(tester, phone);
        final app = appWithModels(40);
        await tester.pumpWidget(appShell(app, Builder(builder: (c) => Scaffold(body: Center(child: TextButton(onPressed: () => showModelPicker(c), child: const Text('open')))))));
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expectInside(rectOf(tester, find.text('Choose model')), phone.safe, 'the sheet title');
        await scrollToEnd(tester, tester.state<ScrollableState>(find.byType(Scrollable).last));
        expect(find.text('Model 39'), findsWidgets);
        // the whole row (name and id line), not only the name text
        final last = tester.getRect(find.ancestor(of: find.text('Model 39'), matching: find.byType(Pressable)).first);
        expect(last.bottom, lessThanOrEqualTo(phone.safe.bottom), reason: 'the last model ($last) must end above the navigation bar (${phone.safe.bottom})');
        expect(last.left, greaterThanOrEqualTo(phone.safe.left));
        expect(last.right, lessThanOrEqualTo(phone.safe.right));
      });
    });
  }

  group('CLI hub', () {
    Future<void> openRunSheet(WidgetTester tester, Phone phone) async {
      applyPhone(tester, phone);
      await tester.pumpWidget(appShell(appWithModels(), const CliHubScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Run in cloud').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    final registry = jsonEncode({
      'clis': [
        for (var i = 0; i < 12; i++) {'name': 'tool$i', 'display_name': 'Tool $i', 'description': 'Does thing $i', 'category': 'dev', 'install_cmd': 'pip install tool$i', 'entry_point': 'tool$i'},
      ],
    });

    for (final phone in phones) {
      testWidgets('list and run sheet on a phone with ${phone.name}', (tester) async {
        await http.runWithClient(() async {
          await openRunSheet(tester, phone);
          // The sheet: title inside the safe area, the Run button above the navigation bar.
          expectInside(rectOf(tester, find.textContaining('Run Tool')), phone.safe, 'the sheet title');
          expectInside(rectOf(tester, find.text('Run')), phone.safe, 'the Run button');
          // Typing: the keyboard comes up and the Run button must stay above it.
          final kb = phone.withKeyboard(math.min(300, phone.size.height * 0.45));
          applyPhone(tester, kb);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: 'the sheet must not overflow with the keyboard open');
          // Content that does not fit scrolls: the user scrolls the Run button into view, and it must then be above the keyboard.
          await tester.ensureVisible(find.text('Run'));
          await tester.pump();
          final run = rectOf(tester, find.text('Run'));
          expect(run.bottom, lessThanOrEqualTo(kb.safe.bottom + 0.5), reason: 'the Run button $run is hidden by the keyboard (${kb.safe.bottom})');
        }, () => MockClient((req) async => http.Response(registry, 200)));
      });
    }

    testWidgets('the list ends above the navigation bar', (tester) async {
      final phone = phones[1];
      await http.runWithClient(() async {
        applyPhone(tester, phone);
        await tester.pumpWidget(appShell(appWithModels(), const CliHubScreen()));
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        // (the search field has a Scrollable of its own, so take the one inside the ListView)
        final list = tester.state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
        await scrollToEnd(tester, list);
        final buttons = find.text('Ask Mugen');
        final last = tester.getRect(buttons.last);
        expect(last.bottom, lessThanOrEqualTo(phone.safe.bottom), reason: 'last card button $last vs bar at ${phone.safe.bottom}');
      }, () => MockClient((req) async => http.Response(registry, 200)));
    });
  });

  group('touch targets', () {
    testWidgets('small icon buttons and small buttons react to a 44 dp area', (tester) async {
      await tester.pumpWidget(appShell(appWithModels(), const SettingsScreen()));
      await tester.pump(const Duration(milliseconds: 300));
      for (final f in [find.byIcon(Icons.arrow_back_rounded), find.text('Test connection')]) {
        final target = find.ancestor(of: f.first, matching: find.byType(GestureDetector)).first;
        final r = tester.getRect(target);
        expect(r.width, greaterThanOrEqualTo(44), reason: '$f is ${r.width} wide');
        expect(r.height, greaterThanOrEqualTo(44), reason: '$f is ${r.height} high');
      }
    });
  });
}

