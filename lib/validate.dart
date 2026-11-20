import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart' show ClientFactory, defaultClientFactory;

/// Checks a generated Flutter project BEFORE it is pushed to GitHub, so a typo
/// does not cost a 5 minute Actions build. Pure Dart: runs in the background isolate.
///
/// What it looks at: the pubspec (name, SDK, dependencies, assets), `lib/main.dart`,
/// every `import` / `export` / `part` (a `package:` import needs a dependency, a
/// relative one needs the file), balanced brackets and strings in every .dart file,
/// placeholder text, APIs that no longer compile, and paths that must not be pushed.
enum Severity { error, warning }

class Issue {
  final Severity severity;
  final String file;
  final String message;
  const Issue(this.severity, this.file, this.message);
  bool get isError => severity == Severity.error;
  @override
  String toString() => '${isError ? 'ERROR' : 'warning'} $file: $message';
}

class Pubspec {
  String? name;
  String? sdkConstraint;
  bool hasFlutterSdk = false;
  final Map<String, String> deps = {}; // name -> constraint text ('' for sdk / path / git entries)
  final Set<String> devDeps = {};
  final List<String> assets = [];
  final List<String> fontAssets = [];
}

String _stripComment(String l) {
  final i = l.indexOf(RegExp(r'(^|\s)#'));
  return (i < 0 ? l : l.substring(0, i)).trimRight();
}

/// A small reader for the parts of pubspec.yaml this app cares about. It does
/// not need to be a full YAML parser: a pubspec is a handful of indented lists.
Pubspec parsePubspec(String text) {
  final ps = Pubspec();
  String? top;
  int? childIndent;
  String? sub; // the dependency whose map we are inside
  int? assetsIndent;
  final lines = const LineSplitter().convert(text);
  for (final raw in lines) {
    final line = _stripComment(raw);
    if (line.trim().isEmpty) continue;
    final indent = line.length - line.trimLeft().length;
    final t = line.trim();
    if (indent == 0) {
      final m = RegExp(r'^([A-Za-z_][\w-]*)\s*:\s*(.*)$').firstMatch(t);
      top = m?.group(1);
      childIndent = null;
      sub = null;
      assetsIndent = null;
      if (top == 'name') ps.name = _unquote(m!.group(2)!);
      continue;
    }
    childIndent ??= indent;
    // - asset: lists under flutter: (fonts) and plain "- path" lists under assets:
    if (top == 'flutter') {
      final am = RegExp(r'^-?\s*asset\s*:\s*(.+)$').firstMatch(t);
      if (am != null) {
        ps.fontAssets.add(_unquote(am.group(1)!));
        continue;
      }
      if (RegExp(r'^assets\s*:\s*$').hasMatch(t)) {
        assetsIndent = indent;
        continue;
      }
      if (assetsIndent != null) {
        if (indent <= assetsIndent) {
          assetsIndent = null;
        } else {
          final lm = RegExp(r'^-\s*(.+)$').firstMatch(t);
          if (lm != null && !lm.group(1)!.contains(':')) {
            ps.assets.add(_unquote(lm.group(1)!));
            continue;
          }
        }
      }
    }
    if (top == 'environment' && indent == childIndent) {
      final m = RegExp(r'^sdk\s*:\s*(.+)$').firstMatch(t);
      if (m != null) ps.sdkConstraint = _unquote(m.group(1)!);
    }
    if (top == 'dependencies' || top == 'dev_dependencies' || top == 'dependency_overrides') {
      if (indent == childIndent) {
        final m = RegExp(r'^([A-Za-z_][\w.-]*)\s*:\s*(.*)$').firstMatch(t);
        if (m == null) continue;
        final name = m.group(1)!;
        final rest = _unquote(m.group(2)!);
        sub = name;
        if (top == 'dependencies') {
          ps.deps[name] = rest;
        } else if (top == 'dev_dependencies') {
          ps.devDeps.add(name);
        }
      } else if (sub != null && indent > childIndent) {
        if (sub == 'flutter' && RegExp(r'^sdk\s*:\s*flutter').hasMatch(t) && top == 'dependencies') ps.hasFlutterSdk = true;
        if (top == 'dependencies' && RegExp(r'^(sdk|path|git|hosted)\s*:').hasMatch(t)) ps.deps[sub] = '';
      }
    }
  }
  return ps;
}

String _unquote(String s) {
  final t = s.trim();
  if (t.length >= 2 && ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'")))) return t.substring(1, t.length - 1);
  return t;
}

// ---------------------------------------------------------------- lexer: brackets and strings

/// The first structural problem of a Dart file (an unclosed or unmatched bracket,
/// an unterminated string or comment), or null. Strings (raw, triple-quoted,
/// with `${...}` interpolation) and comments (nested block comments too) are skipped properly.
String? firstBracketProblem(String src) {
  final stack = <_Frame>[];
  _Str? str;
  var i = 0, line = 1;
  final n = src.length;
  bool isIdent(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);
  while (i < n) {
    final c = src[i];
    if (c == '\n') line++;
    if (str != null) {
      if (c == '\\' && !str.raw) {
        if (i + 1 < n && src[i + 1] == '\n') line++;
        i += 2;
        continue;
      }
      if (!str.raw && c == r'$' && i + 1 < n && src[i + 1] == '{') {
        stack.add(_Frame.interp(str, line));
        str = null;
        i += 2;
        continue;
      }
      if (c == str.quote) {
        if (str.triple) {
          if (src.startsWith(str.quote * 3, i)) {
            str = null;
            i += 3;
            continue;
          }
        } else {
          str = null;
          i++;
          continue;
        }
      }
      if (c == '\n' && !str.triple) return 'a string that starts on line ${str.line} is not closed before the end of the line';
      i++;
      continue;
    }
    // code
    if (c == '/' && i + 1 < n && src[i + 1] == '/') {
      while (i < n && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < n && src[i + 1] == '*') {
      final start = line;
      var depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (src[i] == '\n') line++;
        if (src.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (src.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          i++;
        }
      }
      if (depth > 0) return 'a comment that starts on line $start is never closed';
      continue;
    }
    if (c == "'" || c == '"') {
      final raw = i > 0 && src[i - 1] == 'r' && (i < 2 || !isIdent(src[i - 2]));
      final triple = src.startsWith(c * 3, i);
      str = _Str(c, triple, raw, line);
      i += triple ? 3 : 1;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') {
      stack.add(_Frame.bracket(c, line));
    } else if (c == ')' || c == ']' || c == '}') {
      if (stack.isEmpty) return "an extra '$c' on line $line has no opening bracket";
      final top = stack.removeLast();
      if (top.interp != null) {
        if (c != '}') return "a '\${' on line ${top.line} is closed with '$c' on line $line";
        str = top.interp;
        i++;
        continue;
      }
      final want = switch (top.char) { '(' => ')', '[' => ']', _ => '}' };
      if (c != want) return "'${top.char}' opened on line ${top.line} is closed with '$c' on line $line";
    }
    i++;
  }
  if (str != null) return 'a string that starts on line ${str.line} is never closed';
  if (stack.isNotEmpty) {
    final top = stack.last;
    return top.interp != null ? "a '\${' on line ${top.line} is never closed" : "'${top.char}' opened on line ${top.line} is never closed";
  }
  return null;
}

class _Str {
  final String quote;
  final bool triple;
  final bool raw;
  final int line;
  _Str(this.quote, this.triple, this.raw, this.line);
}

class _Frame {
  final String? char;
  final _Str? interp;
  final int line;
  _Frame.bracket(this.char, this.line) : interp = null;
  _Frame.interp(this.interp, this.line) : char = null;
}

// ---------------------------------------------------------------- the checks

final _importRe = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''', multiLine: true);

String _dirOf(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

String? _resolve(String fromFile, String rel) {
  final parts = <String>[...(_dirOf(fromFile).isEmpty ? <String>[] : _dirOf(fromFile).split('/'))];
  for (final seg in rel.split('/')) {
    if (seg == '..') {
      if (parts.isEmpty) return null;
      parts.removeLast();
    } else if (seg != '.' && seg.isNotEmpty) {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

/// Packages that cannot work here: they need code generation (no build step runs) or a newer Android SDK.
const _blockedDeps = {
  'permission_handler': 'it needs compileSdk 37 or newer, which the build does not have',
  'build_runner': 'no code generation step runs in the build',
  'freezed': 'it needs build_runner code generation',
  'freezed_annotation': 'it needs build_runner code generation',
  'json_serializable': 'it needs build_runner code generation',
  'json_annotation': 'it needs build_runner code generation',
  'hive_generator': 'it needs build_runner code generation',
  'isar_generator': 'it needs build_runner code generation',
  'drift_dev': 'it needs build_runner code generation',
  'injectable_generator': 'it needs build_runner code generation',
};

/// Needs native setup (keys, google-services.json) that the build cannot provide.
bool _needsNativeSetup(String dep) => dep.startsWith('firebase_') || const {'google_mobile_ads', 'google_maps_flutter', 'camera', 'cloud_firestore'}.contains(dep);

final _placeholderRe = RegExp(r'(//|/\*)\s*(\.\.\.|…)|rest of (the )?(code|file|app|widget|class|implementation)|same as (before|above)|(code|implementation) (goes )?here|your code here|implement (me|this|later)|existing code (stays|remains)', caseSensitive: false);
final _todoRe = RegExp(r'\bTODO\b|\bFIXME\b');

/// Everything wrong with [files] (path -> content). [expectedPackage] is the name
/// the model gave the project; the pubspec has to carry the same name.
List<Issue> validateProject(Map<String, String> files, {String? expectedPackage}) {
  final issues = <Issue>[];
  void err(String f, String m) => issues.add(Issue(Severity.error, f, m));
  void warn(String f, String m) => issues.add(Issue(Severity.warning, f, m));

  // paths that must never be pushed
  for (final p in files.keys) {
    if (p.startsWith('/') || p.split('/').contains('..') || p.contains('\\')) err(p, 'unsafe path: files must stay inside the project folder');
    if (p.startsWith('.github/')) err(p, 'workflow files are written by the app; a model-written one would run in your repository and is dropped');
    if (p.startsWith('android/') || p.startsWith('ios/')) warn(p, 'the android/ and ios/ folders are generated by the build; this file is dropped');
  }

  final pubText = files['pubspec.yaml'];
  Pubspec? ps;
  if (pubText == null || pubText.trim().isEmpty) {
    err('pubspec.yaml', 'missing: every project needs a pubspec.yaml');
  } else {
    ps = parsePubspec(pubText);
    if (ps.name == null || ps.name!.isEmpty) {
      err('pubspec.yaml', 'has no "name:" line');
    } else {
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(ps.name!)) err('pubspec.yaml', 'name "${ps.name}" is not a valid Dart package name (lowercase letters, digits and underscores, starting with a letter)');
      if (expectedPackage != null && ps.name != expectedPackage) err('pubspec.yaml', 'name is "${ps.name}" but the project is called "$expectedPackage"; they must be the same');
    }
    if (ps.sdkConstraint == null) err('pubspec.yaml', 'has no "environment: sdk:" constraint (use sdk: ">=3.4.0 <4.0.0")');
    if (!ps.hasFlutterSdk) err('pubspec.yaml', 'dependencies must include "flutter:" with "sdk: flutter"');
    for (final d in ps.deps.keys.followedBy(ps.devDeps)) {
      final why = _blockedDeps[d];
      if (why != null) err('pubspec.yaml', 'dependency "$d" cannot be used: $why');
      if (_needsNativeSetup(d)) warn('pubspec.yaml', 'dependency "$d" needs native setup (keys / config files) that the build does not have');
    }
    for (final a in ps.assets) {
      final dir = a.endsWith('/');
      final found = dir ? files.keys.any((f) => f.startsWith(a)) : files.containsKey(a);
      if (!found) err('pubspec.yaml', 'asset "$a" is listed but no such file is in the project; remove it from "assets:" or add the file');
    }
    for (final a in ps.fontAssets) {
      if (!files.containsKey(a)) err('pubspec.yaml', 'font file "$a" is listed but is not in the project; remove the "fonts:" entry');
    }
  }

  final main = files['lib/main.dart'];
  if (main == null) {
    err('lib/main.dart', 'missing: the app needs lib/main.dart');
  } else if (!RegExp(r'\bvoid\s+main\s*\(|\bmain\s*\(\s*\)\s*(async\s*)?(=>|\{)|\bFuture<void>\s+main\s*\(').hasMatch(main)) {
    err('lib/main.dart', 'has no main() function');
  }

  for (final e in files.entries) {
    final path = e.key;
    if (!path.endsWith('.dart')) continue;
    final src = e.value;
    if (src.trim().isEmpty) {
      err(path, 'the file is empty');
      continue;
    }
    final bracket = firstBracketProblem(src);
    if (bracket != null) err(path, 'unbalanced: $bracket');

    final inLib = path.startsWith('lib/');
    if (inLib) {
      for (final m in _importRe.allMatches(src)) {
        final uri = m.group(1)!;
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        if (uri.startsWith('dart:')) continue;
        if (uri.startsWith('package:')) {
          final rest = uri.substring('package:'.length);
          final slash = rest.indexOf('/');
          final pkg = slash < 0 ? rest : rest.substring(0, slash);
          final sub = slash < 0 ? '' : rest.substring(slash + 1);
          final self = ps?.name ?? expectedPackage;
          if (pkg == self) {
            if (sub.isNotEmpty && !files.containsKey('lib/$sub')) err(path, "line $line: imports '$uri' but lib/$sub is not in the project");
          } else if (pkg == 'flutter') {
            // the SDK
          } else if (pkg == 'flutter_test') {
            err(path, "line $line: imports '$uri' in app code; flutter_test is only for tests");
          } else if (ps != null && !ps.deps.containsKey(pkg)) {
            err(path, "line $line: imports '$uri' but pubspec.yaml has no dependency \"$pkg\" (add it under dependencies:)");
          }
        } else if (!uri.contains(':')) {
          final target = _resolve(path, uri);
          if (target == null || !files.containsKey(target)) err(path, "line $line: imports '$uri' but that file is not in the project");
        }
      }
    }

    // text checks that only apply to comments and code, one finding per file
    for (final l in const LineSplitter().convert(src)) {
      if ((l.contains('//') || l.contains('/*')) && _placeholderRe.hasMatch(l)) {
        err(path, 'contains placeholder text: "${l.trim().length > 70 ? '${l.trim().substring(0, 70)}...' : l.trim()}". Write the full code');
        break;
      }
    }
    if (_todoRe.hasMatch(src)) warn(path, 'contains a TODO');
    for (final r in _removedApis) {
      if (r.pattern.hasMatch(src)) (r.error ? err : warn)(path, r.message);
    }
  }
  return issues;
}

class _Api {
  final RegExp pattern;
  final String message;
  final bool error;
  _Api(String re, this.message, {this.error = false}) : pattern = RegExp(re);
}

final _removedApis = <_Api>[
  _Api(r'\b(RaisedButton|FlatButton|OutlineButton)\b', 'RaisedButton / FlatButton / OutlineButton were removed: use ElevatedButton, TextButton, OutlinedButton', error: true),
  _Api(r'(cardTheme|dialogTheme|tabBarTheme)\s*:\s*(const\s+)?(CardTheme|DialogTheme|TabBarTheme)\(', 'ThemeData wants CardThemeData / DialogThemeData / TabBarThemeData, not CardTheme / DialogTheme / TabBarTheme', error: true),
  _Api(r'\.withOpacity\(', 'Color.withOpacity is deprecated: use withValues(alpha: ...)'),
  _Api(r'\bMaterialState(Property|PropertyAll|Color)?\b', 'MaterialState is renamed WidgetState'),
  _Api(r'\bWillPopScope\b', 'WillPopScope is deprecated: use PopScope'),
  _Api(r'\btextScaleFactor\b', 'textScaleFactor is deprecated: use textScaler'),
  _Api(r'\bwindow\.(devicePixelRatio|physicalSize)', 'the global "window" is deprecated: use View.of(context) or MediaQuery'),
];

// ---------------------------------------------------------------- auto fixes

class FixResult {
  final Map<String, String> files;
  final List<String> notes;
  FixResult(this.files, this.notes);
}

/// Fixes what has one obvious answer, without asking the model: drops files that
/// must not be pushed, aligns the pubspec name, and renames APIs that only changed name.
FixResult autoFix(Map<String, String> input, {String? expectedPackage}) {
  final files = Map<String, String>.from(input);
  final notes = <String>[];

  final drop = files.keys.where((p) => p.startsWith('/') || p.split('/').contains('..') || p.contains('\\') || p.startsWith('.github/') || p.startsWith('android/') || p.startsWith('ios/')).toList();
  for (final p in drop) {
    files.remove(p);
  }
  if (drop.isNotEmpty) notes.add('Left out ${drop.length} generated or unsafe file${drop.length == 1 ? '' : 's'} (${drop.take(3).join(', ')}${drop.length > 3 ? ', ...' : ''})');

  final pub = files['pubspec.yaml'];
  if (pub != null && expectedPackage != null) {
    final ps = parsePubspec(pub);
    if (ps.name != null && ps.name != expectedPackage) {
      final old = ps.name!;
      files['pubspec.yaml'] = pub.replaceFirst(RegExp(r'^name\s*:.*$', multiLine: true), 'name: $expectedPackage');
      for (final e in files.entries.toList()) {
        if (e.key.endsWith('.dart')) files[e.key] = e.value.replaceAll("package:$old/", "package:$expectedPackage/");
      }
      notes.add('Renamed the package from "$old" to "$expectedPackage" in pubspec.yaml and its imports');
    }
  }

  var withOpacity = 0, states = 0, themes = 0;
  for (final e in files.entries.toList()) {
    if (!e.key.endsWith('.dart')) continue;
    var s = e.value;
    s = s.replaceAllMapped(RegExp(r'\.withOpacity\(([^()]*)\)'), (m) {
      withOpacity++;
      return '.withValues(alpha: ${m.group(1)})';
    });
    s = s.replaceAllMapped(RegExp(r'\bMaterialState(Property|PropertyAll|Color)?\b'), (m) {
      states++;
      return 'WidgetState${m.group(1) ?? ''}';
    });
    s = s.replaceAllMapped(RegExp(r'((?:cardTheme|dialogTheme|tabBarTheme)\s*:\s*(?:const\s+)?)(CardTheme|DialogTheme|TabBarTheme)\('), (m) {
      themes++;
      return '${m.group(1)}${m.group(2)}Data(';
    });
    if (s != e.value) files[e.key] = s;
  }
  if (withOpacity > 0) notes.add('Replaced $withOpacity deprecated withOpacity call${withOpacity == 1 ? '' : 's'} with withValues(alpha: ...)');
  if (states > 0) notes.add('Renamed MaterialState to WidgetState in $states place${states == 1 ? '' : 's'}');
  if (themes > 0) notes.add('Renamed $themes theme class${themes == 1 ? '' : 'es'} to the ...ThemeData form');
  return FixResult(files, notes);
}

/// The message that asks the model to repair its project, with the exact problems.
String validationFixPrompt(List<Issue> issues) {
  final errors = issues.where((i) => i.isError).take(25).map((i) => '- ${i.file}: ${i.message}').join('\n');
  return 'Before building, Mugen checked your project and found problems that would make the build fail:\n\n$errors\n\n'
      'Fix every one of them. Reply with one short line, then a <mugen-project> block containing ONLY the files you changed (complete content each, same name attribute as before). '
      'Check every import, every package in pubspec.yaml and every bracket again before answering.';
}

// ---------------------------------------------------------------- pub.dev

/// Asks pub.dev whether each dependency exists, and whether the version asked for
/// exists. A made-up package or version is the most common reason `pub get` fails,
/// and that costs a whole Actions run to find out. Unreachable pub.dev is not an error.
Future<List<Issue>> checkPackages(Pubspec ps, {ClientFactory? clientFactory, Map<String, String>? fixes}) async {
  final issues = <Issue>[];
  final client = (clientFactory ?? defaultClientFactory)();
  try {
    for (final e in ps.deps.entries) {
      final name = e.key;
      final constraint = e.value;
      if (name == 'flutter' || constraint.isEmpty) continue; // the SDK, path and git entries have no version to look up
      http.Response r;
      try {
        r = await client.get(Uri.parse('https://pub.dev/api/packages/$name')).timeout(const Duration(seconds: 12));
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
      if (r.statusCode == 404) {
        issues.add(Issue(Severity.error, 'pubspec.yaml', 'package "$name" does not exist on pub.dev. Use a real package or write the feature yourself'));
        continue;
      }
      if (r.statusCode != 200) continue;
      Map<String, dynamic> j;
      try {
        j = jsonDecode(r.body) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final versions = ((j['versions'] as List?) ?? const []).map((v) => (v as Map)['version'].toString()).toList();
      final latest = ((j['latest'] as Map?)?['version'])?.toString();
      final m = RegExp(r'^\^?(\d+\.\d+\.\d+(?:[-+][\w.]+)?)$').firstMatch(constraint);
      if (m == null || versions.isEmpty) continue;
      final wanted = m.group(1)!;
      if (!versions.contains(wanted)) {
        final major = wanted.split('.').first;
        final sameMajor = versions.where((v) => v.split('.').first == major && !v.contains('-')).toList();
        final suggest = sameMajor.isNotEmpty ? sameMajor.last : latest;
        issues.add(Issue(Severity.error, 'pubspec.yaml', 'version $wanted of "$name" does not exist${suggest != null ? ' (latest: $suggest)' : ''}'));
        if (suggest != null && fixes != null) fixes[name] = '^$suggest';
      }
    }
  } finally {
    client.close();
  }
  return issues;
}

/// Rewrites dependency constraints in pubspec.yaml to the versions in [fixes] (name -> constraint).
String applyVersionFixes(String pubspec, Map<String, String> fixes) {
  var out = pubspec;
  fixes.forEach((name, constraint) {
    final line = RegExp('^([ \\t]+${RegExp.escape(name)}[ \\t]*:[ \\t]*).*\$', multiLine: true);
    out = out.replaceFirstMapped(line, (m) => '${m[1]}$constraint');
  });
  return out;
}

// ---------------------------------------------------------------- the whole check

class VerifyOutcome {
  final Map<String, String> files;
  final List<String> notes; // what was fixed without asking the model
  final List<Issue> errors; // problems still there at the end
  final List<Issue> warnings;
  final int rounds; // how many times the model was asked to repair
  VerifyOutcome(this.files, this.notes, this.errors, this.warnings, this.rounds);
  bool get ok => errors.isEmpty;
}

bool _sameFiles(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

/// Checks the project and repairs it before it costs a GitHub build: first what has one
/// obvious answer ([autoFix], wrong versions on pub.dev), then, for what is left, [askModel]
/// is called with the errors and must return the whole project after the model's repair
/// (or null to stop). At most [maxRounds] repairs are asked for; whatever is left is returned
/// in [VerifyOutcome.errors] so the caller can still decide to build.
Future<VerifyOutcome> verifyAndRepair({
  required Map<String, String> files,
  String? expectedPackage,
  Future<Map<String, String>?> Function(List<Issue> errors)? askModel,
  int maxRounds = 2,
  bool checkPub = true,
  ClientFactory? clientFactory,
  void Function(String step)? onStep,
}) async {
  var cur = Map<String, String>.from(files);
  final notes = <String>[];
  var rounds = 0;
  while (true) {
    final fx = autoFix(cur, expectedPackage: expectedPackage);
    cur = Map<String, String>.from(fx.files);
    for (final n in fx.notes) {
      notes.add(n);
      onStep?.call(n);
    }
    final issues = validateProject(cur, expectedPackage: expectedPackage);
    final errors = issues.where((i) => i.isError).toList();
    final warnings = issues.where((i) => !i.isError).toList();

    final pub = cur['pubspec.yaml'];
    if (checkPub && pub != null) {
      final fixes = <String, String>{};
      final found = await checkPackages(parsePubspec(pub), fixes: fixes, clientFactory: clientFactory);
      if (fixes.isNotEmpty) {
        cur['pubspec.yaml'] = applyVersionFixes(pub, fixes);
        final note = 'Corrected ${fixes.length} package version${fixes.length == 1 ? '' : 's'} that do not exist (${fixes.entries.map((e) => '${e.key} ${e.value}').join(', ')})';
        notes.add(note);
        onStep?.call(note);
      }
      errors.addAll(found.where((i) => !fixes.keys.any((n) => i.message.contains('of "$n"'))));
    }

    if (errors.isEmpty || askModel == null || rounds >= maxRounds) {
      return VerifyOutcome(cur, notes, errors, warnings, rounds);
    }
    rounds++;
    onStep?.call('Asking the AI to fix ${errors.length} problem${errors.length == 1 ? '' : 's'} (try $rounds of $maxRounds)');
    final repaired = await askModel(errors);
    if (repaired == null || _sameFiles(repaired, cur)) {
      // The model changed nothing, so asking again would give the same answer.
      return VerifyOutcome(cur, notes, errors, warnings, rounds);
    }
    cur = Map<String, String>.from(repaired);
  }
}
