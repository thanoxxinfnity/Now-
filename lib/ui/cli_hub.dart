import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import '../github.dart';
import '../insets.dart';
import '../theme.dart';
import 'scope.dart';
import 'widgets.dart';

/// Mugen CLI: every software CLI from the CLI-Anything / CLI-Hub registry.
/// Phones cannot run desktop CLIs, so "Run in cloud" installs the CLI on a
/// GitHub Actions runner in the user's own `mugen-cli-runner` repo and streams the log back.
class CliHubScreen extends StatefulWidget {
  const CliHubScreen({super.key});
  @override
  State<CliHubScreen> createState() => _CliHubState();
}

class _CliHubState extends State<CliHubScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;
  String? err;
  String q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      final r = await http
          .get(Uri.parse('https://raw.githubusercontent.com/HKUDS/CLI-Anything/main/public_registry.json'))
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      final j = jsonDecode(r.body);
      items = (j['clis'] as List).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      err = 'Could not load the registry: $e';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final f = items.where((i) => q.isEmpty || '${i['display_name']} ${i['description']} ${i['category']}'.toLowerCase().contains(q.toLowerCase())).toList();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Tk.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: MIconBtn(Icons.arrow_back_rounded, color: Tk.text, onTap: () => Navigator.pop(context)),
        title: Text('Mugen CLI hub', style: ts(19, w: 600)),
        actions: [MIconBtn(Icons.refresh_rounded, onTap: _load)],
      ),
      body: Column(children: [
        Padding(
          padding: scrollPadding(context, bottom: 0).copyWith(bottom: 8),
          child: TextField(
            onChanged: (v) => setState(() => q = v),
            style: ts(14),
            decoration: InputDecoration(
              hintText: 'Search ${items.length} CLIs',
              hintStyle: ts(14, color: Tk.faint),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Tk.faint),
              isDense: true,
              filled: true,
              fillColor: Tk.field,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.r), borderSide: const BorderSide(color: Tk.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.r), borderSide: const BorderSide(color: Tk.border)),
            ),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: MugenOrb(size: 70, active: true))
              : err != null
                  ? Center(child: Text(err!, style: ts(14, color: Tk.danger)))
                  : ListView.builder(
                      padding: scrollPadding(context, top: 4, bottom: 30),
                      itemCount: f.length,
                      itemBuilder: (_, i) => _CliCard(cli: f[i]).animate().fadeIn(delay: (i * 25).clamp(0, 300).ms, duration: 300.ms).slideY(begin: 0.08),
                    ),
        ),
      ]),
    );
  }
}

class _CliCard extends StatelessWidget {
  final Map<String, dynamic> cli;
  const _CliCard({required this.cli});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${cli['display_name'] ?? cli['name']}', style: ts(15.5, w: 600))),
            Pill('${cli['category'] ?? 'tool'}', Tk.accentInk),
          ]),
          const SizedBox(height: 4),
          Text('${cli['description'] ?? ''}', style: ts(13, color: Tk.dim, h: 1.4)),
          const SizedBox(height: 8),
          Text('${cli['install_cmd'] ?? ''}', style: ts(11.5, mono: true, color: Tk.faint)),
          const SizedBox(height: 10),
          // Wrap, not Row: with a large system font or a narrow phone the buttons go to a second line instead of overflowing.
          Wrap(spacing: 8, runSpacing: 4, children: [
            MBtn('Run in cloud', icon: Icons.cloud_queue_rounded, small: true, kind: BtnKind.primary, onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Tk.card,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Tk.rXl))),
                  builder: (_) => AppScope(state: AppScope.read(context), child: _RunSheet(cli: cli)),
                )),
            MBtn('Ask Mugen', icon: Icons.auto_awesome, small: true, onTap: () async {
              final app = AppScope.read(context);
              app.newChat();
              Navigator.pop(context);
              final ok = await app.send('${cli['display_name'] ?? cli['name']} CLI (${cli['install_cmd']}) - how do I use it? Give practical examples.');
              if (!ok && context.mounted) toast(context, 'Choose a model first', error: true);
            }),
          ]),
        ]),
      ),
    );
  }
}

class _RunSheet extends StatefulWidget {
  final Map<String, dynamic> cli;
  const _RunSheet({required this.cli});
  @override
  State<_RunSheet> createState() => _RunSheetState();
}

class _RunSheetState extends State<_RunSheet> {
  late final cmd = TextEditingController(text: '${widget.cli['entry_point'] ?? widget.cli['name']} --help');
  String log = '';
  String stage = '';
  bool busy = false;

  Future<void> _run() async {
    final app = AppScope.read(context);
    final tok = app.settings.ghToken.trim();
    if (tok.isEmpty) {
      toast(context, 'Add your GitHub token in Settings', error: true);
      return;
    }
    setState(() {
      busy = true;
      log = '';
    });
    try {
      final gh = GitHub(tok);
      setState(() => stage = 'Preparing mugen-cli-runner repo');
      final owner = await gh.login();
      final repo = await gh.ensureRepo(owner, 'mugen-cli-runner', public: true);
      final branch = (repo['default_branch'] ?? 'main') as String;
      await gh.pushFiles(owner, 'mugen-cli-runner', branch, {'.github/workflows/run-cli.yml': cliRunnerWorkflow}, 'Mugen: CLI runner');
      await Future.delayed(const Duration(seconds: 3));
      setState(() => stage = 'Starting run');
      final before = await gh.listRuns(owner, 'mugen-cli-runner');
      final lastId = before.isEmpty ? 0 : before.first['id'] as int;
      await gh.dispatch(owner, 'mugen-cli-runner', 'run-cli.yml', {
        'cli_name': '${widget.cli['name']}',
        'install_cmd': '${widget.cli['install_cmd']}',
        'command': cmd.text.trim(),
      }, ref: branch);
      Map<String, dynamic>? run;
      for (var i = 0; i < 30 && run == null; i++) {
        await Future.delayed(const Duration(seconds: 3));
        final runs = await gh.listRuns(owner, 'mugen-cli-runner');
        if (runs.isNotEmpty && (runs.first['id'] as int) != lastId) run = Map<String, dynamic>.from(runs.first);
      }
      if (run == null) throw 'The run did not start';
      while (run!['status'] != 'completed') {
        if (!mounted) return;
        setState(() => stage = 'Running on GitHub (${run!['status']})...');
        await Future.delayed(const Duration(seconds: 6));
        run = await gh.getRun(owner, 'mugen-cli-runner', run['id'] as int);
      }
      final out = await gh.jobLog(owner, 'mugen-cli-runner', run['id'] as int);
      if (!mounted) return;
      setState(() {
        stage = run!['conclusion'] == 'success' ? 'Done' : 'Finished: ${run['conclusion']}';
        log = out;
      });
    } catch (e) {
      if (mounted) setState(() => stage = 'Error: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    // The keyboard lifts the whole sheet (so the visible area ends above it); the navigation bar
    // only matters while the keyboard is closed. Content that does not fit scrolls.
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16 + mq.padding.left, 16, 16 + mq.padding.right, 16 + (keyboard > 0 ? 0 : mq.padding.bottom)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Run ${widget.cli['display_name'] ?? widget.cli['name']}', style: ts(18, w: 600)),
          const SizedBox(height: 4),
          Text('It is installed on a GitHub Actions runner and the command runs there.', style: ts(12.5, color: Tk.faint)),
          const SizedBox(height: 12),
          TextField(
            controller: cmd,
            style: ts(13.5, mono: true),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Tk.field,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.r), borderSide: const BorderSide(color: Tk.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.r), borderSide: const BorderSide(color: Tk.border)),
            ),
          ),
          const SizedBox(height: 12),
          MBtn(busy ? 'Running...' : 'Run', icon: Icons.play_arrow_rounded, kind: BtnKind.primary, wide: true, onTap: busy ? null : _run),
          if (stage.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(stage, style: ts(13, color: Tk.dim))),
          if (log.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(maxHeight: 260),
              width: double.infinity,
              decoration: BoxDecoration(color: Tk.code, borderRadius: BorderRadius.circular(Tk.r), border: Border.all(color: Tk.border)),
              child: Stack(children: [
                SingleChildScrollView(child: SelectableText(log, style: ts(11, mono: true, color: Tk.dim))),
              ]),
            ),
          if (log.isNotEmpty) MBtn('Copy log', icon: Icons.copy_rounded, small: true, kind: BtnKind.ghost, onTap: () => Clipboard.setData(ClipboardData(text: log))),
        ]),
      ),
    );
  }
}
