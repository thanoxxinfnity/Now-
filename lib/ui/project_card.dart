import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models.dart';
import '../parser.dart';
import '../theme.dart';
import 'scope.dart';
import 'widgets.dart';

/// Code "copy box": one file, collapsed by default, with copy.
class FileBox extends StatefulWidget {
  final String path;
  final String code;
  final bool streaming;
  const FileBox({super.key, required this.path, required this.code, this.streaming = false});
  @override
  State<FileBox> createState() => _FileBoxState();
}

class _FileBoxState extends State<FileBox> {
  bool open = false;
  @override
  Widget build(BuildContext context) {
    final lines = '\n'.allMatches(widget.code).length + 1;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: Tk.code,
        borderRadius: BorderRadius.circular(Tk.r),
        border: Border.all(color: Tk.border),
      ),
      child: Column(children: [
        Pressable(
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(children: [
              const Icon(Icons.description_outlined, size: 15, color: Tk.accentInk),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.path, style: ts(12.5, mono: true, color: Tk.dim), overflow: TextOverflow.ellipsis)),
              if (widget.streaming)
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: Tk.accentInk))
              else
                Text('$lines lines', style: ts(11.5, color: Tk.faint)),
              MIconBtn(Icons.copy_rounded, size: 32, onTap: () {
                Clipboard.setData(ClipboardData(text: widget.code));
                toast(context, 'Copied ${widget.path}');
              }),
              AnimatedRotation(turns: open ? 0.5 : 0, duration: const Duration(milliseconds: 200), child: const Icon(Icons.expand_more, size: 18, color: Tk.faint)),
              const SizedBox(width: 6),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: open
              ? Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 280),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tk.border))),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(widget.code, style: ts(12, mono: true, color: Tk.text, h: 1.45)),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

String _allCode(Map<String, String> files) => files.entries.map((e) => '// ===== ${e.key} =====\n${e.value}').join('\n');

Future<void> shareZip(BuildContext context, String name, Map<String, String> files) async {
  final ar = Archive();
  for (final e in files.entries) {
    final bytes = utf8.encode(e.value);
    ar.addFile(ArchiveFile(e.key, bytes.length, bytes));
  }
  final data = ZipEncoder().encode(ar);
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$name.zip');
  await f.writeAsBytes(data);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: '$name.zip'));
}

/// The generated-project card: files, copy / zip / build, and the live build timeline.
class ProjectCard extends StatelessWidget {
  final ProjectBlock block;
  final bool latest; // only the newest project message drives the build UI
  const ProjectCard({super.key, required this.block, required this.latest});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final pr = latest ? app.current?.project : null;
    final building = pr != null && (pr.status == 'pushing' || pr.status == 'building');
    final files = pr != null && block.complete ? pr.files : block.files;
    return MCard(
      padding: const EdgeInsets.all(12),
      border: building ? Tk.accent.withValues(alpha: 0.7) : Tk.border,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: Tk.accentSoft, borderRadius: BorderRadius.circular(Tk.r)),
            child: const Icon(Icons.rocket_launch_outlined, size: 18, color: Tk.accentInk),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(block.title, style: ts(15.5, w: 600), overflow: TextOverflow.ellipsis),
              Text(block.complete ? '${block.files.length} files written' : 'Writing code... ${block.files.length} files', style: ts(12.5, color: Tk.faint)),
            ]),
          ),
          if (pr != null && pr.status == 'success') const Pill('APK READY', Tk.success),
          if (building) const Pill('BUILDING', Tk.accentInk),
          if (pr != null && pr.status == 'failed') const Pill('FAILED', Tk.danger),
          if (!block.complete) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Tk.accentInk)),
        ]),
        const SizedBox(height: 6),
        ...block.files.entries.map((e) => FileBox(path: e.key, code: e.value, streaming: !block.complete && e.key == block.openFile)),
        if (block.complete) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            MBtn('Copy all', icon: Icons.copy_all_rounded, small: true, onTap: () {
              Clipboard.setData(ClipboardData(text: _allCode(files)));
              toast(context, 'All code copied');
            }),
            MBtn('.zip', icon: Icons.folder_zip_outlined, small: true, onTap: () => shareZip(context, block.name, files)),
            if (latest && pr != null)
              MBtn(pr.status == 'success' ? 'Rebuild APK' : 'Build APK',
                  icon: Icons.android_rounded, small: true, kind: BtnKind.primary, onTap: building ? null : app.pushBuild),
          ]),
        ],
        if (pr != null && pr.steps.isNotEmpty) _BuildTimeline(pr: pr),
      ]),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, curve: Curves.easeOutCubic);
  }
}

class _BuildTimeline extends StatelessWidget {
  final Project pr;
  const _BuildTimeline({required this.pr});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final active = pr.status == 'pushing' || pr.status == 'building';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(height: 1, color: Tk.border),
        const SizedBox(height: 12),
        for (var i = 0; i < pr.steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(children: [
              if (i == pr.steps.length - 1 && active)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Tk.accentInk))
              else
                Icon(
                    i == pr.steps.length - 1 && pr.status == 'failed' ? Icons.cancel : Icons.check_circle,
                    size: 16,
                    color: i == pr.steps.length - 1 && pr.status == 'failed' ? Tk.danger : Tk.success)
                    .animate()
                    .scale(duration: 250.ms, curve: Curves.easeOutBack),
              const SizedBox(width: 10),
              Expanded(child: Text(pr.steps[i], style: ts(13.5, color: i == pr.steps.length - 1 ? Tk.text : Tk.dim))),
            ]).animate().fadeIn(duration: 220.ms).slideX(begin: -0.03),
          ),
        if (active)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Keeps running in the background, even if you close the app.', style: ts(12, color: Tk.faint)),
          ),
        if (pr.status == 'success' && pr.apkUrl != null) ...[
          const SizedBox(height: 8),
          MBtn('Download APK', icon: Icons.download_rounded, kind: BtnKind.primary, wide: true, onTap: () => launchUrl(Uri.parse(pr.apkUrl!), mode: LaunchMode.externalApplication))
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(duration: 1800.ms, color: Colors.white24),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: MBtn('Copy link', icon: Icons.link_rounded, small: true, onTap: () {
              Clipboard.setData(ClipboardData(text: pr.apkUrl!));
              toast(context, 'APK link copied');
            })),
            const SizedBox(width: 8),
            if (pr.repoUrl != null)
              Expanded(child: MBtn('Repository', icon: Icons.code_rounded, small: true, onTap: () => launchUrl(Uri.parse(pr.repoUrl!), mode: LaunchMode.externalApplication))),
          ]),
        ],
        if (pr.status == 'failed') ...[
          if (pr.log != null)
            Container(
              margin: const EdgeInsets.only(top: 6, bottom: 10),
              padding: const EdgeInsets.all(10),
              constraints: const BoxConstraints(maxHeight: 130),
              width: double.infinity,
              decoration: BoxDecoration(color: Tk.code, borderRadius: BorderRadius.circular(Tk.r), border: Border.all(color: Tk.danger.withValues(alpha: 0.4))),
              child: SingleChildScrollView(child: Text(pr.log!.length > 700 ? pr.log!.substring(pr.log!.length - 700) : pr.log!, style: ts(11, mono: true, color: Tk.dim))),
            ),
          Row(children: [
            Expanded(child: MBtn('Fix with AI', icon: Icons.auto_fix_high_rounded, kind: BtnKind.primary, small: true, onTap: app.isRunning(app.current?.id) ? null : app.fixWithAi)),
            const SizedBox(width: 8),
            Expanded(child: MBtn('Retry build', icon: Icons.refresh_rounded, small: true, onTap: app.pushBuild)),
          ]),
        ],
      ]),
    );
  }
}
