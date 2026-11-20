import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;
import 'package:http/http.dart' as http;
import 'models.dart';

/// A failed call to a model provider. [message] is shown to the user as it is,
/// [detail] keeps the server's own text (trimmed) for the "Test" dialogs.
class ApiError implements Exception {
  final String message;
  final int? status;
  final String? detail;
  ApiError(this.message, {this.status, this.detail});
  @override
  String toString() => message;
}

/// Hooks so the network code can be tested without a network.
typedef ClientFactory = http.Client Function();
typedef Sleeper = Future<void> Function(Duration d);
typedef StatusSink = void Function(String text);

/// What every call uses when no client is passed in. Tests (including widget tests) replace it with a scripted server.
ClientFactory defaultClientFactory = http.Client.new;

Map<String, String> _headers(ProviderConfig p) => {
      'Content-Type': 'application/json',
      if (p.apiKey.isNotEmpty) 'Authorization': 'Bearer ${p.apiKey}',
      if (p.kind == ProviderKind.openrouter) 'X-Title': 'Mugen AI',
    };

String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

// ---------------------------------------------------------------- model lists

/// Fetches the live model list of a provider. Nothing is hard-coded, so new
/// model names show up on their own.
Future<List<ModelInfo>> fetchModels(ProviderConfig p, {ClientFactory? clientFactory}) async {
  final base = _trimSlash(p.baseUrl);
  final client = (clientFactory ?? defaultClientFactory)();
  try {
    if (p.kind == ProviderKind.gemini) {
      final out = <ModelInfo>[];
      String? token;
      do {
        final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models')
            .replace(queryParameters: {'key': p.apiKey, 'pageSize': '200', 'pageToken': ?token});
        final r = await client.get(uri).timeout(const Duration(seconds: 25));
        if (r.statusCode != 200) throw _httpError(p, null, r.statusCode, r.body);
        final j = _decodeMap(r.body);
        out.addAll(parseGeminiModels(j, p.id));
        token = j['nextPageToken'] as String?;
      } while (token != null && token.isNotEmpty);
      return out;
    }
    final r = await client.get(Uri.parse('$base/models'), headers: _headers(p)).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) throw _httpError(p, null, r.statusCode, r.body);
    return parseOpenAiModels(_decodeAny(r.body), p);
  } on TimeoutException {
    throw ApiError('${p.name} did not answer the model list request in 25 s. Check the base URL and your connection.');
  } on http.ClientException catch (e) {
    throw ApiError('Could not reach ${p.name} (${e.message}). Check the base URL and your connection.');
  } on IOException catch (e) {
    throw ApiError('Could not reach ${p.name} ($e). Check the base URL and your connection.');
  } finally {
    client.close();
  }
}

Map<String, dynamic> _decodeMap(String body) {
  final j = _decodeAny(body);
  return j is Map<String, dynamic> ? j : <String, dynamic>{};
}

dynamic _decodeAny(String body) {
  try {
    return jsonDecode(body);
  } catch (_) {
    throw ApiError('The server answered with something that is not JSON: ${_clip(body, 160)}');
  }
}

/// Gemini's native list: only models that can generate text.
List<ModelInfo> parseGeminiModels(Map<String, dynamic> j, String providerId) {
  final out = <ModelInfo>[];
  for (final m in (j['models'] as List? ?? const [])) {
    if (m is! Map || m['name'] is! String) continue;
    final methods = ((m['supportedGenerationMethods'] as List?) ?? const []).map((e) => e.toString()).toList();
    if (!methods.contains('generateContent')) continue;
    final id = (m['name'] as String).replaceFirst('models/', '');
    final low = id.toLowerCase();
    if (low.contains('tts') || low.contains('embedding') || low.contains('imagen') || low.contains('veo') || low.contains('aqa')) continue;
    out.add(ModelInfo(id: id, name: (m['displayName'] ?? id).toString(), providerId: providerId, context: (m['inputTokenLimit'] as num?)?.toInt()));
  }
  return out;
}

final _notChat = RegExp(r'embed|rerank|reward|guard|clip|parse|whisper|tts|asr|vision-encoder|safety|detector|calibration|translate|gliner|pii', caseSensitive: false);

/// `GET /models` of an OpenAI-style endpoint (NVIDIA NIM, OpenRouter, custom).
/// Accepts `{"data":[...]}`, `{"models":[...]}` or a bare list. NVIDIA's list
/// also holds embedding, reranking and safety models, which are not chat models.
List<ModelInfo> parseOpenAiModels(dynamic j, ProviderConfig p) {
  final raw = j is List ? j : (j is Map ? (j['data'] ?? j['models']) : null);
  if (raw is! List) return const [];
  final out = <ModelInfo>[];
  final seen = <String>{};
  for (final m in raw) {
    final id = m is Map ? (m['id'] ?? m['name'])?.toString() : (m is String ? m : null);
    if (id == null || id.isEmpty || !seen.add(id)) continue;
    if (p.kind == ProviderKind.nvidia && _notChat.hasMatch(id)) continue;
    final name = m is Map && p.kind == ProviderKind.openrouter ? (m['name'] ?? id).toString() : id;
    final ctx = m is Map ? ((m['context_length'] ?? m['context_window']) as num?)?.toInt() : null;
    out.add(ModelInfo(id: id, name: name, providerId: p.id, context: ctx));
  }
  return out;
}

// ---------------------------------------------------------------- errors

String _clip(String s, int n) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > n ? '${t.substring(0, n)}...' : t;
}

/// The server's own sentence out of whatever JSON shape it used.
String serverText(String body) {
  try {
    final j = jsonDecode(body);
    final e = j is List ? (j.isEmpty ? null : (j.first is Map ? j.first['error'] : j.first)) : (j is Map ? (j['error'] ?? j['message'] ?? j['detail']) : null);
    if (e is Map) {
      final m = e['message'] ?? e['detail'] ?? e['msg'];
      if (m != null) return m.toString();
    }
    if (e is String && e.isNotEmpty) return e;
    if (j is Map && j['detail'] != null) return j['detail'].toString();
  } catch (_) {}
  return _clip(body, 400);
}

/// A clear, specific sentence for an HTTP failure. [model] is null for list calls.
ApiError _httpError(ProviderConfig p, String? model, int status, String body) {
  final who = model == null ? p.name : '${p.name} / $model';
  final said = serverText(body);
  final tail = said.isEmpty ? '' : ' Server said: $said';
  final detail = _clip(body, 800);
  switch (status) {
    case 401:
    case 403:
      return ApiError('$who - the API key was refused ($status). Check the key in Settings, then press "Test connection".$tail', status: status, detail: detail);
    case 402:
      return ApiError('$who - the account has no credit left (402).$tail', status: status, detail: detail);
    case 404:
      if (RegExp(r'Function\s+.?[0-9a-f-]{8,}.?\s*:?\s*Not found for account', caseSensitive: false).hasMatch(body)) {
        return ApiError('$who - NVIDIA lists this model but it is not switched on for your key (404). Pick another model.$tail', status: status, detail: detail);
      }
      return ApiError('$who - not found (404). The base URL or the model ID is wrong, or the model was retired. Pick another model.$tail', status: status, detail: detail);
    case 410:
      return ApiError('$who - this model has been retired by the provider (410). Pick another model.$tail', status: status, detail: detail);
    case 413:
      return ApiError('$who - the request is too large for this model (413). Start a new chat or pick a model with a bigger context.$tail', status: status, detail: detail);
    case 429:
      return ApiError('$who - rate limit or quota reached (429). Wait a little, or pick another model.$tail', status: status, detail: detail);
  }
  if (status >= 500) {
    return ApiError('$who - the provider had an error ($status). Try again, or pick another model.$tail', status: status, detail: detail);
  }
  return ApiError('$who - $status.$tail', status: status, detail: detail);
}

/// How long a 429 asks us to wait, from the header or from the text
/// ("retry in 12.3s", `"retryDelay": "35s"`). Null when it does not say.
Duration? retryAfter(Map<String, String> headers, String body) {
  final h = headers.entries.where((e) => e.key.toLowerCase() == 'retry-after').map((e) => e.value).firstOrNull;
  final secs = double.tryParse(h ?? '');
  if (secs != null) return Duration(milliseconds: (secs * 1000).round());
  final m = RegExp(r'(?:retry[^0-9]{0,30}|retryDelay[^0-9]{0,10})(\d+(?:\.\d+)?)\s*s', caseSensitive: false).firstMatch(body);
  if (m != null) return Duration(milliseconds: (double.parse(m.group(1)!) * 1000).round());
  return null;
}

/// A daily quota or a billing problem will not clear by waiting a few seconds.
bool hardQuota(String body) {
  final t = body.toLowerCase();
  return t.contains('per day') || t.contains('daily') || t.contains('billing') || t.contains('insufficient') || t.contains('exceeded your current quota');
}

// ---------------------------------------------------------------- request shape

/// Some models reject system messages, `max_tokens`, `temperature` or streaming.
/// The shape starts full and is made plainer by what the server complains about.
class RequestShape {
  bool system = true;
  bool temperature = true;
  String? tokenKey = 'max_tokens';
  int tokens;
  bool stream = true;
  RequestShape(this.tokens);

  Map<String, dynamic> body(String model, List<Map<String, String>> messages, double temp) => {
        'model': model,
        'messages': system ? messages : _foldSystem(messages),
        'stream': stream,
        if (temperature) 'temperature': temp,
        ?tokenKey: tokens,
      };

  /// Reads a 400/422 and changes one thing. False when there is nothing left to simplify.
  bool adapt(String text) {
    final t = text.toLowerCase();
    final mentionsTokens = t.contains('max_tokens') || t.contains('max_completion_tokens');
    if (tokenKey == 'max_tokens' && t.contains('max_completion_tokens')) {
      tokenKey = 'max_completion_tokens';
      return true;
    }
    if (tokenKey == 'max_completion_tokens' && t.contains('max_tokens') && !t.contains('max_completion_tokens')) {
      tokenKey = 'max_tokens';
      return true;
    }
    if (tokenKey != null && (t.contains('context length') || t.contains('context window') || t.contains('too many tokens'))) {
      if (tokens > 1024) {
        tokens = tokens ~/ 2;
        return true;
      }
    }
    if (tokenKey != null && mentionsTokens) {
      final limit = RegExp(r'\d{3,6}').allMatches(t).map((m) => int.parse(m.group(0)!)).where((n) => n >= 256 && n < tokens).fold<int?>(null, (a, b) => a == null || b > a ? b : a);
      if (limit != null) {
        tokens = limit;
        return true;
      }
      tokenKey = null;
      return true;
    }
    if (temperature && t.contains('temperature')) {
      temperature = false;
      return true;
    }
    if (system && (t.contains('system') || t.contains('developer') || t.contains('role') || t.contains('instruction'))) {
      system = false;
      return true;
    }
    if (stream && t.contains('stream')) {
      stream = false;
      return true;
    }
    // The server said something else: simplify step by step.
    if (temperature) {
      temperature = false;
      return true;
    }
    if (system) {
      system = false;
      return true;
    }
    if (tokenKey != null) {
      tokenKey = null;
      return true;
    }
    return false;
  }
}

/// Folds system prompts into the first user message, for models that refuse the system role.
List<Map<String, String>> _foldSystem(List<Map<String, String>> msgs) {
  final sys = msgs.where((m) => m['role'] == 'system').map((m) => m['content']!).join('\n\n');
  final rest = msgs.where((m) => m['role'] != 'system').toList();
  if (sys.isEmpty) return rest;
  if (rest.isEmpty) return [{'role': 'user', 'content': sys}];
  final first = Map<String, String>.from(rest.first);
  first['content'] = 'Instructions:\n$sys\n\n${first['content']}';
  return [first, ...rest.skip(1)];
}

String _textOf(dynamic v) {
  if (v is String) return v;
  if (v is List) return v.map((e) => e is Map ? (e['text'] ?? '').toString() : e.toString()).join();
  return '';
}

// ---------------------------------------------------------------- chat

/// OpenAI-compatible chat completion, streamed. NVIDIA NIM, Gemini (its OpenAI
/// endpoint), OpenRouter and custom endpoints all speak this. What goes wrong,
/// and what is done about it:
///  - 400/422 "unsupported system / max_tokens / temperature / stream": the request is made plainer and sent again;
///  - 429: waits as the server asks (or 2, 4, 8, 16 s) and tries again, unless it is a daily quota;
///  - 5xx, timeouts, dropped connections before the first word: tries again twice;
///  - an answer with no text: asks again without streaming, then plainer;
///  - `reasoning_content` is never mixed into the answer; a model that only "thinks" gets a clear error.
/// [onStatus] hears about waits and retries so the chat can show them.
Stream<String> streamChat({
  required ProviderConfig provider,
  required String model,
  required List<Map<String, String>> messages,
  double temperature = 0.7,
  int maxTokens = 16000,
  StatusSink? onStatus,
  ClientFactory? clientFactory,
  Sleeper? sleep,
}) async* {
  final wait = sleep ?? Future<void>.delayed;
  final shape = RequestShape(maxTokens);
  final who = '${provider.name} / $model';
  var shapeFixes = 0, rateRetries = 0, netRetries = 0, emptyRetries = 0;
  final uri = Uri.parse('${_trimSlash(provider.baseUrl)}/chat/completions');

  while (true) {
    final client = (clientFactory ?? defaultClientFactory)();
    var got = false;
    var reasoning = 0;
    String? finish;
    try {
      final req = http.Request('POST', uri)
        ..headers.addAll(_headers(provider))
        ..body = jsonEncode(shape.body(model, messages, temperature));
      final res = await client.send(req).timeout(const Duration(seconds: 90));

      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        final status = res.statusCode;
        if (status == 429) {
          final asked = retryAfter(res.headers, body);
          if (hardQuota(body) && (asked == null || asked.inSeconds > 45)) throw _httpError(provider, model, status, body);
          if (rateRetries < 4 && (asked == null || asked.inSeconds <= 45)) {
            final d = asked ?? Duration(seconds: 2 << rateRetries);
            rateRetries++;
            onStatus?.call('Rate limited, trying again in ${d.inSeconds < 1 ? 1 : d.inSeconds} s ($rateRetries/4)...');
            await wait(d);
            continue;
          }
          throw _httpError(provider, model, status, body);
        }
        if ((status >= 500 || status == 408 || status == 425) && netRetries < 2) {
          netRetries++;
          onStatus?.call('$who had an error ($status), trying again ($netRetries/2)...');
          await wait(Duration(milliseconds: 1500 * netRetries));
          continue;
        }
        if ((status == 400 || status == 422) && shapeFixes < 6 && shape.adapt(body)) {
          shapeFixes++;
          onStatus?.call('Sending a plainer request ($shapeFixes)...');
          continue;
        }
        throw _httpError(provider, model, status, body);
      }

      final type = (res.headers['content-type'] ?? '').toLowerCase();
      if (type.contains('application/json')) {
        // The endpoint ignored `stream`: one JSON document.
        final j = _decodeAny(await res.stream.bytesToString());
        final err = j is Map ? j['error'] : null;
        if (err != null) throw ApiError('$who - ${err is Map ? (err['message'] ?? err) : err}');
        final ch = j is Map ? (j['choices'] as List?)?.firstOrNull : null;
        final msg = ch is Map ? ch['message'] : null;
        final c = _textOf(msg is Map ? msg['content'] : null);
        reasoning += _textOf(msg is Map ? (msg['reasoning_content'] ?? msg['reasoning']) : null).length;
        finish = ch is Map ? ch['finish_reason']?.toString() : null;
        if (c.isNotEmpty) {
          got = true;
          yield c;
        }
      } else {
        // `moveNext().timeout` is the idle limit: 75 s without a single byte. (Stream.timeout would do the same, but
        // it does not deliver events under the test framework's fake clock.)
        final lines = StreamIterator(res.stream.transform(utf8.decoder).transform(const LineSplitter()));
        var thinking = false;
        try {
          while (await lines.moveNext().timeout(const Duration(seconds: 75))) {
            final line = lines.current;
            if (!line.startsWith('data:')) continue; // ": keep-alive" comments and blank lines
            final d = line.substring(5).trim();
            if (d.isEmpty) continue;
            if (d == '[DONE]') break;
            dynamic j;
            try {
              j = jsonDecode(d);
            } catch (_) {
              continue; // a partial line
            }
            if (j is! Map) continue;
            if (j['error'] != null) {
              final e = j['error'];
              throw ApiError('$who - ${e is Map ? (e['message'] ?? e) : e}');
            }
            final ch = (j['choices'] as List?)?.firstOrNull;
            if (ch is! Map) continue;
            final delta = ch['delta'] ?? ch['message'];
            if (delta is Map) {
              final r = _textOf(delta['reasoning_content'] ?? delta['reasoning']);
              if (r.isNotEmpty) {
                reasoning += r.length;
                if (!thinking && !got) {
                  thinking = true;
                  onStatus?.call('Thinking...');
                }
              }
              final c = _textOf(delta['content']);
              if (c.isNotEmpty) {
                got = true;
                yield c;
              }
            }
            if (ch['finish_reason'] != null) finish = ch['finish_reason'].toString();
          }
        } finally {
          // Not awaited: the answer is complete, and waiting for the socket to close only delays it.
          lines.cancel().ignore();
        }
      }

      if (got) return;
      if (reasoning > 0 && finish == 'length') {
        throw ApiError('$who spent all its tokens thinking and wrote no answer. Pick another model, or ask for something shorter.');
      }
      if (emptyRetries < 2) {
        emptyRetries++;
        if (emptyRetries == 1) {
          shape.stream = false;
        } else {
          shape
            ..temperature = false
            ..system = false;
        }
        onStatus?.call('The model sent nothing, asking again ($emptyRetries/2)...');
        continue;
      }
      throw ApiError('$who returned an empty answer ${reasoning > 0 ? '(it only produced reasoning) ' : ''}after 3 tries. Try another model.');
    } on TimeoutException {
      if (got) throw ApiError('$who stopped answering in the middle of the reply (no data for 75 s). Ask it to continue, or pick a faster model.');
      if (netRetries < 2) {
        netRetries++;
        onStatus?.call('$who is slow, trying again ($netRetries/2)...');
        continue;
      }
      throw ApiError('$who did not answer in time (3 tries). Check your connection, or pick a faster model.');
    } on http.ClientException catch (e) {
      if (got) throw ApiError('The connection to ${provider.name} dropped in the middle of the reply (${e.message}).');
      if (netRetries < 2) {
        netRetries++;
        onStatus?.call('Connection problem, trying again ($netRetries/2)...');
        await wait(Duration(milliseconds: 1500 * netRetries));
        continue;
      }
      throw ApiError('Could not reach ${provider.name} (${e.message}). Check the base URL and your connection.');
    } on IOException catch (e) {
      if (got) throw ApiError('The connection to ${provider.name} dropped in the middle of the reply ($e).');
      if (netRetries < 2) {
        netRetries++;
        onStatus?.call('Connection problem, trying again ($netRetries/2)...');
        await wait(Duration(milliseconds: 1500 * netRetries));
        continue;
      }
      throw ApiError('Could not reach ${provider.name} ($e). Check the base URL and your connection.');
    } finally {
      client.close();
    }
  }
}

/// One-shot call used for short helper jobs.
Future<String> completeOnce(ProviderConfig p, String model, String prompt, {ClientFactory? clientFactory, Sleeper? sleep}) async {
  final buf = StringBuffer();
  await for (final d in streamChat(
    provider: p,
    model: model,
    messages: [
      {'role': 'user', 'content': prompt}
    ],
    temperature: 0.3,
    maxTokens: 512,
    clientFactory: clientFactory,
    sleep: sleep,
  )) {
    buf.write(d);
  }
  return buf.toString().trim();
}

// ---------------------------------------------------------------- tests of a provider / model

/// The result of a "Test connection" or "Test model" press. [message] is the
/// exact text to show; [detail] the server's own words when there were any.
class TestResult {
  final bool ok;
  final String message;
  final int ms;
  final String? detail;
  const TestResult(this.ok, this.message, this.ms, {this.detail});
}

/// Asks the provider for its model list: proves the base URL and the key work.
Future<TestResult> testConnection(ProviderConfig p, {ClientFactory? clientFactory}) async {
  final sw = Stopwatch()..start();
  if (p.baseUrl.trim().isEmpty || !p.baseUrl.trim().startsWith('http')) {
    return TestResult(false, 'The base URL "${p.baseUrl}" is not a web address. It should look like https://host/v1', 0);
  }
  if (p.kind != ProviderKind.custom && p.kind != ProviderKind.openrouter && p.apiKey.trim().isEmpty) {
    return TestResult(false, 'No API key for ${p.name} yet. Paste it above first.', 0);
  }
  try {
    final list = await fetchModels(p, clientFactory: clientFactory);
    final ms = sw.elapsedMilliseconds;
    return list.isEmpty
        ? TestResult(true, 'Connected to ${p.name} in $ms ms, but it listed no models. You can still type a model ID by hand in the model picker.', ms)
        : TestResult(true, 'Connected to ${p.name} in $ms ms. ${list.length} models found.', ms);
  } on ApiError catch (e) {
    return TestResult(false, e.message, sw.elapsedMilliseconds, detail: e.detail);
  } catch (e) {
    return TestResult(false, e.toString(), sw.elapsedMilliseconds);
  }
}

/// Sends one short prompt to one model and shows what came back, or the exact error.
Future<TestResult> testModel(ProviderConfig p, String model, {ClientFactory? clientFactory, Sleeper? sleep}) async {
  final sw = Stopwatch()..start();
  final buf = StringBuffer();
  final notes = <String>[];
  try {
    await for (final d in streamChat(
      provider: p,
      model: model,
      messages: [
        {'role': 'system', 'content': 'You are a connection test.'},
        {'role': 'user', 'content': 'Reply with the single word: pong'},
      ],
      temperature: 0.2,
      maxTokens: 512,
      onStatus: notes.add,
      clientFactory: clientFactory,
      sleep: sleep,
    )) {
      buf.write(d);
      if (buf.length > 200) break;
    }
    final ms = sw.elapsedMilliseconds;
    final said = buf.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
    return TestResult(true, '$model answered in $ms ms: "${said.length > 80 ? '${said.substring(0, 80)}...' : said}"', ms,
        detail: notes.isEmpty ? null : notes.join('\n'));
  } on ApiError catch (e) {
    return TestResult(false, e.message, sw.elapsedMilliseconds, detail: e.detail ?? (notes.isEmpty ? null : notes.join('\n')));
  } catch (e) {
    return TestResult(false, '${p.name} / $model - $e', sw.elapsedMilliseconds);
  }
}
