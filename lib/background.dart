import 'dart:async';
import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'engine.dart';
import 'models.dart';

/// Entry point of the background isolate. It keeps running (with a sticky
/// notification) even when the app is swiped away from recents.
@pragma('vm:entry-point')
void mugenServiceCallback() {
  FlutterForegroundTask.setTaskHandler(MugenTaskHandler());
}

class MugenTaskHandler extends TaskHandler {
  int _active = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    FlutterForegroundTask.sendDataToMain({'type': 'ready'});
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {
    if (data is! String) return;
    try {
      final spec = JobSpec.fromJson(Map<String, dynamic>.from(jsonDecode(data)));
      _run(spec);
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({'type': 'error', 'message': 'bad job: $e'});
    }
  }

  Future<void> _run(JobSpec spec) async {
    _active++;
    final engine = JobEngine(
      spec,
      (e) => FlutterForegroundTask.sendDataToMain(e),
      (title, text) => FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text),
    );
    await engine.run();
    _active--;
    if (_active == 0) {
      await Future.delayed(const Duration(seconds: 45)); // leave the final status visible
      if (_active == 0) await FlutterForegroundTask.stopService();
    }
  }
}

class Background {
  static Completer<void>? _ready;

  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'mugen_work',
        channelName: 'Mugen background work',
        channelDescription: 'Keeps chats and APK builds running while the app is closed.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
      ),
    );
  }

  static void onData(Object data) {
    if (data is Map && data['type'] == 'ready') {
      _ready?.complete();
    }
  }

  static Future<void> requestPermissions() async {
    if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  /// Starts the service when needed and hands the job to its isolate.
  static Future<void> start(JobSpec spec) async {
    if (!await FlutterForegroundTask.isRunningService) {
      _ready = Completer<void>();
      final r = await FlutterForegroundTask.startService(
        serviceId: 4242,
        notificationTitle: 'Mugen is working',
        notificationText: 'Starting...',
        callback: mugenServiceCallback,
      );
      if (r is ServiceRequestFailure) throw r.error;
      await _ready!.future.timeout(const Duration(seconds: 8), onTimeout: () {});
    }
    FlutterForegroundTask.sendDataToTask(jsonEncode(spec.toJson()));
  }
}
