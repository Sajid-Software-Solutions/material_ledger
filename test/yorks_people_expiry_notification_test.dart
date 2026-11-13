import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_notification.dart';

/// The daily document expiry summary (PRODUCT_DECISIONS section 44).
void main() {
  YorksV1NotificationRecord record(String event, String? route) =>
      YorksV1NotificationRecord.fromRpcJson({
        'notification_id': '84000000-0000-4000-8000-000000000001',
        'event_code': event,
        'entity_type': 'people_expiry_digest',
        'entity_id': '84000000-0000-4000-8000-000000000002',
        'created_at': '2026-11-14T04:15:00Z',
        'module_route': route,
        'record_label': '17',
      });

  test('the summary opens People in every language, urgent when expired', () {
    for (final language in AppLanguage.values) {
      final expired = record(
        'people_documents_overdue',
        '/yorks/people',
      ).toAppNotification(language);
      expect(expired.route, '/yorks/people');
      expect(expired.isUrgent, isTrue);
      expect(expired.title, isNotEmpty);
      expect(expired.body, isNotEmpty);
      expect(expired.titleSecondary, '17');

      final expiring = record(
        'people_documents_due',
        '/yorks/people',
      ).toAppNotification(language);
      expect(expiring.isUrgent, isFalse);
      expect(expiring.title, isNot(expired.title));
    }
  });

  test('company documents alone open Company documents', () {
    expect(
      record(
        'people_documents_due',
        '/yorks/company-documents',
      ).toAppNotification(AppLanguage.english).route,
      '/yorks/company-documents',
    );
  });

  test('a missing or unsafe link still opens People', () {
    expect(
      record(
        'people_documents_overdue',
        null,
      ).toAppNotification(AppLanguage.english).route,
      '/yorks/people',
    );
    expect(
      record(
        'people_documents_overdue',
        '//attacker.example',
      ).toAppNotification(AppLanguage.english).route,
      '/yorks/people',
    );
  });
}
