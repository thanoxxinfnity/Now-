import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:material_ui/material_ui.dart';
import 'background.dart';
import 'insets.dart';
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
          builder: guardInsets,
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
