import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../api.dart';
import '../theme.dart';
import 'widgets.dart';

/// The exact outcome of a "Test connection" / "Test model" press: green with
/// what came back, or red with the provider's own error text, selectable and
/// copyable so it can be pasted anywhere.
class TestResultBox extends StatelessWidget {
  final TestResult result;
  const TestResultBox(this.result, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = result.ok ? Tk.success : Tk.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(Tk.r), border: Border.all(color: c.withValues(alpha: 0.45))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(result.ok ? Icons.check_circle_rounded : Icons.error_rounded, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(result.message, style: ts(13.5, color: Tk.text, h: 1.4))),
        ]),
        if (result.detail != null && result.detail!.isNotEmpty) ...[
          const SizedBox(height: 8),
          SelectableText(result.detail!, style: ts(11.5, mono: true, color: Tk.faint, h: 1.35)),
        ],
        const SizedBox(height: 8),
        Row(children: [
          MBtn('Copy', icon: Icons.copy_rounded, small: true, onTap: () {
            Clipboard.setData(ClipboardData(text: [result.message, if (result.detail != null) result.detail!].join('\n')));
            toast(context, 'Copied');
          }),
          const SizedBox(width: 8),
          Text('${result.ms} ms', style: ts(12, color: Tk.faint)),
        ]),
      ]),
    );
  }
}

/// Runs [run] and shows a dialog with a spinner, then the exact result.
Future<void> showTestDialog(BuildContext context, {required String title, required String working, required Future<TestResult> Function() run}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TestDialog(title: title, working: working, run: run),
  );
}

class _TestDialog extends StatefulWidget {
  final String title;
  final String working;
  final Future<TestResult> Function() run;
  const _TestDialog({required this.title, required this.working, required this.run});
  @override
  State<_TestDialog> createState() => _TestDialogState();
}

class _TestDialogState extends State<_TestDialog> {
  late Future<TestResult> _f = widget.run();

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: Tk.card,
        scrollable: true,
        title: Text(widget.title, style: ts(17, w: 600)),
        content: FutureBuilder<TestResult>(
          future: _f,
          builder: (_, snap) {
            if (!snap.hasData) {
              return Row(children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Tk.accentInk)),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.working, style: ts(14, color: Tk.dim))),
              ]);
            }
            return TestResultBox(snap.data!);
          },
        ),
        actions: [
          TextButton(onPressed: () => setState(() => _f = widget.run()), child: const Text('Test again')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      );
}
