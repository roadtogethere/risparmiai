import 'package:flutter/foundation.dart';

/// Local development diagnostics only; no ad IDs or user/product data.
void logAdvertisingEvent(
  String format,
  String event, {
  String? trigger,
  int? errorCode,
  int? events,
  int? newAnalyses,
  int? cooldownSeconds,
}) {
  if (!kDebugMode) return;
  debugPrint(
    '[AdMob][$format] $event'
    '${trigger == null ? '' : ' trigger=$trigger'}'
    '${errorCode == null ? '' : ' errorCode=$errorCode'}'
    '${events == null ? '' : ' events=$events'}'
    '${newAnalyses == null ? '' : ' newAnalyses=$newAnalyses'}'
    '${cooldownSeconds == null ? '' : ' cooldownSeconds=$cooldownSeconds'}',
  );
}
