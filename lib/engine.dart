import 'dart:async';
import 'models.dart';
import 'store.dart';
import 'api.dart';
import 'research.dart';
import 'github.dart';
import 'parser.dart';
import 'prompts.dart';

typedef Emit = void Function(Map<String, dynamic> event);
typedef Notify = void Function(String title, String text);

/// Runs one job (chat completion or GitHub push + build watch). Pure Dart so
/// it can live inside the foreground-service isolate and keep working after
/// the UI is swiped away.
class JobEngine {
  final JobSpec job;
  final Emit emit;
  final Notify notify;
  late final ChatStore store = ChatStore(job.docsDir);
  JobEngine(this.job, this.emit, this.notify);

  static const fixMarker = '[[fix]]';

  Future<void> run() async {
    try {
      if (job.kind == 'chat') {
        await _chat();
        await _afterChat();
      } else if (job.kind == 'push') {
        await _push();
      }
      emit({'type': 'done', 'chatId': job.chatId});
    } catch (e) {
      final msg = e.toString();
      _showErrorInChat(msg);
      emit({'type': 'error', 'chatId': job.chatId, 'message': msg});
      _failNote(msg);
    }
  }

  /// Puts the error into the chat itself so it is never lost in a toast.
  void _showErrorInChat(String msg) {
    final c = store.load(job.chatId);
    if (c == null) return;
    final note = '**Error:** $msg';
    if (c.messages.isNotEmpty && c.messages.last.role == 'assistant') {
      final m = c.messages.last;
      m.text = m.text.trim().isEmpty ? note : '${m.text}\n\n$note';
    } else {
      c.messages.add(Msg(id: _id(), role: 'assistant', text: note, model: job.modelId));
    }
    store.save(c);
  }

  void _failNote(String msg) {
    final c = store.load(job.chatId);
    if (c?.project != null && (c!.project!.status == 'pushing' || c.project!.status == 'building')) {
      c.project!.status = 'failed';
      c.project!.log = msg;
      store.save(c);
      emit({'type': 'chat', 'chatId': job.chatId});
    }
  }

  // ---------------------------------------------------------------- chat
  Future<void> _chat() async {
    final chat = store.load(job.chatId)!;
    final lastUser = chat.messages.lastWhere((m) => m.role == 'user');
    notify('Mugen is thinking', _short(lastUser.text));

    final msgs = <Map<String, String>>[
      {'role': 'system', 'content': mugenSystemPrompt + (job.systemExtra.isEmpty ? '' : '\nUser preferences:\n${job.systemExtra}')},
    ];
    List<Map<String, String>> sources = [];
    if (job.research) {
      notify('Mugen researching', 'Searching the web...');
      emit({'type': 'status', 'chatId': job.chatId, 'text': 'Searching the web...'});
      final r = await liveResearch(lastUser.text.replaceFirst(fixMarker, ''));
      sources = r.sources;
      msgs.add({'role': 'system', 'content': '$researchHint\n${r.context}'});
    }
    final proj = chat.project;
    if (proj != null && proj.files.isNotEmpty) {
      final b = StringBuffer('CURRENT PROJECT "${proj.name}" (already built; when the user asks for changes, return only changed files in full):\n');
      var size = 0;
      for (final e in proj.files.entries) {
        if (size > 70000) break;
        b.writeln('--- ${e.key} ---\n${e.value}');
        size += e.value.length;
      }
      msgs.add({'role': 'system', 'content': b.toString()});
    }
    final hist = chat.messages.length > 24 ? chat.messages.sublist(chat.messages.length - 24) : chat.messages;
    for (var i = 0; i < hist.length; i++) {
      final m = hist[i];
      var t = m.text.replaceFirst(fixMarker, '');
      if (m.role == 'assistant') {
        // old code blocks are replaced by a stub; the live project is in the system message
        final p = parseMessage(t);
        if (p.project != null) {
          t = '${p.before}<mugen-project name="${p.project!.name}" title="${p.project!.title}">[${p.project!.files.length} files omitted]</mugen-project>${p.after}';
        }
      }
      if (t.trim().isEmpty) continue;
      msgs.add({'role': m.role, 'content': t});
    }

    final reply = Msg(id: _id(), role: 'assistant', text: '', sources: sources, model: job.modelId);
    chat.messages.add(reply);
    store.save(chat);
    emit({'type': 'chat', 'chatId': job.chatId});

    var lastSave = DateTime.now();
    var lastNote = DateTime.now();
    await for (final d in streamChat(provider: job.provider, model: job.modelId, messages: msgs, temperature: job.temperature)) {
      reply.text += d;
      emit({'type': 'delta', 'chatId': job.chatId, 'text': d});
      final now = DateTime.now();
      if (now.difference(lastSave).inMilliseconds > 1500) {
        store.save(chat);
        lastSave = now;
      }
      if (now.difference(lastNote).inSeconds > 4) {
        final p = parseMessage(reply.text);
        notify(p.project != null ? 'Mugen is coding' : 'Mugen is replying',
            p.project != null ? '${p.project!.files.length} files written...' : _short(reply.text));
        lastNote = now;
      }
    }
    if (reply.text.trim().isEmpty) reply.text = '(empty reply from model)';

    // keep the project in sync with the newest code block
    final parsed = parseMessage(reply.text);
    if (parsed.project != null && parsed.project!.files.isNotEmpty) {
      final pb = parsed.project!;
      final pr = chat.project ??
          Project(name: sanitizeRepoName('${pb.name}-${chat.id.substring(0, 4)}'), title: pb.title);
      pr.files.addAll(pb.files);
      pr.title = pb.title;
      if (pr.status == 'success' || pr.status == 'failed') pr.status = 'idle';
      chat.project = pr;
    }
    if (chat.title == 'New chat') {
      final first = chat.messages.first.text.replaceFirst(fixMarker, '').trim().replaceAll('\n', ' ');
      chat.title = first.length > 42 ? '${first.substring(0, 42)}...' : first;
    }
    store.save(chat);
    emit({'type': 'chat', 'chatId': job.chatId});
    notify('Mugen', 'Reply ready');
  }

  Future<void> _afterChat() async {
    // when this chat run was an auto-fix, push again
    final chat = store.load(job.chatId)!;
    final lastUser = chat.messages.lastWhere((m) => m.role == 'user');
    if (lastUser.text.startsWith(fixMarker) && chat.project != null && job.ghToken.isNotEmpty) {
      await _push();
    }
  }

  // ---------------------------------------------------------------- github
  Future<void> _push() async {
    final chat = store.load(job.chatId)!;
    final pr = chat.project;
    if (pr == null || pr.files.isEmpty) throw ApiError('No project to push yet.');
    if (job.ghToken.isEmpty) throw ApiError('Add your GitHub token in Settings first.');
    final gh = GitHub(job.ghToken);

    void step(String s, {String? status}) {
      pr.steps.add(s);
      if (status != null) pr.status = status;
      store.save(chat);
      emit({'type': 'chat', 'chatId': job.chatId});
      notify('Mugen build', s);
    }

    pr.steps = [];
    pr.log = null;
    pr.apkUrl = null;
    step('Checking GitHub token', status: 'pushing');
    final owner = await gh.login();
    pr.owner = owner;
    step('Preparing repository $owner/${pr.name}');
    final repo = await gh.ensureRepo(owner, pr.name, public: job.publicRepo);
    pr.repoUrl = repo['html_url'];
    final branch = (repo['default_branch'] ?? 'main') as String;

    final files = Map<String, String>.from(pr.files);
    files['.github/workflows/build-apk.yml'] = apkWorkflow(dartPackageName(pr.name), pr.title.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim());
    files['.gitignore'] = 'build/\n.dart_tool/\n.flutter-plugins*\n.packages\n';
    files['README.md'] = '# ${pr.title}\n\nBuilt with **Mugen AI**. Every push builds an APK via GitHub Actions; see Releases.\n';
    step('Pushing ${files.length} files');
    final sha = await gh.pushFiles(owner, pr.name, branch, files, pr.attempts == 0 ? 'Mugen: initial build' : 'Mugen: fix build (attempt ${pr.attempts})');

    step('Waiting for GitHub Actions', status: 'building');
    final run = await gh.findRun(owner, pr.name, sha);
    pr.runUrl = run['html_url'];
    store.save(chat);
    emit({'type': 'chat', 'chatId': job.chatId});
    step('Building APK (takes ~4-8 min)');

    final started = DateTime.now();
    Map<String, dynamic> cur = run;
    while (cur['status'] != 'completed') {
      await Future.delayed(const Duration(seconds: 8));
      cur = await gh.getRun(owner, pr.name, run['id'] as int);
      final mins = DateTime.now().difference(started).inMinutes;
      notify('Mugen build', 'Building APK... ${mins}m ${cur['status']}');
      if (DateTime.now().difference(started).inMinutes > 45) throw ApiError('Build timed out.');
    }

    if (cur['conclusion'] == 'success') {
      String? url;
      for (var i = 0; i < 6 && url == null; i++) {
        url = await gh.latestApkUrl(owner, pr.name);
        if (url == null) await Future.delayed(const Duration(seconds: 3));
      }
      pr.apkUrl = url;
      step('APK ready', status: 'success');
      notify('Mugen build', 'APK ready - tap to download');
      emit({'type': 'success', 'chatId': job.chatId});
      return;
    }

    final log = await gh.failedLog(owner, pr.name, run['id'] as int);
    pr.log = log;
    step('Build failed', status: 'failed');
    if (job.autoFix && pr.attempts < 3) {
      pr.attempts++;
      chat.messages.add(Msg(id: _id(), role: 'user', text: '$fixMarker${fixPrompt(log)}'));
      store.save(chat);
      emit({'type': 'chat', 'chatId': job.chatId});
      notify('Mugen', 'Build failed, fixing automatically (attempt ${pr.attempts})');
      await _chat();
      await _afterChat();
    }
  }

  static String _id() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  static String _short(String s) => s.length > 70 ? '${s.substring(0, 70)}...' : s;
}
