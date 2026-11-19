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
  bool showPaid = false;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final providers = app.settings.providers.where((p) => p.enabled).toList();
    pid ??= app.settings.selProvider ?? (providers.isNotEmpty ? providers.first.id : null);
    final p = providers.where((e) => e.id == pid).firstOrNull ?? (providers.isNotEmpty ? providers.first : null);
    final all = p == null ? <ModelInfo>[] : (app.settings.models[p.id] ?? []);
    final f = all.where((m) => q.isEmpty || m.name.toLowerCase().contains(q.toLowerCase()) || m.id.toLowerCase().contains(q.toLowerCase())).toList();
    final free = f.where((m) => !app.settings.isPaid(m)).toList();
    final paid = f.where((m) => app.settings.isPaid(m)).toList();
    final fetching = p != null && (app.fetching[p.id] ?? false);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.4,
      maxChildSize: 0.95,
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
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(children: [
            Expanded(
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
            const SizedBox(width: 10),
            Text('Paid', style: ts(13, color: Tk.dim)),
            Switch(value: showPaid, onChanged: (v) => setState(() => showPaid = v)),
          ]),
        ),
        Expanded(
          child: p == null
              ? const _Hint('Settings me koi provider on karo.')
              : all.isEmpty
                  ? _Hint(p.apiKey.isEmpty && p.kind != ProviderKind.openrouter ? 'Pehle Settings me ${p.name} ki API key daalo, phir refresh dabao.' : 'Refresh dabao - models live load honge.')
                  : ListView(controller: sc, padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
                      Caption('Free  -  ${free.length}'),
                      ...free.map((m) => _row(app, m)),
                      if (showPaid) ...[
                        Caption('Paid  -  ${paid.length}'),
                        ...paid.map((m) => _row(app, m)),
                      ] else if (paid.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text('${paid.length} paid models hidden. "Paid" switch on karo dekhne ke liye.', style: ts(12.5, color: Tk.faint)),
                        ),
                    ]),
        ),
      ]),
    );
  }

  Widget _row(AppState app, ModelInfo m) {
    final sel = app.settings.selProvider == m.providerId && app.settings.selModel == m.id;
    final paid = app.settings.isPaid(m);
    return Pressable(
      onTap: () async {
        await app.selectModel(m);
        if (mounted) Navigator.pop(context);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        decoration: BoxDecoration(
          color: sel ? Tk.accentSoft : Tk.field,
          borderRadius: BorderRadius.circular(Tk.r),
          border: Border.all(color: sel ? Tk.accent.withValues(alpha: 0.6) : Tk.border),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.name, style: ts(14, w: 500, color: sel ? Tk.accentInk : Tk.text), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(m.id + (m.context != null ? '  -  ${(m.context! / 1000).round()}k ctx' : ''), style: ts(11.5, mono: true, color: Tk.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('paid', style: ts(10.5, color: Tk.faint)),
            SizedBox(
              height: 26,
              child: Checkbox(
                value: paid,
                visualDensity: VisualDensity.compact,
                activeColor: Tk.warn,
                side: const BorderSide(color: Tk.faint, width: 1.4),
                onChanged: (v) => app.setPaid(m, v ?? false),
              ),
            ),
          ]),
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
