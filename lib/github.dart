import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart' show ApiError;

/// Shell that creates the android/ folder next to the generated Dart code.
String scaffoldScript(String pkg, String title) => '''
flutter create --platforms=android --project-name $pkg --org com.mugen --description "$title" /tmp/scaffold
rm -rf android
cp -r /tmp/scaffold/android ./android
sed -i 's|<application|<uses-permission android:name="android.permission.INTERNET"/>\\n    <application|' android/app/src/main/AndroidManifest.xml
sed -i 's|android:label="[^"]*"|android:label="$title"|' android/app/src/main/AndroidManifest.xml''';

String _indent(String s, int n) => s.split('\n').map((l) => ' ' * n + l).join('\n');

String apkWorkflow(String pkg, String title) => '''
name: Build APK
on:
  push:
    branches: [main, master]
  workflow_dispatch:
permissions:
  contents: write
jobs:
  build:
    runs-on: ubuntu-latest
    timeout-minutes: 40
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - name: Generate Android scaffold
        run: |
${_indent(scaffoldScript(pkg, title), 10)}
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: apk
          path: build/app/outputs/flutter-apk/app-release.apk
      - name: Publish release
        env:
          GH_TOKEN: \${{ github.token }}
        run: |
          cp build/app/outputs/flutter-apk/app-release.apk "$pkg.apk"
          gh release create "build-\${{ github.run_number }}" "$pkg.apk" --title "$title build \${{ github.run_number }}" --notes "Built by Mugen AI" --latest
''';

/// Workflow used by the Mugen CLI hub: installs a CLI-Anything / CLI-Hub tool
/// on a GitHub runner and runs a command with it.
const cliRunnerWorkflow = r'''
name: Mugen CLI Runner
on:
  workflow_dispatch:
    inputs:
      cli_name:
        description: CLI-Hub name to install
        required: true
      install_cmd:
        description: Install command
        required: true
      command:
        description: Command to run
        required: true
jobs:
  run:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Install CLI
        run: |
          pip install cli-anything-hub || true
          ${{ inputs.install_cmd }}
      - name: Run
        run: |
          mkdir -p out && cd out
          ${{ inputs.command }}
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: out
          path: out
''';

class GitHub {
  final String token;
  GitHub(this.token);

  Map<String, String> get _h => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
      };

  static const _api = 'https://api.github.com';

  Future<dynamic> _req(String method, String path, {Object? body, List<int> ok = const [200, 201, 202, 204]}) async {
    final uri = Uri.parse(path.startsWith('http') ? path : '$_api$path');
    final req = http.Request(method, uri)..headers.addAll(_h);
    if (body != null) req.body = jsonEncode(body);
    final streamed = await req.send().timeout(const Duration(seconds: 45));
    final res = await http.Response.fromStream(streamed);
    if (!ok.contains(res.statusCode)) {
      String msg = res.body;
      try {
        msg = jsonDecode(res.body)['message'] ?? msg;
      } catch (_) {}
      if (res.statusCode == 401) msg = 'GitHub token invalid or expired';
      if (res.statusCode == 404) msg = '$msg (token needs "repo" + "workflow" scopes)';
      throw ApiError('GitHub ${res.statusCode}: $msg');
    }
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(res.body);
    } catch (_) {
      return res.body;
    }
  }

  Future<String> login() async => (await _req('GET', '/user'))['login'] as String;

  /// Creates the repository (or reuses it when it already exists).
  Future<Map<String, dynamic>> ensureRepo(String owner, String name, {required bool public}) async {
    try {
      return Map<String, dynamic>.from(await _req('GET', '/repos/$owner/$name'));
    } on ApiError {
      final r = await _req('POST', '/user/repos', body: {
        'name': name,
        'private': !public,
        'auto_init': true,
        'description': 'Built with Mugen AI',
      });
      await Future.delayed(const Duration(seconds: 2));
      return Map<String, dynamic>.from(r);
    }
  }

  /// Commits all files in a single commit through the Git Data API. Returns the commit sha.
  Future<String> pushFiles(String owner, String repo, String branch, Map<String, String> files, String message) async {
    final ref = await _req('GET', '/repos/$owner/$repo/git/ref/heads/$branch');
    final parent = ref['object']['sha'] as String;
    final parentCommit = await _req('GET', '/repos/$owner/$repo/git/commits/$parent');
    final baseTree = parentCommit['tree']['sha'] as String;
    final tree = <Map<String, dynamic>>[];
    for (final e in files.entries) {
      final blob = await _req('POST', '/repos/$owner/$repo/git/blobs',
          body: {'content': base64Encode(utf8.encode(e.value)), 'encoding': 'base64'});
      tree.add({'path': e.key, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']});
    }
    final newTree = await _req('POST', '/repos/$owner/$repo/git/trees', body: {'base_tree': baseTree, 'tree': tree});
    final commit = await _req('POST', '/repos/$owner/$repo/git/commits',
        body: {'message': message, 'tree': newTree['sha'], 'parents': [parent]});
    await _req('PATCH', '/repos/$owner/$repo/git/refs/heads/$branch', body: {'sha': commit['sha']});
    return commit['sha'] as String;
  }

  /// Waits for the workflow run triggered by [sha]; returns the run json.
  Future<Map<String, dynamic>> findRun(String owner, String repo, String sha) async {
    for (var i = 0; i < 30; i++) {
      final r = await _req('GET', '/repos/$owner/$repo/actions/runs?head_sha=$sha');
      final runs = (r['workflow_runs'] as List);
      if (runs.isNotEmpty) return Map<String, dynamic>.from(runs.first);
      await Future.delayed(const Duration(seconds: 4));
    }
    throw ApiError('GitHub Actions did not start a run. Is Actions enabled for the repository?');
  }

  Future<Map<String, dynamic>> getRun(String owner, String repo, int id) async =>
      Map<String, dynamic>.from(await _req('GET', '/repos/$owner/$repo/actions/runs/$id'));

  Future<String?> latestApkUrl(String owner, String repo) async {
    try {
      final r = await _req('GET', '/repos/$owner/$repo/releases/latest');
      final assets = (r['assets'] as List);
      final apk = assets.cast<Map>().firstWhere((a) => a['name'].toString().endsWith('.apk'), orElse: () => {});
      return apk.isEmpty ? (r['html_url'] as String?) : apk['browser_download_url'] as String;
    } catch (_) {
      return null;
    }
  }

  /// Last ~N chars of the log of the first failed job.
  Future<String> failedLog(String owner, String repo, int runId, {int tail = 5500}) async {
    final jobs = await _req('GET', '/repos/$owner/$repo/actions/runs/$runId/jobs');
    final failed = (jobs['jobs'] as List).cast<Map>().firstWhere((j) => j['conclusion'] == 'failure', orElse: () => {});
    if (failed.isEmpty) return 'Build failed but no job log was found.';
    final id = failed['id'];
    final req = http.Request('GET', Uri.parse('$_api/repos/$owner/$repo/actions/jobs/$id/logs'))..headers.addAll(_h);
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 45)));
    var t = res.body.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '').replaceAll(RegExp(r'\d{4}-\d\d-\d\dT[\d:.]+Z '), '');
    final errs = t.split('\n').where((l) => RegExp(r'error|Error|ERROR|FAILURE|Could not|failed', caseSensitive: false).hasMatch(l)).toList();
    final focus = errs.length > 60 ? errs.sublist(errs.length - 60) : errs;
    final tailTxt = t.length > tail ? t.substring(t.length - tail) : t;
    final out = '${focus.join('\n')}\n--- end of log ---\n$tailTxt';
    return out.length > tail + 2500 ? out.substring(out.length - (tail + 2500)) : out;
  }

  /// Plain log (tail) of the first job of a run, whatever its result.
  Future<String> jobLog(String owner, String repo, int runId, {int tail = 7000}) async {
    final jobs = await _req('GET', '/repos/$owner/$repo/actions/runs/$runId/jobs');
    final list = (jobs['jobs'] as List);
    if (list.isEmpty) return '';
    final id = list.first['id'];
    final req = http.Request('GET', Uri.parse('$_api/repos/$owner/$repo/actions/jobs/$id/logs'))..headers.addAll(_h);
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 45)));
    final t = res.body.replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '').replaceAll(RegExp(r'\d{4}-\d\d-\d\dT[\d:.]+Z '), '');
    return t.length > tail ? t.substring(t.length - tail) : t;
  }

  Future<void> dispatch(String owner, String repo, String file, Map<String, String> inputs, {String ref = 'main'}) =>
      _req('POST', '/repos/$owner/$repo/actions/workflows/$file/dispatches', body: {'ref': ref, 'inputs': inputs});

  Future<List<dynamic>> listRuns(String owner, String repo) async =>
      (await _req('GET', '/repos/$owner/$repo/actions/runs?per_page=5'))['workflow_runs'] as List;
}
