import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'api.dart';
import 'background.dart';
import 'engine.dart';
import 'github.dart';
import 'models.dart';
import 'store.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  late ChatStore chats;
  final settings = SettingsStore();
  late String docsDir;
  bool ready = false;

  List<Chat> history = [];
  Chat? current;
  final Set<String> running = {};
  final Map<String, String> status = {};
  String? error;
  final Map<String, bool> fetching = {};
  final successTick = ValueNotifier<int>(0);

  Future<void> init() async {
    docsDir = (await getApplicationDocumentsDirectory()).path;
    chats = ChatStore(docsDir);
    await settings.load();
    FlutterForegroundTask.addTaskDataCallback(_onData);
    WidgetsBinding.instance.addObserver(this);
    history = chats.all();
    ready = true;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && ready) {
      _reloadFromDisk();
    }
  }

  void _reloadFromDisk() {
    history = chats.all();
    if (current != null) {
      final c = chats.load(current!.id);
      if (c != null) current = c;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ events
  void _onData(Object data) {
    Background.onData(data);
    if (data is! Map) return;
    handle(Map<String, dynamic>.from(data));
  }

  void handle(Map<String, dynamic> e) {
    final id = e['chatId'] as String?;
    switch (e['type']) {
      case 'delta':
        if (current?.id == id && current!.messages.isNotEmpty && current!.messages.last.role == 'assistant') {
          current!.messages.last.text += e['text'] as String;
          status.remove(id);
          notifyListeners();
        }
        break;
      case 'status':
        status[id!] = e['text'];
        notifyListeners();
        break;
      case 'chat':
        history = chats.all();
        if (current?.id == id) {
          final fresh = chats.load(id!);
          if (fresh != null) current = fresh;
        }
        notifyListeners();
        break;
      case 'success':
        successTick.value++;
        break;
      case 'error':
        if (id != null) running.remove(id);
        error = e['message'];
        _reloadFromDisk();
        break;
      case 'done':
        if (id != null) running.remove(id);
        status.remove(id);
        _reloadFromDisk();
        break;
    }
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ chats
  void newChat() {
    current = null;
    notifyListeners();
  }

  void openChat(String id) {
    current = chats.load(id);
    notifyListeners();
  }

  void deleteChat(String id) {
    chats.delete(id);
    if (current?.id == id) current = null;
    history = chats.all();
    notifyListeners();
  }

  void renameChat(String id, String title) {
    final c = chats.load(id);
    if (c == null) return;
    c.title = title;
    chats.save(c);
    if (current?.id == id) current!.title = title;
    history = chats.all();
    notifyListeners();
  }

  // ------------------------------------------------------------ models
  ProviderConfig? get selProvider {
    for (final p in settings.providers) {
      if (p.id == settings.selProvider) return p;
    }
    return null;
  }

  ModelInfo? get selModel {
    final list = settings.models[settings.selProvider] ?? [];
    for (final m in list) {
      if (m.id == settings.selModel) return m;
    }
    return null;
  }

  Future<void> selectModel(ModelInfo m) async {
    settings.selProvider = m.providerId;
    settings.selModel = m.id;
    await settings.save();
    notifyListeners();
  }

  Future<String?> refreshModels(ProviderConfig p) async {
    fetching[p.id] = true;
    notifyListeners();
    try {
      final list = await fetchModels(p);
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      settings.models[p.id] = list;
      await settings.save();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      fetching[p.id] = false;
      notifyListeners();
    }
  }

  Future<void> setPaid(ModelInfo m, bool paid) async {
    settings.paidOverride[m.key] = paid;
    await settings.save();
    notifyListeners();
  }

  Future<void> saveSettings() async {
    await settings.save();
    notifyListeners();
  }

  Future<String?> verifyGithub() async {
    try {
      settings.ghLogin = await GitHub(settings.ghToken.trim()).login();
      await settings.save();
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ------------------------------------------------------------ sending
  JobSpec? _spec(String chatId, String kind) {
    final p = selProvider;
    final m = selModel;
    if (p == null || m == null) return null;
    return JobSpec(
      chatId: chatId, kind: kind, provider: p, modelId: m.id,
      research: settings.research, systemExtra: settings.systemExtra,
      temperature: settings.temperature, ghToken: settings.ghToken.trim(),
      publicRepo: settings.publicRepo, autoFix: settings.autoFix, docsDir: docsDir,
    );
  }

  Future<void> _dispatch(JobSpec spec) async {
    running.add(spec.chatId);
    notifyListeners();
    try {
      if (settings.backgroundMode) {
        await Background.start(spec);
      } else {
        unawaited(JobEngine(spec, handle, (a, b) {}).run());
      }
    } catch (e) {
      running.remove(spec.chatId);
      error = 'Could not start background work: $e';
      notifyListeners();
    }
  }

  /// Returns false when no model is chosen yet (UI opens the picker).
  Future<bool> send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return true;
    if (selModel == null || selProvider == null) return false;
    var c = current;
    if (c == null) {
      c = Chat(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36));
      current = c;
    }
    c.messages.add(Msg(id: DateTime.now().microsecondsSinceEpoch.toRadixString(36), role: 'user', text: t));
    chats.save(c);
    history = chats.all();
    final spec = _spec(c.id, 'chat')!;
    // placeholder so the UI shows the thinking state immediately
    c.messages.add(Msg(id: 'pending', role: 'assistant', text: '', model: spec.modelId));
    notifyListeners();
    if (settings.backgroundMode) await Background.requestPermissions();
    await _dispatch(spec);
    return true;
  }

  Future<void> pushBuild() async {
    final c = current;
    if (c == null || c.project == null) return;
    if (settings.ghToken.trim().isEmpty) {
      error = 'Settings me GitHub token daalo pehle.';
      notifyListeners();
      return;
    }
    final spec = _spec(c.id, 'push');
    if (spec == null) return;
    c.project!.status = 'pushing';
    c.project!.attempts = 0;
    chats.save(c);
    notifyListeners();
    if (settings.backgroundMode) await Background.requestPermissions();
    await _dispatch(spec);
  }

  Future<void> fixWithAi() async {
    final c = current;
    if (c?.project?.log == null) return;
    final log = c!.project!.log!;
    await send('${JobEngine.fixMarker}${_fix(log)}');
  }

  String _fix(String log) => 'The GitHub Actions build of the app FAILED. End of the failing log:\n\n```\n$log\n```\n\nFind the cause and fix it. Reply with one short line, then a <mugen-project> block with ONLY the changed files (complete content).';

  bool isRunning(String? id) => id != null && running.contains(id);
}
