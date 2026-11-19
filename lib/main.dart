import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:material_ui/material_ui.dart';
import 'background.dart';
import 'state.dart';
import 'theme.dart';
import 'ui/home.dart';
import 'ui/scope.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  Background.init();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Tk.canvas,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const MugenApp());
}

class MugenApp extends StatefulWidget {
  const MugenApp({super.key});
  @override
  State<MugenApp> createState() => _MugenAppState();
}

class _MugenAppState extends State<MugenApp> {
  final state = AppState();

  @override
  void initState() {
    super.initState();
    state.init();
  }

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: MaterialApp(
          title: 'Mugen AI',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          builder: (context, child) {
            // Some Android versions draw edge-to-edge but report no insets, which pushed the
            // UI under the status / navigation bars. Always keep a safe margin.
            final mq = MediaQuery.of(context);
            final v = View.of(context);
            final dpr = v.devicePixelRatio;
            var top = [mq.padding.top, mq.viewPadding.top, v.viewPadding.top / dpr].reduce((a, b) => a > b ? a : b);
            var bottom = [mq.padding.bottom, mq.viewPadding.bottom, v.viewPadding.bottom / dpr].reduce((a, b) => a > b ? a : b);
            if (top < 1) top = 28;
            if (bottom < 1 && mq.viewInsets.bottom == 0) bottom = 16;
            return MediaQuery(
              data: mq.copyWith(
                padding: mq.padding.copyWith(top: top, bottom: mq.viewInsets.bottom > 0 ? mq.padding.bottom : bottom),
                viewPadding: mq.viewPadding.copyWith(top: top, bottom: bottom),
              ),
              child: child!,
            );
          },
          home: ListenableBuilder(
            listenable: state,
            builder: (_, __) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: state.ready
                  ? const HomeScreen(key: ValueKey('home'))
                  : const Scaffold(key: ValueKey('splash'), body: Center(child: MugenOrb(size: 110, active: true))),
            ),
          ),
        ),
      );
}
