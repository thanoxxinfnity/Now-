import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../engine.dart';
import '../models.dart';
import '../parser.dart';
import '../theme.dart';
import 'project_card.dart';
import 'scope.dart';
import 'widgets.dart';

class _CodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final text = element.textContent;
    if (!text.contains('\n')) return null; // inline code keeps the default look
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(color: Tk.code, borderRadius: BorderRadius.circular(Tk.r), border: Border.all(color: Tk.border)),
      child: Stack(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 44, 12),
          child: Text(text.trimRight(), style: ts(12.5, mono: true, h: 1.45)),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: MIconBtn(Icons.copy_rounded, size: 34, onTap: () {
            Clipboard.setData(ClipboardData(text: text.trimRight()));
            toast(context, 'Copied');
          }),
        ),
      ]),
    );
  }
}

MarkdownStyleSheet _sheet() => MarkdownStyleSheet(
      p: ts(15, h: 1.5),
      h1: ts(21, w: 650),
      h2: ts(18, w: 650),
      h3: ts(16, w: 600),
      strong: ts(15, w: 650),
      em: ts(15).copyWith(fontStyle: FontStyle.italic),
      listBullet: ts(15, color: Tk.accentInk),
      a: ts(15, color: Tk.accentInk).copyWith(decoration: TextDecoration.underline),
      code: ts(13, mono: true, color: Tk.accentInk).copyWith(backgroundColor: Tk.raised),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
      blockquoteDecoration: const BoxDecoration(border: Border(left: BorderSide(color: Tk.accent, width: 3))),
      blockquote: ts(15, color: Tk.dim),
      tableBorder: TableBorder.all(color: Tk.border),
      tableHead: ts(14, w: 600),
      tableBody: ts(14),
      horizontalRuleDecoration: const BoxDecoration(border: Border(top: BorderSide(color: Tk.border))),
    );

class MessageView extends StatelessWidget {
  final Msg msg;
  final bool last;
  final bool running;
  final String? status;
  const MessageView({super.key, required this.msg, required this.last, required this.running, this.status});

  @override
  Widget build(BuildContext context) {
    if (msg.role == 'user') return _user(context);
    return _assistant(context);
  }

  Widget _user(BuildContext context) {
    final fix = msg.text.startsWith(JobEngine.fixMarker);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 48, top: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: fix ? Tk.raised : Tk.accent.withValues(alpha: 0.18),
          borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(Tk.rXl), topRight: Radius.circular(Tk.rXl), bottomLeft: Radius.circular(Tk.rXl), bottomRight: Radius.circular(4)),
          border: Border.all(color: fix ? Tk.border : Tk.accent.withValues(alpha: 0.35)),
        ),
        child: fix
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.build_circle_outlined, size: 16, color: Tk.warn),
                const SizedBox(width: 8),
                Text('Build log bheja, Mugen fix kar raha hai', style: ts(13.5, color: Tk.dim)),
              ])
            : SelectableText(msg.text, style: ts(15, h: 1.45)),
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.06, curve: Curves.easeOutCubic);
  }

  Widget _assistant(BuildContext context) {
    final app = AppScope.of(context);
    final parsed = parseMessage(msg.text);
    final waiting = msg.text.isEmpty && running;
    final withProject = app.current?.messages.where((m) => m.role == 'assistant' && m.text.contains('<mugen-project')).toList() ?? [];
    final latestProject = withProject.isNotEmpty && withProject.last.id == msg.id;
    return Padding(
      padding: const EdgeInsets.only(top: 16, right: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          MugenOrb(size: 26, active: running && last),
          const SizedBox(width: 8),
          Text('Mugen', style: ts(13.5, w: 600, color: Tk.dim)),
          if (msg.model != null) ...[
            const SizedBox(width: 8),
            Flexible(child: Text(msg.model!.split('/').last, style: ts(11.5, color: Tk.faint), overflow: TextOverflow.ellipsis)),
          ],
        ]),
        const SizedBox(height: 6),
        if (waiting)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Row(children: [
              const TypingDots(),
              if (status != null) ...[const SizedBox(width: 10), Text(status!, style: ts(13, color: Tk.faint))],
            ]),
          ),
        if (parsed.before.trim().isNotEmpty) _md(parsed.before),
        if (parsed.project != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: ProjectCard(block: parsed.project!, latest: latestProject)),
        if (parsed.after.trim().isNotEmpty) _md(parsed.after),
        if (msg.sources.isNotEmpty) _sources(),
        if (msg.text.isNotEmpty && !(running && last))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              MIconBtn(Icons.copy_rounded, size: 32, color: Tk.faint, onTap: () {
                Clipboard.setData(ClipboardData(text: parsed.before + parsed.after));
                toast(context, 'Copied');
              }),
            ]),
          ),
      ]),
    ).animate().fadeIn(duration: 260.ms);
  }

  Widget _md(String t) => MarkdownBody(
        data: t.trim(),
        selectable: false,
        styleSheet: _sheet(),
        builders: {'code': _CodeBuilder()},
        onTapLink: (_, href, __) {
          if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
        },
      );

  Widget _sources() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < msg.sources.length; i++)
            Pressable(
              onTap: () => launchUrl(Uri.parse(msg.sources[i]['url']!), mode: LaunchMode.externalApplication),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 220),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(color: Tk.field, borderRadius: BorderRadius.circular(Tk.r), border: Border.all(color: Tk.border)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${i + 1}', style: ts(11.5, w: 600, color: Tk.accentInk)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(msg.sources[i]['title']!, style: ts(12, color: Tk.dim), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
        ]),
      );
}
