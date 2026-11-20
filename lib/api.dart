import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

Map<String, String> _headers(ProviderConfig p) => {
      'Content-Type': 'application/json',
      if (p.apiKey.isNotEmpty) 'Authorization': 'Bearer ${p.apiKey}',
      if (p.kind == ProviderKind.openrouter) 'X-Title': 'Mugen AI',
    };

String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// Fetches the live model list of a provider. New model names show up
/// automatically because nothing is hard-coded.
Future<List<ModelInfo>> fetchModels(ProviderConfig p) async {
  final base = _trimSlash(p.baseUrl);
  switch (p.kind) {
    case ProviderKind.gemini:
      final out = <ModelInfo>[];
      String? token;
      do {
        final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models')
            .replace(queryParameters: {'key': p.apiKey, 'pageSize': '200', if (token != null) 'pageToken': token});
        final r = await http.get(uri).timeout(const Duration(seconds: 25));
        if (r.statusCode != 200) throw ApiError(_errText(r));
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        for (final m in (j['models'] as List? ?? [])) {
          final methods = (m['supportedGenerationMethods'] as List? ?? []).cast<String>();
          if (!methods.contains('generateContent')) continue;
          final id = (m['name'] as String).replaceFirst('models/', '');
          final low = id.toLowerCase();
          if (low.contains('tts') || low.contains('embedding') || low.contains('imagen') || low.contains('veo') || low.contains('aqa')) continue;
          out.add(ModelInfo(
            id: id, name: (m['displayName'] ?? id).toString(), providerId: p.id,
            context: m['inputTokenLimit'],
          ));
        }
        token = j['nextPageToken'] as String?;
      } while (token != null && token.isNotEmpty);
      return out;
    case ProviderKind.openrouter:
      final r = await http.get(Uri.parse('$base/models'), headers: _headers(p)).timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) throw ApiError(_errText(r));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      return (j['data'] as List).map((m) {
        return ModelInfo(
            id: m['id'], name: (m['name'] ?? m['id']).toString(), providerId: p.id,
            context: (m['context_length'] as num?)?.toInt());
      }).toList();
    case ProviderKind.nvidia:
    case ProviderKind.custom:
      final r = await http.get(Uri.parse('$base/models'), headers: _headers(p)).timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) throw ApiError(_errText(r));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final skip = RegExp(r'embed|rerank|reward|guard|clip|nv-embed|parse|whisper|tts|asr|vision-encoder', caseSensitive: false);
      return (j['data'] as List)
          .where((m) => p.kind == ProviderKind.custom || !skip.hasMatch(m['id'].toString()))
          .map((m) => ModelInfo(id: m['id'], name: m['id'].toString(), providerId: p.id))
          .toList();
  }
}

String _errText(http.Response r) {
  try {
    final j = jsonDecode(r.body);
    final e = j is List ? j.first['error'] : j['error'];
    if (e is Map) return '${r.statusCode}: ${e['message']}';
    if (e is String) return '${r.statusCode}: $e';
    if (j['message'] != null) return '${r.statusCode}: ${j['message']}';
  } catch (_) {}
  final b = r.body.length > 300 ? r.body.substring(0, 300) : r.body;
  return '${r.statusCode}: $b';
}

/// Some models reject system messages, max_tokens or temperature. Fold system
/// prompts into the first user message for the retry.
List<Map<String, String>> _foldSystem(List<Map<String, String>> msgs) {
  final sys = msgs.where((m) => m['role'] == 'system').map((m) => m['content']!).join('\n\n');
  final rest = msgs.where((m) => m['role'] != 'system').toList();
  if (sys.isEmpty) return rest;
  if (rest.isEmpty) return [{'role': 'user', 'content': sys}];
  final first = Map<String, String>.from(rest.first);
  first['content'] = 'Instructions:\n$sys\n\n${first['content']}';
  return [first, ...rest.skip(1)];
}

/// OpenAI-compatible streaming chat completion. NVIDIA NIM, Gemini (openai
/// compat endpoint), OpenRouter and custom endpoints all speak this. If the
/// first attempt is rejected (400/422) it retries with the plainest request.
Stream<String> streamChat({
  required ProviderConfig provider,
  required String model,
  required List<Map<String, String>> messages,
  double temperature = 0.7,
}) async* {
  for (var attempt = 0; attempt < 3; attempt++) {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('${_trimSlash(provider.baseUrl)}/chat/completions'));
      req.headers.addAll(_headers(provider));
      req.body = jsonEncode({
        'model': model,
        'messages': attempt == 0 ? messages : _foldSystem(messages),
        'stream': true,
        if (attempt == 0) 'temperature': temperature,
        if (attempt < 2) 'max_tokens': attempt == 0 ? 16000 : 4096,
      });
      final res = await client.send(req).timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        if ((res.statusCode == 400 || res.statusCode == 422) && attempt < 2) continue;
        throw ApiError('${provider.name} / $model - ${_errText(http.Response(body, res.statusCode))}');
      }
      var got = false;
      final lines = res.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final d = line.substring(5).trim();
        if (d.isEmpty) continue;
        if (d == '[DONE]') break;
        try {
          final j = jsonDecode(d);
          final ch = (j['choices'] as List?)?.firstOrNull;
          final c = ch?['delta']?['content'];
          if (c is String && c.isNotEmpty) {
            got = true;
            yield c;
          }
        } catch (_) {/* partial / keep-alive */}
      }
      if (!got) throw ApiError('${provider.name} / $model returned an empty answer. Try another model.');
      return;
    } on TimeoutException {
      if (attempt >= 2) throw ApiError('${provider.name} did not answer in time. Check your connection or try another model.');
    } finally {
      client.close();
    }
  }
}

/// One-shot call used for short helper jobs (chat titles).
Future<String> completeOnce(ProviderConfig p, String model, String prompt) async {
  final buf = StringBuffer();
  await for (final d in streamChat(provider: p, model: model, messages: [
    {'role': 'user', 'content': prompt}
  ], temperature: 0.3)) {
    buf.write(d);
  }
  return buf.toString().trim();
}
