import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/materials/presentation/screens/yorks_v1_material_request_centre.dart';
import 'package:material_ledger/shared/models/app_language.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_request.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_register.dart';

void main() {
  setUpAll(() async {
    final nexusFontLoader = FontLoader('NexusSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabicFontLoader = FontLoader('NotoSansArabic')
      ..addFont(rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    final flutterCache = _flutterCacheDirectory();
    final iconBytes = await File(
      '${flutterCache.path}/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    final iconFontLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await Future.wait([
      nexusFontLoader.load(),
      arabicFontLoader.load(),
      iconFontLoader.load(),
    ]);
  });

  for (final temporary in [true, false]) {
    testWidgets(
      'register ${temporary ? 'retains and retries transient data' : 'clears data on confirmed denial'}',
      (tester) async {
        await _setViewport(tester, const Size(1440, 1024));
        var revision = 0;
        var loads = 0;
        late StateSetter rebuild;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return YorksV1MaterialRequestCentre(
                    requests: const [],
                    language: AppLanguage.english,
                    canCreate: true,
                    onCreate: () {},
                    onOpen: (_) {},
                    onRefresh: () {},
                    refreshRevision: revision,
                    registerPageLoader: (_) async {
                      if (++loads == 2) {
                        throw YorksV1DomainException(
                          temporary
                              ? YorksV1DomainErrorCode.backendUnavailable
                              : YorksV1DomainErrorCode.unauthorized,
                        );
                      }
                      return YorksV1MaterialRegisterPage(
                        items: [
                          YorksV1MaterialRegisterEntry.project(
                            _summary(
                              index: 1,
                              updatedAt: DateTime.utc(2026, 9, 25),
                            ).toRegisterProjection(),
                          ),
                        ],
                        totalCount: 1,
                        limit: 15,
                        offset: 0,
                        hasMore: false,
                        metrics: const YorksV1MaterialRequestSummaryMetrics(
                          total: 1,
                          open: 1,
                          inProgress: 0,
                          dispatched: 0,
                          received: 0,
                          closed: 0,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byKey(
          const ValueKey('material-request-row-server-summary-1'),
        );
        expect(row, findsOneWidget);
        rebuild(() => revision++);
        await tester.pumpAndSettle();
        expect(row, temporary ? findsOneWidget : findsNothing);
        if (temporary) {
          expect(
            find.textContaining('Showing the last available data.'),
            findsOneWidget,
          );
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          expect(loads, 3);
          expect(
            find.textContaining('Showing the last available data.'),
            findsNothing,
          );
        } else {
          await tester.pump(const Duration(seconds: 4));
          expect(
            loads,
            2,
            reason: 'Confirmed denials are never automatically retried',
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final width in [1440.0, 1024.0, 360.0]) {
    testWidgets('unified register opens native Company rows at $width px', (
      tester,
    ) async {
      await _setViewport(tester, Size(width, 1000));
      String? companyOpened;
      String? projectOpened;
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: YorksV1MaterialRequestCentre(
              requests: const [],
              language: AppLanguage.english,
              canCreate: true,
              canCreateCompany: true,
              onCreate: () {},
              onCreateCompany: () {},
              onOpen: (request) => projectOpened = request.id,
              onOpenCompany: (id) async {
                companyOpened = id;
              },
              onRefresh: () {},
              registerPageLoader: (query) async {
                loads++;
                return YorksV1MaterialRegisterPage(
                  items: [
                    YorksV1MaterialRegisterEntry.company(_companyRegisterRow),
                    YorksV1MaterialRegisterEntry.project(
                      _summary(
                        index: 1,
                        updatedAt: DateTime.utc(2026, 9, 25),
                      ).toRegisterProjection(),
                    ),
                  ],
                  totalCount: 2,
                  limit: 15,
                  offset: 0,
                  hasMore: false,
                  metrics: const YorksV1MaterialRequestSummaryMetrics(
                    total: 2,
                    open: 2,
                    inProgress: 0,
                    dispatched: 0,
                    received: 0,
                    closed: 0,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(
        const ValueKey('material-request-row-company:company-proof'),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: row,
          matching: find.byIcon(Icons.business_center_outlined),
        ),
        findsOneWidget,
      );
      final projectRow = find.byKey(
        const ValueKey('material-request-row-server-summary-1'),
      );
      expect(
        find.descendant(
          of: projectRow,
          matching: find.byIcon(Icons.folder_open_outlined),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Company use'), findsWidgets);
      expect(find.textContaining('Company approver'), findsWidgets);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r35/unified_mr_register_${width.toInt()}.png',
        ),
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      final openPreview = find.byKey(
        const ValueKey('material-request-tablet-open'),
      );
      if (companyOpened == null && openPreview.evaluate().isNotEmpty) {
        await tester.ensureVisible(openPreview);
        await tester.tap(openPreview);
        await tester.pumpAndSettle();
      }
      expect(companyOpened, 'company-proof');
      expect(projectOpened, isNull);
      expect(
        loads,
        2,
        reason: 'Returning from Company workflow refreshes the shared list',
      );
    });
  }

  testWidgets('desktop centre groups, searches and opens server requests', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1440, 1024));
    String? openedRequestId;
    var created = false;
    await _pump(
      tester,
      onOpen: (request) => openedRequestId = request.id,
      onCreate: () => created = true,
    );

    expect(
      find.byKey(const ValueKey('material-request-centre')),
      findsOneWidget,
    );
    expect(find.text('Material Request Centre'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('material-request-row-mr-322-closed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-request-project-project-322')),
      findsNothing,
    );
    expect(find.text('Total Material Requests'), findsAtLeastNWidgets(1));
    expect(find.textContaining('YRA-322'), findsWidgets);
    expect(find.textContaining('YRA-314'), findsWidgets);
    expect(find.textContaining('YRA-313'), findsWidgets);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/mr_centre_desktop.png'),
    );

    await tester.tap(
      find.byKey(const ValueKey('material-request-centre-filter-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Apply filters'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/mr_centre_desktop_filters.png'),
    );
    await tester.tap(
      find.byKey(const ValueKey('material-request-centre-apply-filters')).last,
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('material-request-centre-create')),
    );
    expect(created, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('material-request-centre-view-projects')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('material-request-project-arrow-project-322')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const ValueKey('material-request-project-contents-project-322'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-request-row-mr-322-closed')),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/mr_centre_desktop_expanded.png'),
    );
    expect(openedRequestId, isNull);

    await tester.tap(
      find.byKey(const ValueKey('material-request-row-mr-322-closed')),
    );
    expect(openedRequestId, 'mr-322-closed');

    await tester.enterText(
      find.byKey(const ValueKey('material-request-centre-search')),
      'Electrical',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-request-project-project-314')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('material-request-project-project-314')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-request-row-mr-314-dispatched')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-request-row-mr-322-closed')),
      findsNothing,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('compact centre keeps filters and closed requests usable', (
    tester,
  ) async {
    await _setViewport(tester, const Size(390, 844));
    String? openedRequestId;
    await _pump(tester, onOpen: (request) => openedRequestId = request.id);

    expect(find.text('Material Request Centre'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('material-request-centre-filter-button')),
      findsOneWidget,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/mr_centre_mobile_390.png'),
    );
    await tester.tap(
      find.byKey(const ValueKey('material-request-centre-filter-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Apply filters'), findsOneWidget);

    final applyFilters = find
        .byKey(const ValueKey('material-request-centre-apply-filters'))
        .at(0);
    await tester.ensureVisible(applyFilters);
    await tester.pumpAndSettle();
    await tester.tap(applyFilters);
    await tester.pumpAndSettle();
    await tester.fling(
      find.byKey(const ValueKey('material-request-centre')),
      const Offset(0, 1200),
      2000,
    );
    await tester.pumpAndSettle();

    final closedMetric = find
        .byKey(const ValueKey('material-request-metric-closed'))
        .at(0);
    await tester.ensureVisible(closedMetric);
    await tester.pumpAndSettle();
    await tester.tap(closedMetric);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-request-row-mr-322-closed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-request-row-mr-314-dispatched')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('material-request-row-mr-322-closed')),
    );
    expect(openedRequestId, 'mr-322-closed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet centre uses a selectable master detail workspace', (
    tester,
  ) async {
    await _setViewport(tester, const Size(820, 1180));
    String? openedRequestId;
    await _pump(tester, onOpen: (request) => openedRequestId = request.id);

    expect(
      find.byKey(const ValueKey('material-request-tablet-master-detail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-request-tablet-preview')),
      findsOneWidget,
    );
    expect(find.text('Request preview'), findsOneWidget);
    expect(find.textContaining('Current owner:'), findsWidgets);
    expect(find.textContaining('Next action:'), findsWidgets);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/mr_centre_tablet_820x1180.png'),
    );

    await tester.tap(
      find.byKey(const ValueKey('material-request-row-mr-314-dispatched')),
    );
    await tester.pumpAndSettle();
    expect(openedRequestId, isNull);
    expect(
      find.byKey(const ValueKey('material-request-selected-mr-314-dispatched')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('material-request-tablet-open')),
    );
    expect(openedRequestId, 'mr-314-dispatched');
    expect(tester.takeException(), isNull);
  });

  testWidgets('All Requests uses fifteen-row pages', (tester) async {
    await _setViewport(tester, const Size(1280, 3200));
    final requests = List.generate(
      16,
      (index) => _request(
        id: 'mr-page-$index',
        projectId: 'project-page-${index % 3}',
        reference: 'YRA-${320 + index % 3}',
        projectName: 'Project ${index + 1}',
        number: 'YRA-${320 + index % 3}-MR${index + 1}',
        title: 'Material request ${index + 1}',
        scope: 'Common / All Buildings',
        state: YorksV1MaterialRequestState.submitted,
        updatedAt: DateTime.utc(2026, 8, 20).subtract(Duration(minutes: index)),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          body: YorksV1MaterialRequestCentre(
            requests: requests,
            language: AppLanguage.english,
            canCreate: true,
            onCreate: () {},
            onOpen: (_) {},
            onRefresh: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1–15 / 16'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('material-request-row-mr-page-14')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-request-row-mr-page-15')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('material-request-centre-page-next')),
    );
    await tester.pumpAndSettle();
    expect(find.text('16–16 / 16'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('material-request-row-mr-page-15')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('summary metrics return to latest all-request rows', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1280, 1100));
    await _pump(tester);

    await tester.tap(
      find.byKey(const ValueKey('material-request-centre-view-projects')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-request-project-project-322')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('material-request-metric-all')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('material-request-project-project-322')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('material-request-row-mr-322-closed')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.byKey(const ValueKey('material-request-row-mr-322-closed')),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey('material-request-row-mr-314-dispatched'),
              ),
            )
            .dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'attention filter and activity sort update the folder hierarchy',
    (tester) async {
      await _setViewport(tester, const Size(1280, 1100));
      await _pump(tester);

      await tester.tap(
        find.byKey(const ValueKey('material-request-centre-filter-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('material-request-filter-attention')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byKey(const ValueKey('material-request-centre-apply-filters'))
            .last,
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('material-request-centre-view-projects')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('material-request-project-project-322')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('material-request-row-mr-322-approval')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('material-request-row-mr-322-closed')),
        findsNothing,
      );

      await tester.tap(find.text('Latest Activity'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oldest Activity').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .getTopLeft(
              find.byKey(
                const ValueKey('material-request-project-project-313'),
              ),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.byKey(
                  const ValueKey('material-request-project-project-322'),
                ),
              )
              .dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow centre defaults to all requests and expands projects', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800));
    await _pump(tester);

    expect(
      find.byKey(const ValueKey('material-request-row-mr-322-closed')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-request-project-project-322')),
      findsNothing,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/mr_centre_mobile_360.png'),
    );
    await tester.tap(
      find.byKey(const ValueKey('material-request-centre-view-projects')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('material-request-project-project-322')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('material-request-row-mr-322-closed')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('server summary loader pages fifteen rows without full detail', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1280, 3000));
    final queries = <YorksV1MaterialRequestSummaryQuery>[];
    Future<YorksV1MaterialRequestSummaryPage> load(
      YorksV1MaterialRequestSummaryQuery query,
    ) async {
      queries.add(query);
      final remaining = 16 - query.offset;
      final count = remaining.clamp(0, query.limit);
      return YorksV1MaterialRequestSummaryPage(
        items: List.generate(
          count,
          (index) => _summary(
            index: query.offset + index,
            updatedAt: DateTime.utc(
              2026,
              8,
              21,
            ).subtract(Duration(minutes: query.offset + index)),
          ),
        ),
        totalCount: 16,
        limit: query.limit,
        offset: query.offset,
        hasMore: query.offset + count < 16,
        metrics: const YorksV1MaterialRequestSummaryMetrics(
          total: 16,
          open: 16,
          inProgress: 0,
          dispatched: 0,
          received: 0,
          closed: 0,
        ),
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          body: YorksV1MaterialRequestCentre(
            requests: const [],
            language: AppLanguage.english,
            canCreate: true,
            onCreate: () {},
            onOpen: (_) {},
            onRefresh: () {},
            summaryPageLoader: load,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(queries.single.limit, 15);
    expect(queries.single.offset, 0);
    expect(
      queries.single.registerView,
      YorksV1MaterialRequestRegisterView.total,
    );
    expect(find.text('1–15 / 16'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('material-request-row-server-summary-14')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-request-row-server-summary-15')),
      findsNothing,
    );

    await tester.tap(find.text('My Material Requests'));
    await tester.pumpAndSettle();
    expect(queries.last.registerView, YorksV1MaterialRequestRegisterView.mine);

    await tester.tap(find.text('My Work'));
    await tester.pumpAndSettle();
    expect(
      queries.last.registerView,
      YorksV1MaterialRequestRegisterView.myWork,
    );

    await tester.tap(find.text('Exceptions'));
    await tester.pumpAndSettle();
    expect(
      queries.last.registerView,
      YorksV1MaterialRequestRegisterView.exceptions,
    );

    await tester.tap(
      find.byKey(const ValueKey('material-request-centre-page-next')),
    );
    await tester.pumpAndSettle();
    expect(queries.last.offset, 15);
    expect(find.text('16–16 / 16'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('material-request-row-server-summary-15')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('historical insights load only when opened', (tester) async {
    await _setViewport(tester, const Size(1280, 1000));
    var insightsLoads = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: YorksV1MaterialRequestCentre(
            requests: const [],
            language: AppLanguage.english,
            canCreate: false,
            onCreate: null,
            onOpen: (_) {},
            onRefresh: () {},
            summaryPageLoader: (query) async =>
                YorksV1MaterialRequestSummaryPage(
                  items: [],
                  totalCount: 0,
                  limit: 15,
                  offset: 0,
                  hasMore: false,
                  metrics: YorksV1MaterialRequestSummaryMetrics(
                    total: 0,
                    open: 0,
                    inProgress: 0,
                    dispatched: 0,
                    received: 0,
                    closed: 0,
                  ),
                ),
            operationsDashboardLoader: (_) async {
              insightsLoads++;
              throw StateError('test dashboard unavailable');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(insightsLoads, 0);
    await tester.tap(
      find.byKey(const ValueKey('material-request-operational-insights')),
    );
    await tester.pumpAndSettle();
    expect(insightsLoads, 1);
  });

  testWidgets('overlapping register changes keep only the latest page', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1280, 1000));
    final first = Completer<YorksV1MaterialRequestSummaryPage>();
    final searches = <String>[];
    var active = 0;
    var peak = 0;
    Future<YorksV1MaterialRequestSummaryPage> load(
      YorksV1MaterialRequestSummaryQuery query,
    ) async {
      searches.add(query.search ?? '');
      active++;
      if (active > peak) peak = active;
      try {
        if (searches.length == 1) return await first.future;
        return YorksV1MaterialRequestSummaryPage(
          items: [_summary(index: 2, updatedAt: DateTime.utc(2026, 8, 21))],
          totalCount: 1,
          limit: 15,
          offset: 0,
          hasMore: false,
          metrics: const YorksV1MaterialRequestSummaryMetrics(
            total: 1,
            open: 1,
            inProgress: 0,
            dispatched: 0,
            received: 0,
            closed: 0,
          ),
        );
      } finally {
        active--;
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: YorksV1MaterialRequestCentre(
            requests: const [],
            language: AppLanguage.english,
            canCreate: false,
            onCreate: null,
            onOpen: (_) {},
            onRefresh: () {},
            summaryPageLoader: load,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('material-request-centre-search')),
      'latest',
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(searches.length, 1);
    first.complete(
      YorksV1MaterialRequestSummaryPage(
        items: [_summary(index: 1, updatedAt: DateTime.utc(2026, 8, 21))],
        totalCount: 1,
        limit: 15,
        offset: 0,
        hasMore: false,
        metrics: const YorksV1MaterialRequestSummaryMetrics(
          total: 1,
          open: 1,
          inProgress: 0,
          dispatched: 0,
          received: 0,
          closed: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(searches, ['', 'latest']);
    expect(peak, 1);
    expect(
      find.byKey(const ValueKey('material-request-row-server-summary-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('material-request-row-server-summary-1')),
      findsNothing,
    );
  });

  testWidgets('operational insights remain readable at mobile width', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: YorksV1MaterialRequestOperationalInsightsPanel(
              language: AppLanguage.english,
              dashboard: const YorksV1MaterialRequestOperationsDashboard(
                myWorkCount: 4,
                exceptionRequestCount: 3,
                requiredDateOverdueCount: 2,
                actionDuePolicy: 'not_configured',
                averageApprovalHours: 6.25,
                averageArrangementHours: 9.5,
                warehouseFillRatePercent: 82.75,
                averageReceiptTurnaroundHours: 3.5,
                outstandingReplacementQuantity: '12.5',
                averageReturnClosureHours: 18,
              ),
              loading: false,
              failed: false,
              onRetry: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('material-request-operational-insights')),
      findsOneWidget,
    );
    expect(find.text('4 My Work · 3 Exceptions'), findsOneWidget);
    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.text('Average approval time'), findsOneWidget);
    expect(find.text('Warehouse fill rate'), findsOneWidget);
    expect(find.text('82.8%'), findsOneWidget);
    expect(find.textContaining('approved Yorks SLA policy'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/mr_operational_insights_360.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('operational insights use a calm desktop metric grid', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 500));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: YorksV1MaterialRequestOperationalInsightsPanel(
              language: AppLanguage.english,
              dashboard: const YorksV1MaterialRequestOperationsDashboard(
                myWorkCount: 4,
                exceptionRequestCount: 3,
                requiredDateOverdueCount: 2,
                actionDuePolicy: 'not_configured',
                averageApprovalHours: 6.25,
                averageArrangementHours: 9.5,
                warehouseFillRatePercent: 82.75,
                averageReceiptTurnaroundHours: 3.5,
                outstandingReplacementQuantity: '12.5',
                averageReturnClosureHours: 18,
              ),
              loading: false,
              failed: false,
              onRetry: _noop,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Insights'));
    await tester.pumpAndSettle();

    expect(find.text('Average arrangement time'), findsOneWidget);
    expect(find.text('Return closure time'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/r35/mr_operational_insights_desktop.png'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('register surfaces action age, due risk and exceptions', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1280, 800));
    final request = _request(
      id: 'mr-action-facts',
      projectId: 'project-action-facts',
      reference: 'YRA-401',
      projectName: 'Action facts project',
      number: 'YRA-401-MR001',
      title: 'Late external material',
      scope: 'Building A',
      state: YorksV1MaterialRequestState.approvedForArrangement,
      updatedAt: DateTime.utc(2026, 8, 20, 9),
      action: 'arrangement_required',
      ownerRole: 'procurement',
      scheduledDate: DateTime.utc(2026, 8, 19),
      currentActionAgeHours: 27.5,
      requiredOnSiteOverdue: true,
      actorCanAct: true,
      exceptionCodes: const [
        YorksV1MaterialRequestExceptionCode.lateExternalSupply,
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          body: YorksV1MaterialRequestCentre(
            requests: [request],
            language: AppLanguage.english,
            canCreate: false,
            onCreate: null,
            onOpen: (_) {},
            onRefresh: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Current owner'), findsOneWidget);
    expect(find.textContaining('Next action'), findsOneWidget);
    expect(find.textContaining('Required on site'), findsOneWidget);
    expect(find.textContaining('Action age'), findsOneWidget);
    expect(find.text('Late external supply'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

Future<void> _pump(
  WidgetTester tester, {
  ValueChanged<YorksV1MaterialRequest>? onOpen,
  VoidCallback? onCreate,
}) => tester.pumpWidget(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      body: YorksV1MaterialRequestCentre(
        requests: _requests,
        language: AppLanguage.english,
        canCreate: true,
        onCreate: onCreate ?? () {},
        onRefresh: () {},
        onOpen: onOpen ?? (_) {},
      ),
    ),
  ),
);

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

final _requests = <YorksV1MaterialRequest>[
  _request(
    id: 'mr-322-closed',
    projectId: 'project-322',
    reference: 'YRA-322',
    projectName: 'N-19957.2 Project Nexus (Power)',
    number: 'YRA-322-MR004',
    title: 'Bulk transmission materials',
    scope: 'DF6W · 132/33kV Substation',
    state: YorksV1MaterialRequestState.closed,
    updatedAt: DateTime.utc(2026, 8, 20, 9),
  ),
  _request(
    id: 'mr-322-approval',
    projectId: 'project-322',
    reference: 'YRA-322',
    projectName: 'N-19957.2 Project Nexus (Power)',
    number: 'YRA-322-MR005',
    title: 'Chilled water accessories',
    scope: 'Common / All Buildings',
    state: YorksV1MaterialRequestState.awaitingRequestApproval,
    updatedAt: DateTime.utc(2026, 8, 20, 8),
    action: 'engineering_approval_required',
    ownerRole: 'project_engineer',
  ),
  _request(
    id: 'mr-314-dispatched',
    projectId: 'project-314',
    reference: 'YRA-314',
    projectName: 'Independent Subsea HVDC System Project',
    number: 'YRA-314-MR006',
    title: 'Electrical',
    scope: 'Common / All Buildings',
    state: YorksV1MaterialRequestState.dispatched,
    updatedAt: DateTime.utc(2026, 8, 19, 9),
    action: 'receipt_review_required',
    ownerRole: 'project_engineer',
  ),
  _request(
    id: 'mr-313-received',
    projectId: 'project-313',
    reference: 'YRA-313',
    projectName: 'Duct work',
    number: 'YRA-313-MR016',
    title: 'Duct work',
    scope: 'Common / All Buildings',
    state: YorksV1MaterialRequestState.received,
    updatedAt: DateTime.utc(2026, 8, 18, 9),
    action: 'close_request',
    ownerRole: 'project_engineer',
  ),
];

YorksV1MaterialRequestSummary _summary({
  required int index,
  required DateTime updatedAt,
}) => YorksV1MaterialRequestSummary(
  id: 'server-summary-$index',
  projectId: 'server-project-${index % 2}',
  projectReference: 'YRA-${330 + index % 2}',
  projectName: 'Server project ${index % 2}',
  scopeId: 'server-scope-${index % 2}',
  scopeName: 'Common / All Buildings',
  state: YorksV1MaterialRequestState.submitted,
  recordVersion: 1,
  requestNumber: 'YRA-MR-${index + 1}',
  title: 'Server summary ${index + 1}',
  timing: YorksV1MaterialRequestTiming.normal,
  itemCount: index + 1,
  createdAt: updatedAt,
  updatedAt: updatedAt,
  workAssignment: YorksV1MaterialRequestWorkAssignment(
    requestId: 'server-summary-$index',
    assignmentVersion: 0,
    canManage: true,
  ),
);

YorksV1MaterialRequest _request({
  required String id,
  required String projectId,
  required String reference,
  required String projectName,
  required String number,
  required String title,
  required String scope,
  required YorksV1MaterialRequestState state,
  required DateTime updatedAt,
  String? action,
  String? ownerRole,
  DateTime? scheduledDate,
  double currentActionAgeHours = 0,
  bool requiredOnSiteOverdue = false,
  bool actorCanAct = false,
  List<YorksV1MaterialRequestExceptionCode> exceptionCodes = const [],
}) => YorksV1MaterialRequest(
  id: id,
  projectId: projectId,
  projectReference: reference,
  projectName: projectName,
  scopeId: '$projectId-$scope',
  scopeName: scope,
  state: state,
  recordVersion: 1,
  createdAt: updatedAt.subtract(const Duration(days: 1)),
  updatedAt: updatedAt,
  timing: scheduledDate == null
      ? YorksV1MaterialRequestTiming.normal
      : YorksV1MaterialRequestTiming.scheduled,
  scheduledDate: scheduledDate,
  requestNumber: number,
  title: title,
  requesterDisplayName: 'Faisal Ahmed',
  requesterProjectRole: 'Project Engineer',
  currentActionCode: action,
  currentActionOwnerRole: ownerRole,
  currentActionAgeHours: currentActionAgeHours,
  requiredOnSiteOverdue: requiredOnSiteOverdue,
  actorCanAct: actorCanAct,
  exceptionCodes: exceptionCodes,
  lines: const [
    YorksV1MaterialRequestLine(
      id: 'line',
      displayOrder: 1,
      source: YorksV1MaterialRequestLineSource.custom,
      description: 'Controlled material',
      quantity: '1',
      unit: 'Nos',
    ),
  ],
);

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

final _companyRegisterRow = <String, dynamic>{
  'id': 'company-proof',
  'request_kind': 'company',
  'state': 'awaiting_company_approval',
  'category_name': 'Workshop materials',
  'responsible_unit_name': 'Main workshop',
  'created_at': '2026-09-25T08:00:00Z',
  'updated_at': '2026-09-25T08:00:00Z',
  'request_number': 'CMR-0042',
  'title': 'Safety equipment',
  'item_count': 3,
  'requester_display_name': 'Site Engineer',
  'current_action_owner_role': 'company_approver',
  'current_action_code': 'approve',
};
