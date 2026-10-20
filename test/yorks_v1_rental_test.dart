import 'dart:io';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:material_ledger/shared/models/yorks_v1_domain_error.dart';
import 'package:material_ledger/shared/models/yorks_v1_feature_flags.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_material_request_repository.dart';
import 'package:material_ledger/shared/sync/connectivity_service.dart';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/core/constants/constants.dart';
import 'package:material_ledger/core/widgets/widgets.dart';
import 'package:material_ledger/features/rentals/presentation/screens/yorks_v1_rental_screens.dart';
import 'package:material_ledger/shared/models/yorks_v1_boq_workbook.dart';
import 'package:material_ledger/shared/models/yorks_v1_document.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental.dart';
import 'package:material_ledger/shared/models/yorks_v1_rental_workbook.dart';
import 'package:material_ledger/shared/providers/yorks_v1_documents_repository_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_rental_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_documents_repository.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_rental_repository.dart';
import 'package:material_ledger/shared/services/yorks_v1_boq_workbook_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_rental_workbook_service.dart';

void main() {
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

  test(
    'annual optional input keeps nulls and normalizes displayed choices for RPC',
    () {
      final input = YorksV1RentalPropertyInput(
        unitCode: 'SOURCE-17',
        propertyName: 'Office (Store) SOURCE-17',
        propertyType: 'Office (Store)',
        location: '',
        occupancy: YorksV1RentalOccupancy.unknown,
        contractNumber: '',
        contractType: 'Tenancy Contract',
        contractStatus: 'Notice Due',
        monthlyRent: null,
        annualRent: 27825,
        securityDeposit: 0,
        monthlyDueDay: 1,
        gracePeriodDays: 5,
        defaultPaymentMethod: 'Bank Transfer',
        paymentFrequency: 'Annual',
        contractCheques: 0,
        annualEscalationPercent: 0,
        renewalNoticeDays: 90,
        sourceMetadata: const {
          'original_values': {'Security Cheque (AED)': '4 YEARS'},
        },
      );
      final payload = input.toRpcPayload();
      expect(payload['property_type'], 'office_store');
      expect(payload['occupancy_state'], 'unknown');
      expect(payload['occupied'], isFalse);
      expect(payload['contract_type'], 'tenancy_contract');
      expect(payload['contract_status'], 'notice_due');
      expect(payload['default_payment_method'], 'bank_transfer');
      expect(payload['payment_frequency'], 'annual');
      expect(payload['annual_rent'], 27825);
      expect(payload['monthly_rent'], isNull);
      expect(payload['lease_start'], isNull);
      expect(payload['lease_end'], isNull);
      expect(payload['billing_start'], isNull);
      expect(payload['source_metadata'], input.sourceMetadata);
    },
  );

  test(
    'missing rent and unknown occupancy remain distinct from zero and vacant',
    () {
      final missing = YorksV1RentalProperty.fromJson({
        'occupancy_state': 'unknown',
        'payment_frequency': 'annual',
        'annual_rent': null,
        'monthly_rent': null,
        'missing_fields': ['rent_amount', 'occupancy'],
        'source_metadata': {
          'original_values': {'Status': null},
        },
      });
      final zero = YorksV1RentalProperty.fromJson({
        'occupancy_state': 'vacant',
        'payment_frequency': 'annual',
        'annual_rent': 0,
      });
      expect(missing.occupancy, YorksV1RentalOccupancy.unknown);
      expect(missing.isOccupied, isFalse);
      expect(missing.rentAmount, isNull);
      expect(missing.needsCompletion, isTrue);
      expect(missing.sourceMetadata['original_values'], {'Status': null});
      expect(zero.occupancy, YorksV1RentalOccupancy.vacant);
      expect(zero.rentAmount, 0);
    },
  );

  test(
    'portfolio rent_frequency and lease payment_frequency keep annual values identical',
    () {
      for (final frequencyKey in ['rent_frequency', 'payment_frequency']) {
        final property = YorksV1RentalProperty.fromJson({
          frequencyKey: 'annual',
          'annual_rent': 27825,
          'monthly_rent': null,
        });
        expect(property.paymentFrequency, 'annual');
        expect(property.isAnnual, isTrue);
        expect(property.hasRentAmount, isTrue);
        expect(property.rentAmount, 27825);
      }
    },
  );

  test(
    'unconfirmed payment retries reuse the committed command identity',
    () async {
      final repository = _RetryRentalFixtureRepository()
        ..loseNextResponse = true;
      final container = ProviderContainer(
        overrides: [
          yorksV1RentalRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final subscription = container.listen(
        yorksV1RentalCommandProvider,
        (_, _) {},
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      final commands = container.read(yorksV1RentalCommandProvider.notifier);
      Future<bool> pay() => commands.recordPayment(
        propertyId: 'source-property',
        periodId: 'source-period',
        amount: 100,
        paymentDate: DateTime(2026, 10, 20),
        paymentMethod: 'bank_transfer',
        reference: 'BANK-RETRY-1',
      );
      expect(await pay(), isFalse);
      expect(await pay(), isTrue);
      expect(repository.paymentKeys, hasLength(2));
      expect(repository.paymentKeys[0], repository.paymentKeys[1]);
      expect(repository.committedPaymentKeys, hasLength(1));
    },
  );

  test(
    'payment command blocks competing taps while the first result is pending',
    () async {
      final repository = _RetryRentalFixtureRepository()
        ..pendingPayment = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          yorksV1RentalRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final subscription = container.listen(
        yorksV1RentalCommandProvider,
        (_, _) {},
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      final commands = container.read(yorksV1RentalCommandProvider.notifier);
      Future<bool> pay() => commands.recordPayment(
        propertyId: 'source-property',
        periodId: 'source-period',
        amount: 100,
        paymentDate: DateTime(2026, 10, 20),
        paymentMethod: 'bank_transfer',
      );
      final first = pay();
      await Future<void>.delayed(Duration.zero);
      expect(await pay(), isFalse);
      expect(repository.paymentKeys, hasLength(1));
      repository.pendingPayment!.complete();
      expect(await first, isTrue);
    },
  );

  group('R38.4 rental workbook contract', () {
    const codec = YorksV1RentalWorkbookCodec();

    test('template contains the five exact controlled worksheets', () {
      final workbook = const YorksV1BoqWorkbookCodec().decode(
        bytes: codec.buildImportTemplate(),
        fileName: 'Yorks_Rental_Properties_Import.xlsx',
      );

      expect(
        workbook.sheets.map((sheet) => sheet.name),
        containsAllInOrder(const [
          YorksV1RentalWorkbookCodec.instructionsSheet,
          YorksV1RentalWorkbookCodec.propertySheet,
          YorksV1RentalWorkbookCodec.paymentSheet,
          YorksV1RentalWorkbookCodec.chequeSheet,
          YorksV1RentalWorkbookCodec.listsSheet,
        ]),
      );
      expect(
        _sheet(workbook, YorksV1RentalWorkbookCodec.propertySheet).rows[2],
        [
          ...YorksV1RentalWorkbookCodec.trackerHeaders,
          ...YorksV1RentalWorkbookCodec.trackerOptionalHeaders,
        ],
      );
      expect(
        _sheet(workbook, YorksV1RentalWorkbookCodec.paymentSheet).rows.first,
        YorksV1RentalWorkbookCodec.paymentHeaders,
      );
      expect(
        _sheet(workbook, YorksV1RentalWorkbookCodec.chequeSheet).rows.first,
        YorksV1RentalWorkbookCodec.chequeHeaders,
      );
      final frequencies = _sheet(
        workbook,
        YorksV1RentalWorkbookCodec.listsSheet,
      ).rows.skip(1).map((row) => row[6]).where((value) => value.isNotEmpty);
      expect(frequencies, ['Monthly', 'Annual']);
    });

    test('tracker format reports all three missing data worksheets', () {
      final preview = codec.preview(
        selected: YorksV1RentalSelectedWorkbook(
          fileName: 'tracker.xlsx',
          bytes: _workbook({
            'Sheet1': const [
              ['Lease contracts tracker'],
              ['Unit No', 'Unit Type', 'Annual Rent (AED)'],
              ['1', 'Shop', '12000'],
            ],
          }),
        ),
        portfolio: rentalPortfolioFixture,
      );
      expect(preview.rows, isEmpty);
      expect(preview.errorCount, 3);
      expect(preview.canConfirm, isFalse);
      expect(preview.issues.map((issue) => issue.sheet), [
        YorksV1RentalWorkbookCodec.propertySheet,
        YorksV1RentalWorkbookCodec.paymentSheet,
        YorksV1RentalWorkbookCodec.chequeSheet,
      ]);
    });

    test(
      'incomplete tracker rows remain importable without inventing financial facts',
      () {
        final preview = _previewRentalTracker([
          _rentalTrackerValues({
            'Unit No': '1',
            'Unit Type': 'Shop',
            'Tenant / Company': 'Test tenant',
            'Contract Start': '2026-01-01',
            'Contract End': '2026-12-31',
            'Annual Rent (AED)': '27825',
            'Status': 'Active',
            'Security Cheque (AED)': '2000',
            'Days to Expiry': '72',
            'Expiry Flag': 'OK',
          }),
          _rentalTrackerValues({
            'Unit No': '1',
            'Unit Type': 'Store',
            'Status': 'Active',
          }),
          _rentalTrackerValues({
            'Unit Type': 'Office (Store)',
            'Security Cheque (AED)': '4 YEARS',
          }),
          _rentalTrackerValues({
            'Unit No': 'AC1(1)',
            'Tenant / Company': 'Internal use',
          }),
        ]);
        expect(preview.canConfirm, isTrue);
        expect(preview.errorCount, 0);
        expect(preview.warningCount, greaterThan(0));
        expect(preview.properties.map((row) => row.payload['unit_code']), [
          'SHOP-1',
          'STORE-1',
          'SOURCE-6',
          'UNIT-AC1-1',
        ]);
        final first = preview.properties.first.payload;
        expect(first['annual_rent'], 27825);
        expect(first['monthly_rent'], isNull);
        expect(first['payment_frequency'], 'annual');
        expect(first['billing_start'], isNull);
        expect(first['location'], isNull);
        expect(first['contract_number'], isNull);
        expect(first.containsKey('security_deposit'), isFalse);
        expect(first['occupancy_state'], 'occupied');
        expect(preview.properties[1].payload['annual_rent'], isNull);
        expect(preview.properties[1].payload['property_type'], 'store');
        expect(preview.properties[2].payload['property_type'], 'office_store');
        expect(preview.properties[3].payload['occupancy_state'], 'unknown');
        final metadata =
            preview.properties[2].payload['source_metadata'] as Map;
        expect(metadata['source_row'], 6);
        expect(
          (metadata['original_values'] as Map)['Security Cheque (AED)'],
          '4 YEARS',
        );
        expect(metadata['source_unit_number'], isNull);
        expect(preview.payments, isEmpty);
        expect(preview.cheques, isEmpty);
      },
    );

    test(
      'tracker dates and source notes are preserved without using static expiry flags',
      () {
        final preview = _previewRentalTracker([
          _rentalTrackerValues({
            'Unit No': 'AC2 - 6',
            'Unit Type': 'Office',
            'Status': 'Active',
            'Annual Rent (AED)': '7875',
            'Contract Start': '2025-12-08',
            'Contract End': '2026-12-07',
            'Security Cheque (AED)': 'NO',
            'Days to Expiry': '48',
            'Expiry Flag': 'OK',
          }),
        ]);
        expect(preview.canConfirm, isTrue);
        final payload = preview.properties.single.payload;
        expect(payload['lease_start'], '2025-12-08');
        expect(payload['lease_end'], '2026-12-07');
        expect(payload['billing_start'], isNull);
        expect(payload['lease_notes'], contains('NO'));
        final original =
            (payload['source_metadata'] as Map)['original_values'] as Map;
        expect(original['Days to Expiry'], '48');
        expect(original['Expiry Flag'], 'OK');
      },
    );

    test(
      'tracker monthly rent requires an explicit monthly choice and a single amount',
      () {
        final monthly = _previewRentalTracker([
          _rentalTrackerValues({
            'Unit No': 'M1',
            'Unit Type': 'Office',
            'Rent Frequency': 'Monthly',
            'Monthly Rent (AED)': '1250.50',
            'Billing Start': '2026-11-01',
            'Monthly Due Day': '5',
          }),
        ]);
        expect(monthly.canConfirm, isTrue);
        expect(monthly.properties.single.payload['annual_rent'], isNull);
        expect(monthly.properties.single.payload['monthly_rent'], 1250.5);
        expect(
          monthly.properties.single.payload['payment_frequency'],
          'monthly',
        );
        expect(
          monthly.properties.single.payload['billing_start'],
          '2026-11-01',
        );
        for (final values in [
          {'Monthly Rent (AED)': '100'},
          {
            'Rent Frequency': 'Monthly',
            'Monthly Rent (AED)': '100',
            'Annual Rent (AED)': '1200',
          },
          {'Rent Frequency': 'Quarterly', 'Annual Rent (AED)': '1200'},
        ]) {
          expect(
            _previewRentalTracker([
              _rentalTrackerValues({
                'Unit No': 'M1',
                'Unit Type': 'Office',
                ...values,
              }),
            ]).canConfirm,
            isFalse,
          );
        }
      },
    );

    test(
      'tracker malformed values and duplicate identities block the whole workbook',
      () {
        for (final values in [
          {'Annual Rent (AED)': '4 YEARS'},
          {'Annual Rent (AED)': 'NaN'},
          {'Contract Start': '2026-02-30'},
          {'Contract Start': '2027-01-01', 'Contract End': '2026-12-31'},
          {'Billing Start': 'invalid'},
          {'Monthly Due Day': '0'},
        ]) {
          expect(
            _previewRentalTracker([
              _rentalTrackerValues({
                'Unit No': '1',
                'Unit Type': 'Shop',
                ...values,
              }),
            ]).canConfirm,
            isFalse,
            reason: values.toString(),
          );
        }
        final row = _rentalTrackerValues({'Unit No': '1', 'Unit Type': 'Shop'});
        final duplicate = _previewRentalTracker([row, row]);
        expect(duplicate.canConfirm, isFalse);
        expect(
          duplicate.issues.map((issue) => issue.message),
          contains('Unit Code is duplicated in this workbook.'),
        );
      },
    );

    test(
      'tracker reimport requires a deliberate Update and preserves completed details',
      () {
        final source = {
          'Unit No': '1',
          'Unit Type': 'Shop',
          'Annual Rent (AED)': '27825',
          'Status': 'Active',
        };
        final first = _previewRentalTracker([_rentalTrackerValues(source)]);
        final originalMetadata =
            first.properties.single.payload['source_metadata'];
        final existing = YorksV1RentalPortfolio.fromJson({
          'summary': <String, dynamic>{},
          'properties': [
            {
              ...first.properties.single.payload,
              'id': 'saved-source',
              'lease_id': 'saved-lease',
              'record_version': 9,
              'property_name': 'Owner corrected property name',
              'location': 'Confirmed location',
              'contract_number': 'CONFIRMED-1',
              'tenant_name': 'Confirmed tenant',
              'contact_number': 'Confirmed contact',
              'lease_start': '2026-01-01',
              'lease_end': '2026-12-31',
              'billing_start': '2026-11-01',
              'monthly_due_day': 5,
            },
          ],
          'recent_payments': [],
          'cheques': [],
        });
        final unconfirmed = _previewRentalTracker([
          _rentalTrackerValues(source),
        ], portfolio: existing);
        expect(unconfirmed.canConfirm, isFalse);
        expect(
          unconfirmed.issues.map((issue) => issue.message),
          contains(
            'This Unit Code already exists. Enter Update in Import Action to deliberately update it.',
          ),
        );
        final confirmed = _previewRentalTracker([
          _rentalTrackerValues({...source, 'Import Action': 'Update'}),
        ], portfolio: existing);
        expect(confirmed.canConfirm, isTrue);
        final payload = confirmed.properties.single.payload;
        expect(payload['action'], 'update');
        expect(payload['property_id'], 'saved-source');
        expect(payload['expected_version'], 9);
        expect(payload['property_name'], 'Owner corrected property name');
        expect(payload['location'], 'Confirmed location');
        expect(payload['contract_number'], 'CONFIRMED-1');
        expect(payload['tenant_name'], 'Confirmed tenant');
        expect(payload['contact_number'], 'Confirmed contact');
        expect(payload['lease_start'], '2026-01-01');
        expect(payload['lease_end'], '2026-12-31');
        expect(payload['billing_start'], '2026-11-01');
        expect(payload['monthly_due_day'], 5);
        expect(payload['source_metadata'], originalMetadata);
        expect(payload.containsKey('lease_notes'), isFalse);
        expect(payload.containsKey('monthly_rent'), isFalse);
        final changedEvidence = _previewRentalTracker([
          _rentalTrackerValues({
            ...source,
            'Annual Rent (AED)': '30000',
            'Import Action': 'Update',
          }),
        ], portfolio: existing);
        expect(changedEvidence.canConfirm, isFalse);
        expect(
          changedEvidence.issues.map((issue) => issue.message),
          contains(
            'Original imported source values changed. Keep the source evidence unchanged and edit live property details instead.',
          ),
        );
      },
    );

    test('missing or duplicated headers block unsafe field mapping', () {
      for (final duplicated in [false, true]) {
        final headers = [...YorksV1RentalWorkbookCodec.propertyHeaders];
        headers[2] = duplicated ? 'Unit Code *' : 'Unrecognized property label';
        final preview = _previewRentalProperties([
          _propertyRow(action: 'Create', unitCode: 'NEW-1'),
        ], headers: headers);
        expect(preview.canConfirm, isFalse);
        expect(preview.properties, isEmpty);
        expect(
          preview.issues.map((issue) => issue.message),
          contains('Required column “Property Name *” is missing.'),
        );
        if (duplicated) {
          expect(
            preview.issues.map((issue) => issue.message),
            contains('Required column “Unit Code *” is duplicated.'),
          );
        }
      }
    });

    test(
      'unknown property and lease choices never become an importable row',
      () {
        for (final entry in const {
          'Property Type *': 'Unsupported type',
          'Occupancy *': 'Active',
          'Contract Type': 'Unknown contract',
          'Contract Status': 'Empty',
          'Default Payment Method': 'Credit card',
          'Payment Frequency': 'Quarterly',
        }.entries) {
          final preview = _previewRentalProperties([
            _rentalPropertyValues({entry.key: entry.value}),
          ]);
          expect(preview.canConfirm, isFalse, reason: entry.key);
          expect(preview.properties.single.hasError, isTrue, reason: entry.key);
          expect(
            preview.issues.map((issue) => issue.message),
            contains('${entry.key.replaceAll(' *', '')} is not supported.'),
          );
        }
      },
    );

    test('malformed financial and integer values block confirmation', () {
      for (final field in const [
        'Monthly Rent AED',
        'Monthly Due Day',
        'Grace Period Days',
        'Security Deposit AED',
        'No. of Contract Cheques',
        'Annual Escalation %',
        'Renewal Notice Days',
      ]) {
        for (final value in const [
          'not supplied',
          'NaN',
          'Infinity',
          '1e999',
          '1,2,3',
        ]) {
          final preview = _previewRentalProperties([
            _rentalPropertyValues({field: value}),
          ]);
          expect(preview.canConfirm, isFalse, reason: '$field=$value');
          expect(preview.properties.single.hasError, isTrue);
        }
      }
      for (final field in const [
        'Monthly Due Day',
        'Grace Period Days',
        'No. of Contract Cheques',
        'Renewal Notice Days',
      ]) {
        expect(
          _previewRentalProperties([
            _rentalPropertyValues({field: '1.5'}),
          ]).canConfirm,
          isFalse,
          reason: field,
        );
      }
    });

    test('lease term boundaries and impossible dates fail before commit', () {
      for (final entry in const {
        'Monthly Rent AED': '-1',
        'Monthly Due Day': '32',
        'Grace Period Days': '91',
        'Security Deposit AED': '-1',
        'No. of Contract Cheques': '241',
        'Annual Escalation %': '101',
        'Renewal Notice Days': '731',
        'Contract Signed Date': '2026-02-30',
        'Lease Start': '2026-02-29',
        'Lease End': 'not a date',
      }.entries) {
        expect(
          _previewRentalProperties([
            _rentalPropertyValues({entry.key: entry.value}),
          ]).canConfirm,
          isFalse,
          reason: entry.key,
        );
      }
      final reversed = _previewRentalProperties([
        _rentalPropertyValues({
          'Lease Start': '2026-12-31',
          'Lease End': '2026-01-01',
        }),
      ]);
      expect(reversed.canConfirm, isFalse);
      expect(
        reversed.issues.map((issue) => issue.message),
        contains('Lease End cannot be before Lease Start.'),
      );
    });

    test(
      'valid grouped amounts, integer cells and supported dates are preserved',
      () {
        final preview = _previewRentalProperties([
          _rentalPropertyValues({
            'Occupancy *': 'Occupied',
            'Tenant / Company Name': 'Test tenant',
            'Monthly Rent AED': '1,234.50',
            'Monthly Due Day': '31.0',
            'Grace Period Days': '0',
            'Security Deposit AED': '.50',
            'No. of Contract Cheques': '240',
            'Annual Escalation %': '100',
            'Renewal Notice Days': '730',
            'Contract Signed Date': '45000',
            'Lease Start': '29/02/2028',
            'Lease End': '2028-12-31',
          }),
        ]);
        expect(preview.issues, isEmpty);
        expect(preview.canConfirm, isTrue);
        final payload = preview.properties.single.payload;
        expect(payload['monthly_rent'], 1234.5);
        expect(payload['monthly_due_day'], 31);
        expect(payload['security_deposit'], .5);
        expect(payload['signed_date'], '2023-03-15');
        expect(payload['lease_start'], '2028-02-29');
        expect(payload['occupied'], isTrue);
      },
    );

    test('preview classifies Create/Update and never mutates repository', () {
      final repository = _RentalFixtureRepository();
      final bytes = _workbook({
        YorksV1RentalWorkbookCodec.instructionsSheet: const [
          ['Instructions'],
        ],
        YorksV1RentalWorkbookCodec.propertySheet: [
          YorksV1RentalWorkbookCodec.propertyHeaders,
          _propertyRow(action: 'Update', unitCode: 'RU-004'),
          _propertyRow(action: 'Create', unitCode: 'RU-005'),
        ],
        YorksV1RentalWorkbookCodec.paymentSheet: [
          YorksV1RentalWorkbookCodec.paymentHeaders,
        ],
        YorksV1RentalWorkbookCodec.chequeSheet: [
          YorksV1RentalWorkbookCodec.chequeHeaders,
        ],
        YorksV1RentalWorkbookCodec.listsSheet: const [
          ['Import Action'],
        ],
      });

      final preview = codec.preview(
        selected: YorksV1RentalSelectedWorkbook(
          fileName: 'rentals.xlsx',
          bytes: bytes,
        ),
        portfolio: rentalPortfolioFixture,
      );

      expect(preview.canConfirm, isTrue);
      expect(preview.updatedPropertyCount, 1);
      expect(preview.newPropertyCount, 1);
      expect(repository.importCalls, isEmpty);
      expect(preview.toRpcPayload()['properties'], hasLength(2));
    });

    test('duplicate payment identity blocks confirm before server commit', () {
      final payment = [
        'RU-004',
        '2026-08-01',
        '14000',
        '2026-08-11',
        'Bank Transfer',
        'BANK-101',
        'August rent',
      ];
      final preview = codec.preview(
        selected: YorksV1RentalSelectedWorkbook(
          fileName: 'duplicate-payment.xlsx',
          bytes: _workbook({
            YorksV1RentalWorkbookCodec.instructionsSheet: const [
              ['Instructions'],
            ],
            YorksV1RentalWorkbookCodec.propertySheet: [
              YorksV1RentalWorkbookCodec.propertyHeaders,
            ],
            YorksV1RentalWorkbookCodec.paymentSheet: [
              YorksV1RentalWorkbookCodec.paymentHeaders,
              payment,
              payment,
            ],
            YorksV1RentalWorkbookCodec.chequeSheet: [
              YorksV1RentalWorkbookCodec.chequeHeaders,
            ],
            YorksV1RentalWorkbookCodec.listsSheet: const [
              ['Import Action'],
            ],
          }),
        ),
        portfolio: rentalPortfolioFixture,
      );

      expect(preview.canConfirm, isFalse);
      expect(
        preview.issues.map((issue) => issue.message),
        contains('The same rent receipt is duplicated in this workbook.'),
      );
    });

    test('all five export registers produce readable Excel workbooks', () {
      final data = <String, dynamic>{
        'properties': [
          {'Unit Code': 'RU-004', 'Property': 'Mussafah Shop 04'},
        ],
        'periods': [
          {'Unit Code': 'RU-004', 'Period': '2026-08'},
        ],
        'payments': [
          {'Unit Code': 'RU-004', 'Amount': 14000},
        ],
        'cheques': [
          {'Unit Code': 'RU-004', 'Cheque No.': 'PDC-001'},
        ],
        'lease_expiry': [
          {'Unit Code': 'RU-004', 'Lease End': '2027-07-31'},
        ],
      };

      for (final register in YorksV1RentalExportRegister.values) {
        final bytes = codec.buildExport(register: register, data: data);
        final workbook = const YorksV1BoqWorkbookCodec().decode(
          bytes: bytes,
          fileName: '${register.name}.xlsx',
        );
        expect(workbook.sheets, hasLength(1));
        expect(workbook.sheets.single.rows, hasLength(2));
      }
    });
  });

  for (final evidence in <({String suffix, Size size})>[
    (suffix: 'desktop', size: const Size(1366, 768)),
    (suffix: 'mobile', size: const Size(360, 800)),
  ]) {
    testWidgets('source-like 52 property portfolio — ${evidence.size}', (
      tester,
    ) async {
      await _setViewport(tester, evidence.size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1RentalRepositoryProvider.overrideWithValue(
              _SourceRentalFixtureRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1RentalDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_sourceRentalPortfolio.properties, hasLength(52));
      expect(_sourceRentalPortfolio.summary.annualRentRoll, 710238);
      expect(_sourceRentalPortfolio.summary.monthlyRentRoll, 0);
      expect(find.text('Complete property details'), findsOneWidget);
      expect(find.text('Annual rent roll'), findsOneWidget);
      expect(find.text('AED 710,238.00'), findsOneWidget);
      expect(find.text('Review missing details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r38_4/rental_source_portfolio_${evidence.suffix}.png',
        ),
      );
    });

    testWidgets(
      'source register never marks unconfirmed billing paid — ${evidence.size}',
      (tester) async {
        await _setViewport(tester, evidence.size);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              yorksV1RentalRepositoryProvider.overrideWithValue(
                _SourceRentalFixtureRepository(),
              ),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              home: const YorksV1RentalDashboardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (evidence.size.width < 720) {
          await tester.tap(
            find.byWidgetPredicate(
              (widget) => widget is DropdownButtonFormField,
            ),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Property register'));
        await tester.pumpAndSettle();
        expect(find.text('Paid'), findsNothing);
        expect(find.text('AED 0.00'), findsNothing);
        expect(find.text('Not confirmed'), findsWidgets);
        expect(find.text('Unknown'), findsNWidgets(2));
        for (final text in tester.widgetList<Text>(
          find.text('Not confirmed'),
        )) {
          expect(text.style?.color, AppColors.warning);
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r38_4/rental_source_register_${evidence.suffix}.png',
          ),
        );
      },
    );

    testWidgets(
      'source detail retains missing fields and original evidence — ${evidence.size}',
      (tester) async {
        await _setViewport(tester, evidence.size);
        await _openSourceRentalDetail(tester, _SourceRentalFixtureRepository());
        expect(find.text('Complete property details'), findsOneWidget);
        expect(find.text('Opening balance unconfirmed'), findsOneWidget);
        expect(find.text('Unknown'), findsWidgets);
        for (final label in ['Current period paid', 'Total outstanding']) {
          final card = find
              .ancestor(of: find.text(label), matching: find.byType(LedgerCard))
              .first;
          expect(
            find.descendant(of: card, matching: find.text('Not confirmed')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: card, matching: find.text('AED 0.00')),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r38_4/rental_source_detail_${evidence.suffix}.png',
          ),
        );
        await tester.scrollUntilVisible(
          find.text('Imported source details'),
          220,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
        await tester.tap(find.text('Imported source details'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Security Cheque (AED)'),
          220,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .first,
        );
        expect(find.text('4 YEARS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'optional source edit keeps unknown state and separate rent amounts — ${evidence.size}',
      (tester) async {
        await _setViewport(tester, evidence.size);
        final repository = _SourceRentalFixtureRepository();
        await _openSourceRentalDetail(tester, repository);
        await tester.tap(find.text('Edit property'));
        await tester.pumpAndSettle();
        final dialogScroll = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Payment Frequency'),
          240,
          scrollable: dialogScroll,
        );
        final annual = find.widgetWithText(TextFormField, 'Annual Rent (AED)');
        expect(
          tester.widget<TextFormField>(annual).controller!.text,
          '20000.0',
        );
        await _selectRentalFrequency(tester, 'Monthly');
        final monthly = find.widgetWithText(
          TextFormField,
          'Monthly Rent (AED)',
        );
        expect(tester.widget<TextFormField>(monthly).controller!.text, isEmpty);
        await Scrollable.ensureVisible(tester.element(monthly), alignment: .5);
        await tester.pumpAndSettle();
        await tester.enterText(monthly, '1234.50');
        await _selectRentalFrequency(tester, 'Annual');
        expect(
          tester.widget<TextFormField>(annual).controller!.text,
          '20000.0',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Save property'));
        await tester.pumpAndSettle();
        expect(repository.saveInputs, hasLength(1));
        final saved = repository.saveInputs.single;
        expect(saved.location, isEmpty);
        expect(saved.contractNumber, isEmpty);
        expect(saved.tenantName, isEmpty);
        expect(saved.leaseStart, isNull);
        expect(saved.leaseEnd, isNull);
        expect(saved.billingStart, isNull);
        expect(saved.occupancy, YorksV1RentalOccupancy.unknown);
        expect(saved.annualRent, 20000);
        expect(saved.monthlyRent, isNull);
        expect(saved.toRpcPayload()['payment_frequency'], 'annual');
        expect(
          saved.sourceMetadata,
          _sourceRentalDetail.property.sourceMetadata,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'rental import workbook blockers remain visible — ${evidence.size}',
      (tester) async {
        await _setViewport(tester, evidence.size);
        final repository = _RentalFixtureRepository();
        await _openRentalImport(
          tester,
          repository,
          _workbook({
            'Sheet1': const [
              ['Lease contracts tracker'],
            ],
          }),
        );
        expect(find.text('Workbook issues'), findsOneWidget);
        expect(find.textContaining('Required worksheet'), findsNWidgets(3));
        expect(
          find.textContaining('Required worksheet “Rental Properties”'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Required worksheet “Payment History”'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Required worksheet “Cheque Register”'),
          findsOneWidget,
        );
        final confirm = find.widgetWithText(
          PrimaryButton,
          'Confirm Import (0)',
        );
        expect(tester.widget<PrimaryButton>(confirm).onPressed, isNull);
        expect(repository.importCalls, isEmpty);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/r38_4/rental_import_blocked_${evidence.suffix}.png',
          ),
        );
      },
    );

    testWidgets('R38.4 rental register — ${evidence.size}', (tester) async {
      await _setViewport(tester, evidence.size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1RentalRepositoryProvider.overrideWithValue(
              _RentalFixtureRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1RentalDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rental Properties'), findsWidgets);
      expect(find.text('Property & Rent Register'), findsOneWidget);
      expect(find.text('Mussafah Shop 04'), findsOneWidget);
      expect(find.text('AED 14,000.00'), findsWidgets);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r38_4/rental_register_${evidence.suffix}.png',
        ),
      );
    });

    testWidgets('R38.4 property register — ${evidence.size}', (tester) async {
      await _setViewport(tester, evidence.size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1RentalRepositoryProvider.overrideWithValue(
              _RentalFixtureRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1RentalDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (evidence.size.width < 720) {
        await tester.tap(
          find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Property register'));
      await tester.pumpAndSettle();

      expect(find.text('Property & Rent Register'), findsOneWidget);
      expect(find.textContaining('RU-004'), findsWidgets);
      expect(find.text('AED 14,000.00'), findsWidgets);
      if (evidence.size.width >= 1040) {
        expect(find.textContaining('TC-RU-004-2026'), findsOneWidget);
        expect(find.text('NEXT CDC / PDC'), findsOneWidget);
        expect(find.text('LEASE'), findsOneWidget);
      } else {
        expect(find.textContaining('Mussafah M-37'), findsOneWidget);
        expect(find.text('OUTSTANDING'), findsWidgets);
        expect(find.text('LEASE END'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r38_4/rental_property_register_${evidence.suffix}.png',
        ),
      );
    });

    testWidgets('R38.4 rental property detail — ${evidence.size}', (
      tester,
    ) async {
      await _setViewport(tester, evidence.size);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1RentalRepositoryProvider.overrideWithValue(
              _RentalFixtureRepository(),
            ),
            yorksV1RentalDocumentsRepositoryProvider.overrideWithValue(
              const _RentalFixtureDocumentsRepository(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            home: const YorksV1RentalPropertyScreen(propertyId: 'property-4'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mussafah Shop 04'), findsOneWidget);
      expect(find.text('Current Rent Position'), findsOneWidget);
      expect(find.text('Tenant & Lease'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/r38_4/rental_detail_${evidence.suffix}.png'),
      );
    });
  }

  testWidgets(
    'empty rental home explains the first step without a false ratio',
    (tester) async {
      await _setViewport(tester, const Size(360, 800));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            yorksV1RentalPortfolioProvider.overrideWith(
              (ref) async => YorksV1RentalPortfolio.fromJson({
                'summary': <String, dynamic>{},
                'properties': [],
                'recent_payments': [],
                'cheques': [],
              }),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const YorksV1RentalDashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add your first rental property'), findsOneWidget);
      expect(find.text('0%'), findsNothing);
      expect(find.text('Add property'), findsOneWidget);
      await tester.tap(find.byTooltip('Import Excel'));
      await tester.pumpAndSettle();
      expect(find.text('Download import format'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1200, 900), const Size(360, 800)]) {
    testWidgets('property editor fits $size with optional sections', (
      tester,
    ) async {
      await _openRentalEditor(tester, _RentalFixtureRepository(), size: size);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('Create property').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'goldens/r38_4/rental_editor_${size.width.toInt()}.png',
        ),
      );
    });
  }

  testWidgets(
    'failed property save keeps values and corrected payload gets a new key',
    (tester) async {
      final repo = _RentalFixtureRepository()
        ..saveFailure = const YorksV1DomainException(
          YorksV1DomainErrorCode.invalidInput,
        );
      await _openRentalEditor(tester, repo);
      await tester.tap(find.text('Create property'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The property was not saved.'),
        findsOneWidget,
      );
      expect(find.text('Shop trial'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      final firstKey = repo.saveKeys.single;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Property Name'),
        'Shop corrected',
      );
      repo.saveFailure = null;
      await tester.tap(find.text('Create property'));
      await tester.pumpAndSettle();
      expect(repo.saveKeys, hasLength(2));
      expect(repo.saveKeys.last, isNot(firstKey));
      expect(repo.saveInputs.last.propertyName, 'Shop corrected');
      expect(find.text('Confirmed property'), findsOneWidget);
    },
  );

  testWidgets(
    'uncertain property save retries the exact command and blocks double submission',
    (tester) async {
      final repo = _RentalFixtureRepository()
        ..pendingSave = Completer<String>();
      await _openRentalEditor(tester, repo);
      await tester.tap(find.text('Create property'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      await tester.tap(find.text('Saving…'));
      await tester.pump();
      expect(repo.saveKeys, hasLength(1));
      repo.pendingSave!.completeError(
        const YorksV1DomainException(YorksV1DomainErrorCode.backendUnavailable),
      );
      await tester.pumpAndSettle();
      expect(find.text('Shop trial'), findsOneWidget);
      expect(find.text('Confirm save'), findsOneWidget);
      repo.pendingSave = null;
      await tester.tap(find.text('Confirm save'));
      await tester.pumpAndSettle();
      expect(repo.saveKeys, hasLength(2));
      expect(repo.saveKeys.first, repo.saveKeys.last);
      expect(
        repo.saveInputs.first.toRpcPayload(),
        repo.saveInputs.last.toRpcPayload(),
      );
      expect(find.text('Confirmed property'), findsOneWidget);
    },
  );

  test(
    'confirmed property command does not depend on a follow-up read',
    () async {
      final rpc = _RentalSaveRpc();
      final connectivity = DefaultConnectivity();
      addTearDown(connectivity.dispose);
      final repo = YorksV1SupabaseRentalRepository(
        featureFlags: const YorksV1FeatureFlags(foundation: true),
        connectivity: connectivity,
        rpcClient: rpc,
      );
      final id = await repo.saveProperty(
        _rentalSaveInput,
        expectedVersion: null,
        idempotencyKey: 'same-command',
      );
      expect(id, 'confirmed-property');
      expect(rpc.calls, ['v1_save_rental_property']);
    },
  );

  testWidgets('lease documents use the controlled Yorks document workspace', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 768));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          yorksV1RentalRepositoryProvider.overrideWithValue(
            _RentalFixtureRepository(),
          ),
          yorksV1RentalDocumentsRepositoryProvider.overrideWithValue(
            const _RentalFixtureDocumentsRepository(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: const YorksV1RentalPropertyScreen(propertyId: 'property-4'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Documents'));
    await tester.pumpAndSettle();

    expect(find.text('Lease Documents'), findsOneWidget);
    expect(find.text('No lease documents attached'), findsOneWidget);
    expect(find.text('Controlled document boundary'), findsOneWidget);
    expect(find.textContaining('Private, versioned'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

List<String> _rentalTrackerValues(Map<String, String> values) {
  final headers = [
    ...YorksV1RentalWorkbookCodec.trackerHeaders,
    ...YorksV1RentalWorkbookCodec.trackerOptionalHeaders,
  ];
  return [for (final header in headers) values[header] ?? ''];
}

YorksV1RentalImportPreview _previewRentalTracker(
  List<List<String>> rows, {
  YorksV1RentalPortfolio? portfolio,
}) => const YorksV1RentalWorkbookCodec().preview(
  selected: YorksV1RentalSelectedWorkbook(
    fileName: 'tracker.xlsx',
    bytes: _workbook({
      'Sheet1': [
        ['YORKS PROPERTIES — Lease Contracts Tracker'],
        [],
        [
          ...YorksV1RentalWorkbookCodec.trackerHeaders,
          ...YorksV1RentalWorkbookCodec.trackerOptionalHeaders,
        ],
        ...rows,
      ],
    }),
  ),
  portfolio: portfolio ?? rentalPortfolioFixture,
);

List<String> _rentalPropertyValues(Map<String, String> overrides) {
  final row = _propertyRow(action: 'Create', unitCode: 'NEW-1');
  for (final entry in overrides.entries) {
    row[YorksV1RentalWorkbookCodec.propertyHeaders.indexOf(entry.key)] =
        entry.value;
  }
  return row;
}

YorksV1RentalImportPreview _previewRentalProperties(
  List<List<String>> rows, {
  List<String> headers = YorksV1RentalWorkbookCodec.propertyHeaders,
}) => const YorksV1RentalWorkbookCodec().preview(
  selected: YorksV1RentalSelectedWorkbook(
    fileName: 'rentals.xlsx',
    bytes: _workbook({
      YorksV1RentalWorkbookCodec.propertySheet: [headers, ...rows],
      YorksV1RentalWorkbookCodec.paymentSheet: [
        YorksV1RentalWorkbookCodec.paymentHeaders,
      ],
      YorksV1RentalWorkbookCodec.chequeSheet: [
        YorksV1RentalWorkbookCodec.chequeHeaders,
      ],
    }),
  ),
  portfolio: rentalPortfolioFixture,
);

Future<void> _openRentalImport(
  WidgetTester tester,
  _RentalFixtureRepository repository,
  Uint8List bytes,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        yorksV1RentalRepositoryProvider.overrideWithValue(repository),
        yorksV1RentalWorkbookFileServiceProvider.overrideWithValue(
          _RentalImportFixtureFileService(bytes),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const YorksV1RentalDashboardScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Import Excel'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Import Excel'));
  await tester.pumpAndSettle();
}

class _RentalImportFixtureFileService
    implements YorksV1RentalWorkbookFileService {
  const _RentalImportFixtureFileService(this.bytes);
  final Uint8List bytes;

  @override
  Future<YorksV1RentalSelectedWorkbook?> selectWorkbook() async =>
      YorksV1RentalSelectedWorkbook(fileName: 'tracker.xlsx', bytes: bytes);

  @override
  Future<bool> saveImportTemplate() async => false;

  @override
  Future<bool> saveExport({
    required Uint8List bytes,
    required String suggestedName,
  }) async => false;
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _selectRentalFrequency(WidgetTester tester, String value) async {
  final field = find.widgetWithText(
    DropdownButtonFormField<String>,
    'Payment Frequency',
  );
  final scrollable = find
      .descendant(of: find.byType(Dialog), matching: find.byType(Scrollable))
      .first;
  await tester.scrollUntilVisible(field, 160, scrollable: scrollable);
  await Scrollable.ensureVisible(tester.element(field), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> _openSourceRentalDetail(
  WidgetTester tester,
  _SourceRentalFixtureRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        yorksV1RentalRepositoryProvider.overrideWithValue(repository),
        yorksV1RentalDocumentsRepositoryProvider.overrideWithValue(
          const _RentalFixtureDocumentsRepository(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const YorksV1RentalPropertyScreen(propertyId: 'fixture-21'),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

YorksV1BoqWorkbookSheet _sheet(
  YorksV1BoqParsedWorkbook workbook,
  String name,
) => workbook.sheets.singleWhere((sheet) => sheet.name == name);

List<String> _propertyRow({required String action, required String unitCode}) {
  return [
    action,
    unitCode,
    unitCode == 'RU-004' ? 'Mussafah Shop 04' : 'Mussafah Shop 05',
    'Shop',
    unitCode == 'RU-004' ? 'M37-S04' : 'M37-S05',
    'Mussafah M-37',
    'Vacant',
    '',
    '',
    '',
    '',
    'TC-$unitCode-2026',
    'Tenancy Contract',
    'Draft',
    '',
    '',
    '',
    '14000',
    '1',
    '5',
    '0',
    'Bank Transfer',
    'Monthly',
    '12',
    '5',
    '90',
    '',
  ];
}

Uint8List _workbook(Map<String, List<List<String>>> sheets) {
  final names = sheets.keys.toList();
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('[Content_Types].xml', _contentTypes(names.length)),
    )
    ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
    ..addFile(ArchiveFile.string('xl/workbook.xml', _workbookXml(names)))
    ..addFile(
      ArchiveFile.string(
        'xl/_rels/workbook.xml.rels',
        _workbookRelationships(names.length),
      ),
    );
  for (var index = 0; index < names.length; index++) {
    archive.addFile(
      ArchiveFile.string(
        'xl/worksheets/sheet${index + 1}.xml',
        _sheetXml(sheets[names[index]]!),
      ),
    );
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _sheetXml(List<List<String>> rows) {
  final out = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>',
  );
  for (var row = 0; row < rows.length; row++) {
    out.write('<row r="${row + 1}">');
    for (var column = 0; column < rows[row].length; column++) {
      out.write(
        '<c r="${_column(column)}${row + 1}" t="inlineStr"><is><t xml:space="preserve">${_xml(rows[row][column])}</t></is></c>',
      );
    }
    out.write('</row>');
  }
  out.write('</sheetData></worksheet>');
  return out.toString();
}

String _contentTypes(int count) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${[for (var index = 1; index <= count; index++) '<Override PartName="/xl/worksheets/sheet$index.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}</Types>';

const _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>';

String _workbookXml(List<String> names) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${[for (var index = 0; index < names.length; index++) '<sheet name="${_xml(names[index])}" sheetId="${index + 1}" r:id="rId${index + 1}"/>'].join()}</sheets></workbook>';

String _workbookRelationships(int count) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${[for (var index = 1; index <= count; index++) '<Relationship Id="rId$index" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$index.xml"/>'].join()}</Relationships>';

String _column(int index) {
  var value = index + 1;
  var result = '';
  while (value > 0) {
    value--;
    result = String.fromCharCode(65 + value % 26) + result;
    value ~/= 26;
  }
  return result;
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

final rentalPortfolioFixture = YorksV1RentalPortfolio.fromJson({
  'as_of': '2026-08-11T08:31:00Z',
  'summary': {
    'total_properties': 2,
    'occupied': 1,
    'monthly_rent_roll': 22000,
    'collected_this_month': 8000,
    'outstanding': 14000,
    'security_deposits': 16000,
    'expiring_within_90': 1,
    'cheque_attention': 1,
  },
  'properties': [
    {
      'id': 'property-4',
      'unit_code': 'RU-004',
      'property_name': 'Mussafah Shop 04',
      'property_type': 'Shop',
      'municipality_number': 'M37-S04',
      'location': 'Mussafah M-37',
      'occupancy_state': 'vacant',
      'is_archived': false,
      'record_version': 3,
      'contract_number': 'TC-RU-004-2026',
      'contract_type': 'Tenancy Contract',
      'contract_status': 'Draft',
      'monthly_rent': 14000,
      'security_deposit': 0,
      'monthly_due_day': 1,
      'grace_period_days': 5,
      'default_payment_method': 'Bank Transfer',
      'annual_escalation_percent': 5,
      'renewal_notice_days': 90,
      'current_due': 14000,
      'current_paid': 0,
      'outstanding': 14000,
    },
    {
      'id': 'property-1',
      'unit_code': 'RU-001',
      'property_name': 'Al Dhafra Shop 12',
      'property_type': 'Shop',
      'municipality_number': 'AD-887-321',
      'location': 'Al Dhafra, Abu Dhabi',
      'occupancy_state': 'occupied',
      'is_archived': false,
      'record_version': 5,
      'lease_id': 'lease-1',
      'tenant_name': 'Gulf Air Ducts Co.',
      'contract_number': 'CTR-2026-001',
      'contract_type': 'Lease',
      'contract_status': 'Active',
      'lease_start': '2026-01-01',
      'lease_end': '2026-12-31',
      'monthly_rent': 8000,
      'security_deposit': 16000,
      'monthly_due_day': 5,
      'grace_period_days': 5,
      'default_payment_method': 'PDC',
      'annual_escalation_percent': 5,
      'renewal_notice_days': 60,
      'current_due': 8000,
      'current_paid': 8000,
      'outstanding': 0,
      'next_cheque_date': '2026-09-05',
      'next_cheque_number': 'PDC-009',
    },
  ],
  'recent_payments': [
    {
      'id': 'receipt-1',
      'property_id': 'property-1',
      'period_id': 'period-1',
      'period_month': '2026-08-01',
      'amount_received': 8000,
      'payment_date': '2026-08-05',
      'payment_method': 'PDC',
      'reference': 'PDC-008',
      'unit_code': 'RU-001',
      'property_name': 'Al Dhafra Shop 12',
    },
  ],
  'cheques': [
    {
      'id': 'cheque-1',
      'property_id': 'property-1',
      'lease_id': 'lease-1',
      'period_id': 'period-1',
      'cheque_number': 'PDC-009',
      'cheque_type': 'PDC',
      'bank_name': 'ADCB',
      'cheque_date': '2026-09-05',
      'amount': 8000,
      'status': 'received',
      'record_version': 1,
      'unit_code': 'RU-001',
      'property_name': 'Al Dhafra Shop 12',
      'tenant_name': 'Gulf Air Ducts Co.',
    },
  ],
});

final rentalPropertyDetailFixture = YorksV1RentalPropertyDetail.fromJson({
  'property': {
    'id': 'property-4',
    'unit_code': 'RU-004',
    'property_name': 'Mussafah Shop 04',
    'property_type': 'Shop',
    'municipality_number': 'M37-S04',
    'location': 'Mussafah M-37',
    'occupancy_state': 'vacant',
    'is_archived': false,
    'record_version': 3,
    'updated_at': '2026-08-11T08:31:00Z',
  },
  'lease': {
    'id': 'lease-4',
    'contract_number': 'TC-RU-004-2026',
    'contract_type': 'Tenancy Contract',
    'contract_status': 'Draft',
    'monthly_rent': 14000,
    'security_deposit': 0,
    'monthly_due_day': 1,
    'grace_period_days': 5,
    'default_payment_method': 'Bank Transfer',
    'payment_frequency': 'Monthly',
    'contract_cheque_count': 12,
    'annual_escalation_percent': 5,
    'renewal_notice_days': 90,
  },
  'periods': [
    {
      'id': 'period-4',
      'period_month': '2026-08-01',
      'due_date': '2026-08-01',
      'amount_due': 14000,
      'amount_paid': 0,
      'balance': 14000,
      'status': 'due',
    },
  ],
  'receipts': [],
  'cheques': [],
  'activity': [
    {
      'id': 'activity-4',
      'event_type': 'rental_property_created',
      'actor_role': 'admin',
      'actor_name': 'Faisal Ahmed',
      'occurred_at': '2026-08-11T08:31:00Z',
    },
  ],
});

class _RentalFixtureRepository implements YorksV1RentalRepository {
  final importCalls = <Map<String, Object?>>[];
  final saveKeys = <String>[];
  final saveInputs = <YorksV1RentalPropertyInput>[];
  Object? saveFailure;
  Completer<String>? pendingSave;

  @override
  Future<YorksV1RentalPortfolio> getPortfolio() async => rentalPortfolioFixture;

  @override
  Future<YorksV1RentalPropertyDetail> getProperty(String propertyId) async =>
      rentalPropertyDetailFixture;

  @override
  Future<String> saveProperty(
    YorksV1RentalPropertyInput input, {
    required int? expectedVersion,
    required String idempotencyKey,
  }) async {
    saveKeys.add(idempotencyKey);
    saveInputs.add(input);
    if (saveFailure != null) throw saveFailure!;
    if (pendingSave != null) return pendingSave!.future;
    return rentalPropertyDetailFixture.property.id;
  }

  @override
  Future<void> recordPayment({
    required String periodId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    required String? reference,
    required String? note,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> saveCheque({
    required Map<String, Object?> payload,
    required int? expectedVersion,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> transitionCheque({
    required String chequeId,
    required int expectedVersion,
    required YorksV1RentalChequeStatus nextStatus,
    required String? reason,
    required String idempotencyKey,
  }) async {}

  @override
  Future<void> archiveProperty({
    required String propertyId,
    required int expectedVersion,
    required String reason,
    required String idempotencyKey,
  }) async {}

  @override
  Future<Map<String, dynamic>> getExportData() async => const {};

  @override
  Future<void> importWorkbook({
    required Map<String, Object?> payload,
    required String idempotencyKey,
  }) async {
    importCalls.add({...payload, 'idempotency_key': idempotencyKey});
  }
}

class _RetryRentalFixtureRepository extends _RentalFixtureRepository {
  final paymentKeys = <String>[];
  final committedPaymentKeys = <String>{};
  bool loseNextResponse = false;
  Completer<void>? pendingPayment;

  @override
  Future<void> recordPayment({
    required String periodId,
    required double amount,
    required DateTime paymentDate,
    required String paymentMethod,
    required String? reference,
    required String? note,
    required String idempotencyKey,
  }) async {
    paymentKeys.add(idempotencyKey);
    if (pendingPayment != null) await pendingPayment!.future;
    committedPaymentKeys.add(idempotencyKey);
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const YorksV1DomainException(
        YorksV1DomainErrorCode.backendUnavailable,
      );
    }
  }
}

class _SourceRentalFixtureRepository extends _RentalFixtureRepository {
  @override
  Future<YorksV1RentalPortfolio> getPortfolio() async => _sourceRentalPortfolio;

  @override
  Future<YorksV1RentalPropertyDetail> getProperty(String propertyId) async =>
      _sourceRentalDetail;
}

const _sourceAnnualRents = <int, double>{
  4: 27825,
  5: 30000,
  6: 25000,
  7: 39375,
  8: 45938,
  9: 28350,
  10: 6825,
  14: 50000,
  15: 84000,
  16: 91350,
  19: 5000,
  20: 12600,
  21: 20000,
  22: 13125,
  23: 7350,
  24: 15750,
  25: 7350,
  26: 10500,
  27: 9450,
  28: 9450,
  29: 29400,
  30: 4725,
  31: 7875,
  32: 7875,
  33: 5250,
  34: 6300,
  35: 5250,
  36: 3000,
  39: 11550,
  40: 11550,
  42: 11550,
  46: 5500,
  47: 5500,
  48: 7875,
  49: 7875,
  50: 7875,
  51: 7350,
  52: 14700,
  55: 10000,
};

const _sourceUnitCodes = [
  'SHOP-1',
  'SHOP-2',
  'SHOP-3',
  'SHOP-4',
  'SHOP-5',
  'SHOP-6',
  'SHOP-7',
  'STORE-1',
  'STORE-2',
  'STORE-3',
  'STORE-4',
  'STORE-5',
  'STORE-6',
  'SOURCE-17',
  'OFFICE-F-4-1',
  'OFFICE-F-4-2',
  'OFFICE-F-4-3',
  'OFFICE-F-4-4',
  'OFFICE-F-4-5',
  'OFFICE-F-4-6',
  'OFFICE-F-4-7',
  'OFFICE-F-5-1',
  'OFFICE-F-5-2',
  'OFFICE-F-5-3',
  'OFFICE-F-5-4',
  'OFFICE-F-5-5',
  'OFFICE-F-5-6',
  'OFFICE-F-5-7',
  'OFFICE-F-5-8',
  'OFFICE-F-5-9',
  'OFFICE-F-5-10',
  'OFFICE-F-5-11',
  'UNIT-AC1-1',
  'OFFICE-AC1-2',
  'OFFICE-AC1-3',
  'OFFICE-AC1-4',
  'OFFICE-AC1-5',
  'OFFICE-AC1-6',
  'OFFICE-AC1-7',
  'OFFICE-AC1-8',
  'OFFICE-AC1-9',
  'OFFICE-AC2-1',
  'OFFICE-AC2-2',
  'OFFICE-AC2-3',
  'OFFICE-AC2-4',
  'OFFICE-AC2-5',
  'OFFICE-AC2-6',
  'OFFICE-AC2-7',
  'OFFICE-AC2-8',
  'OFFICE-AC2-9',
  'OFFICE-AC2-10',
  'OFFICE-AC2-11',
];

Map<String, dynamic> _sourcePropertyJson(int row) {
  final code = _sourceUnitCodes[row - 4];
  final type = row <= 10
      ? 'shop'
      : row <= 16
      ? 'store'
      : row == 17
      ? 'office_store'
      : row == 36
      ? 'other'
      : 'office';
  final occupancy = {37, 44}.contains(row)
      ? 'unknown'
      : {38, 41, 43, 45}.contains(row)
      ? 'vacant'
      : 'occupied';
  final undated = {
    11,
    12,
    13,
    18,
    37,
    38,
    41,
    43,
    44,
    45,
    53,
    54,
  }.contains(row);
  final rent = _sourceAnnualRents[row];
  final sourceValues = <String, Object?>{
    for (final header in YorksV1RentalWorkbookCodec.trackerHeaders)
      header: null,
    'Unit No': row == 17 ? null : code,
    'Unit Type': row == 36 ? null : type,
    'Tenant / Company': {37, 45}.contains(row) ? null : 'Example tenant $row',
    'Contract Start': undated ? null : '2026-01-01',
    'Contract End': undated ? null : '2026-12-31',
    'Annual Rent (AED)': rent,
    'Status': occupancy == 'unknown'
        ? null
        : occupancy == 'vacant'
        ? 'Empty'
        : 'Active',
    'Security Cheque (AED)': {21, 29}.contains(row)
        ? '4 YEARS'
        : row == 30
        ? '6 Months'
        : row == 55
        ? 'NO'
        : null,
  };
  return {
    'id': 'fixture-$row',
    'lease_id': 'fixture-lease-$row',
    'unit_code': code,
    'property_name': code.replaceAll('-', ' '),
    'property_type': type,
    'location': null,
    'occupancy_state': occupancy,
    'is_archived': false,
    'record_version': 1,
    'tenant_name': sourceValues['Tenant / Company'],
    'contract_number': null,
    'contract_type': 'tenancy_contract',
    'contract_status': 'active',
    'lease_start': sourceValues['Contract Start'],
    'lease_end': sourceValues['Contract End'],
    'annual_rent': rent,
    'monthly_rent': null,
    'payment_frequency': 'annual',
    'security_deposit': 0,
    'monthly_due_day': 1,
    'renewal_notice_days': 90,
    'billing_start': null,
    'billing_setup_pending': true,
    'outstanding': 0,
    'current_paid': 0,
    'current_due': 0,
    'days_to_lease_end': undated ? null : 72,
    'missing_fields': [
      'location',
      'contract_number',
      'billing_start',
      if (undated) ...['lease_start', 'lease_end'],
      if (rent == null) 'rent_amount',
      if (occupancy == 'unknown') 'occupancy',
      if (row == 17) 'source_unit_number',
      if (row == 36) 'source_property_type',
    ],
    'source_metadata': {
      'format': 'yorks_properties_tracker_v1',
      'source_format': 'yorks_properties_tracker_v1',
      'source_file': 'anonymized-tracker.xlsx',
      'source_sheet': 'Sheet1',
      'source_row': row,
      'source_unit_number': sourceValues['Unit No'],
      'source_unit_type': sourceValues['Unit Type'],
      'original_values': sourceValues,
    },
  };
}

final _sourceRentalPortfolio = YorksV1RentalPortfolio.fromJson({
  'as_of': '2026-10-20T12:00:00Z',
  'summary': {
    'total_properties': 52,
    'occupied': 46,
    'annual_rent_roll': _sourceAnnualRents.values.fold<double>(
      0,
      (sum, rent) => sum + rent,
    ),
    'monthly_rent_roll': 0,
    'collected_this_month': 0,
    'outstanding': 0,
    'security_deposits': 0,
    'expiring_within_90': 19,
    'cheque_attention': 0,
  },
  'properties': [for (var row = 4; row <= 55; row++) _sourcePropertyJson(row)],
  'recent_payments': [],
  'cheques': [],
});

final _sourceRentalDetail = YorksV1RentalPropertyDetail.fromJson({
  'property': {
    ..._sourcePropertyJson(21),
    'occupancy_state': 'unknown',
    'missing_fields': [
      'location',
      'contract_number',
      'tenant_name',
      'occupancy',
      'lease_start',
      'lease_end',
      'billing_start',
    ],
  },
  'lease': {
    'id': 'fixture-lease-21',
    'tenant_name': null,
    'contract_number': null,
    'contract_type': 'tenancy_contract',
    'contract_status': 'active',
    'lease_start': null,
    'lease_end': null,
    'annual_rent': 20000,
    'monthly_rent': null,
    'payment_frequency': 'annual',
    'billing_start': null,
    'notes': 'Source Security Cheque (AED): 4 YEARS',
  },
  'periods': [],
  'receipts': [],
  'cheques': [],
  'activity': [],
});

class _RentalFixtureDocumentsRepository
    implements YorksV1RentalDocumentsRepository {
  const _RentalFixtureDocumentsRepository();

  @override
  Future<YorksV1DocumentWorkspace> getRentalWorkspace(String propertyId) async {
    return YorksV1DocumentWorkspace(
      projectId: propertyId,
      documents: const [],
      auditEntries: const [],
    );
  }

  @override
  Future<YorksV1DocumentWorkspace> uploadRental(
    YorksV1DocumentUploadInput input,
  ) => getRentalWorkspace(input.projectId);

  @override
  Future<Uint8List> downloadDocument({
    required String bucketId,
    required String objectPath,
  }) async => Uint8List(0);
}

Future<void> _openRentalEditor(
  WidgetTester tester,
  _RentalFixtureRepository repository, {
  Size size = const Size(1200, 900),
}) async {
  await _setViewport(tester, size);
  final router = GoRouter(
    initialLocation: '/rentals',
    routes: [
      GoRoute(
        path: '/rentals',
        builder: (_, _) => const YorksV1RentalDashboardScreen(),
      ),
      GoRoute(
        path: '/rentals/:id',
        builder: (_, _) => const Scaffold(body: Text('Confirmed property')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        yorksV1RentalRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add property'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Unit Code'),
    'TRIAL-1',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Property Name'),
    'Shop trial',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Location'),
    'Abu Dhabi',
  );
}

const _rentalSaveInput = YorksV1RentalPropertyInput(
  unitCode: 'TRIAL-1',
  propertyName: 'Shop trial',
  propertyType: 'Shop',
  location: 'Abu Dhabi',
  occupancy: YorksV1RentalOccupancy.vacant,
  contractNumber: '',
  contractType: 'Tenancy Contract',
  contractStatus: 'Draft',
  monthlyRent: 0,
  securityDeposit: 0,
  monthlyDueDay: 1,
  gracePeriodDays: 0,
  defaultPaymentMethod: 'PDC',
  paymentFrequency: 'Monthly',
  contractCheques: 0,
  annualEscalationPercent: 0,
  renewalNoticeDays: 90,
);

class _RentalSaveRpc implements YorksV1MaterialRequestRpcClient {
  final calls = <String>[];
  @override
  Future<Object?> invoke({
    required String functionName,
    required Map<String, Object?> parameters,
  }) async {
    calls.add(functionName);
    if (functionName != 'v1_save_rental_property') {
      throw StateError('Detail read unavailable');
    }
    return {'property_id': 'confirmed-property'};
  }
}
