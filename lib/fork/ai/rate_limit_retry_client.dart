import 'package:http/http.dart' as http;

/// Asks once more after a 429, a moment later, so a vendor's brief rate
/// limit is not shown to the user as a failed read. Every client
/// `mealItemsApiFor` builds sends through one (S171).
///
/// Live runs through OpenRouter on 2026-10-28 got occasional 429s from the
/// OpenAI and Anthropic endpoints with one call in flight; they cleared on
/// the next try. One retry only, and only for a short wait: the client's own timeout
/// still covers both attempts, so a read never takes longer than before. A
/// `retry-after` longer than [maxWait] is passed through at once, as is the
/// second 429, and the client classifies it as it always did (an OpenAI
/// quota 429 stays a quota failure).
class RateLimitRetryClient extends http.BaseClient {
  /// The wait when the vendor names none.
  static const defaultWait = Duration(seconds: 2);

  /// The longest wait worth taking inside a 20 s read.
  static const maxWait = Duration(seconds: 5);

  final http.Client _inner;
  final Future<void> Function(Duration) _sleep;

  RateLimitRetryClient(this._inner, {Future<void> Function(Duration)? sleep})
    : _sleep = sleep ?? Future<void>.delayed;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) return _inner.send(request);
    final first = await _inner.send(request);
    if (first.statusCode != 429) return first;
    final wait = _waitFor(first.headers['retry-after']);
    if (wait == null) return first;
    await first.stream.drain<void>();
    await _sleep(wait);
    return _inner.send(_copy(request));
  }

  /// A request is sent only once, so the second attempt is a copy.
  static http.Request _copy(http.Request request) =>
      http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection
        ..bodyBytes = request.bodyBytes;

  /// [defaultWait] with no `retry-after`, its seconds when within
  /// [maxWait], or null for a longer one (or an HTTP date, which means one).
  static Duration? _waitFor(String? retryAfter) {
    if (retryAfter == null) return defaultWait;
    final seconds = double.tryParse(retryAfter.trim());
    if (seconds == null || seconds < 0) return null;
    final wait = Duration(milliseconds: (seconds * 1000).round());
    return wait > maxWait ? null : wait;
  }
}
