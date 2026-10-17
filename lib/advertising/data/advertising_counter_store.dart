import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AdvertisingCounterStore {
  static const key = 'advertising.interstitial.v1';

  Future<({int saves, DateTime? lastShown})> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return (saves: 0, lastShown: null);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return (
      saves: data['saves'] as int,
      lastShown: DateTime.tryParse(data['lastShown'] as String? ?? ''),
    );
  }

  Future<void> write(int saves, DateTime? lastShown) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      key,
      jsonEncode({
        'saves': saves,
        'lastShown': lastShown?.toUtc().toIso8601String(),
      }),
    )) {
      throw StateError('Unable to persist advertising counters');
    }
  }
}
