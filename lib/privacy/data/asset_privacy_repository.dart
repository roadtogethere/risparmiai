import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/privacy_repository.dart';

class AssetPrivacyRepository implements PrivacyRepository {
  AssetPrivacyRepository({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  static const viewedVersionKey = 'privacy.viewed_notice_version';

  @override
  Future<bool> hasViewedCurrentNotice() async =>
      (await SharedPreferences.getInstance()).getString(viewedVersionKey) ==
      privacyNoticeVersion;

  @override
  Future<void> markCurrentNoticeViewed() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(viewedVersionKey, privacyNoticeVersion)) {
      throw StateError('Unable to store privacy notice acknowledgement');
    }
  }

  @override
  Future<String> loadNotice(String languageCode) => _bundle.loadString(
    'assets/privacy_policy/privacy_policy_${languageCode == 'en' ? 'en' : 'it'}.md',
  );
}
