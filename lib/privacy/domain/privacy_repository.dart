const privacyNoticeVersion = '2026-10-17.2';

abstract interface class PrivacyRepository {
  Future<bool> hasViewedCurrentNotice();
  Future<void> markCurrentNoticeViewed();
  Future<String> loadNotice(String languageCode);
}
