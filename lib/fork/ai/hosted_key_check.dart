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

  /// The provider's own words for a refusal, or a plain fallback.
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
      _providerMessage(response.body) ?? 'The provider refused this key',
    );
  }
  return const HostedKeyResult(HostedKeyVerdict.unchecked);
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
