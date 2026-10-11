import 'dart:async';
import 'package:http/http.dart' as http;
import '../../domain/entities/savings_failure.dart';

/// Owns one client per attempt, including response-body consumption.
/// Future.timeout discards late completion; close also releases/aborts the
/// transport where supported, but cannot guarantee cancellation at the server.
Future<http.Response> postAiRequest(
  Uri uri, {
  required Map<String, String> headers,
  required String body,
  required Duration timeout,
  required http.Client Function() clientFactory,
  Duration totalTimeout = const Duration(seconds: 30),
  Duration retryDelay = const Duration(milliseconds: 500),
  bool automaticRetry = true,
}) async {
  if (timeout <= Duration.zero ||
      totalTimeout <= Duration.zero ||
      retryDelay.isNegative) {
    throw const SavingsFailure(SavingsFailureKind.configurationError);
  }
  final watch = Stopwatch()..start();
  for (var attempt = 0; ; attempt++) {
    final remaining = totalTimeout - watch.elapsed;
    if (remaining <= Duration.zero) {
      throw const SavingsFailure(SavingsFailureKind.timeout);
    }
    final client = clientFactory();
    late http.Response response;
    try {
      response = await client
          .post(uri, headers: headers, body: body)
          .timeout(timeout < remaining ? timeout : remaining);
    } on TimeoutException {
      throw const SavingsFailure(SavingsFailureKind.timeout);
    } on http.ClientException {
      // ClientException does not reliably distinguish transient failures from
      // TLS, browser policy or permanent connectivity errors. Manual retry only.
      throw const SavingsFailure(SavingsFailureKind.networkError);
    } finally {
      client.close();
    }
    if (response.statusCode == 200) return response;
    final kind = switch (response.statusCode) {
      429 => SavingsFailureKind.rateLimited,
      500 || 502 || 503 || 504 => SavingsFailureKind.serviceUnavailable,
      401 || 403 => SavingsFailureKind.authenticationError,
      _ => SavingsFailureKind.configurationError,
    };
    if (!automaticRetry ||
        attempt > 0 ||
        (kind != SavingsFailureKind.rateLimited &&
            kind != SavingsFailureKind.serviceUnavailable)) {
      throw SavingsFailure(kind);
    }
    final retryAfter = parseRetryAfter(
      response.headers['retry-after'],
      DateTime.now().toUtc(),
    );
    final delay = retryAfter != null && retryAfter > retryDelay
        ? retryAfter
        : retryDelay;
    if (delay >= totalTimeout - watch.elapsed) throw SavingsFailure(kind);
    await Future<void>.delayed(delay);
  }
}

/// Retry-After delta-seconds or IMF-fixdate, without platform-specific dart:io.
Duration? parseRetryAfter(String? header, DateTime now) {
  if (header == null) return null;
  final value = header.trim();
  final seconds = int.tryParse(value);
  if (seconds != null && seconds >= 0) {
    // Avoid Duration overflow; a day already exceeds the interactive budget.
    return Duration(seconds: seconds > 86400 ? 86400 : seconds);
  }
  final match = RegExp(
    r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value);
  if (match == null) return null;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months.indexOf(match[2]!) + 1;
  if (month == 0) return null;
  final date = DateTime.utc(
    int.parse(match[3]!),
    month,
    int.parse(match[1]!),
    int.parse(match[4]!),
    int.parse(match[5]!),
    int.parse(match[6]!),
  );
  final delay = date.difference(now);
  return delay.isNegative ? Duration.zero : delay;
}
