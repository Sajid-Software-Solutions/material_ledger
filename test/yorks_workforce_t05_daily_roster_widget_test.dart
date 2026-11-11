import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/workforce/application/workforce_daily_roster_controller.dart';
import 'package:material_ledger/features/workforce/application/workforce_providers.dart';
import 'package:material_ledger/features/workforce/data/workforce_repository.dart';
import 'package:material_ledger/features/workforce/domain/workforce_attendance_models.dart';
import 'package:material_ledger/features/workforce/domain/workforce_configuration_models.dart';
import 'package:material_ledger/features/workforce/domain/workforce_daily_roster_models.dart';
import 'package:material_ledger/features/workforce/presentation/screens/yorks_workforce_daily_attendance_screen.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_notification.dart';
import 'package:material_ledger/shared/models/yorks_v1_workforce_strings.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_notification_provider.dart';
import 'package:material_ledger/shared/services/yorks_v1_critical_command_key_store.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final nexus = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabic = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final cache = _flutterCacheDirectory();
    final icons = await File(
      '${cache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons)));
    await Future.wait([nexus.load(), arabic.load(), materialIcons.load()]);
  });

  for (final scenario in [
    'success',
    'denied',
    'load_failure',
    'missing_team',
    'wrong_date',
    'wrong_team',
    'wrong_actor',
    'invalid_date',
    'invalid_team',
    'offline',
  ]) {
    testWidgets(
      'daily digest acknowledges only its exact authorized team/date: $scenario',
      (tester) async {
        final notifications = _DailyNotificationRecorder();
        final fixture = await _pumpDailyNotification(
          tester,
          scenario: scenario,
          notifications: notifications,
        );
        await tester.pumpAndSettle();
        expect(
          notifications.seen,
          scenario == 'success' ? [_dailyNotificationId] : isEmpty,
        );
        if (scenario == 'invalid_date' ||
            scenario == 'invalid_team' ||
            scenario == 'offline') {
          expect(fixture.repository.loads, isEmpty);
        } else {
          expect(fixture.repository.loads.single.date, _workDate);
          expect(fixture.repository.loads.single.filters.teamId, _teamId);
        }
        if (scenario == 'success') {
          final state = fixture.container.read(
            yorksWorkforceDailyRosterControllerProvider,
          );
          expect(state.workDate, _workDate);
          expect(state.filters.teamId, _teamId);
          fixture.router.go(
            _dailyNotificationLocation(_secondDailyNotificationId),
          );
          await tester.pumpAndSettle();
          expect(notifications.seen, [
            _dailyNotificationId,
            _secondDailyNotificationId,
          ]);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final interruption in ['route', 'account']) {
    testWidgets(
      'daily digest retains unread state after $interruption changes during loading',
      (tester) async {
        final pending = Completer<YorksWorkforceDailyRosterProjection>();
        final actor = StateProvider<String?>((_) => _actorId);
        final notifications = _DailyNotificationRecorder();
        final fixture = await _pumpDailyNotification(
          tester,
          scenario: 'success',
          notifications: notifications,
          pending: pending,
          actorProvider: actor,
        );
        await tester.pump();
        if (interruption == 'route') {
          fixture.router.go('/away');
        } else {
          fixture.container.read(actor.notifier).state = 'other-account';
        }
        await tester.pump();
        pending.complete(
          _projection(
            includeRow: false,
            filters: YorksWorkforceRosterFilters(teamId: _teamId),
          ),
        );
        await tester.pumpAndSettle();
        expect(notifications.seen, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'daily digest retry acknowledges only after its roster succeeds',
    (tester) async {
      final notifications = _DailyNotificationRecorder();
      final fixture = await _pumpDailyNotification(
        tester,
        scenario: 'load_failure',
        notifications: notifications,
      );
      await tester.pumpAndSettle();
      expect(notifications.seen, isEmpty);
      fixture.repository.scenario = 'success';
      await tester.tap(
        find.text(YorksV1WorkforceStrings.text(AppLanguage.english, 'retry')),
      );
      await tester.pumpAndSettle();
      expect(notifications.seen, [_dailyNotificationId]);
      expect(fixture.repository.loads, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'daily digest acknowledgement failure does not break the loaded roster',
    (tester) async {
      final notifications = _DailyNotificationRecorder(fail: true);
      final fixture = await _pumpDailyNotification(
        tester,
        scenario: 'success',
        notifications: notifications,
      );
      await tester.pumpAndSettle();
      expect(notifications.seen, isEmpty);
      expect(
        fixture.container
            .read(yorksWorkforceDailyRosterControllerProvider)
            .status,
        YorksWorkforceDailyRosterStatus.ready,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'daily roster is overflow-free at acceptance viewports in English and Arabic RTL',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      const viewports = <Size>[
        Size(1440, 900),
        Size(1366, 768),
        Size(1180, 820),
        Size(1024, 768),
        Size(820, 1180),
        Size(768, 1024),
        Size(430, 932),
        Size(390, 844),
        Size(360, 800),
      ];

      for (final language in const [AppLanguage.english, AppLanguage.arabic]) {
        for (final viewport in viewports) {
          await _pumpRoster(tester, viewport: viewport, language: language);

          expect(
            find.text(
              YorksV1WorkforceStrings.text(
                language,
                viewport.width < 720
                    ? 'mobile_attendance_title'
                    : 'daily_attendance',
              ),
            ),
            findsOneWidget,
            reason: '${language.code} at $viewport',
          );
          final screenContext = tester.element(
            find.byType(YorksWorkforceDailyAttendanceScreen),
          );
          expect(
            Directionality.of(screenContext),
            language.isRtl ? TextDirection.rtl : TextDirection.ltr,
          );
          if (viewport.width < 720) {
            expect(
              find.text(
                YorksV1WorkforceStrings.text(language, 'mobile_today_team'),
              ),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('workforce-mobile-completion-footer')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('workforce-mobile-worker-$_workerId')),
              findsOneWidget,
            );
            expect(find.byType(EditableText), findsOneWidget);
            expect(
              find.byType(
                DropdownButtonFormField<YorksWorkforceAttendanceStatus>,
              ),
              findsNothing,
            );
            expect(
              find.byKey(const Key('workforce-tablet-roster-master')),
              findsNothing,
            );
          } else if (viewport.width < 1200) {
            expect(
              find.byKey(const Key('workforce-tablet-roster-master')),
              findsOneWidget,
            );
            if (viewport.width > viewport.height) {
              expect(
                find.byKey(
                  const Key('workforce-tablet-landscape-master-detail'),
                ),
                findsOneWidget,
              );
              expect(
                find.byType(
                  DropdownButtonFormField<YorksWorkforceAttendanceStatus>,
                ),
                findsOneWidget,
              );
            } else {
              expect(
                find.byType(
                  DropdownButtonFormField<YorksWorkforceAttendanceStatus>,
                ),
                findsNothing,
              );
            }
            expect(
              find.byKey(const Key('workforce-tablet-completion-footer')),
              findsOneWidget,
            );
          } else {
            expect(find.byType(EditableText), findsWidgets);
            expect(
              find.byType(
                DropdownButtonFormField<YorksWorkforceAttendanceStatus>,
              ),
              findsNWidgets(2),
            );
            expect(
              find.byKey(const Key('workforce-desktop-worker-editor')),
              findsOneWidget,
            );
            expect(
              find.byKey(const Key('workforce-desktop-completion-footer')),
              findsOneWidget,
            );
          }
          expect(
            tester.takeException(),
            isNull,
            reason: 'No Flutter overflow or render exception at $viewport',
          );
        }
      }
    },
  );

  testWidgets('daily roster acceptance viewports match deterministic goldens', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    const cases = <(AppLanguage, Size, String)>[
      (AppLanguage.english, Size(1440, 900), 'en_1440x900'),
      (AppLanguage.english, Size(1366, 768), 'en_1366x768'),
      (AppLanguage.english, Size(1180, 820), 't11_en_1180x820'),
      (AppLanguage.english, Size(1024, 768), 't11_en_1024x768'),
      (AppLanguage.english, Size(820, 1180), 't11_en_820x1180'),
      (AppLanguage.english, Size(768, 1024), 't11_en_768x1024'),
      (AppLanguage.english, Size(360, 800), 't12_en_360x800'),
      (AppLanguage.english, Size(390, 844), 't12_en_390x844'),
      (AppLanguage.arabic, Size(390, 844), 't12_ar_390x844'),
      (AppLanguage.urdu, Size(360, 800), 't12_ur_360x800'),
      (AppLanguage.arabic, Size(1024, 768), 't11_ar_1024x768'),
    ];

    for (final (language, viewport, suffix) in cases) {
      await _pumpRoster(tester, viewport: viewport, language: language);
      await expectLater(
        find.byType(YorksWorkforceDailyAttendanceScreen),
        matchesGoldenFile(
          'goldens/yorks_workforce_t05_daily_roster_$suffix.png',
        ),
      );
    }
  });

  testWidgets(
    'mobile Today team mounts one focused editor and keeps edits local until review',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await _pumpRoster(
        tester,
        viewport: const Size(390, 844),
        language: AppLanguage.english,
        projection: _projection(rowCount: 120),
      );

      expect(
        find.byKey(const Key('workforce-mobile-today-team')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('workforce-mobile-worker-editor-$_workerId')),
        findsNothing,
      );
      expect(
        find.byType(DropdownButtonFormField<YorksWorkforceAttendanceStatus>),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('workforce-mobile-details-$_workerId')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('workforce-mobile-worker-editor-$_workerId')),
        findsOneWidget,
      );
      expect(
        find.byType(DropdownButtonFormField<YorksWorkforceAttendanceStatus>),
        findsOneWidget,
      );
      expect(find.byKey(const Key('regular-minute-decrease')), findsOneWidget);
      expect(find.byKey(const Key('overtime-minute-increase')), findsOneWidget);

      await tester.tap(find.byKey(const Key('regular-minute-decrease')));
      await tester.pump();
      expect(find.text('7:45'), findsOneWidget);

      Navigator.of(
        tester.element(
          find.byKey(const Key('workforce-mobile-worker-editor-$_workerId')),
        ),
      ).pop();
      await tester.pumpAndSettle();
      final review = find.byKey(const Key('workforce-mobile-review-day'));
      expect(review, findsOneWidget);
      expect(tester.getSize(review).height, greaterThanOrEqualTo(44));
      await tester.tap(review);
      await tester.pump();
      expect(
        find.byKey(const Key('workforce-mobile-back-to-edit')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('workforce-mobile-save-day')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('direct mobile marks stay local and undo restores hours', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = await _pumpRoster(
      tester,
      viewport: const Size(390, 844),
      language: AppLanguage.english,
    );
    final before = controller.state.rows.first;
    await tester.tap(find.byKey(const Key('workforce-absent-$_workerId')));
    await tester.pumpAndSettle();
    expect(
      controller.state.rows.first.status,
      YorksWorkforceAttendanceStatus.absent,
    );
    expect(controller.state.rows.first.regularMinutes, 0);
    expect(controller.state.isReviewing, isFalse);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(controller.state.rows.first, same(before));
    expect(controller.state.dirtyRows, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile focused editor and bulk sheet match visual evidence', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    await _pumpRoster(
      tester,
      viewport: const Size(390, 844),
      language: AppLanguage.english,
    );

    await tester.tap(
      find.byKey(const Key('workforce-mobile-details-$_workerId')),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/yorks_workforce_t05_daily_roster_t12_en_390x844_editor.png',
      ),
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('workforce-mobile-worker-editor-$_workerId')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    Navigator.of(
      tester.element(
        find.byKey(const Key('workforce-mobile-worker-editor-$_workerId')),
      ),
    ).pop();
    await tester.pumpAndSettle();

    final card = find.byKey(const Key('workforce-mobile-worker-$_workerId'));
    await tester.tap(
      find.descendant(of: card, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('workforce-mobile-bulk-actions')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        'goldens/yorks_workforce_t05_daily_roster_t12_en_390x844_bulk.png',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile bulk sheet reports the selected affected count', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pumpRoster(
      tester,
      viewport: const Size(360, 800),
      language: AppLanguage.urdu,
    );

    final card = find.byKey(const Key('workforce-mobile-worker-$_workerId'));
    await tester.tap(
      find.descendant(of: card, matching: find.byType(Checkbox)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('workforce-mobile-bulk-actions')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('workforce-mobile-bulk-sheet')),
      findsOneWidget,
    );
    expect(
      find.text(
        '1 ${YorksV1WorkforceStrings.text(AppLanguage.urdu, 'affected')}',
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile future roster remains readable and non-editable', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pumpRoster(
      tester,
      viewport: const Size(390, 844),
      language: AppLanguage.english,
      projection: _projection(isFuture: true),
    );

    expect(find.text('Future dates are read-only'), findsOneWidget);
    final review = tester.widget<ElevatedButton>(
      find.byKey(const Key('workforce-mobile-review-day')),
    );
    expect(review.onPressed, isNull);
    final card = find.byKey(const Key('workforce-mobile-worker-$_workerId'));
    final checkbox = tester.widget<Checkbox>(
      find.descendant(of: card, matching: find.byType(Checkbox)),
    );
    expect(checkbox.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile native date picker does not offer a future local date', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pumpRoster(
      tester,
      viewport: const Size(390, 844),
      language: AppLanguage.english,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, _workDate));
    await tester.pumpAndSettle();
    final picker = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(
      DateUtils.isSameDay(picker.lastDate, DateUtils.dateOnly(DateTime.now())),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile restricted allocation remains redacted and locked', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pumpRoster(
      tester,
      viewport: const Size(360, 800),
      language: AppLanguage.arabic,
      projection: _projection(allocationRestricted: true),
    );

    final card = find.byKey(const Key('workforce-mobile-worker-$_workerId'));
    expect(
      find.descendant(of: card, matching: find.byIcon(Icons.lock_outline)),
      findsOneWidget,
    );
    final checkbox = tester.widget<Checkbox>(
      find.descendant(of: card, matching: find.byType(Checkbox)),
    );
    expect(checkbox.onChanged, isNull);
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('workforce-mobile-worker-editor-$_workerId')),
      findsOneWidget,
    );
    expect(find.text('تفاصيل التوزيع مقيدة'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile shows invalid, offline and protected-state purge cues', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final connectivity = _MutableConnectivity();
    addTearDown(connectivity.dispose);
    final controller = await _pumpRoster(
      tester,
      viewport: const Size(390, 844),
      language: AppLanguage.english,
      connectivity: connectivity,
    );

    expect(find.text('Make a change to enable saving.'), findsOneWidget);

    controller.updateRow(_workerId, regularMinutes: 0);
    await tester.pump();
    expect(
      find.text('Present workers need valid minutes up to 1,440'),
      findsOneWidget,
    );

    expect(
      find.text('Check the highlighted workers before saving.'),
      findsOneWidget,
    );

    connectivity.setOnline(false);
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Connect to the internet to save.'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.byKey(const Key('workforce-mobile-review-day')),
          )
          .onPressed,
      isNull,
    );

    controller.purgeProtectedState();
    await tester.pump();
    expect(find.text('Workforce access changed'), findsOneWidget);
    expect(find.byKey(const Key('workforce-mobile-today-team')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile remains overflow-free with enlarged text', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pumpRoster(
      tester,
      viewport: const Size(390, 844),
      language: AppLanguage.hindi,
      textScaler: const TextScaler.linear(1.3),
    );
    expect(
      find.byKey(const Key('workforce-mobile-today-team')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tablet landscape keeps one editor for a large roster and portrait opens one focused sheet',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await _pumpRoster(
        tester,
        viewport: const Size(1180, 820),
        language: AppLanguage.english,
        projection: _projection(rowCount: 120),
      );

      expect(
        find.byType(DropdownButtonFormField<YorksWorkforceAttendanceStatus>),
        findsOneWidget,
      );
      expect(find.byType(EditableText), findsNWidgets(5));
      expect(tester.takeException(), isNull);

      await _pumpRoster(
        tester,
        viewport: const Size(820, 1180),
        language: AppLanguage.english,
      );
      expect(
        find.byType(DropdownButtonFormField<YorksWorkforceAttendanceStatus>),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const Key('workforce-tablet-worker-$_workerId')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('workforce-tablet-worker-editor-$_workerId')),
        findsOneWidget,
      );
      expect(
        find.byType(DropdownButtonFormField<YorksWorkforceAttendanceStatus>),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tablet edit remains a local draft until explicit Review Day and can return to edit',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await _pumpRoster(
        tester,
        viewport: const Size(1024, 768),
        language: AppLanguage.english,
      );
      final regular = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.keyboardType == TextInputType.number &&
            widget.controller?.text == '480',
      );
      expect(regular, findsOneWidget);
      await tester.enterText(regular, '420');
      await tester.pump();

      final review = find.byKey(const Key('workforce-tablet-review-day'));
      expect(review, findsOneWidget);
      expect(tester.getSize(review).height, greaterThanOrEqualTo(44));
      await tester.tap(review);
      await tester.pump();

      expect(
        find.byKey(const Key('workforce-tablet-save-day')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('workforce-tablet-back-to-edit')),
        findsOneWidget,
      );
      expect(find.text('1 Changed rows'), findsWidgets);
      await tester.tap(find.byKey(const Key('workforce-tablet-back-to-edit')));
      await tester.pump();
      expect(
        find.byKey(const Key('workforce-tablet-review-day')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('tablet editor preserves keyboard focus order in RTL', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pumpRoster(
      tester,
      viewport: const Size(1024, 768),
      language: AppLanguage.arabic,
    );
    final regular = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.keyboardType == TextInputType.number &&
          widget.controller?.text == '480',
    );
    final overtime = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.keyboardType == TextInputType.number &&
          widget.controller?.text == '0',
    );
    await tester.tap(regular);
    await tester.pump();
    _expectFocused(tester, regular);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    _expectFocused(tester, overtime);
    await _shiftKey(tester, LogicalKeyboardKey.tab);
    _expectFocused(tester, regular);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    _expectFocused(tester, overtime);
    expect(
      tester
          .getSize(find.byKey(const Key('workforce-tablet-worker-$_workerId')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker row exposes a stable combined semantics label', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final semantics = tester.ensureSemantics();
    await _pumpRoster(
      tester,
      viewport: const Size(1366, 768),
      language: AppLanguage.english,
    );

    expect(find.bySemanticsLabel('Ahmed Khan, WF-001'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'Tab and row arrow or Enter shortcuts move focus in deterministic order',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await _pumpRoster(
        tester,
        viewport: const Size(1366, 768),
        language: AppLanguage.english,
      );
      final regular = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.keyboardType == TextInputType.number &&
            widget.controller?.text == '480',
      );
      final overtime = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.keyboardType == TextInputType.number &&
            widget.controller?.text == '0',
      );
      final roster = find.byKey(const Key('workforce-desktop-roster-grid'));
      final gridRegular = find.descendant(of: roster, matching: regular);
      final gridOvertime = find.descendant(of: roster, matching: overtime);
      expect(gridRegular, findsOneWidget);
      expect(gridOvertime, findsOneWidget);

      await tester.tap(gridRegular);
      await tester.pump();
      _expectFocused(tester, gridRegular);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      _expectFocused(tester, gridOvertime);
      await _shiftKey(tester, LogicalKeyboardKey.tab);
      _expectFocused(tester, gridRegular);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      _expectFocused(tester, gridOvertime);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      _expectFocused(tester, gridRegular);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      _expectFocused(tester, gridOvertime);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      _expectFocused(tester, gridRegular);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      _expectFocused(tester, gridOvertime);
      await _shiftKey(tester, LogicalKeyboardKey.enter);
      _expectFocused(tester, gridRegular);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('allocation editor exposes command-authorized targets only', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pumpRoster(
      tester,
      viewport: const Size(1366, 768),
      language: AppLanguage.english,
      projection: _projection(includeProjectTarget: false),
    );

    final target = find.byKey(
      const ValueKey('70010000-0000-4000-8000-000000000001-target-none'),
    );
    const readOnlyProjectTarget = 'YRA-313 · Common / All Buildings';
    expect(find.text(readOnlyProjectTarget), findsNWidgets(2));
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.text('Main Workshop'), findsOneWidget);
    expect(
      find.text(readOnlyProjectTarget),
      findsNWidgets(2),
      reason:
          'The read-only assignment label must not be duplicated as a target',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop worker editor supports a balanced split allocation', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = await _pumpRoster(
      tester,
      viewport: const Size(1440, 900),
      language: AppLanguage.english,
    );
    controller.assignProject(
      _workerId,
      projectId: _projectId,
      projectScopeId: _scopeId,
    );
    await tester.pumpAndSettle();

    final splitButton = find.byKey(
      const Key(
        'workforce-split-allocation-70010000-0000-4000-8000-000000000001',
      ),
    );
    expect(splitButton, findsOneWidget);
    await tester.tap(splitButton);
    await tester.pumpAndSettle();

    expect(controller.state.rows.single.allocations, hasLength(2));
    final splitEditor = find.byKey(
      const Key(
        'workforce-allocation-split-editor-70010000-0000-4000-8000-000000000001',
      ),
    );
    await tester.scrollUntilVisible(
      splitEditor,
      280,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('workforce-desktop-worker-editor')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(
      find.byKey(const Key('workforce-desktop-worker-editor')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(splitEditor, findsOneWidget);
    expect(
      find.text('Allocated time matches the worker’s day.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(YorksWorkforceDailyAttendanceScreen),
      matchesGoldenFile(
        'goldens/yorks_workforce_t05_daily_roster_desktop_split_editor.png',
      ),
    );
  });

  testWidgets(
    'an empty conservative page does not claim every date is future',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await _pumpRoster(
        tester,
        viewport: const Size(1366, 768),
        language: AppLanguage.english,
        projection: _projection(isFuture: true, includeRow: false),
      );

      expect(find.text('Future dates are read-only'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<YorksWorkforceDailyRosterController> _pumpRoster(
  WidgetTester tester, {
  required Size viewport,
  required AppLanguage language,
  YorksWorkforceDailyRosterProjection? projection,
  ConnectivityService? connectivity,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  SharedPreferences.setMockInitialValues({'selected_language': language.code});
  final preferences = await SharedPreferences.getInstance();
  final controller = YorksWorkforceDailyRosterController(
    repository: _WidgetRepository(projection ?? _projection()),
    commandKeys: YorksV1CriticalCommandKeyStore(
      preferences: preferences,
      actorAuthUserId: _actorId,
      uuidFactory: () => _idempotencyKey,
    ),
    connectivity: connectivity ?? const _Connectivity(),
    clock: () => DateTime.utc(2026, 8, 30, 12),
  );
  expect(await controller.load(workDate: _workDate), isTrue);
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksWorkforceDailyRosterControllerProvider.overrideWith(
          (ref) => controller,
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Directionality(
          textDirection: language.isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: const YorksWorkforceDailyAttendanceScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void _expectFocused(WidgetTester tester, Finder textField) {
  final editable = find.descendant(
    of: textField,
    matching: find.byType(EditableText),
  );
  expect(editable, findsOneWidget);
  expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
}

Future<void> _shiftKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

YorksWorkforceDailyRosterProjection _projection({
  bool includeProjectTarget = true,
  bool isFuture = false,
  bool includeRow = true,
  bool allocationRestricted = false,
  int rowCount = 1,
  String workDate = _workDate,
  String actorAuthUserId = _actorId,
  YorksWorkforceRosterFilters filters = const YorksWorkforceRosterFilters(),
  bool includeTeam = true,
}) {
  final selectors = YorksWorkforceRosterSelectors(
    teams: includeTeam
        ? const [
            YorksWorkforceRosterTeamSelector(id: _teamId, name: 'Duct Team'),
          ]
        : const [],
    projects: const [
      YorksWorkforceRosterProjectSelector(
        id: _projectId,
        reference: 'YRA-313',
        name: 'Riyadh Substation',
      ),
    ],
    projectScopes: const [
      YorksWorkforceRosterScopeSelector(
        projectId: _projectId,
        id: _scopeId,
        name: 'Common / All Buildings',
      ),
    ],
    internalLocations: const [
      YorksWorkforceRosterLocationSelector(
        id: _locationId,
        name: 'Main Workshop',
      ),
    ],
  );
  final allocationTargets = YorksWorkforceRosterAllocationTargets(
    projects: includeProjectTarget
        ? const [
            YorksWorkforceRosterProjectSelector(
              id: _projectId,
              reference: 'YRA-313',
              name: 'Riyadh Substation',
            ),
          ]
        : const [],
    projectScopes: includeProjectTarget
        ? const [
            YorksWorkforceRosterAllocationScopeTarget(
              projectId: _projectId,
              id: _scopeId,
              kind: 'common',
              code: 'common',
              name: 'Common / All Buildings',
            ),
          ]
        : const [],
    internalLocations: const [
      YorksWorkforceRosterAllocationLocationTarget(
        id: _locationId,
        code: 'MAIN',
        name: 'Main Workshop',
        departmentCostCentre: null,
      ),
    ],
  );
  return YorksWorkforceDailyRosterProjection(
    schemaVersion: 1,
    authorizationMode: 'enforced_t05',
    actorAuthUserId: actorAuthUserId,
    workDate: workDate,
    isFuture: isFuture,
    serverTime: '2026-08-30T12:00:00Z',
    filters: filters,
    capabilities: YorksWorkforceRosterCapabilities(
      canView: true,
      canMaintainAttendance: !isFuture,
      canMaintainTimesheet: !isFuture,
    ),
    selectors: selectors,
    allocationTargets: allocationTargets,
    totalCount: includeRow ? rowCount : 0,
    rows: includeRow
        ? List.generate(
            rowCount,
            (index) => _rosterRow(
              index,
              editable: !isFuture,
              allocationRestricted: allocationRestricted,
            ),
          )
        : const [],
  );
}

YorksWorkforceDailyRosterRow _rosterRow(
  int index, {
  bool editable = true,
  bool allocationRestricted = false,
}) {
  final workerId = _workerUuid(index);
  return YorksWorkforceDailyRosterRow(
    workerId: workerId,
    workerNumber: 'WF-${(index + 1).toString().padLeft(3, '0')}',
    workerName: index == 0 ? 'Ahmed Khan' : 'Worker ${index + 1}',
    designation: 'Ductman',
    tradeId: _tradeId,
    tradeName: 'Ductman',
    department: 'Operations',
    employerCompany: 'Yorks AC & Ref.',
    workerType: 'yorks_employee',
    assignment: _assignment,
    scheduleSuggestion: _suggestion,
    attendance: index == 0 ? _attendance : null,
    allocationSet: null,
    hasActiveAllocationLock: allocationRestricted,
    allocationDetailsRestricted: allocationRestricted,
    canMaintainAttendance: editable,
    canMaintainTimesheet: editable && !allocationRestricted,
  );
}

String _workerUuid(int index) =>
    '70010000-0000-4000-8000-${(index + 1).toString().padLeft(12, '0')}';

const _assignment = YorksWorkforceAttendanceAssignmentSnapshot(
  id: '71000000-0000-4000-8000-000000000001',
  kind: 'primary',
  teamId: _teamId,
  teamName: 'Duct Team',
  supervisorAuthUserId: _actorId,
  supervisorName: 'Workforce Supervisor',
  projectId: _projectId,
  projectRef: 'YRA-313',
  projectName: 'Riyadh Substation',
  projectScopeId: _scopeId,
  projectScopeName: 'Common / All Buildings',
  internalLocationId: null,
  internalLocationName: null,
  validFrom: '2026-01-01',
  validTo: null,
  recordVersion: 1,
);

const _schedule = YorksWorkforceAttendanceScheduleSnapshot(
  teamScheduleLinkId: '71010000-0000-4000-8000-000000000001',
  teamScheduleRecordVersion: 1,
  calendarId: '71020000-0000-4000-8000-000000000001',
  calendarCode: 'UAE-SITE',
  calendarName: 'UAE Site Calendar',
  calendarTimezone: 'Asia/Dubai',
  calendarRecordVersion: 1,
  calendarDateOverrideId: null,
  calendarDateOverrideVersion: null,
  calendarOverrideKind: null,
  calendarExceptionName: null,
  dayTypeSource: 'weekday',
  isoWeekday: 7,
  dayType: YorksWorkforceDayType.regularWorkingDay,
  scheduledMinutes: 480,
  breakMinutes: 60,
  shiftTemplateId: null,
  shiftCode: null,
  shiftName: null,
  shiftKind: null,
  shiftStartTime: null,
  shiftEndTime: null,
  shiftScheduledMinutes: null,
  shiftBreakMinutes: null,
  shiftCrossesMidnight: null,
  shiftWorkDateBasis: null,
  shiftRecordVersion: null,
);

const _suggestion = YorksWorkforceRosterScheduleSuggestion(
  schedule: _schedule,
  suggestedStatus: YorksWorkforceAttendanceStatus.present,
  suggestedRegularMinutes: 480,
  suggestedOvertimeMinutes: 0,
  requiresConfirmation: true,
);

const _attendance = YorksWorkforceAttendanceDay(
  id: _attendanceId,
  workerId: _workerId,
  workerNumber: 'WF-001',
  workerName: 'Ahmed Khan',
  workerJoiningDate: '2026-01-01',
  workerLeavingDate: null,
  workDate: _workDate,
  status: YorksWorkforceAttendanceStatus.present,
  regularMinutes: 480,
  overtimeMinutes: 0,
  overtimeReason: null,
  reason: 'Confirmed attendance',
  recordVersion: 1,
  createdAt: '2026-08-30T08:00:00Z',
  updatedAt: '2026-08-30T08:00:00Z',
  assignment: _assignment,
  initialAuthority: YorksWorkforceAttendanceAuthoritySnapshot(
    kind: 'responsibility',
    responsibilityAssignmentId: '71030000-0000-4000-8000-000000000001',
    scopeKind: 'project',
    scopeReference: 'project:$_projectId',
    recordVersion: 1,
  ),
  schedule: _schedule,
);

const _actorId = '70000000-0000-4000-8000-000000000001';
const _workerId = '70010000-0000-4000-8000-000000000001';
const _attendanceId = '70020000-0000-4000-8000-000000000001';
const _teamId = '70030000-0000-4000-8000-000000000001';
const _tradeId = '70040000-0000-4000-8000-000000000001';
const _projectId = '70050000-0000-4000-8000-000000000001';
const _scopeId = '70060000-0000-4000-8000-000000000001';
const _locationId = '70070000-0000-4000-8000-000000000001';
const _idempotencyKey = '70080000-0000-4000-8000-000000000001';
const _workDate = '2026-08-30';

final class _WidgetRepository implements YorksWorkforceRepository {
  const _WidgetRepository(this.projection);

  final YorksWorkforceDailyRosterProjection projection;

  @override
  Future<YorksWorkforceDailyRosterProjection> getDailyRoster({
    required String workDate,
    YorksWorkforceRosterFilters filters = const YorksWorkforceRosterFilters(),
  }) async => projection;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Connectivity implements ConnectivityService {
  const _Connectivity({this.online = true});
  final bool online;

  @override
  bool get isOnline => online;

  @override
  Stream<bool> get onChange => const Stream.empty();
}

final class _MutableConnectivity implements ConnectivityService {
  final _changes = StreamController<bool>.broadcast(sync: true);
  bool _online = true;

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get onChange => _changes.stream;

  void setOnline(bool online) {
    _online = online;
    _changes.add(online);
  }

  void dispose() => _changes.close();
}

Directory _flutterCacheDirectory() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 8; level++) {
    if (directory.path.endsWith('${Platform.pathSeparator}cache')) {
      return directory;
    }
    directory = directory.parent;
  }
  throw StateError('Could not locate the Flutter cache from the test runner');
}

const _dailyNotificationId = 'ab500000-0000-4000-8000-000000000001';
const _secondDailyNotificationId = 'ab500000-0000-4000-8000-000000000002';
String _dailyNotificationLocation(
  String notificationId, {
  String teamId = _teamId,
  String date = _workDate,
}) =>
    '/yorks/workforce/attendance?team_id=$teamId&date=$date&notificationId=$notificationId';

Future<
  ({
    ProviderContainer container,
    GoRouter router,
    _DailyNotificationRepository repository,
  })
>
_pumpDailyNotification(
  WidgetTester tester, {
  required String scenario,
  required _DailyNotificationRecorder notifications,
  Completer<YorksWorkforceDailyRosterProjection>? pending,
  StateProvider<String?>? actorProvider,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final repository = _DailyNotificationRepository(scenario, pending);
  final router = GoRouter(
    initialLocation: _dailyNotificationLocation(
      _dailyNotificationId,
      date: scenario == 'invalid_date' ? '2026-02-30' : _workDate,
      teamId: scenario == 'invalid_team' ? 'not-a-team' : _teamId,
    ),
    routes: [
      GoRoute(
        path: '/yorks/workforce/attendance',
        builder: (_, state) => YorksWorkforceDailyAttendanceScreen(
          initialTeamId: state.uri.queryParameters['team_id'],
          initialWorkDate: state.uri.queryParameters['date'],
        ),
      ),
      GoRoute(
        path: '/away',
        builder: (_, _) => const Scaffold(body: Text('Away')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        if (actorProvider == null)
          yorksV1AuthUserIdProvider.overrideWithValue(_actorId)
        else
          yorksV1AuthUserIdProvider.overrideWith(
            (ref) => ref.watch(actorProvider),
          ),
        yorksV1NotificationsProvider.overrideWith((_) => notifications),
        yorksWorkforceDailyRosterControllerProvider.overrideWith(
          (_) => YorksWorkforceDailyRosterController(
            repository: repository,
            commandKeys: YorksV1CriticalCommandKeyStore(
              preferences: preferences,
              actorAuthUserId: _actorId,
            ),
            connectivity: _Connectivity(online: scenario != 'offline'),
            clock: () => DateTime.utc(2026, 9, 10),
          ),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pump();
  return (
    container: ProviderScope.containerOf(
      tester.element(find.byType(YorksWorkforceDailyAttendanceScreen)),
    ),
    router: router,
    repository: repository,
  );
}

class _DailyNotificationRecorder extends YorksV1NotificationsNotifier {
  _DailyNotificationRecorder({this.fail = false})
    : super(client: null, repository: null, authUserId: null) {
    state = const AsyncData(<YorksV1NotificationRecord>[]);
  }
  final bool fail;
  final seen = <String>[];
  @override
  Future<void> markSeen(String notificationId) async {
    if (fail) throw StateError('Acknowledgement unavailable');
    seen.add(notificationId);
  }
}

class _DailyNotificationRepository implements YorksWorkforceRepository {
  _DailyNotificationRepository(this.scenario, this.pending);
  String scenario;
  final Completer<YorksWorkforceDailyRosterProjection>? pending;
  final loads = <({String date, YorksWorkforceRosterFilters filters})>[];
  @override
  Future<YorksWorkforceDailyRosterProjection> getDailyRoster({
    required String workDate,
    YorksWorkforceRosterFilters filters = const YorksWorkforceRosterFilters(),
  }) async {
    loads.add((date: workDate, filters: filters));
    if (scenario == 'denied') {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.unauthorized);
    }
    if (scenario == 'load_failure') {
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
    if (pending != null) return pending!.future;
    return _projection(
      includeRow: false,
      workDate: scenario == 'wrong_date' ? '2026-08-29' : workDate,
      actorAuthUserId: scenario == 'wrong_actor'
          ? '70010000-0000-4000-8000-000000000099'
          : _actorId,
      filters: scenario == 'wrong_team'
          ? const YorksWorkforceRosterFilters()
          : filters,
      includeTeam: scenario != 'missing_team',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
