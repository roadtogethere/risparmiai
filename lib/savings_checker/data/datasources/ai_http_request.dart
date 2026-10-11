import 'package:http/http.dart' as http;

/// Owns one client per attempt, including response-body consumption.
/// Future.timeout discards late completion; close also releases/aborts the
/// transport where supported, but cannot guarantee cancellation at the server.
Future<http.Response> postAiRequest(
  Uri uri, {
  required Map<String, String> headers,
  required String body,
  required Duration timeout,
  required http.Client Function() clientFactory,
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
  }
  final client = clientFactory();
  try {
    return await client
        .post(uri, headers: headers, body: body)
        .timeout(timeout);
  } finally {
    client.close();
  }
}
