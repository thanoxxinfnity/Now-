import 'package:material_ui/material_ui.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import 'scope.dart';
import 'widgets.dart';

void showModelPicker(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Tk.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Tk.rXl))),
    builder: (_) => AppScope(state: AppScope.read(context), child: const _Picker()),
  );
}

class _Picker extends StatefulWidget {
  const _Picker();
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String? pid;
  String q = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final providers = app.settings.providers.where((p) => p.enabled).toList();
    pid ??= app.settings.selProvider ?? (providers.isNotEmpty ? providers.first.id : null);
    final p = providers.where((e) => e.id == pid).firstOrNull ?? (providers.isNotEmpty ? providers.first : null);
    final all = p == null ? <ModelInfo>[] : (app.settings.models[p.id] ?? []);
    final ql = q.trim().toLowerCase();
    final f = all.where((m) => ql.isEmpty || m.name.toLowerCase().contains(ql) || m.id.toLowerCase().contains(ql)).toList();
    final exact = all.any((m) => m.id.toLowerCase() == ql);
    final fetching = p != null && (app.fetching[p.id] ?? false);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 1,
      builder: (_, sc) => Column(children: [
        Container(margin: const EdgeInsets.only(top: 8), width: 38, height: 4, decoration: BoxDecoration(color: Tk.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Expanded(child: Text('Choose model', style: ts(18, w: 600))),
            if (p != null)
              fetching
                  ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Tk.accentInk)))
                  : MIconBtn(Icons.refresh_rounded, onTap: () async {
                      final err = await app.refreshModels(p);
                      if (err != null && context.mounted) toast(context, err, error: true);
                    }),
          ]),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final pr in providers)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Pressable(
                    onTap: () => setState(() => pid = pr.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: pr.id == p?.id ? Tk.accentSoft : Tk.field,
                        borderRadius: BorderRadius.circular(Tk.r),
                        border: Border.all(color: pr.id == p?.id ? Tk.accent.withValues(alpha: 0.6) : Tk.border),
                      ),
                      child: Text(pr.name, style: ts(13.5, w: 500, color: pr.id == p?.id ? Tk.accentInk : Tk.dim)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: TextField(
            onChanged: (v) => setState(() => q = v),
            style: ts(14),
            decoration: InputDecoration(
              hintText: 'Search ${all.length} models',
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
          child: p == null
              ? const _Hint('Turn on a provider in Settings.')
              : ListView(controller: sc, padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
                  if (ql.isNotEmpty && !exact)
                    _row(app, ModelInfo(id: q.trim(), name: 'Use "${q.trim()}" as model ID', providerId: p.id), manual: true),
                  if (all.isEmpty)
                    _Hint(p.apiKey.isEmpty && p.kind != ProviderKind.openrouter
                        ? 'Add your ${p.name} API key in Settings, then tap refresh.'
                        : 'Tap refresh to load the live model list, or type a model ID above.'),
                  ...f.map((m) => _row(app, m)),
                ]),
        ),
      ]),
    );
  }

  Widget _row(AppState app, ModelInfo m, {bool manual = false}) {
    final sel = !manual && app.settings.selProvider == m.providerId && app.settings.selModel == m.id;
    return Pressable(
      onTap: () async {
        await app.selectModel(m);
        if (mounted) Navigator.pop(context);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: sel ? Tk.accentSoft : Tk.field,
          borderRadius: BorderRadius.circular(Tk.r),
          border: Border.all(color: sel ? Tk.accent.withValues(alpha: 0.6) : Tk.border),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: ts(14, w: 500, color: sel ? Tk.accentInk : Tk.text), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (!manual) Text(m.id + (m.context != null ? '  -  ${(m.context! / 1000).round()}k ctx' : ''), style: ts(11.5, mono: true, color: Tk.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (sel) const Icon(Icons.check_rounded, size: 18, color: Tk.accentInk),
        ]),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String t;
  const _Hint(this.t);
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(30), child: Text(t, textAlign: TextAlign.center, style: ts(14, color: Tk.faint))));
}
