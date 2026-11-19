import 'dart:convert';

enum ProviderKind { nvidia, gemini, openrouter, custom }

class ProviderConfig {
  String id;
  ProviderKind kind;
  String name;
  String baseUrl;
  String apiKey;
  bool enabled;

  ProviderConfig({
    required this.id,
    required this.kind,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.enabled = true,
  });

  bool get ready => apiKey.trim().isNotEmpty || kind == ProviderKind.openrouter || kind == ProviderKind.custom;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'enabled': enabled,
      };

  factory ProviderConfig.fromJson(Map<String, dynamic> j) => ProviderConfig(
        id: j['id'],
        kind: ProviderKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => ProviderKind.custom),
        name: j['name'] ?? 'Custom',
        baseUrl: j['baseUrl'] ?? '',
        apiKey: j['apiKey'] ?? '',
        enabled: j['enabled'] ?? true,
      );

  static List<ProviderConfig> defaults() => [
        ProviderConfig(id: 'nvidia', kind: ProviderKind.nvidia, name: 'NVIDIA NIM', baseUrl: 'https://integrate.api.nvidia.com/v1'),
        ProviderConfig(id: 'gemini', kind: ProviderKind.gemini, name: 'Google Gemini', baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai'),
        ProviderConfig(id: 'openrouter', kind: ProviderKind.openrouter, name: 'OpenRouter', baseUrl: 'https://openrouter.ai/api/v1'),
      ];
}

class ModelInfo {
  final String id; // id sent to the API
  final String name;
  final String providerId;
  final bool autoFree; // what we detected
  final int? context;
  ModelInfo({required this.id, required this.name, required this.providerId, required this.autoFree, this.context});

  String get key => '$providerId::$id';

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'p': providerId, 'free': autoFree, 'ctx': context};
  factory ModelInfo.fromJson(Map<String, dynamic> j) => ModelInfo(
      id: j['id'], name: j['name'], providerId: j['p'], autoFree: j['free'] ?? true, context: j['ctx']);
}

class GenFile {
  String path;
  String content;
  GenFile(this.path, this.content);
}

/// State of the GitHub project attached to a chat.
class Project {
  String name; // repo name
  String title;
  Map<String, String> files; // path -> content
  String? owner;
  String? runUrl;
  String? apkUrl;
  String? repoUrl;
  String status; // idle | pushing | building | success | failed
  String? log; // tail of failed build log
  int attempts;
  List<String> steps;

  Project({
    required this.name,
    required this.title,
    Map<String, String>? files,
    this.owner,
    this.runUrl,
    this.apkUrl,
    this.repoUrl,
    this.status = 'idle',
    this.log,
    this.attempts = 0,
    List<String>? steps,
  })  : files = files ?? {},
        steps = steps ?? [];

  Map<String, dynamic> toJson() => {
        'name': name, 'title': title, 'files': files, 'owner': owner, 'runUrl': runUrl,
        'apkUrl': apkUrl, 'repoUrl': repoUrl, 'status': status, 'log': log,
        'attempts': attempts, 'steps': steps,
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        name: j['name'], title: j['title'] ?? j['name'],
        files: Map<String, String>.from(j['files'] ?? {}),
        owner: j['owner'], runUrl: j['runUrl'], apkUrl: j['apkUrl'], repoUrl: j['repoUrl'],
        status: j['status'] ?? 'idle', log: j['log'], attempts: j['attempts'] ?? 0,
        steps: List<String>.from(j['steps'] ?? []),
      );
}

class Msg {
  final String id;
  final String role; // user | assistant
  String text;
  List<Map<String, String>> sources; // {title,url}
  String? model;
  final int ts;
  Msg({required this.id, required this.role, required this.text, List<Map<String, String>>? sources, this.model, int? ts})
      : sources = sources ?? [],
        ts = ts ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {'id': id, 'role': role, 'text': text, 'sources': sources, 'model': model, 'ts': ts};
  factory Msg.fromJson(Map<String, dynamic> j) => Msg(
        id: j['id'], role: j['role'], text: j['text'] ?? '',
        sources: (j['sources'] as List? ?? []).map((e) => Map<String, String>.from(e)).toList(),
        model: j['model'], ts: j['ts'],
      );
}

class Chat {
  final String id;
  String title;
  int updated;
  List<Msg> messages;
  Project? project;
  Chat({required this.id, this.title = 'New chat', int? updated, List<Msg>? messages, this.project})
      : updated = updated ?? DateTime.now().millisecondsSinceEpoch,
        messages = messages ?? [];

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'updated': updated,
        'messages': messages.map((m) => m.toJson()).toList(),
        'project': project?.toJson(),
      };
  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        id: j['id'], title: j['title'] ?? 'Chat', updated: j['updated'],
        messages: (j['messages'] as List? ?? []).map((e) => Msg.fromJson(Map<String, dynamic>.from(e))).toList(),
        project: j['project'] == null ? null : Project.fromJson(Map<String, dynamic>.from(j['project'])),
      );
  String encode() => jsonEncode(toJson());
}

/// Everything the background isolate needs to run one job.
class JobSpec {
  final String chatId;
  final String kind; // chat | push
  final ProviderConfig provider;
  final String modelId;
  final bool research;
  final String systemExtra;
  final double temperature;
  final String ghToken;
  final bool publicRepo;
  final bool autoFix;
  final String docsDir;

  JobSpec({
    required this.chatId, required this.kind, required this.provider, required this.modelId,
    required this.research, required this.systemExtra, required this.temperature,
    required this.ghToken, required this.publicRepo, required this.autoFix, required this.docsDir,
  });

  Map<String, dynamic> toJson() => {
        'chatId': chatId, 'kind': kind, 'provider': provider.toJson(), 'modelId': modelId,
        'research': research, 'systemExtra': systemExtra, 'temperature': temperature,
        'ghToken': ghToken, 'publicRepo': publicRepo, 'autoFix': autoFix, 'docsDir': docsDir,
      };
  factory JobSpec.fromJson(Map<String, dynamic> j) => JobSpec(
        chatId: j['chatId'], kind: j['kind'],
        provider: ProviderConfig.fromJson(Map<String, dynamic>.from(j['provider'])),
        modelId: j['modelId'], research: j['research'], systemExtra: j['systemExtra'] ?? '',
        temperature: (j['temperature'] as num).toDouble(), ghToken: j['ghToken'] ?? '',
        publicRepo: j['publicRepo'] ?? true, autoFix: j['autoFix'] ?? true, docsDir: j['docsDir'],
      );
}
