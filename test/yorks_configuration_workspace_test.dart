// Configuration against a fake server: the setup checklist, saving company
// bank details with a reviewed reason, a refused value staying on screen,
// Accounts stages that must total 100%, PR's limited view and phone layouts.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/features/configuration/application/configuration_workspace_providers.dart';
import 'package:material_ledger/features/configuration/data/configuration_workspace_repository.dart';
import 'package:material_ledger/features/configuration/presentation/configuration_screen.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/accounts_v2_golden_fonts.dart';

Map<String, Object?> _setting(Object? value, [String mode = 'operational']) => {
  'value': value,
  'mode': mode,
  'type': 'string',
};

Map<String, Object?> _workspace({bool admin = true, int version = 2}) => {
  'version': version,
  'today': '2026-11-13',
  'editable': {
    'company': admin,
    'requests': admin,
    'inventory': admin,
    'projects': admin,
    'accounts': admin,
    'notifications': admin,
    'rentals': true,
    'workforce': true,
  },
  'settings': admin
      ? {
          'company.legal_name': _setting(
            'Example Air Conditioning & Refrigeration LLC',
          ),
          'company.short_name': _setting('Example AC'),
          'company.arabic_name': _setting('مثال للتكييف'),
          'company.address': _setting('P.O. Box 1234, Abu Dhabi, U.A.E'),
          'company.phone': _setting('02-5550000'),
          'company.fax': _setting(''),
          'company.email': _setting('office@example.ae'),
          'company.trn': _setting('100000000000003'),
          'company.bank_name': _setting(''),
          'company.bank_account_name': _setting(''),
          'company.bank_iban': _setting(''),
          'support.developer_whatsapp': _setting('+971500000000'),
          'regional.currency': _setting('AED', 'protected'),
          'regional.timezone': _setting('Asia/Dubai', 'planned'),
          'company.workspace_name': _setting('Example Workspace', 'protected'),
          'documents.allowed_formats': _setting(['PDF', 'XLSX'], 'protected'),
          'documents.maximum_file_size_mb': _setting(20, 'protected'),
          'requests.default_timing': _setting('normal'),
          'requests.urgent_enabled': _setting(true),
          'requests.allow_authorized_creator_self_approval': _setting(true),
          'procurement.require_external_source_readiness': _setting(false),
          'notifications.push_enabled': _setting(true),
          'numbering.material_request_pattern': _setting(
            '{PROJECT_REF}-MR{NNN}',
            'protected',
          ),
          'numbering.dispatch_pattern': _setting(
            '{PROJECT_REF}-DSP{NNN}',
            'protected',
          ),
          'numbering.return_pattern': _setting(
            '{PROJECT_REF}-RTN{NNN}',
            'protected',
          ),
          'numbering.invoice_pattern': _setting(
            'INV-{PROJECT}-{###}',
            'protected',
          ),
        }
      : <String, Object?>{},
  'boq_templates': admin
      ? [
          {
            'id': 't1',
            'key': 'workshop_materials',
            'name': 'Workshop Materials',
            'order': 1,
            'active': true,
            'scopes': 12,
          },
          {
            'id': 't2',
            'key': 'gi_ductwork',
            'name': 'GI Ductwork',
            'order': 20,
            'active': false,
            'scopes': 0,
          },
        ]
      : <Object>[],
  'inventory_categories': <Object>[],
  'units': <Object>[],
  'mr_categories': <Object>[],
  'mr_departments': <Object>[],
  'accounts': admin
      ? {
          'payment_terms_days': 90,
          'reminder_lead_days': 10,
          'stages': [
            {
              'key': 'design',
              'name': 'Design',
              'percent': '10.0000',
              'active': true,
            },
            {
              'key': 'material_supply',
              'name': 'Material Supply',
              'percent': '50.0000',
              'active': true,
            },
            {
              'key': 'installation',
              'name': 'Installation',
              'percent': '40.0000',
              'active': true,
            },
          ],
        }
      : null,
  'rentals': {'enabled': true, 'push': true, 'last_run_at': null},
  'checks': {
    'bank_missing': admin,
    'trn_missing': false,
    'push_off': false,
    'holidays_this_year': 0,
    'active_pr_users': 1,
    'default_folders': 1,
    'rentals_off': false,
  },
};

final class _FakeRpc implements ConfigRpcClient {
  _FakeRpc(this.handlers);

  final Map<String, FutureOr<Object?> Function(Map<String, Object?>)> handlers;
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Object?> invoke(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    calls.add((functionName, parameters));
    final handler = handlers[functionName];
    if (handler == null) throw StateError('unexpected $functionName');
    return handler(parameters);
  }
}

final class _Online implements ConnectivityService {
  const _Online();
  @override
  bool get isOnline => true;
  @override
  Stream<bool> get onChange => const Stream.empty();
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, _FakeRpc rpc, {String? section}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/yorks/configuration',
    routes: [
      GoRoute(
        path: '/yorks/configuration',
        builder: (_, _) =>
            Scaffold(body: ConfigurationScreen(initialSection: section)),
      ),
      GoRoute(path: '/users', builder: (_, _) => const Text('users')),
      GoRoute(
        path: '/yorks/workforce/crews',
        builder: (_, _) => const Text('crews'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        configWorkspaceRepositoryProvider.overrideWithValue(
          ConfigWorkspaceRepository(
            connectivity: const _Online(),
            rpcClient: rpc,
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the checklist shows what still needs attention', (tester) async {
    _size(tester, const Size(1366, 900));
    final rpc = _FakeRpc({'v1_cfg_get_workspace': (_) => _workspace()});
    await _pump(tester, rpc);

    expect(find.text('Configuration'), findsOneWidget);
    expect(find.text('Missing — invoices print no bank block'), findsOneWidget);
    expect(
      find.text('None entered — holiday overtime will not be counted'),
      findsOneWidget,
    );
    // Planned settings with no effect are never offered.
    expect(find.textContaining('Date format'), findsNothing);
    expect(find.textContaining('password'), findsNothing);

    await _tap(tester, find.byKey(const ValueKey('config-check-bank')).first);
    final fix = find.descendant(
      of: find.byKey(const ValueKey('config-check-bank')),
      matching: find.text('Fix'),
    );
    await _tap(tester, fix);
    expect(find.byKey(const ValueKey('config-letterhead')), findsOneWidget);
  });

  testWidgets('bank details are saved with a reason after review', (
    tester,
  ) async {
    _size(tester, const Size(1366, 1200));
    var refuse = true;
    final rpc = _FakeRpc({
      'v1_cfg_get_workspace': (_) => _workspace(),
      'v1_cfg_apply': (params) {
        if (refuse) {
          refuse = false;
          throw const PostgrestException(
            message: 'V1_CFG_IBAN_INVALID',
            code: '22023',
          );
        }
        return {'version': 3, 'changes': 2};
      },
    });
    await _pump(tester, rpc, section: 'company');

    await tester.enterText(
      find.byKey(const ValueKey('config-field-company.bank_name')),
      'Example Bank PJSC',
    );
    await tester.enterText(
      find.byKey(const ValueKey('config-field-company.bank_iban')),
      'ae07 0331 2345',
    );
    await tester.pumpAndSettle();
    expect(find.text('2 unsaved changes'), findsOneWidget);
    // The letterhead preview shows the new bank block before saving.
    expect(find.textContaining('IBAN AE070331'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('config-review')));
    expect(find.text('Save 2 changes?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('config-save')));
    await tester.pumpAndSettle();
    expect(rpc.calls.where((c) => c.$1 == 'v1_cfg_apply'), isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('config-reason')),
      'Invoice bank details',
    );
    await tester.tap(find.byKey(const ValueKey('config-save')));
    await tester.pumpAndSettle();
    // Refused: the message is shown and everything typed stays.
    expect(find.textContaining('That IBAN is not valid'), findsOneWidget);
    expect(find.byKey(const ValueKey('config-review-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('config-save')));
    await tester.pumpAndSettle();
    final sent = rpc.calls.lastWhere((c) => c.$1 == 'v1_cfg_apply').$2;
    expect(sent['p_section'], 'company');
    expect(sent['p_expected_version'], 2);
    expect(sent['p_reason'], 'Invoice bank details');
    expect(sent['p_changes'], [
      {
        'kind': 'setting',
        'key': 'company.bank_name',
        'value': 'Example Bank PJSC',
      },
      {'kind': 'setting', 'key': 'company.bank_iban', 'value': 'AE0703312345'},
    ]);
    expect(find.byKey(const ValueKey('config-review-dialog')), findsNothing);
  });

  testWidgets('Accounts stages must add up to 100%', (tester) async {
    _size(tester, const Size(1366, 1200));
    final rpc = _FakeRpc({'v1_cfg_get_workspace': (_) => _workspace()});
    await _pump(tester, rpc, section: 'accounts');

    expect(find.text('Total 100%'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('config-stage-percent-2')),
      '30',
    );
    await tester.pumpAndSettle();
    expect(find.text('Total 90%'), findsOneWidget);
    expect(
      find.text('Active stages must add up to exactly 100%.'),
      findsOneWidget,
    );
  });

  testWidgets('turning on a default folder stages one change', (tester) async {
    _size(tester, const Size(1366, 1000));
    final rpc = _FakeRpc({'v1_cfg_get_workspace': (_) => _workspace()});
    await _pump(tester, rpc, section: 'projects');

    expect(find.text('In 12 folders'), findsOneWidget);
    await _tap(
      tester,
      find.byKey(const ValueKey('config-folder-switch-gi_ductwork')),
    );
    expect(find.text('1 unsaved changes'), findsOneWidget);
    await _tap(
      tester,
      find.byKey(const ValueKey('config-folder-switch-gi_ductwork')),
    );
    expect(find.byKey(const ValueKey('config-save-bar')), findsNothing);
  });

  testWidgets('PR sees only Workforce and Rentals', (tester) async {
    _size(tester, const Size(1366, 900));
    final rpc = _FakeRpc({
      'v1_cfg_get_workspace': (_) => _workspace(admin: false),
    });
    await _pump(tester, rpc);

    expect(find.byKey(const ValueKey('config-nav-workforce')), findsOneWidget);
    expect(find.byKey(const ValueKey('config-nav-rentals')), findsOneWidget);
    expect(find.byKey(const ValueKey('config-nav-company')), findsNothing);
    expect(find.byKey(const ValueKey('config-nav-accounts')), findsNothing);
  });

  for (final (name, section) in [
    ('sections', null),
    ('company', 'company'),
    ('requests', 'requests'),
    ('accounts', 'accounts'),
    ('numbering', 'numbering'),
  ]) {
    testWidgets('the $name page fits a 360px phone', (tester) async {
      _size(tester, const Size(360, 800));
      final rpc = _FakeRpc({'v1_cfg_get_workspace': (_) => _workspace()});
      await _pump(tester, rpc, section: section);
      expect(tester.takeException(), isNull);
    });
  }

  group('screenshots (desktop and 360px phone)', () {
    setUpAll(loadAccountsV2GoldenFonts);

    Future<void> shot(
      WidgetTester tester,
      Size size,
      String? section,
      String name,
    ) async {
      _size(tester, size);
      await _pump(
        tester,
        _FakeRpc({'v1_cfg_get_workspace': (_) => _workspace()}),
        section: section,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/configuration_$name.png'),
      );
    }

    testWidgets('desktop checklist', (tester) async {
      await shot(tester, const Size(1366, 900), null, 'desktop_checklist');
    });
    testWidgets('desktop company', (tester) async {
      await shot(tester, const Size(1366, 1400), 'company', 'desktop_company');
    });
    testWidgets('desktop projects', (tester) async {
      await shot(tester, const Size(1366, 900), 'projects', 'desktop_projects');
    });
    testWidgets('desktop accounts', (tester) async {
      await shot(tester, const Size(1366, 900), 'accounts', 'desktop_accounts');
    });
    testWidgets('phone sections', (tester) async {
      await shot(tester, const Size(360, 800), null, 'phone_sections');
    });
    testWidgets('phone accounts', (tester) async {
      await shot(tester, const Size(360, 800), 'accounts', 'phone_accounts');
    });
    testWidgets('phone company', (tester) async {
      await shot(tester, const Size(360, 800), 'company', 'phone_company');
    });
  });
}
