import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AdvertisingCounterStore {
  static const key = 'advertising.interstitial.v1';

  Future<
    ({
      int saves,
      int events,
      int newAnalyses,
      int chatMessages,
      DateTime? lastShown,
    })
  >
  read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) {
      return (
        saves: 0,
        events: 0,
        newAnalyses: 0,
        chatMessages: 0,
        lastShown: null,
      );
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return (
      saves: data['saves'] as int,
      events: data['events'] as int? ?? data['saves'] as int,
      newAnalyses: data['newAnalyses'] as int? ?? 0,
      chatMessages: data['chatMessages'] as int? ?? 0,
      lastShown: DateTime.tryParse(data['lastShown'] as String? ?? ''),
    );
  }

  Future<void> write(
    int saves,
    DateTime? lastShown, {
    required int events,
    required int newAnalyses,
    required int chatMessages,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      key,
      jsonEncode({
        'saves': saves,
        'events': events,
        'newAnalyses': newAnalyses,
        'chatMessages': chatMessages,
        'lastShown': lastShown?.toUtc().toIso8601String(),
      }),
    )) {
      throw StateError('Unable to persist advertising counters');
    }
  }
}
