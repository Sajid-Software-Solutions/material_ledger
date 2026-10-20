import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_notification.dart';

void main() {
  const propertyId = '83000000-0000-4000-8000-000000000010';
  const events = [
    'rental_lease_notice_due',
    'rental_lease_expired',
    'rental_cheque_due',
    'rental_cheque_returned',
    'rental_rent_due',
    'rental_rent_overdue',
  ];
  YorksV1NotificationRecord record(
    String event,
    String entityType,
    String id,
  ) => YorksV1NotificationRecord.fromRpcJson({
    'notification_id': '83000000-0000-4000-8000-000000000001',
    'event_code': event,
    'entity_type': entityType,
    'entity_id': id,
    'created_at': '2026-10-20T10:00:00Z',
    'module_route': event == 'rental_completeness_review'
        ? '/rentals'
        : '/rentals/$id',
    'record_label': 'RU-10',
  });

  test(
    'rental obligations open their property in every configured language',
    () {
      for (final event in events) {
        for (final language in AppLanguage.values) {
          final notification = record(
            event,
            'rental_property',
            propertyId,
          ).toAppNotification(language);
          expect(notification.route, '/rentals/$propertyId');
          expect(notification.title, isNotEmpty);
          expect(notification.body, isNotEmpty);
          expect(notification.body, isNot(contains('AED')));
          expect(notification.titleSecondary, 'RU-10');
        }
      }
    },
  );

  test('completeness review opens register; malformed targets fail safely', () {
    expect(
      record(
        'rental_completeness_review',
        'rental_portfolio',
        propertyId,
      ).toAppNotification(AppLanguage.english).route,
      '/rentals',
    );
    for (final event in events) {
      expect(
        record(
          event,
          'material_request',
          propertyId,
        ).toAppNotification(AppLanguage.english).route,
        isEmpty,
      );
      expect(
        record(
          event,
          'rental_property',
          '//attacker.example',
        ).toAppNotification(AppLanguage.english).route,
        isEmpty,
      );
    }
  });

  test('missing or unrelated server context cannot revive a rental link', () {
    for (final route in [null, '/yorks/workforce/timesheets']) {
      final notification = YorksV1NotificationRecord.fromRpcJson({
        'notification_id': '83000000-0000-4000-8000-000000000001',
        'event_code': 'rental_cheque_returned',
        'entity_type': 'rental_property',
        'entity_id': propertyId,
        'created_at': '2026-10-20T10:00:00Z',
        'module_route': route,
      }).toAppNotification(AppLanguage.english);
      expect(notification.route, isEmpty);
      expect(notification.body, contains('no available detail link'));
    }
  });
}
