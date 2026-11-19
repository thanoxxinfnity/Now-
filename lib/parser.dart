/// Parsed view of an assistant reply. The model emits a project like:
///
///   <mugen-project name="todo_app" title="Todo App">
///   <file path="lib/main.dart">...</file>
///   </mugen-project>
class ProjectBlock {
  final String name;
  final String title;
  final Map<String, String> files;
  final bool complete; // closing tag seen
  final String? openFile; // file currently being streamed
  ProjectBlock(this.name, this.title, this.files, this.complete, this.openFile);
}

class ParsedMsg {
  final String before;
  final ProjectBlock? project;
  final String after;
  ParsedMsg(this.before, this.project, this.after);
}

final _open = RegExp(r'<mugen-project([^>]*)>');
final _attr = RegExp(r'(\w+)="([^"]*)"');

ParsedMsg parseMessage(String raw) {
  final m = _open.firstMatch(raw);
  if (m == null) {
    // hide a half-typed opening tag while streaming
    final cut = raw.lastIndexOf('<mugen');
    if (cut >= 0 && !raw.substring(cut).contains('>')) return ParsedMsg(raw.substring(0, cut), null, '');
    return ParsedMsg(raw, null, '');
  }
  final attrs = {for (final a in _attr.allMatches(m.group(1)!)) a.group(1)!: a.group(2)!};
  final before = raw.substring(0, m.start);
  final endIdx = raw.indexOf('</mugen-project>', m.end);
  final complete = endIdx >= 0;
  final body = complete ? raw.substring(m.end, endIdx) : raw.substring(m.end);
  final after = complete ? raw.substring(endIdx + '</mugen-project>'.length) : '';

  final files = <String, String>{};
  String? openFile;
  var i = 0;
  final fileOpen = RegExp(r'<file\s+path="([^"]+)"\s*>');
  while (true) {
    final fm = fileOpen.firstMatch(body.substring(i));
    if (fm == null) break;
    final path = fm.group(1)!;
    final start = i + fm.end;
    final close = body.indexOf('</file>', start);
    if (close < 0) {
      files[path] = _clean(body.substring(start));
      openFile = path;
      break;
    }
    files[path] = _clean(body.substring(start, close));
    i = close + '</file>'.length;
  }
  return ParsedMsg(
    before,
    ProjectBlock(attrs['name'] ?? 'mugen_app', attrs['title'] ?? attrs['name'] ?? 'App', files, complete, openFile),
    after,
  );
}

/// Strips a leading newline and an accidental markdown fence around file content.
String _clean(String s) {
  var t = s;
  if (t.startsWith('\n')) t = t.substring(1);
  final fence = RegExp(r'^\s*```[a-zA-Z]*\n');
  if (fence.hasMatch(t)) {
    t = t.replaceFirst(fence, '');
    final end = t.lastIndexOf('```');
    if (end >= 0) t = t.substring(0, end);
  }
  return t.trimRight().isEmpty ? t : '${t.trimRight()}\n';
}

String sanitizeRepoName(String s) {
  final r = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return r.isEmpty ? 'mugen-app' : r;
}

String dartPackageName(String s) {
  var r = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  if (r.isEmpty || RegExp(r'^[0-9]').hasMatch(r)) r = 'app_$r';
  return r;
}
