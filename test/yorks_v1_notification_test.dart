import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/app_notification.dart';
import 'package:material_ledger/shared/models/yorks_v1_notification.dart';
import 'package:material_ledger/shared/services/push_service.dart';

void main() {
  test('push payload keeps Team Chat on its dedicated surface', () {
    final chat = PushMessage.fromData({
      'notificationId': '21000000-0000-4000-8000-000000000001',
      'eventCode': 'team_chat_message',
      'surface': 'team_chat',
      'type': 'info',
      'title': 'New Team Chat message',
      'route': '/yorks/team-chat/22000000-0000-4000-8000-000000000001',
    });
    final workflow = PushMessage.fromData({
      'eventCode': 'material_request_submitted',
      'surface': 'workflow',
      'type': 'request',
      'title': 'New material request',
    });

    expect(chat.isTeamChat, isTrue);
    expect(workflow.isTeamChat, isFalse);
  });

  const requestId = '22000000-0000-4000-8000-000000000001';

  YorksV1NotificationRecord record({
    String eventCode = 'material_request_submitted',
    DateTime? seenAt,
  }) {
    return YorksV1NotificationRecord.fromRpcJson({
      'notification_id': '21000000-0000-4000-8000-000000000001',
      'event_code': eventCode,
      'entity_type': 'material_request',
      'entity_id': requestId,
      'request_id': requestId,
      'project_id': '23000000-0000-4000-8000-000000000001',
      'created_at': '2026-08-09T12:00:00Z',
      'seen_at': seenAt?.toUtc().toIso8601String(),
    });
  }

  test('server notification maps to the exact Material Request route', () {
    final notification = record().toAppNotification(AppLanguage.english);

    expect(notification.origin, NotificationOrigin.yorksV1);
    expect(notification.type, NotificationType.request);
    expect(notification.refId, requestId);
    expect(notification.route, '/yorks/material-requests/$requestId');
    expect(notification.isRead, isFalse);
    expect(notification.title, 'New material request');
  });

  test('company decisions use specific copy and the company request route', () {
    for (final eventCode in <String>[
      'company_material_request_approval_requested',
      'company_material_request_approved',
      'company_material_request_returned',
      'company_material_request_rejected',
      'company_material_request_cancelled',
    ]) {
      final notification = YorksV1NotificationRecord.fromRpcJson({
        'notification_id': '21000000-0000-4000-8000-000000000005',
        'event_code': eventCode,
        'entity_type': 'company_material_request',
        'entity_id': requestId,
        'request_id': null,
        'project_id': null,
        'created_at': '2026-09-18T12:00:00Z',
        'seen_at': null,
      }).toAppNotification(AppLanguage.english);

      expect(notification.route, '/yorks/material-requests/company/$requestId');
      expect(notification.refId, requestId);
      expect(notification.title, isNot('Yorks workflow update'));
      expect(notification.body.trim(), isNotEmpty);
    }
  });

  test('request comment mention opens and identifies the exact comment', () {
    const commentId = '26000000-0000-4000-8000-000000000001';
    final record = YorksV1NotificationRecord.fromRpcJson({
      'notification_id': '21000000-0000-4000-8000-000000000004',
      'event_code': 'material_request_mentioned',
      'entity_type': 'chat_message',
      'entity_id': commentId,
      'request_id': requestId,
      'project_id': '23000000-0000-4000-8000-000000000001',
      'chat_conversation_id': '27000000-0000-4000-8000-000000000001',
      'created_at': '2026-08-09T12:00:00Z',
      'seen_at': null,
    });

    expect(record.isChatTransport, isFalse);
    expect(
      record.toAppNotification(AppLanguage.english).route,
      '/yorks/material-requests/$requestId?comment=$commentId',
    );
  });

  test('seen_at is the only authoritative read-state source', () {
    final notification = record(
      seenAt: DateTime.utc(2026, 8, 9, 12, 5),
    ).toAppNotification(AppLanguage.english);

    expect(notification.isRead, isTrue);
  });

  test('workflow notification copy supports every configured language', () {
    for (final language in AppLanguage.values) {
      final notification = record().toAppNotification(language);
      expect(notification.title.trim(), isNotEmpty, reason: language.code);
      expect(notification.body.trim(), isNotEmpty, reason: language.code);
    }
  });

  test(
    'preparation completion is informational and opens its request in every language',
    () {
      for (final language in AppLanguage.values) {
        final notification = YorksV1NotificationRecord.fromRpcJson({
          'notification_id': '21000000-0000-4000-8000-000000000009',
          'event_code': 'arrangement_preparation_completed',
          'entity_type': 'procurement_arrangement',
          'entity_id': '25000000-0000-4000-8000-000000000009',
          'request_id': requestId,
          'project_id': '23000000-0000-4000-8000-000000000001',
          'created_at': '2026-10-09T12:00:00Z',
        }).toAppNotification(language);
        expect(notification.type, NotificationType.info, reason: language.code);
        expect(notification.route, '/yorks/material-requests/$requestId');
        expect(
          notification.title,
          isNot(
            record(
              eventCode: 'future_server_event',
            ).toAppNotification(language).title,
          ),
        );
        expect(notification.body.trim(), isNotEmpty, reason: language.code);
      }
      expect(
        record(
          eventCode: 'arrangement_preparation_completed',
        ).toAppNotification(AppLanguage.english).title,
        'Materials prepared',
      );
    },
  );

  test('unknown server event remains safe and routes to its request', () {
    final notification = record(
      eventCode: 'future_server_event',
    ).toAppNotification(AppLanguage.english);

    expect(notification.type, NotificationType.info);
    expect(notification.title, 'Yorks workflow update');
    expect(notification.route, '/yorks/material-requests/$requestId');
  });

  test('project membership alert uses the protected project route', () {
    final notification = YorksV1NotificationRecord.fromRpcJson({
      'notification_id': '21000000-0000-4000-8000-000000000002',
      'event_code': 'project_member_assigned',
      'entity_type': 'project_member',
      'entity_id': '24000000-0000-4000-8000-000000000001',
      'request_id': null,
      'project_id': '23000000-0000-4000-8000-000000000001',
      'created_at': '2026-08-13T12:00:00Z',
      'seen_at': null,
    }).toAppNotification(AppLanguage.english);

    expect(notification.title, 'Project access assigned');
    expect(
      notification.route,
      '/yorks/projects/23000000-0000-4000-8000-000000000001',
    );
  });

  test('return decisions and cancellation have specific safe copy', () {
    expect(
      record(
        eventCode: 'material_return_confirmed',
      ).toAppNotification(AppLanguage.english).title,
      'Material return confirmed',
    );
    expect(
      record(
        eventCode: 'material_request_cancelled',
      ).toAppNotification(AppLanguage.english).title,
      'Material request cancelled',
    );
  });

  test('material return notifications open the standalone return record', () {
    final returnNotification = YorksV1NotificationRecord.fromRpcJson({
      'notification_id': '21000000-0000-4000-8000-000000000003',
      'event_code': 'material_return_approval_required',
      'entity_type': 'material_return',
      'entity_id': '25000000-0000-4000-8000-000000000001',
      // A legacy request association must not override the first-class return
      // destination.
      'request_id': requestId,
      'project_id': '23000000-0000-4000-8000-000000000001',
      'created_at': '2026-08-24T12:00:00Z',
      'seen_at': null,
    }).toAppNotification(AppLanguage.english);

    expect(returnNotification.refId, '25000000-0000-4000-8000-000000000001');
    expect(
      returnNotification.route,
      '/yorks/returns/25000000-0000-4000-8000-000000000001',
    );
    expect(returnNotification.title, 'Material return approval required');
  });

  test('every controlled material return transition has specific copy', () {
    for (final eventCode in <String>[
      'material_return_approval_required',
      'material_return_approved',
      'material_return_returned_for_changes',
      'material_return_rejected',
      'material_return_receipt_required',
      'material_return_confirmed',
      'material_return_cancelled',
    ]) {
      final notification = record(
        eventCode: eventCode,
      ).toAppNotification(AppLanguage.english);
      expect(
        notification.title,
        isNot('Yorks workflow update'),
        reason: eventCode,
      );
      expect(notification.body.trim(), isNotEmpty, reason: eventCode);
    }
  });

  test('work assignment uses specific localized request copy', () {
    for (final language in AppLanguage.values) {
      final notification = record(
        eventCode: 'material_request_work_assigned',
      ).toAppNotification(language);

      expect(notification.type, NotificationType.request);
      expect(notification.title.trim(), isNotEmpty, reason: language.code);
      expect(notification.body.trim(), isNotEmpty, reason: language.code);
      expect(notification.route, '/yorks/material-requests/$requestId');
    }
  });

  test(
    'all-unavailable alert keeps the request open for a deliberate action',
    () {
      final notification = record(
        eventCode: 'arrangement_completed_unavailable',
      ).toAppNotification(AppLanguage.english);

      expect(notification.title, 'All items currently unavailable');
      expect(notification.body, contains('Procurement can revise'));
      expect(notification.body, contains('cancel the request'));
      expect(notification.body.toLowerCase(), isNot(contains('completed')));
    },
  );

  test('legacy JSON remains legacy while server origin round-trips', () {
    final legacy = AppNotification.fromJson({
      'id': 'legacy',
      'type': 'info',
      'title': 'Legacy',
      'timestamp': '2026-08-09T12:00:00Z',
    });
    expect(legacy.origin, NotificationOrigin.legacy);

    final server = record().toAppNotification(AppLanguage.english);
    expect(
      AppNotification.fromJson(server.toJson()).origin,
      NotificationOrigin.yorksV1,
    );
  });
}
