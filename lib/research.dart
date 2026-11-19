import 'dart:convert';
import 'package:http/http.dart' as http;

class ResearchResult {
  final String context;
  final List<Map<String, String>> sources;
  ResearchResult(this.context, this.sources);
}

String _strip(String html) {
  var s = html
      .replaceAll(RegExp(r'<(script|style|noscript|svg)[\s\S]*?</\1>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Live web research without any API key: DuckDuckGo HTML results, then the
/// top pages are fetched and reduced to plain text.
Future<ResearchResult> liveResearch(String query) async {
  const ua = {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36'};
  final results = <Map<String, String>>[];
  try {
    final r = await http
        .get(Uri.parse('https://html.duckduckgo.com/html/?q=${Uri.encodeQueryComponent(query)}'), headers: ua)
        .timeout(const Duration(seconds: 15));
    final links = RegExp(r'class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)</a>').allMatches(r.body).toList();
    final snips = RegExp(r'class="result__snippet"[^>]*>([\s\S]*?)</a>').allMatches(r.body).toList();
    for (var i = 0; i < links.length && results.length < 5; i++) {
      var url = links[i].group(1)!.replaceAll('&amp;', '&');
      final u = Uri.tryParse(url.startsWith('//') ? 'https:$url' : url);
      if (u == null) continue;
      if (u.host.contains('duckduckgo.com') && u.queryParameters['uddg'] != null) {
        url = u.queryParameters['uddg']!;
      } else if (url.startsWith('//')) {
        url = 'https:$url';
      }
      results.add({
        'title': _strip(links[i].group(2)!),
        'url': url,
        'snippet': i < snips.length ? _strip(snips[i].group(1)!) : '',
      });
    }
  } catch (_) {}

  final buf = StringBuffer('LIVE WEB RESEARCH (fetched just now, ${DateTime.now().toIso8601String()}). Query: "$query"\n');
  var n = 0;
  for (final r in results) {
    n++;
    buf.writeln('\n[$n] ${r['title']} - ${r['url']}\n${r['snippet']}');
    if (n <= 3) {
      try {
        final p = await http.get(Uri.parse(r['url']!), headers: ua).timeout(const Duration(seconds: 10));
        if (p.statusCode == 200 && (p.headers['content-type'] ?? '').contains('html')) {
          final t = _strip(utf8.decode(p.bodyBytes, allowMalformed: true));
          buf.writeln('Page text: ${t.length > 2500 ? t.substring(0, 2500) : t}');
        }
      } catch (_) {}
    }
  }
  if (results.isEmpty) buf.writeln('(No results could be fetched. Say so and answer from your own knowledge.)');
  return ResearchResult(buf.toString(), results.map((e) => {'title': e['title']!, 'url': e['url']!}).toList());
}
