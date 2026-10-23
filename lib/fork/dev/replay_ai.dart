import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Answers Anthropic's messages endpoint from answers written beforehand,
/// so a real model's replies can be run through the app without the app
/// calling one. A Claude Code subagent plays the model (fork/eval/REPLAY.md).
///
/// A request with no answer yet is saved under `requests/` as
/// `<key>.json` (the system prompt, the tool, the text) and `<key>.jpg`
/// when it carries a photo, and fails with a 503, which the app offers to
/// retry. Once `answers/<key>.json` holds the tool's input, the same
/// request is answered with it. The key is a hash of the request body, so
/// the same photo and prompt always find the same answer.
class ReplayAiClient extends http.BaseClient {
  final http.Client _inner;
  final Future<Directory> Function() _dir;

  ReplayAiClient(this._inner, this._dir);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host != 'api.anthropic.com' || request is! http.Request) {
      return _inner.send(request);
    }
    final dir = await _dir();
    final key = replayKey(request.body);
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final tool = (body['tools'] as List).first as Map<String, dynamic>;
    final answer = File('${dir.path}/answers/$key.json');
    if (!answer.existsSync()) {
      _saveRequest(Directory('${dir.path}/requests'), key, body, tool);
      return _reply(503, {'error': 'no replay answer for $key yet'});
    }
    return _reply(200, {
      'content': [
        {
          'type': 'tool_use',
          'id': key,
          'name': tool['name'],
          'input': jsonDecode(answer.readAsStringSync()),
        },
      ],
      'stop_reason': 'tool_use',
    });
  }

  static void _saveRequest(
    Directory dir,
    String key,
    Map<String, dynamic> body,
    Map<String, dynamic> tool,
  ) {
    dir.createSync(recursive: true);
    final text = StringBuffer();
    String? image;
    for (final message in body['messages'] as List) {
      final content = (message as Map)['content'];
      if (content is String) text.writeln(content);
      for (final block in content is List ? content : const []) {
        if (block['type'] == 'text') text.writeln(block['text']);
        if (block['type'] == 'image') {
          image = '$key.jpg';
          File(
            '${dir.path}/$image',
          ).writeAsBytesSync(base64Decode('${block['source']['data']}'));
        }
      }
    }
    File('${dir.path}/$key.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'system': body['system'],
        'tool': {
          'name': tool['name'],
          'description': tool['description'],
          'input_schema': tool['input_schema'],
        },
        'text': text.toString().trim(),
        'image': image,
      }),
    );
  }

  static http.StreamedResponse _reply(int status, Object json) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(json))),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// FNV-1a over the request body, as 16 hex digits.
String replayKey(String body) {
  var hash = 0xcbf29ce484222325;
  for (final unit in utf8.encode(body)) {
    hash = (hash ^ unit) * 0x100000001b3;
  }
  // Two halves: a 64-bit int past 2^63 is negative and prints with a sign.
  return [
    hash >>> 32,
    hash & 0xffffffff,
  ].map((half) => half.toRadixString(16).padLeft(8, '0')).join();
}
