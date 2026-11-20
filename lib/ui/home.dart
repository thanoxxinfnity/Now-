import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import 'cli_hub.dart';
import 'message_view.dart';
import 'model_picker.dart';
import 'scope.dart';
import 'settings.dart';
import 'techniques.dart';
import 'widgets.dart';

Route<T> fadeRoute<T>(Widget w) => PageRouteBuilder<T>(
      pageBuilder: (_, __, ___) => w,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    );

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scroll = ScrollController();
  final _ctrl = TextEditingController();
  final _scaffold = GlobalKey<ScaffoldState>();
  int _lastLen = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max - _scroll.offset < 260) _scroll.animateTo(max, duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
    });
  }

  Future<void> _send(String text) async {
    final app = AppScope.read(context);
    final t = text.trim();
    if (t.isEmpty) return;
    final ok = await app.send(t);
    if (!ok) {
      if (!mounted) return;
      toast(context, 'Choose a model first (add an API key in Settings).');
      showModelPicker(context);
      return;
    }
    _ctrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final chat = app.current;
    final running = app.isRunning(chat?.id);
    final len = chat?.messages.fold<int>(0, (a, m) => a + m.text.length) ?? 0;
    if (len != _lastLen) {
      _lastLen = len;
      _toBottom();
    }
    if (app.error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || app.error == null) return;
        toast(context, app.error!, error: true);
        app.clearError();
      });
    }
    return Scaffold(
      key: _scaffold,
      drawer: _HistoryDrawer(onOpenSettings: () => Navigator.push(context, fadeRoute(const SettingsScreen()))),
      body: SafeArea(
        child: Stack(children: [
          if (chat == null) const Positioned.fill(child: AuraBackground()),
          Column(children: [
            _topBar(app, chat, running),
            Expanded(child: chat == null ? _empty() : _list(app, chat, running)),
            _Composer(controller: _ctrl, running: running, onSend: _send),
          ]),
          Positioned.fill(child: TechniqueOverlay(trigger: app.successTick)),
        ]),
      ),
    );
  }

  Widget _topBar(AppState app, Chat? chat, bool running) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 8, 4),
        child: Row(children: [
          MIconBtn(Icons.menu_rounded, onTap: () => _scaffold.currentState?.openDrawer()),
          const SizedBox(width: 2),
          if (chat != null) MugenOrb(size: 28, active: running),
          if (chat != null) const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(chat?.title ?? 'Mugen', key: ValueKey(chat?.title), style: ts(chat == null ? 19 : 16, w: 600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          MIconBtn(Icons.edit_square, onTap: app.newChat),
        ]),
      );

  Widget _empty() {
    const sugg = [
      'Build me a todo app with a dark theme and smooth animations',
      'Make a premium-looking calculator app',
      "Research today's latest AI news for me",
      'Explain state management in Flutter',
    ];
    return LayoutBuilder(
      builder: (_, c) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const TechniqueStage(height: 260).animate().fadeIn(duration: 700.ms).scale(begin: const Offset(0.7, 0.7), curve: Curves.easeOutBack, duration: 800.ms),
            const SizedBox(height: 10),
            Text('Mugen', style: ts(34, w: 650)).animate().fadeIn(delay: 200.ms, duration: 500.ms).slideY(begin: 0.2),
            const SizedBox(height: 6),
            Text('Chat with me, or say "build an app" and get an APK.', textAlign: TextAlign.center, style: ts(15, color: Tk.dim))
                .animate()
                .fadeIn(delay: 350.ms, duration: 500.ms),
            const SizedBox(height: 28),
            for (var i = 0; i < sugg.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Pressable(
                  onTap: () => _send(sugg[i]),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(color: Tk.card.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(Tk.rLg), border: Border.all(color: Tk.border)),
                    child: Row(children: [
                      Expanded(child: Text(sugg[i], style: ts(14, color: Tk.dim))),
                      const Icon(Icons.north_east_rounded, size: 15, color: Tk.faint),
                    ]),
                  ),
                ).animate().fadeIn(delay: (500 + i * 90).ms, duration: 400.ms).slideY(begin: 0.25, curve: Curves.easeOutCubic),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _list(AppState app, Chat chat, bool running) => ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: chat.messages.length,
        itemBuilder: (_, i) {
          final m = chat.messages[i];
          final last = i == chat.messages.length - 1;
          return MessageView(key: ValueKey(m.id), msg: m, last: last, running: running, status: app.status[chat.id]);
        },
      );
}

class _Composer extends StatefulWidget {
  final TextEditingController controller;
  final bool running;
  final ValueChanged<String> onSend;
  const _Composer({required this.controller, required this.running, required this.onSend});
  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _has = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_chg);
  }

  void _chg() {
    final h = widget.controller.text.trim().isNotEmpty;
    if (h != _has) setState(() => _has = h);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_chg);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = app.selModel;
    final canSend = _has && !widget.running;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
      decoration: BoxDecoration(
        color: Tk.field,
        borderRadius: BorderRadius.circular(Tk.rXl),
        border: Border.all(color: widget.running ? Tk.accent.withValues(alpha: 0.6) : Tk.border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: widget.controller,
          minLines: 1,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
          style: ts(15.5),
          cursorColor: Tk.accent,
          decoration: InputDecoration(
            hintText: 'Ask anything or build an app...',
            hintStyle: ts(15.5, color: Tk.faint),
            border: InputBorder.none,
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        Row(children: [
          Pressable(
            onTap: () {
              app.settings.research = !app.settings.research;
              app.saveSettings();
              HapticFeedback.selectionClick();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: app.settings.research ? Tk.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(Tk.r),
                border: Border.all(color: app.settings.research ? Tk.accent.withValues(alpha: 0.6) : Tk.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.public_rounded, size: 15, color: app.settings.research ? Tk.accentInk : Tk.faint),
                const SizedBox(width: 5),
                Text('Research', style: ts(12.5, w: 500, color: app.settings.research ? Tk.accentInk : Tk.faint)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Pressable(
              onTap: () => showModelPicker(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(Tk.r), border: Border.all(color: Tk.border)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_awesome, size: 14, color: Tk.accentInk),
                  const SizedBox(width: 5),
                  Flexible(child: Text(m?.name ?? 'Choose model', style: ts(12.5, w: 500, color: Tk.dim), overflow: TextOverflow.ellipsis, maxLines: 1)),
                  const Icon(Icons.expand_more, size: 15, color: Tk.faint),
                ]),
              ),
            ),
          ),
          const Spacer(),
          Pressable(
            onTap: canSend ? () => widget.onSend(widget.controller.text) : null,
            haptic: true,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: canSend ? Tk.accent : Tk.raised,
                borderRadius: BorderRadius.circular(19),
                boxShadow: canSend ? [BoxShadow(color: Tk.accent.withValues(alpha: 0.45), blurRadius: 14)] : null,
              ),
              child: widget.running
                  ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: Tk.accentInk))
                  : Icon(Icons.arrow_upward_rounded, size: 20, color: canSend ? Colors.white : Tk.faint),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _HistoryDrawer extends StatefulWidget {
  final VoidCallback onOpenSettings;
  const _HistoryDrawer({required this.onOpenSettings});
  @override
  State<_HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends State<_HistoryDrawer> {
  String q = '';

  Future<void> _rename(AppState app, Chat c) async {
    final t = TextEditingController(text: c.title);
    final r = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Tk.card,
        title: Text('Rename chat', style: ts(17, w: 600)),
        content: TextField(controller: t, autofocus: true, style: ts(15)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, t.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (r != null && r.isNotEmpty) app.renameChat(c.id, r);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final items = app.history.where((c) => q.isEmpty || c.title.toLowerCase().contains(q.toLowerCase())).toList();
    return Drawer(
      backgroundColor: Tk.chrome,
      width: 310,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
            child: Row(children: [
              const MugenOrb(size: 34),
              const SizedBox(width: 10),
              Text('Mugen', style: ts(20, w: 650)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: MBtn('New chat', icon: Icons.add_rounded, kind: BtnKind.primary, wide: true, onTap: () {
              app.newChat();
              Navigator.pop(context);
            }),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              style: ts(14),
              decoration: InputDecoration(
                hintText: 'Search history',
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
            child: items.isEmpty
                ? Center(child: Text('No history yet', style: ts(14, color: Tk.faint)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final c = items[i];
                      final sel = app.current?.id == c.id;
                      return Dismissible(
                        key: ValueKey(c.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Tk.danger.withValues(alpha: 0.25),
                            child: const Icon(Icons.delete_outline, color: Tk.danger)),
                        onDismissed: (_) => app.deleteChat(c.id),
                        child: Pressable(
                          onTap: () {
                            app.openChat(c.id);
                            Navigator.pop(context);
                          },
                          onLongPress: () => _rename(app, c),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(color: sel ? Tk.accentSoft : Colors.transparent, borderRadius: BorderRadius.circular(Tk.r)),
                            child: Row(children: [
                              Icon(c.project != null ? Icons.rocket_launch_outlined : Icons.chat_bubble_outline_rounded, size: 16, color: sel ? Tk.accentInk : Tk.faint),
                              const SizedBox(width: 10),
                              Expanded(child: Text(c.title, style: ts(14, color: sel ? Tk.text : Tk.dim), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              if (app.isRunning(c.id)) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: Tk.accentInk)),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Tk.border),
          _tile(Icons.terminal_rounded, 'Mugen CLI hub', () {
            Navigator.pop(context);
            Navigator.push(context, fadeRoute(const CliHubScreen()));
          }),
          _tile(Icons.settings_outlined, 'Settings', () {
            Navigator.pop(context);
            widget.onOpenSettings();
          }),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  Widget _tile(IconData i, String t, VoidCallback f) => Pressable(
        onTap: f,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [Icon(i, size: 19, color: Tk.dim), const SizedBox(width: 14), Expanded(child: Text(t, style: ts(15, color: Tk.text), maxLines: 1, overflow: TextOverflow.ellipsis))]),
        ),
      );
}
