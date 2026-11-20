import 'package:material_ui/material_ui.dart';
import '../api.dart';
import '../models.dart';
import '../state.dart';
import '../insets.dart';
import '../theme.dart';
import 'scope.dart';
import 'test_dialog.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = app.settings;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Tk.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: MIconBtn(Icons.arrow_back_rounded, color: Tk.text, onTap: () => Navigator.pop(context)),
        title: Text('Settings', style: ts(19, w: 600)),
      ),
      body: ListView(padding: scrollPadding(context, bottom: 40), children: [
        const Caption('AI providers'),
        for (final p in s.providers) _ProviderCard(key: ValueKey(p.id), p: p),
        const SizedBox(height: 4),
        MBtn('Add custom endpoint', icon: Icons.add_link_rounded, wide: true, onTap: () => _addCustom(context, app)),
        const Caption('GitHub (APK builds)'),
        _GithubCard(app: app),
        const Caption('Behaviour'),
        MCard(child: Column(children: [
          _switch('Background work', 'Keep chats and builds running even after the app is closed', s.backgroundMode, (v) {
            s.backgroundMode = v;
            app.saveSettings();
          }),
          const Divider(color: Tk.border, height: 20),
          _switch('Auto-fix failed builds', 'If a build fails, the AI reads the log, fixes the code and pushes again (max 3 tries)', s.autoFix, (v) {
            s.autoFix = v;
            app.saveSettings();
          }),
          const Divider(color: Tk.border, height: 20),
          _switch('Live research by default', 'Search the web for every question', s.research, (v) {
            s.research = v;
            app.saveSettings();
          }),
          const Divider(color: Tk.border, height: 20),
          Row(children: [
            Expanded(child: Text('Creativity (temperature)', style: ts(14.5))),
            Text(s.temperature.toStringAsFixed(1), style: ts(14, w: 600, color: Tk.accentInk)),
          ]),
          Slider(value: s.temperature, min: 0, max: 1.5, divisions: 15, onChanged: (v) {
            s.temperature = v;
            app.saveSettings();
          }),
        ])),
        const Caption('Extra instructions for the AI'),
        _Field(
          label: 'e.g. "Always reply in Hinglish"',
          initial: s.systemExtra,
          lines: 3,
          onChanged: (v) {
            s.systemExtra = v;
            app.saveSettings();
          },
        ),
        const SizedBox(height: 24),
        Center(child: Text('Mugen AI 1.0', style: ts(12.5, color: Tk.faint))),
      ]),
    );
  }

  Widget _switch(String t, String sub, bool v, ValueChanged<bool> f) => Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: ts(14.5, w: 500)), const SizedBox(height: 2), Text(sub, style: ts(12.5, color: Tk.faint))])),
        Switch(value: v, onChanged: f),
      ]);

  Future<void> _addCustom(BuildContext context, AppState app) async {
    final name = TextEditingController();
    final url = TextEditingController(text: 'https://');
    final key = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Tk.card,
        title: Text('Custom endpoint', style: ts(17, w: 600)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Any OpenAI-compatible API (Ollama, LM Studio, Groq, Together, vLLM...)', style: ts(12.5, color: Tk.faint)),
          const SizedBox(height: 12),
          TextField(controller: name, style: ts(14), decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: url, style: ts(14), decoration: const InputDecoration(labelText: 'Base URL (…/v1)')),
          TextField(controller: key, obscureText: true, style: ts(14), decoration: const InputDecoration(labelText: 'API key (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      app.settings.providers.add(ProviderConfig(
        id: 'c${DateTime.now().millisecondsSinceEpoch}',
        kind: ProviderKind.custom,
        name: name.text.trim(),
        baseUrl: url.text.trim(),
        apiKey: key.text.trim(),
      ));
      await app.saveSettings();
    }
  }
}

class _Field extends StatefulWidget {
  final String label;
  final String initial;
  final bool obscure;
  final int lines;
  final ValueChanged<String> onChanged;
  const _Field({required this.label, required this.initial, required this.onChanged, this.obscure = false, this.lines = 1});
  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final c = TextEditingController(text: widget.initial);
  bool hide = true;
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: c,
        obscureText: widget.obscure && hide,
        minLines: widget.lines,
        maxLines: widget.obscure ? 1 : widget.lines,
        onChanged: widget.onChanged,
        style: ts(14.5, mono: widget.obscure),
        decoration: InputDecoration(
          hintText: widget.label,
          hintStyle: ts(14, color: Tk.faint),
          isDense: true,
          filled: true,
          fillColor: Tk.field,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.r), borderSide: const BorderSide(color: Tk.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.r), borderSide: const BorderSide(color: Tk.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Tk.r), borderSide: const BorderSide(color: Tk.accent)),
          suffixIcon: widget.obscure ? MIconBtn(hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, onTap: () => setState(() => hide = !hide)): null,
        ),
      );
}

class _ProviderCard extends StatefulWidget {
  final ProviderConfig p;
  const _ProviderCard({super.key, required this.p});
  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  bool testing = false;
  TestResult? result;

  Future<void> _test() async {
    setState(() {
      testing = true;
      result = null;
    });
    final r = await testConnection(widget.p);
    if (!mounted) return;
    setState(() {
      testing = false;
      result = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final app = AppScope.of(context);
    final n = app.settings.models[p.id]?.length ?? 0;
    final fetching = app.fetching[p.id] ?? false;
    final hint = switch (p.kind) {
      ProviderKind.nvidia => 'nvapi-…  (build.nvidia.com)',
      ProviderKind.gemini => 'AIza…  (aistudio.google.com)',
      ProviderKind.openrouter => 'sk-or-…  (openrouter.ai/keys)',
      ProviderKind.custom => 'API key (optional)',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(p.name, style: ts(16, w: 600))),
            if (n > 0) Pill('$n models', Tk.success),
            const SizedBox(width: 6),
            Switch(value: p.enabled, onChanged: (v) {
              p.enabled = v;
              app.saveSettings();
            }),
            if (p.kind == ProviderKind.custom)
              MIconBtn(Icons.delete_outline, color: Tk.danger, onTap: () {
                app.settings.providers.remove(p);
                app.settings.models.remove(p.id);
                app.saveSettings();
              }),
          ]),
          const SizedBox(height: 8),
          _Field(label: hint, initial: p.apiKey, obscure: true, onChanged: (v) {
            p.apiKey = v.trim();
            app.saveSettings();
          }),
          if (p.kind == ProviderKind.custom) ...[
            const SizedBox(height: 8),
            _Field(label: 'Name', initial: p.name, onChanged: (v) {
              p.name = v;
              app.saveSettings();
            }),
          ],
          if (p.kind == ProviderKind.custom || p.kind == ProviderKind.nvidia) ...[
            const SizedBox(height: 8),
            _Field(label: 'Base URL', initial: p.baseUrl, onChanged: (v) {
              p.baseUrl = v.trim();
              app.saveSettings();
            }),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            MBtn(fetching ? 'Loading...' : (n > 0 ? 'Refresh models' : 'Load models'), icon: Icons.cloud_download_outlined, small: true, onTap: fetching
                ? null
                : () async {
                    final err = await app.refreshModels(p);
                    if (!context.mounted) return;
                    toast(context, err ?? 'Models loaded', error: err != null);
                  }),
            MBtn(testing ? 'Testing...' : 'Test connection', icon: Icons.network_check_rounded, small: true, onTap: testing ? null : _test),
          ]),
          if (result != null) ...[const SizedBox(height: 10), TestResultBox(result!)],
        ]),
      ),
    );
  }
}

class _GithubCard extends StatefulWidget {
  final AppState app;
  const _GithubCard({required this.app});
  @override
  State<_GithubCard> createState() => _GithubCardState();
}

class _GithubCardState extends State<_GithubCard> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.app.settings;
    return MCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Personal access token', style: ts(14.5, w: 600)),
        const SizedBox(height: 4),
        Text('github.com/settings/tokens - classic token, scopes: repo + workflow. Mugen uses it to create a repo, push the code and build the APK with GitHub Actions.', style: ts(12.5, color: Tk.faint, h: 1.4)),
        const SizedBox(height: 10),
        _Field(label: 'ghp_… / github_pat_…', initial: s.ghToken, obscure: true, onChanged: (v) {
          s.ghToken = v.trim();
          s.ghLogin = '';
          widget.app.saveSettings();
        }),
        const SizedBox(height: 10),
        Row(children: [
          MBtn(busy ? 'Checking...' : 'Verify', icon: Icons.verified_outlined, small: true, onTap: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  final err = await widget.app.verifyGithub();
                  if (!mounted) return;
                  setState(() => busy = false);
                  toast(context, err ?? 'Connected as @${s.ghLogin}', error: err != null);
                }),
          const SizedBox(width: 10),
          if (s.ghLogin.isNotEmpty) Pill('@${s.ghLogin}', Tk.success),
        ]),
        const Divider(color: Tk.border, height: 24),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Public repositories', style: ts(14.5, w: 500)),
            Text('Public repos give an APK link anyone can open (private repos need a GitHub login)', style: ts(12.5, color: Tk.faint)),
          ])),
          Switch(value: s.publicRepo, onChanged: (v) {
            s.publicRepo = v;
            widget.app.saveSettings();
          }),
        ]),
      ]),
    );
  }
}
