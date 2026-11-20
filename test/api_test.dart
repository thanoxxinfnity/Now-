import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mugen_ai/api.dart';
import 'package:mugen_ai/models.dart';

ProviderConfig prov({ProviderKind kind = ProviderKind.custom, String key = 'k'}) =>
    ProviderConfig(id: 'p1', kind: kind, name: 'Test', baseUrl: 'https://api.test/v1', apiKey: key);

http.StreamedResponse resp(int status, String body, {Map<String, String> headers = const {}}) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), status, headers: {'content-type': 'application/json', ...headers});

String sse(List<Map<String, dynamic>> deltas, {String? finish}) {
  final b = StringBuffer(': keep-alive\n\n');
  for (final d in deltas) {
    b.write('data: ${jsonEncode({'choices': [{'delta': d}]})}\n\n');
  }
  if (finish != null) b.write('data: ${jsonEncode({'choices': [{'delta': {}, 'finish_reason': finish}]})}\n\n');
  b.write('data: [DONE]\n\n');
  return b.toString();
}

http.StreamedResponse stream(String body) => resp(200, body, headers: {'content-type': 'text/event-stream'});

typedef Step = FutureOr<http.StreamedResponse> Function(Map<String, dynamic> body);

/// A scripted server: answers the n-th request with the n-th step (the last step repeats) and records every request body.
class Server {
  final List<Step> steps;
  final List<Map<String, dynamic>> seen = [];
  final List<Duration> sleeps = [];
  final List<String> status = [];
  Server(this.steps);
  ClientFactory get factory => () => MockClient.streaming((req, bodyStream) async {
        final body = jsonDecode(await bodyStream.bytesToString()) as Map<String, dynamic>;
        seen.add(body);
        return steps[(seen.length - 1).clamp(0, steps.length - 1)](body);
      });
  Future<void> sleep(Duration d) async => sleeps.add(d);

  Future<String> chat({List<Map<String, String>>? messages, ProviderConfig? provider, int maxTokens = 16000}) async {
    final out = StringBuffer();
    await for (final d in streamChat(
      provider: provider ?? prov(),
      model: 'm1',
      messages: messages ??
          [
            {'role': 'system', 'content': 'SYS'},
            {'role': 'user', 'content': 'hello'}
          ],
      maxTokens: maxTokens,
      clientFactory: factory,
      sleep: sleep,
      onStatus: status.add,
    )) {
      out.write(d);
    }
    return out.toString();
  }
}

Future<Object?> failure(Future<void> Function() f) async {
  try {
    await f();
  } catch (e) {
    return e;
  }
  return null;
}

void main() {
  group('streaming', () {
    test('streams the content and keeps reasoning_content out of the answer', () async {
      final s = Server([
        (_) => stream(sse([
              {'reasoning_content': 'let me think'},
              {'content': 'Hel'},
              {'content': 'lo'},
            ], finish: 'stop'))
      ]);
      expect(await s.chat(), 'Hello');
      expect(s.seen.length, 1);
      expect(s.seen.first['stream'], true);
      expect(s.seen.first['max_tokens'], 16000);
      expect(s.seen.first['temperature'], 0.7);
      expect((s.seen.first['messages'] as List).first['role'], 'system');
      expect(s.status, ['Thinking...']);
    });

    test('content sent as a list of parts is joined', () async {
      final s = Server([
        (_) => stream(sse([
              {'content': [{'type': 'text', 'text': 'A'}, {'type': 'text', 'text': 'B'}]},
            ]))
      ]);
      expect(await s.chat(), 'AB');
    });

    test('an endpoint that ignores stream and returns one JSON document still works', () async {
      final s = Server([(_) => resp(200, jsonEncode({'choices': [{'message': {'content': 'plain json'}, 'finish_reason': 'stop'}]}))]);
      expect(await s.chat(), 'plain json');
    });

    test('an error object in the middle of the stream becomes a clear error', () async {
      final s = Server([(_) => stream('data: ${jsonEncode({'error': {'message': 'upstream exploded'}})}\n\n')]);
      final e = await failure(s.chat);
      expect(e, isA<ApiError>());
      expect(e.toString(), allOf(contains('Test / m1'), contains('upstream exploded')));
    });
  });

  group('400 / 422: the request is made plainer', () {
    test('a model without max_tokens gets none on the second try', () async {
      final s = Server([
        (_) => resp(400, jsonEncode({'error': {'message': "Unsupported parameter: 'max_tokens' is not supported with this model."}})),
        (_) => stream(sse([{'content': 'ok'}])),
      ]);
      expect(await s.chat(), 'ok');
      expect(s.seen[0].containsKey('max_tokens'), true);
      expect(s.seen[1].containsKey('max_tokens'), false);
      expect(s.seen[1]['temperature'], 0.7, reason: 'only the complained-about parameter is removed');
    });

    test('max_completion_tokens is used when the server asks for it', () async {
      final s = Server([
        (_) => resp(400, jsonEncode({'error': {'message': "Unsupported parameter: 'max_tokens'. Use 'max_completion_tokens' instead."}})),
        (_) => stream(sse([{'content': 'ok'}])),
      ]);
      expect(await s.chat(), 'ok');
      expect(s.seen[1].containsKey('max_tokens'), false);
      expect(s.seen[1]['max_completion_tokens'], 16000);
    });

    test('a token limit named in the message is respected', () async {
      final s = Server([
        (_) => resp(400, jsonEncode({'error': {'message': 'max_tokens must be less than or equal to 8192, you requested 16000'}})),
        (_) => stream(sse([{'content': 'ok'}])),
      ]);
      expect(await s.chat(), 'ok');
      expect(s.seen[1]['max_tokens'], 8192);
    });

    test('temperature is dropped when the model refuses it', () async {
      final s = Server([
        (_) => resp(422, jsonEncode({'detail': "temperature is not supported for this model"})),
        (_) => stream(sse([{'content': 'ok'}])),
      ]);
      expect(await s.chat(), 'ok');
      expect(s.seen[1].containsKey('temperature'), false);
      expect(s.seen[1]['max_tokens'], 16000);
    });

    test('the system role is folded into the first user message', () async {
      final s = Server([
        (_) => resp(400, jsonEncode({'error': {'message': 'Developer instruction / system role is not enabled for models/gemma'}})),
        (_) => stream(sse([{'content': 'ok'}])),
      ]);
      expect(await s.chat(), 'ok');
      final msgs = s.seen[1]['messages'] as List;
      expect(msgs.length, 1);
      expect(msgs.first['role'], 'user');
      expect(msgs.first['content'], allOf(contains('SYS'), contains('hello')));
    });

    test('a vague 400 simplifies step by step and finally gives up with the server text', () async {
      final s = Server([(_) => resp(400, jsonEncode({'error': {'message': 'Bad request, no idea why'}}))]);
      final e = await failure(s.chat);
      expect(e, isA<ApiError>());
      expect(e.toString(), contains('Bad request, no idea why'));
      expect(s.seen.length, 4, reason: 'full, no temperature, no system, no max_tokens');
      expect(s.seen.last.containsKey('temperature') || s.seen.last.containsKey('max_tokens'), false);
    });
  });

  group('429 and server errors', () {
    test('waits as Retry-After says, then succeeds', () async {
      final s = Server([
        (_) => resp(429, jsonEncode({'error': {'message': 'slow down'}}), headers: {'retry-after': '3'}),
        (_) => stream(sse([{'content': 'ok'}])),
      ]);
      expect(await s.chat(), 'ok');
      expect(s.sleeps, [const Duration(seconds: 3)]);
      expect(s.status.single, contains('Rate limited'));
    });

    test('reads the wait out of the text when there is no header', () async {
      final s = Server([
        (_) => resp(429, jsonEncode({'error': {'message': 'Resource exhausted. Please retry in 12.5s.'}})),
        (_) => stream(sse([{'content': 'ok'}])),
      ]);
      await s.chat();
      expect(s.sleeps, [const Duration(milliseconds: 12500)]);
    });

    test('backs off 2, 4, 8, 16 s and then reports the rate limit', () async {
      final s = Server([(_) => resp(429, jsonEncode({'error': {'message': 'too many requests'}}))]);
      final e = await failure(s.chat);
      expect(e.toString(), allOf(contains('429'), contains('too many requests')));
      expect(s.sleeps.map((d) => d.inSeconds), [2, 4, 8, 16]);
      expect(s.seen.length, 5);
    });

    test('a daily quota is not retried', () async {
      final s = Server([(_) => resp(429, jsonEncode({'error': {'message': 'You exceeded your current quota, please check your plan and billing details.'}}))]);
      final e = await failure(s.chat);
      expect(e, isA<ApiError>());
      expect(s.seen.length, 1);
      expect(s.sleeps, isEmpty);
    });

    test('a 503 is tried again twice, then succeeds', () async {
      final s = Server([
        (_) => resp(503, 'upstream busy'),
        (_) => resp(502, 'bad gateway'),
        (_) => stream(sse([{'content': 'ok'}])),
      ]);
      expect(await s.chat(), 'ok');
      expect(s.seen.length, 3);
    });

    test('a 500 that never clears ends with a clear error', () async {
      final s = Server([(_) => resp(500, jsonEncode({'error': {'message': 'internal'}}))]);
      final e = await failure(s.chat);
      expect(e.toString(), allOf(contains('Test / m1'), contains('500'), contains('internal')));
      expect(s.seen.length, 3);
    });

    test('401, 402, 404 and 410 each say what to do', () async {
      for (final c in const [
        [401, 'key was refused'],
        [402, 'no credit'],
        [404, 'not found'],
        [410, 'retired'],
      ]) {
        final s = Server([(_) => resp(c[0] as int, jsonEncode({'error': {'message': 'nope'}}))]);
        final e = await failure(s.chat);
        expect(e.toString(), allOf(contains(c[1] as String), contains('nope')), reason: 'status ${c[0]}');
        expect(s.seen.length, 1);
      }
    });

    test('NVIDIA\'s "not found for account" 404 says the model is not switched on', () async {
      final s = Server([(_) => resp(404, jsonEncode({'status': 404, 'title': 'Not Found', 'detail': "Function '1a2b3c4d-0000-1111-2222-333344445555': Not found for account 'abc'"}))]);
      final e = await failure(s.chat);
      expect(e.toString(), allOf(contains('not switched on for your key'), contains('Pick another model')));
    });
  });

  group('network', () {
    test('a dropped connection before the first word is retried', () async {
      var n = 0;
      final seen = <int>[];
      final out = StringBuffer();
      await for (final d in streamChat(
        provider: prov(),
        model: 'm1',
        messages: [
          {'role': 'user', 'content': 'hi'}
        ],
        sleep: (_) async {},
        clientFactory: () => MockClient.streaming((req, b) async {
          seen.add(++n);
          if (n == 1) throw http.ClientException('Connection reset by peer');
          if (n == 2) throw const SocketException('Network is unreachable');
          return stream(sse([{'content': 'back'}]));
        }),
      )) {
        out.write(d);
      }
      expect(out.toString(), 'back');
      expect(seen, [1, 2, 3]);
    });

    test('a timeout before any text is retried, then reported', () async {
      final s = Server([(_) => throw TimeoutException('slow')]);
      final e = await failure(s.chat);
      expect(e.toString(), allOf(contains('did not answer in time'), contains('Test / m1')));
      expect(s.seen.length, 3);
    });

    test('a connection that dies after some text keeps the text and says so', () async {
      final controller = StreamController<List<int>>();
      final s = Server([
        (_) {
          controller.add(utf8.encode('data: ${jsonEncode({'choices': [{'delta': {'content': 'partial '}}]})}\n\n'));
          Future<void>.delayed(const Duration(milliseconds: 20), () => controller.addError(http.ClientException('socket closed')));
          return http.StreamedResponse(controller.stream, 200, headers: {'content-type': 'text/event-stream'});
        }
      ]);
      final got = StringBuffer();
      Object? error;
      try {
        await for (final d in streamChat(provider: prov(), model: 'm1', messages: const [{'role': 'user', 'content': 'x'}], clientFactory: s.factory, sleep: s.sleep)) {
          got.write(d);
        }
      } catch (e) {
        error = e;
      }
      expect(got.toString(), 'partial ');
      expect(error.toString(), contains('dropped in the middle of the reply'));
      expect(s.seen.length, 1, reason: 'no retry once text was shown: it would repeat itself');
    });
  });

  group('empty answers', () {
    test('asks again without streaming, then returns the text', () async {
      final s = Server([
        (_) => stream('data: [DONE]\n\n'),
        (_) => resp(200, jsonEncode({'choices': [{'message': {'content': 'second try'}}]})),
      ]);
      expect(await s.chat(), 'second try');
      expect(s.seen[0]['stream'], true);
      expect(s.seen[1]['stream'], false);
      expect(s.status.single, contains('sent nothing'));
    });

    test('the third try is the plainest request', () async {
      final s = Server([
        (_) => stream('data: [DONE]\n\n'),
        (_) => resp(200, jsonEncode({'choices': [{'message': {'content': ''}}]})),
        (_) => resp(200, jsonEncode({'choices': [{'message': {'content': 'finally'}}]})),
      ]);
      expect(await s.chat(), 'finally');
      expect(s.seen[2].containsKey('temperature'), false);
      expect((s.seen[2]['messages'] as List).length, 1);
    });

    test('three empty answers end with a clear error', () async {
      final s = Server([(_) => stream('data: [DONE]\n\n')]);
      final e = await failure(s.chat);
      expect(e.toString(), allOf(contains('empty answer'), contains('Try another model')));
      expect(s.seen.length, 3);
    });

    test('a model that only thinks and runs out of tokens is named as such', () async {
      final s = Server([(_) => stream(sse([{'reasoning_content': 'hmm ' * 50}], finish: 'length'))]);
      final e = await failure(s.chat);
      expect(e.toString(), contains('spent all its tokens thinking'));
      expect(s.seen.length, 1);
    });
  });

  group('Test connection / Test model show the exact error', () {
    test('testModel: success shows the reply', () async {
      final s = Server([(_) => stream(sse([{'content': 'pong'}]))]);
      final r = await testModel(prov(), 'm1', clientFactory: s.factory, sleep: s.sleep);
      expect(r.ok, true);
      expect(r.message, allOf(contains('m1'), contains('pong')));
    });

    test('testModel: failure carries the provider, the model and the server text', () async {
      final s = Server([(_) => resp(400, jsonEncode({'error': {'message': 'model not enabled for tier'}}))]);
      final r = await testModel(prov(), 'm1', clientFactory: s.factory, sleep: s.sleep);
      expect(r.ok, false);
      expect(r.message, allOf(contains('Test / m1'), contains('model not enabled for tier')));
      expect(r.detail, isNotNull);
    });

    test('testConnection: lists the models', () async {
      final c = MockClient((req) async {
        expect(req.url.toString(), 'https://api.test/v1/models');
        expect(req.headers['Authorization'], 'Bearer k');
        return http.Response(jsonEncode({'data': [{'id': 'a'}, {'id': 'b'}]}), 200);
      });
      final r = await testConnection(prov(), clientFactory: () => c);
      expect(r.ok, true);
      expect(r.message, contains('2 models found'));
    });

    test('testConnection: a wrong key is said plainly, with the server text', () async {
      final c = MockClient((req) async => http.Response(jsonEncode({'error': {'message': 'Invalid API key'}}), 401));
      final r = await testConnection(prov(kind: ProviderKind.nvidia), clientFactory: () => c);
      expect(r.ok, false);
      expect(r.message, allOf(contains('key was refused'), contains('Invalid API key'), contains('401')));
    });

    test('testConnection: no key, a bad URL and an unreachable host are each caught', () async {
      expect((await testConnection(prov(kind: ProviderKind.gemini, key: ''))).message, contains('No API key'));
      final bad = ProviderConfig(id: 'x', kind: ProviderKind.custom, name: 'X', baseUrl: 'localhost:11434');
      expect((await testConnection(bad)).message, contains('not a web address'));
      final down = MockClient((req) async => throw http.ClientException('Failed host lookup'));
      final r = await testConnection(prov(), clientFactory: () => down);
      expect(r.ok, false);
      expect(r.message, contains('Could not reach Test'));
    });
  });

  group('model lists (real NVIDIA and OpenRouter lists, Gemini in its documented shape)', () {
    final nvidia = jsonDecode(File('test/fixtures/nvidia_models.json').readAsStringSync());
    final openrouter = jsonDecode(File('test/fixtures/openrouter_models.json').readAsStringSync());

    test('NVIDIA: chat models stay, embedding / safety / retrieval models go', () {
      final list = parseOpenAiModels(nvidia, prov(kind: ProviderKind.nvidia));
      final ids = list.map((m) => m.id).toSet();
      expect(ids, containsAll(['moonshotai/kimi-k3.1-pro', 'minimaxai/minimax-m3.1-flash', 'nvidia/nemotron-3-ultra-550b-a55b', 'google/gemma-4-31b-it', 'poolside/laguna-xs-2.1']));
      for (final bad in ['nvidia/nemotron-3-embed-1b', 'nvidia/nvclip', 'nvidia/llama-3.1-nemoguard-8b-topic-control', 'nvidia/nemotron-3.5-content-safety', 'snowflake/arctic-embed-l', 'nvidia/ai-synthetic-video-detector', 'nvidia/riva-translate-4b-instruct-v2']) {
        expect(ids.contains(bad), false, reason: bad);
      }
      expect(list.length, lessThan((nvidia['data'] as List).length));
    });

    test('a custom endpoint keeps every model: nothing is filtered, any ID can be used', () {
      final list = parseOpenAiModels(nvidia, prov());
      expect(list.length, (nvidia['data'] as List).length);
    });

    test('OpenRouter: names and context sizes come from the list', () {
      final list = parseOpenAiModels(openrouter, prov(kind: ProviderKind.openrouter));
      expect(list.length, (openrouter['data'] as List).length);
      final first = list.first;
      expect(first.id, (openrouter['data'] as List).first['id']);
      expect(first.name, (openrouter['data'] as List).first['name']);
      expect(first.context, (openrouter['data'] as List).first['context_length']);
      expect(list.any((m) => m.id.endsWith(':free')), true, reason: 'free models are ordinary models: no free/paid split');
    });

    test('Gemini: only models that can generate text, without the models/ prefix', () {
      final list = parseGeminiModels({
        'models': [
          {'name': 'models/gemini-2.5-flash', 'displayName': 'Gemini 2.5 Flash', 'inputTokenLimit': 1048576, 'supportedGenerationMethods': ['generateContent', 'countTokens']},
          {'name': 'models/text-embedding-004', 'displayName': 'Embedding', 'supportedGenerationMethods': ['embedContent']},
          {'name': 'models/gemini-2.5-flash-preview-tts', 'displayName': 'TTS', 'supportedGenerationMethods': ['generateContent']},
          {'name': 'models/imagen-4', 'supportedGenerationMethods': ['predict']},
          {'broken': true},
        ],
      }, 'g');
      expect(list.map((m) => m.id), ['gemini-2.5-flash']);
      expect(list.single.name, 'Gemini 2.5 Flash');
      expect(list.single.context, 1048576);
    });

    test('odd shapes do not crash: a bare list, "models", nothing at all', () {
      final p = prov();
      expect(parseOpenAiModels([{'id': 'a'}, 'b', {'name': 'c'}, {'id': 'a'}], p).map((m) => m.id), ['a', 'b', 'c']);
      expect(parseOpenAiModels({'models': [{'id': 'z'}]}, p).single.id, 'z');
      expect(parseOpenAiModels({'object': 'list'}, p), isEmpty);
      expect(parseOpenAiModels('nonsense', p), isEmpty);
    });

    test('fetchModels asks the right URL with the key and returns the parsed list', () async {
      final urls = <String>[];
      final c = MockClient((req) async {
        urls.add(req.url.toString());
        return http.Response(jsonEncode(nvidia), 200);
      });
      final list = await fetchModels(ProviderConfig(id: 'n', kind: ProviderKind.nvidia, name: 'NVIDIA NIM', baseUrl: 'https://integrate.api.nvidia.com/v1/', apiKey: 'nvapi-x'), clientFactory: () => c);
      expect(urls, ['https://integrate.api.nvidia.com/v1/models']);
      expect(list.any((m) => m.id == 'moonshotai/kimi-k3.1-pro'), true);
    });
  });

  group('helpers', () {
    test('serverText reads the common error shapes', () {
      expect(serverText(jsonEncode({'error': {'message': 'a'}})), 'a');
      expect(serverText(jsonEncode([{'error': {'message': 'gemini style', 'status': 'X'}}])), 'gemini style');
      expect(serverText(jsonEncode({'error': 'plain string'})), 'plain string');
      expect(serverText(jsonEncode({'detail': 'nvidia style'})), 'nvidia style');
      expect(serverText('<html>gateway</html>'), '<html>gateway</html>');
    });

    test('retryAfter: header first, then the text', () {
      expect(retryAfter({'Retry-After': '7'}, ''), const Duration(seconds: 7));
      expect(retryAfter({}, '{"retryDelay": "35s"}'), const Duration(seconds: 35));
      expect(retryAfter({}, 'nothing here'), isNull);
    });
  });
}
