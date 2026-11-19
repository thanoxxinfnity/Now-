import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

/// Chats live as one JSON file each, so the background isolate and the UI
/// share history through the disk (and history survives the app being killed).
class ChatStore {
  final Directory dir;
  ChatStore(String docsDir) : dir = Directory('$docsDir/chats') {
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  File _f(String id) => File('${dir.path}/$id.json');

  Chat? load(String id) {
    final f = _f(id);
    if (!f.existsSync()) return null;
    try {
      return Chat.fromJson(jsonDecode(f.readAsStringSync()));
    } catch (_) {
      return null;
    }
  }

  void save(Chat c) {
    c.updated = DateTime.now().millisecondsSinceEpoch;
    final tmp = File('${_f(c.id).path}.tmp')..writeAsStringSync(c.encode(), flush: true);
    tmp.renameSync(_f(c.id).path);
  }

  void delete(String id) {
    final f = _f(id);
    if (f.existsSync()) f.deleteSync();
  }

  List<Chat> all() {
    final out = <Chat>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      try {
        out.add(Chat.fromJson(jsonDecode(f.readAsStringSync())));
      } catch (_) {}
    }
    out.sort((a, b) => b.updated.compareTo(a.updated));
    return out;
  }
}

class SettingsStore {
  static const _sec = FlutterSecureStorage();
  late SharedPreferences prefs;

  List<ProviderConfig> providers = ProviderConfig.defaults();
  Map<String, List<ModelInfo>> models = {};
  String ghToken = '';
  String ghLogin = '';
  bool publicRepo = true;
  bool autoFix = true;
  bool research = false;
  bool backgroundMode = true;
  double temperature = 0.7;
  String systemExtra = '';
  String? selProvider;
  String? selModel;

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    ghToken = await _sec.read(key: 'gh_token') ?? '';
    final raw = prefs.getString('providers');
    if (raw != null) {
      providers = (jsonDecode(raw) as List).map((e) => ProviderConfig.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    for (final p in providers) {
      p.apiKey = await _sec.read(key: 'key_${p.id}') ?? '';
    }
    final m = prefs.getString('models');
    if (m != null) {
      final j = Map<String, dynamic>.from(jsonDecode(m));
      models = j.map((k, v) => MapEntry(k, (v as List).map((e) => ModelInfo.fromJson(Map<String, dynamic>.from(e))).toList()));
    }
    ghLogin = prefs.getString('gh_login') ?? '';
    publicRepo = prefs.getBool('public_repo') ?? true;
    autoFix = prefs.getBool('auto_fix') ?? true;
    research = prefs.getBool('research') ?? false;
    backgroundMode = prefs.getBool('bg') ?? true;
    temperature = prefs.getDouble('temp') ?? 0.7;
    systemExtra = prefs.getString('sys') ?? '';
    selProvider = prefs.getString('sel_p');
    selModel = prefs.getString('sel_m');
  }

  Future<void> save() async {
    await _sec.write(key: 'gh_token', value: ghToken);
    for (final p in providers) {
      await _sec.write(key: 'key_${p.id}', value: p.apiKey);
    }
    final pj = providers.map((p) => (p.toJson()..['apiKey'] = '')).toList();
    await prefs.setString('providers', jsonEncode(pj));
    await prefs.setString('models', jsonEncode(models.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList()))));
    await prefs.setString('gh_login', ghLogin);
    await prefs.setBool('public_repo', publicRepo);
    await prefs.setBool('auto_fix', autoFix);
    await prefs.setBool('research', research);
    await prefs.setBool('bg', backgroundMode);
    await prefs.setDouble('temp', temperature);
    await prefs.setString('sys', systemExtra);
    if (selProvider != null) await prefs.setString('sel_p', selProvider!);
    if (selModel != null) await prefs.setString('sel_m', selModel!);
  }

}
