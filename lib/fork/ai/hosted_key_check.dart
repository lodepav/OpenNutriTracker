import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';

/// How long OK waits for a hosted provider to answer the key check (S357).
const hostedKeyCheckTimeout = Duration(seconds: 8);

enum HostedKeyVerdict {
  /// The provider accepted the key.
  checked,

  /// The provider refused the key (401); it is not saved.
  refused,

  /// Nothing answered in time; the key is saved unchecked.
  offline,

  /// The provider answered something else (a 403 is permission or region,
  /// not a mistyped key; a 429, a 5xx); saved unchecked.
  unchecked,
}

class HostedKeyResult {
  final HostedKeyVerdict verdict;

  /// For a refusal: the app's sentence naming the next step, then the
  /// provider's own words, if it gave any, on a line of their own.
  final String? message;

  const HostedKeyResult(this.verdict, [this.message]);
}

/// The cheapest request each hosted provider answers only with a valid key.
/// OpenRouter's model list is public, so its key route is asked instead.
http.Request hostedKeyCheckRequest(AiProvider provider, String key) =>
    switch (provider) {
      AiProvider.anthropic =>
        http.Request('GET', Uri.parse('https://api.anthropic.com/v1/models'))
          ..headers.addAll({
            'x-api-key': key,
            'anthropic-version': '2023-06-01',
          }),
      AiProvider.openai =>
        http.Request('GET', Uri.parse('https://api.openai.com/v1/models'))
          ..headers['authorization'] = 'Bearer $key',
      AiProvider.openrouter =>
        http.Request('GET', Uri.parse('https://openrouter.ai/api/v1/key'))
          ..headers['authorization'] = 'Bearer $key',
      AiProvider.ownServer => throw ArgumentError.value(
        provider,
        'provider',
        'a server the user runs has its own setup check',
      ),
    };

/// Asks [provider] whether [key] works. Never throws.
Future<HostedKeyResult> checkHostedKey(
  http.Client client,
  AiProvider provider,
  String key, {
  Duration timeout = hostedKeyCheckTimeout,
}) async {
  final http.Response response;
  try {
    response = await client
        .send(hostedKeyCheckRequest(provider, key))
        .then(http.Response.fromStream)
        .timeout(timeout);
  } catch (_) {
    // Not bound: a socket error can carry the request, and the request carries the key.
    return const HostedKeyResult(HostedKeyVerdict.offline);
  }
  if (response.statusCode == 200) {
    return const HostedKeyResult(HostedKeyVerdict.checked);
  }
  if (response.statusCode == 401) {
    return HostedKeyResult(
      HostedKeyVerdict.refused,
      _refusedKeyMessage(provider, _providerMessage(response.body)),
    );
  }
  return const HostedKeyResult(HostedKeyVerdict.unchecked);
}

/// A refusal in the app's words: the provider's own ("Missing
/// Authentication header") read as an app bug and gave no next step.
String _refusedKeyMessage(AiProvider provider, String? providerSaid) {
  final name = switch (provider) {
    AiProvider.anthropic => 'Anthropic',
    AiProvider.openai => 'OpenAI',
    AiProvider.openrouter => 'OpenRouter',
    // Never asked: its request is not built (hostedKeyCheckRequest)
    AiProvider.ownServer => throw ArgumentError.value(provider, 'provider'),
  };
  final lead =
      "$name didn't accept this key. It was not saved. "
      'Check it on your $name keys page.';
  return providerSaid == null ? lead : '$lead\n$name said: $providerSaid';
}

/// `error.message` in the shape all three providers answer a refusal with.
String? _providerMessage(String body) {
  try {
    final error = (jsonDecode(body) as Map<String, dynamic>)['error'];
    final message = error is Map<String, dynamic> ? error['message'] : null;
    return message is String && message.trim().isNotEmpty
        ? message.trim()
        : null;
  } catch (_) {
    return null;
  }
}
