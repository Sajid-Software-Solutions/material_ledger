import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:material_ledger/app/router.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/notification_module_catalogue.dart';
import 'package:material_ledger/shared/models/yorks_v1_notification.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_notification_repository.dart';

void main() {
  test(
    'authentication return intent preserves record and comment and rejects external URLs',
    () {
      const target =
          '/yorks/material-requests/record?comment=comment&notificationId=event';
      final login = Uri.parse(
        guardedReturnLocation('/login', Uri.parse(target)),
      );
      final password = Uri.parse(
        guardedReturnLocation('/change-password', login),
      );
      expect(safeReturnLocation(password.queryParameters['returnTo']), target);
      var gate = Uri.parse(target);
      for (final path in [
        '/maintenance',
        '/update-required',
        '/splash',
        '/language-selection',
        '/login',
        '/change-password',
      ]) {
        gate = Uri.parse(guardedReturnLocation(path, gate));
        expect(gate.queryParameters['returnTo'], target);
      }
      for (final bad in [
        'https://evil.test',
        '//evil.test',
        '/\\evil.test',
        '/login',
        '/change-password',
        '/hello\nworld',
      ]) {
        expect(safeReturnLocation(bad), isNull, reason: bad);
      }
    },
  );

  test(
    'repository decodes the paged RPC and keeps Chat out of history',
    () async {
      final client = SupabaseClient(
        'https://ci.invalid',
        'test',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/v1_notification_page');
          final body = jsonDecode(request.body) as Map;
          expect(body['p_limit'], 2);
          expect(body['p_unread_only'], true);
          return http.Response(
            jsonEncode({
              'records': [_row('3'), _row('2'), _row('1')],
              'attention': [_row('chat', chat: true)],
              'unreadCount': 10001,
              'servicePaused': true,
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final page = await YorksV1SupabaseNotificationRepository(
        client,
      ).page(limit: 2, unreadOnly: true);
      expect(page.records.map((n) => n.id), ['3', '2']);
      expect(page.attention.single.isChatTransport, isTrue);
      expect(page.unreadCount, 10001);
      expect(page.hasMore, isTrue);
      expect(page.servicePaused, isTrue);
    },
  );

  test(
    'malformed server response is an error, never an empty success',
    () async {
      final client = SupabaseClient(
        'https://ci.invalid',
        'test',
        httpClient: MockClient(
          (request) async => http.Response(
            '{}',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          ),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        YorksV1SupabaseNotificationRepository(client).page(),
        throwsFormatException,
      );
    },
  );

  test(
    'server module destination retains exact record and rejects external links',
    () {
      const target =
          '/yorks/projects/ab100000-0000-4000-8000-000000000001/accounts/client-invoices?invoice_id=ab200000-0000-4000-8000-000000000001';
      final row = {
        ..._row('module'),
        'event_code': 'accounts_claim_returned',
        'module_route': target,
      };
      final record = YorksV1NotificationRecord.fromRpcJson(row);
      expect(record.toAppNotification(AppLanguage.english).route, target);
      expect(record.acknowledgedAt(DateTime.now()).moduleRoute, target);
      expect(
        YorksV1NotificationRecord.fromRpcJson({
          ...row,
          'module_route': 'https://evil.test',
        }).moduleRoute,
        isNull,
      );
    },
  );

  test(
    'every module event has localized copy and a protected workspace destination',
    () {
      for (final code in notificationModuleEvents.keys) {
        for (final language in AppLanguage.values) {
          final n = YorksV1NotificationRecord(
            id: 'id',
            eventCode: code,
            entityType: code.startsWith('rental_')
                ? (code == 'rental_completeness_review'
                      ? 'rental_portfolio'
                      : 'rental_property')
                : code.startsWith('accounts_')
                ? 'accounts_client_invoice'
                : 'workforce_monthly_period',
            entityId: '83000000-0000-4000-8000-000000000010',
            moduleRoute: code.startsWith('rental_')
                ? (code == 'rental_completeness_review'
                      ? '/rentals'
                      : '/rentals/83000000-0000-4000-8000-000000000010')
                : null,
            projectId: 'project',
            createdAt: DateTime.now(),
          ).toAppNotification(language);
          expect(n.title, isNot('Yorks workflow update'));
          expect(
            n.route,
            startsWith(code.startsWith('rental_') ? '/rentals' : '/yorks/'),
          );
          expect(n.body, isNotEmpty);
          expect(n.isUrgent, code.endsWith('_overdue'));
        }
      }
    },
  );
}

Map<String, Object?> _row(String id, {bool chat = false}) => {
  'notification_id': id,
  'event_code': chat ? 'team_chat_message' : 'material_request_submitted',
  'entity_type': chat ? 'chat_message' : 'material_request',
  'entity_id': 'entity',
  'created_at': '2026-09-30T12:00:00Z',
  'seen_at': null,
};
