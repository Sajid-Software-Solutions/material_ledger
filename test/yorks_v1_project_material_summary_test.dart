import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_project_material_summary.dart';
import 'package:material_ledger/shared/services/yorks_v1_material_summary_document_service.dart';

import 'support/yorks_v1_material_summary_fixture.dart';

void main() {
  group('YorksV1ProjectMaterialSummary.fromRpcJson', () {
    late YorksV1ProjectMaterialSummary summary;

    setUp(() {
      summary = YorksV1ProjectMaterialSummary.fromRpcJson(
        yorksV1MaterialSummaryFixture(),
      );
    });

    test('decodes items, requests and scopes in server order', () {
      expect(summary.projectId, 'project-1');
      expect(summary.items.map((item) => item.description), [
        'Aluminium Tap',
        'Aluminium Tape',
        'Copper Pipe',
        'Safety Gloves',
      ]);
      expect(summary.items[1].index, 1);
      expect(summary.items[1].itemCodes, ['AT-001']);
      expect(summary.items[1].brandOrigins, ['3M', 'Local']);
      expect(summary.requests.map((request) => request.number), [
        'YRA-MR-005',
        'YRA-MR-003',
        'YRA-MR-004',
      ]);
      expect(summary.scopeName('scope-a'), 'Building A');
      expect(summary.scopeName('missing'), isNull);
    });

    test('keeps exact decimal strings and derives percentages', () {
      final gloves = summary.items[3];
      expect(gloves.requested, '50');
      expect(gloves.sent, '32.5');
      expect(gloves.returned, '2');
      expect(gloves.sentOfRequested, closeTo(.65, 1e-9));
      expect(gloves.fullySent, isFalse);
      expect(gloves.awaitingDispatch, isTrue);
      // A cancelled request whose dispatch is still reported has no
      // fulfilment ratio rather than an infinite one.
      expect(summary.items[2].sentOfRequested, isNull);
      expect(summary.items[2].awaitingDispatch, isFalse);
    });

    test('resolves request links for items and periods', () {
      expect(
        summary
            .requestsFor(summary.items[1].requestRefs)
            .map((request) => request.number),
        ['YRA-MR-003', 'YRA-MR-004'],
      );
      expect(summary.requestsFor([2, 2, 99]).single.number, 'YRA-MR-004');
    });

    test('groups compact period rows newest first', () {
      expect(summary.months.map(yorksV1MaterialSummaryDateKeyOf), [
        '2026-11-01',
        '2026-10-01',
      ]);
      expect(summary.weeks.map(yorksV1MaterialSummaryDateKeyOf), [
        '2026-11-02',
        '2026-10-26',
        '2026-10-12',
      ]);
      expect(summary.months.first.lines.map((line) => line.itemIndex), [
        0,
        1,
        3,
      ]);
      expect(summary.weeks[1].requestRefs, {1});
    });

    test('month and Monday-Sunday week boundaries are inclusive', () {
      expect(
        yorksV1MaterialSummaryDateKey(summary.months.first.end),
        '2026-11-30',
      );
      final week = summary.weeks[1];
      expect(week.start.weekday, DateTime.monday);
      expect(week.end.weekday, DateTime.sunday);
      expect(yorksV1MaterialSummaryDateKey(week.end), '2026-11-01');
    });

    test('share of item total is unit-safe and falls back to sent', () {
      final novemberGloves = summary.months.first.lines.last;
      expect(summary.shareOfItem(novemberGloves), 1);
      final weekGloves = summary.weeks[1].lines.last;
      expect(summary.shareOfItem(weekGloves), closeTo(.4, 1e-9));
      final cancelledCopper = summary.months.last.lines.single;
      expect(summary.shareOfItem(cancelledCopper), 1);
    });

    test('summary metrics count materials, not mixed-unit quantities', () {
      expect(summary.fullySentCount, 0);
      expect(summary.awaitingDispatchCount, 3);
      expect(summary.isEmpty, isFalse);
    });

    test('rejects malformed responses instead of guessing', () {
      Matcher unexpected() => throwsA(
        isA<YorksV1DomainException>().having(
          (error) => error.code,
          'code',
          YorksV1DomainErrorCode.unexpectedResponse,
        ),
      );
      expect(() => YorksV1ProjectMaterialSummary.fromRpcJson([]), unexpected());

      final badQuantity = yorksV1MaterialSummaryFixture();
      (badQuantity['items']! as List).first['requested_qty'] = 'ten';
      expect(
        () => YorksV1ProjectMaterialSummary.fromRpcJson(badQuantity),
        unexpected(),
      );

      final badPeriod = yorksV1MaterialSummaryFixture();
      (badPeriod['weeks']! as List).first = [
        '2026-11-02',
        42,
        '1',
        '0',
        '0',
        <int>[],
      ];
      expect(
        () => YorksV1ProjectMaterialSummary.fromRpcJson(badPeriod),
        unexpected(),
      );
    });
  });

  group('YorksV1MaterialSummaryQuery', () {
    test('normalizes search and serializes calendar dates', () {
      final query = YorksV1MaterialSummaryQuery(
        projectId: 'project-1',
        from: DateTime.utc(2026, 11, 2),
        to: DateTime.utc(2026, 11, 8),
        scopeId: 'scope-a',
        search: '  aluminium    tape ',
      );
      expect(query.toRpcParameters(), {
        'p_project_id': 'project-1',
        'p_from': '2026-11-02',
        'p_to': '2026-11-08',
        'p_scope_id': 'scope-a',
        'p_search': 'aluminium tape',
      });
      expect(query.hasFilters, isTrue);
    });

    test('equal filters share one provider family member', () {
      const a = YorksV1MaterialSummaryQuery(projectId: 'p', search: 'tape ');
      const b = YorksV1MaterialSummaryQuery(projectId: 'p', search: ' tape');
      const empty = YorksV1MaterialSummaryQuery(projectId: 'p', search: '  ');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(empty, const YorksV1MaterialSummaryQuery(projectId: 'p'));
      expect(empty.hasFilters, isFalse);
    });

    test('search is bounded to the server limit', () {
      final query = YorksV1MaterialSummaryQuery(
        projectId: 'p',
        search: 'x' * 200,
      );
      expect(
        query.normalizedSearch!.length,
        YorksV1MaterialSummaryQuery.maxSearchLength,
      );
    });
  });

  group('Gulf calendar helpers', () {
    test('a late Saturday UTC request is Sunday in Dubai', () {
      final today = yorksV1GulfToday(DateTime.utc(2026, 10, 31, 21, 30));
      expect(yorksV1MaterialSummaryDateKey(today), '2026-11-01');
      expect(
        yorksV1MaterialSummaryDateKey(yorksV1MaterialSummaryWeekStart(today)),
        '2026-10-26',
      );
    });

    test('Monday starts a new week', () {
      final monday = DateTime.utc(2026, 11, 2);
      expect(yorksV1MaterialSummaryWeekStart(monday), monday);
    });
  });

  group('labels', () {
    test('formats periods and percentages', () {
      final summary = YorksV1ProjectMaterialSummary.fromRpcJson(
        yorksV1MaterialSummaryFixture(),
      );
      expect(
        yorksV1MaterialSummaryPeriodLabel(summary.months.first),
        'November 2026',
      );
      expect(
        yorksV1MaterialSummaryPeriodLabel(summary.weeks[1]),
        'Mon 26 Oct – Sun 1 Nov 2026',
      );
      expect(yorksV1MaterialSummaryPercent(null), '—');
      expect(yorksV1MaterialSummaryPercent(.004), '<1%');
      expect(yorksV1MaterialSummaryPercent(.655), '66%');
      expect(yorksV1MaterialSummaryPercent(1.2), '120%');
    });
  });

  group('Excel export', () {
    final summary = YorksV1ProjectMaterialSummary.fromRpcJson(
      yorksV1MaterialSummaryFixture(),
    );
    final context = YorksV1MaterialSummaryExportContext(
      projectReference: 'YRA-322',
      projectName: 'Tower <A> & Podium',
      buildingLabel: 'All buildings',
      periodLabel: 'All time',
      search: 'tape',
      generatedAt: DateTime.utc(2026, 11, 3, 12),
    );
    const service = YorksV1MaterialSummaryDocumentService();

    Map<String, String> unzip() {
      final archive = ZipDecoder().decodeBytes(
        service.buildExcel(summary, context),
      );
      return {
        for (final file in archive.files)
          if (file.isFile) file.name: utf8.decode(file.content as List<int>),
      };
    }

    test('writes three named sheets with a valid package structure', () {
      final files = unzip();
      expect(files.keys, contains('[Content_Types].xml'));
      expect(files.keys, contains('xl/styles.xml'));
      expect(files['xl/workbook.xml'], contains('name="Overall"'));
      expect(files['xl/workbook.xml'], contains('name="Monthly"'));
      expect(files['xl/workbook.xml'], contains('name="Weekly"'));
      expect(files.keys, contains('xl/worksheets/sheet3.xml'));
    });

    test('quantities and percentages are numeric cells', () {
      final overall = unzip()['xl/worksheets/sheet1.xml']!;
      // Safety Gloves: requested 50, sent 32.5, 65% sent of requested.
      expect(overall, contains('<v>50</v>'));
      expect(overall, contains('<v>32.5</v>'));
      expect(overall, contains('<v>0.650000</v>'));
      expect(overall, contains('YRA-MR-003, YRA-MR-004'));
      expect(overall, contains('state="frozen"'));
      expect(overall, contains('<autoFilter'));
    });

    test('escapes text and records the filters that produced it', () {
      final overall = unzip()['xl/worksheets/sheet1.xml']!;
      expect(overall, contains('Tower &lt;A&gt; &amp; Podium'));
      expect(overall, contains('Search: &quot;tape&quot;'));
    });

    test('period sheets carry share of item total', () {
      final weekly = unzip()['xl/worksheets/sheet3.xml']!;
      expect(weekly, contains('Mon 26 Oct – Sun 1 Nov 2026'));
      expect(weekly, contains('Share of item total'));
      expect(weekly, contains('<v>0.400000</v>'));
    });

    test('contains no commercial field', () {
      final text = unzip().values.join().toLowerCase();
      expect(text, isNot(contains('unit cost')));
      expect(text, isNot(contains('total cost')));
      expect(text, isNot(contains('supplier')));
    });

    test('suggested file names are filesystem-safe', () {
      expect(
        service.suggestedFileName(context, 'xlsx'),
        startsWith('YRA-322_material_summary_'),
      );
      expect(service.suggestedFileName(context, 'pdf'), endsWith('.pdf'));
    });
  });
}

String yorksV1MaterialSummaryDateKeyOf(YorksV1MaterialSummaryPeriod period) =>
    yorksV1MaterialSummaryDateKey(period.start);
