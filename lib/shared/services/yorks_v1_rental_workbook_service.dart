import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/yorks_v1_boq_workbook.dart';
import '../models/yorks_v1_domain_error.dart';
import '../models/yorks_v1_rental.dart';
import '../models/yorks_v1_rental_workbook.dart';
import 'yorks_v1_boq_workbook_service.dart';

abstract interface class YorksV1RentalWorkbookFileService {
  Future<YorksV1RentalSelectedWorkbook?> selectWorkbook();

  Future<bool> saveImportTemplate();

  Future<bool> saveExport({
    required Uint8List bytes,
    required String suggestedName,
  });
}

class YorksV1PlatformRentalWorkbookFileService
    implements YorksV1RentalWorkbookFileService {
  const YorksV1PlatformRentalWorkbookFileService();

  static const _mime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  static const _type = XTypeGroup(
    label: 'Excel workbook',
    extensions: ['xlsx'],
    mimeTypes: [_mime],
  );

  @override
  Future<YorksV1RentalSelectedWorkbook?> selectWorkbook() async {
    final file = await openFile(acceptedTypeGroups: const [_type]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (!file.name.toLowerCase().endsWith('.xlsx') ||
        bytes.isEmpty ||
        bytes.lengthInBytes > 15 * 1024 * 1024) {
      throw const YorksV1DomainException(YorksV1DomainErrorCode.invalidInput);
    }
    return YorksV1RentalSelectedWorkbook(
      fileName: _fileName(file.name),
      bytes: bytes,
    );
  }

  @override
  Future<bool> saveImportTemplate() => saveExport(
    bytes: const YorksV1RentalWorkbookCodec().buildImportTemplate(),
    suggestedName: 'Yorks_Rental_Properties_Import_Template.xlsx',
  );

  @override
  Future<bool> saveExport({
    required Uint8List bytes,
    required String suggestedName,
  }) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [_type],
    );
    if (location == null) return false;
    await XFile.fromData(
      bytes,
      name: suggestedName,
      mimeType: _mime,
    ).saveTo(location.path);
    return true;
  }

  static String _fileName(String value) {
    final normalized = value.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}

class YorksV1RentalWorkbookCodec {
  const YorksV1RentalWorkbookCodec();

  static const _uuid = Uuid();
  static const propertySheet = 'Rental Properties';
  static const paymentSheet = 'Payment History';
  static const chequeSheet = 'Cheque Register';
  static const instructionsSheet = 'Instructions';
  static const listsSheet = 'Lists';

  static const trackerHeaders = [
    'Unit No',
    'Unit Type',
    'Tenant / Company',
    'Contract Start',
    'Contract End',
    'Annual Rent (AED)',
    'Status',
    'Security Cheque (AED)',
    'Contact',
    'Days to Expiry',
    'Expiry Flag',
  ];
  static const trackerOptionalHeaders = [
    'Rent Frequency',
    'Monthly Rent (AED)',
    'Location',
    'Contract No.',
    'Unit Code',
    'Billing Start',
    'Monthly Due Day',
    'Import Action',
  ];

  static const propertyHeaders = [
    'Import Action *',
    'Unit Code *',
    'Property Name *',
    'Property Type *',
    'Property / Municipality No.',
    'Location *',
    'Occupancy *',
    'Tenant / Company Name',
    'Tenant Contact',
    'Tenant Email',
    'Trade Licence No.',
    'Contract No.',
    'Contract Type',
    'Contract Status',
    'Contract Signed Date',
    'Lease Start',
    'Lease End',
    'Monthly Rent AED',
    'Monthly Due Day',
    'Grace Period Days',
    'Security Deposit AED',
    'Default Payment Method',
    'Payment Frequency',
    'No. of Contract Cheques',
    'Annual Escalation %',
    'Renewal Notice Days',
    'Notes',
  ];
  static const paymentHeaders = [
    'Unit Code *',
    'Rent Period *',
    'Amount Received AED *',
    'Payment Date *',
    'Payment Method *',
    'Receipt / Bank / Cheque Reference',
    'Payment Note',
  ];
  static const chequeHeaders = [
    'Unit Code *',
    'Cheque Type *',
    'Cheque Number *',
    'Bank *',
    'Linked Rent Period *',
    'Cheque Date *',
    'Amount AED *',
    'Status *',
    'Note',
  ];

  YorksV1RentalImportPreview preview({
    required YorksV1RentalSelectedWorkbook selected,
    required YorksV1RentalPortfolio portfolio,
  }) {
    final workbook = const YorksV1BoqWorkbookCodec().decode(
      bytes: selected.bytes,
      fileName: selected.fileName,
    );
    final issues = <YorksV1RentalImportIssue>[];
    final tracker = _trackerSheet(workbook);
    final properties = tracker == null
        ? _propertyRows(
            _sheet(workbook, propertySheet, issues),
            portfolio,
            issues,
          )
        : _trackerRows(
            tracker.sheet,
            tracker.headerIndex,
            selected.fileName,
            portfolio,
            issues,
          );
    final knownCodes = <String>{
      for (final property in portfolio.properties)
        property.unitCode.trim().toUpperCase(),
      for (final row in properties)
        if (!row.hasError) row.payload['unit_code']!.toString(),
    };
    final payments = _paymentRows(
      tracker == null
          ? _sheet(workbook, paymentSheet, issues)
          : _optionalSheet(workbook, paymentSheet),
      knownCodes,
      issues,
    );
    final cheques = _chequeRows(
      tracker == null
          ? _sheet(workbook, chequeSheet, issues)
          : _optionalSheet(workbook, chequeSheet),
      knownCodes,
      issues,
    );
    return YorksV1RentalImportPreview(
      fileName: selected.fileName,
      commandId: _uuid.v4(),
      properties: properties,
      payments: payments,
      cheques: cheques,
      issues: issues,
    );
  }

  Uint8List buildImportTemplate() => _WorkbookWriter.encode({
    instructionsSheet: [
      ['Yorks Rental Properties Import'],
      [
        'Preview and resolve every ERROR before Confirm Import. Nothing changes during preview.',
      ],
      [
        'The property tracker starts at row 3. Annual Rent stays annual. Choose Monthly only when entering Monthly Rent, and leave Annual Rent blank.',
      ],
      [
        'Missing details remain editable after import. Billing Start must be explicitly entered to generate rent periods; it is never inferred from Contract Start.',
      ],
      [
        'Security Cheque is retained as source information, not a cash deposit or cleared payment. Optional Payment History and Cheque Register sheets require actual transaction evidence.',
      ],
      [
        'Existing Unit Codes require an explicit Update in Import Action. Blank optional details do not clear completed fields, and original imported source evidence remains unchanged.',
      ],
    ],
    propertySheet: [
      ['YORKS PROPERTIES — Lease Contracts Tracker'],
      <String>[],
      [...trackerHeaders, ...trackerOptionalHeaders],
    ],
    paymentSheet: [paymentHeaders],
    chequeSheet: [chequeHeaders],
    listsSheet: const [
      [
        'Import Action',
        'Property Type',
        'Occupancy',
        'Contract Type',
        'Contract Status',
        'Payment Method',
        'Payment Frequency',
        'Cheque Type',
        'Cheque Status',
      ],
      [
        'Create',
        'Shop',
        'Occupied',
        'Tenancy Contract',
        'Draft',
        'Bank Transfer',
        'Monthly',
        'CDC',
        'Scheduled',
      ],
      [
        'Update',
        'Warehouse',
        'Vacant',
        'Lease',
        'Active',
        'Cash',
        'Annual',
        'PDC',
        'Received',
      ],
      ['', 'Office', '', '', 'Expired', 'CDC', '', '', 'Deposited'],
      ['', 'Villa', '', '', 'Terminated', 'PDC', '', '', 'Cleared'],
      ['', 'Labour Camp', '', '', 'Renewed', 'Other', '', '', 'Returned'],
      ['', 'Other', '', '', '', '', '', '', 'Cancelled'],
      ['', 'Store', 'Unknown', 'Licence', 'Notice Due', '', '', '', ''],
      ['', 'Office (Store)', '', 'Other', '', '', '', '', ''],
    ],
  });

  static YorksV1BoqWorkbookSheet? _optionalSheet(
    YorksV1BoqParsedWorkbook workbook,
    String name,
  ) {
    for (final sheet in workbook.sheets) {
      if (sheet.name.trim().toLowerCase() == name.toLowerCase()) return sheet;
    }
    return null;
  }

  static ({YorksV1BoqWorkbookSheet sheet, int headerIndex})? _trackerSheet(
    YorksV1BoqParsedWorkbook workbook,
  ) {
    for (final sheet in workbook.sheets) {
      if (!{
        'sheet1',
        propertySheet.toLowerCase(),
      }.contains(sheet.name.trim().toLowerCase())) {
        continue;
      }
      for (final index in [2, 0]) {
        if (sheet.rows.length <= index) continue;
        final row = sheet.rows[index];
        if (row.length >= trackerHeaders.length &&
            List.generate(
              trackerHeaders.length,
              (column) => column,
            ).every((column) => row[column].trim() == trackerHeaders[column])) {
          return (sheet: sheet, headerIndex: index);
        }
      }
    }
    return null;
  }

  List<YorksV1RentalImportRow> _trackerRows(
    YorksV1BoqWorkbookSheet sheet,
    int headerIndex,
    String fileName,
    YorksV1RentalPortfolio portfolio,
    List<YorksV1RentalImportIssue> allIssues,
  ) {
    final headers = sheet.rows[headerIndex];
    for (final header in [...trackerHeaders, ...trackerOptionalHeaders]) {
      if (headers.where((value) => value.trim() == header).length > 1) {
        allIssues.add(
          YorksV1RentalImportIssue(
            sheet: sheet.name,
            rowNumber: headerIndex + 1,
            message: 'Required column “$header” is duplicated.',
          ),
        );
      }
    }
    if (allIssues.isNotEmpty) return const [];
    final existing = {
      for (final property in portfolio.properties)
        property.unitCode.trim().toUpperCase(): property,
    };
    final seen = <String>{};
    final result = <YorksV1RentalImportRow>[];
    for (var index = headerIndex + 1; index < sheet.rows.length; index++) {
      final source = sheet.rows[index];
      if (source.every((cell) => cell.trim().isEmpty)) continue;
      final rowNumber = index + 1;
      final issues = <YorksV1RentalImportIssue>[];
      void issue(String message, {bool blocking = false}) => issues.add(
        YorksV1RentalImportIssue(
          sheet: sheet.name,
          rowNumber: rowNumber,
          message: message,
          severity: blocking
              ? YorksV1RentalImportSeverity.error
              : YorksV1RentalImportSeverity.warning,
        ),
      );
      String value(String header) => _sourceValue(headers, source, header);
      double? amount(String header) {
        final text = value(header);
        if (text.isEmpty) return null;
        final amount = _parsedNumber(text);
        if (amount == null || amount < 0) {
          issue('$header must be a valid non-negative number.', blocking: true);
          return null;
        }
        return amount;
      }

      String? date(String header) {
        final text = value(header);
        if (text.isEmpty) return null;
        final parsed = _date(text);
        if (parsed == null) {
          issue('$header must be a valid date.', blocking: true);
        }
        return parsed;
      }

      final unitNumber = value('Unit No');
      final sourceType = value('Unit Type');
      final explicitCode = value('Unit Code');
      final code = explicitCode.isNotEmpty
          ? explicitCode.toUpperCase()
          : unitNumber.isEmpty
          ? 'SOURCE-$rowNumber'
          : _wire(
              '${sourceType.isEmpty ? 'Unit' : sourceType} $unitNumber',
            ).replaceAll('_', '-').toUpperCase();
      if (!seen.add(code)) {
        issue('Unit Code is duplicated in this workbook.', blocking: true);
      }
      if (code.isEmpty || code.length > 40) {
        issue(
          'Unit Code must contain between 1 and 40 characters.',
          blocking: true,
        );
      }
      final existingProperty = existing[code];
      final requestedAction = value('Import Action').toLowerCase();
      if (requestedAction.isNotEmpty &&
          !{'create', 'update'}.contains(requestedAction)) {
        issue('Import Action must be Create or Update.', blocking: true);
      }
      if (existingProperty != null && requestedAction != 'update') {
        issue(
          'This Unit Code already exists. Enter Update in Import Action to deliberately update it.',
          blocking: true,
        );
      }
      if (existingProperty == null && requestedAction == 'update') {
        issue('Update requires an existing Unit Code.', blocking: true);
      }
      if (unitNumber.isEmpty && explicitCode.isEmpty) {
        issue(
          'Unit number is missing. $code preserves the source row until it is completed.',
        );
      }
      final type = _wire(sourceType);
      final supportedType = const {
        'shop',
        'store',
        'office_store',
        'warehouse',
        'office',
        'labour_camp',
        'villa',
        'other',
      }.contains(type);
      final propertyType = sourceType.isEmpty && existingProperty != null
          ? _wire(existingProperty.propertyType)
          : supportedType
          ? type
          : 'other';
      if (!supportedType) {
        issue('Property type needs review; the original value is preserved.');
      }
      final sourceStatus = value('Status').toLowerCase();
      final occupancy = switch (sourceStatus) {
        'active' => 'occupied',
        'empty' => 'vacant',
        _ => existingProperty?.occupancy.wireValue ?? 'unknown',
      };
      final frequencyText = value('Rent Frequency');
      final frequency = frequencyText.isEmpty
          ? value('Annual Rent (AED)').isNotEmpty
                ? 'annual'
                : existingProperty?.paymentFrequency ?? 'annual'
          : _wire(frequencyText);
      if (!{'annual', 'monthly'}.contains(frequency)) {
        issue('Rent Frequency must be Annual or Monthly.', blocking: true);
      }
      final suppliedAnnualRent = amount('Annual Rent (AED)');
      final suppliedMonthlyRent = amount('Monthly Rent (AED)');
      final annualRent = suppliedAnnualRent ?? existingProperty?.annualRent;
      final monthlyRent =
          suppliedMonthlyRent ??
          (existingProperty != null &&
                  !existingProperty.isAnnual &&
                  existingProperty.hasRentAmount
              ? existingProperty.monthlyRent
              : null);
      if ((frequency == 'annual' && suppliedMonthlyRent != null) ||
          (frequency == 'monthly' && suppliedAnnualRent != null)) {
        issue(
          'Keep only the amount for the selected Rent Frequency.',
          blocking: true,
        );
      }
      final leaseStart =
          date('Contract Start') ??
          existingProperty?.leaseStart?.toIso8601String().split('T').first;
      final leaseEnd =
          date('Contract End') ??
          existingProperty?.leaseEnd?.toIso8601String().split('T').first;
      final billingStart =
          date('Billing Start') ??
          existingProperty?.billingStart?.toIso8601String().split('T').first;
      final location =
          _null(value('Location')) ?? _null(existingProperty?.location);
      final contractNumber =
          _null(value('Contract No.')) ?? existingProperty?.contractNumber;
      final tenantName =
          _null(value('Tenant / Company')) ?? existingProperty?.tenantName;
      final contactNumber =
          _null(value('Contact')) ?? existingProperty?.contactNumber;
      if (leaseStart != null &&
          leaseEnd != null &&
          leaseEnd.compareTo(leaseStart) < 0) {
        issue('Contract End cannot be before Contract Start.', blocking: true);
      }
      int? dueDay = existingProperty?.monthlyDueDay;
      final dueText = value('Monthly Due Day');
      if (dueText.isNotEmpty) {
        final due = _parsedNumber(dueText);
        if (due == null ||
            due != due.truncateToDouble() ||
            due < 1 ||
            due > 31) {
          issue(
            'Monthly Due Day must be a whole number between 1 and 31.',
            blocking: true,
          );
        } else {
          dueDay = due.toInt();
        }
      }
      final missing = <String>[
        if (location == null) 'location',
        if (!supportedType && existingProperty == null) 'property_type',
        if (occupancy == 'unknown') 'occupancy',
        if (occupancy == 'occupied' && tenantName == null) 'tenant_name',
        if (contractNumber == null) 'contract_number',
        if (leaseStart == null) 'lease_start',
        if (leaseEnd == null) 'lease_end',
        if (frequency == 'annual' ? annualRent == null : monthlyRent == null)
          'rent_amount',
        if (billingStart == null) 'billing_start',
      ];
      if (missing.isNotEmpty) {
        issue(
          'Incomplete details: ${missing.join(', ')}. These can be completed after import.',
        );
      }
      if (billingStart == null) {
        issue(
          'Billing has not started. No rent periods or arrears will be inferred.',
        );
      }
      final security = value('Security Cheque (AED)');
      if (security.isNotEmpty) {
        issue(
          'Security Cheque is preserved as source information, not a cash deposit or payment.',
        );
      }
      final originalValues = <String, Object?>{
        for (var column = 0; column < headers.length; column++)
          if (headers[column].isNotEmpty)
            headers[column]: column < source.length && source[column].isNotEmpty
                ? source[column]
                : null,
      };
      final oldOriginal = existingProperty?.sourceMetadata['original_values'];
      if (oldOriginal is Map &&
          trackerHeaders.any(
            (header) => oldOriginal[header] != originalValues[header],
          )) {
        issue(
          'Original imported source values changed. Keep the source evidence unchanged and edit live property details instead.',
          blocking: true,
        );
      }
      final propertyName =
          existingProperty?.propertyName ??
          (unitNumber.isEmpty
              ? '${sourceType.isEmpty ? 'Property' : sourceType} $code'
              : '${sourceType.isEmpty ? 'Unit' : sourceType} $unitNumber');
      result.add(
        YorksV1RentalImportRow(
          sheet: sheet.name,
          rowNumber: rowNumber,
          action: existingProperty == null ? 'create' : 'update',
          label: '$code · $propertyName',
          issues: issues,
          payload: {
            'source_row': rowNumber,
            'action': existingProperty == null ? 'create' : 'update',
            if (existingProperty != null) 'property_id': existingProperty.id,
            if (existingProperty?.leaseId != null)
              'lease_id': existingProperty!.leaseId,
            if (existingProperty != null)
              'expected_version': existingProperty.recordVersion,
            'unit_code': code,
            'property_name': propertyName,
            'property_type': propertyType,
            'location': location,
            'occupancy_state': occupancy,
            'occupied': occupancy == 'occupied',
            'tenant_name': tenantName,
            'contact_number': contactNumber,
            'contract_number': contractNumber,
            if (existingProperty == null) ...{
              'contract_type': 'tenancy_contract',
              'contract_status': sourceStatus == 'active' ? 'active' : 'draft',
            },
            'lease_start': leaseStart,
            'lease_end': leaseEnd,
            if (existingProperty == null ||
                value('Annual Rent (AED)').isNotEmpty)
              'annual_rent': annualRent,
            if (existingProperty == null ||
                value('Monthly Rent (AED)').isNotEmpty)
              'monthly_rent': monthlyRent,
            'payment_frequency': frequency,
            'billing_start': billingStart,
            'monthly_due_day': ?dueDay,
            if (existingProperty == null)
              'lease_notes': security.isEmpty
                  ? null
                  : 'Source Security Cheque (AED): $security',
            'source_metadata':
                existingProperty?.sourceMetadata.isNotEmpty == true
                ? existingProperty!.sourceMetadata
                : {
                    'format': 'yorks_properties_tracker_v1',
                    'source_format': 'yorks_properties_tracker_v1',
                    'source_file': fileName,
                    'source_sheet': sheet.name,
                    'source_row': rowNumber,
                    'source_unit_number': _null(unitNumber),
                    'source_unit_type': _null(sourceType),
                    'original_values': originalValues,
                    'missing_fields': missing,
                  },
          },
        ),
      );
      allIssues.addAll(issues);
    }
    return result;
  }

  Uint8List buildExport({
    required YorksV1RentalExportRegister register,
    required Map<String, dynamic> data,
  }) {
    final key = switch (register) {
      YorksV1RentalExportRegister.propertyLease => 'properties',
      YorksV1RentalExportRegister.rentSchedule => 'periods',
      YorksV1RentalExportRegister.payments => 'payments',
      YorksV1RentalExportRegister.cheques => 'cheques',
      YorksV1RentalExportRegister.leaseExpiry => 'lease_expiry',
    };
    final title = switch (register) {
      YorksV1RentalExportRegister.propertyLease => 'Property & Lease Register',
      YorksV1RentalExportRegister.rentSchedule => 'Rent Schedule & Outstanding',
      YorksV1RentalExportRegister.payments => 'Payment Receipt Register',
      YorksV1RentalExportRegister.cheques => 'CDC PDC Register',
      YorksV1RentalExportRegister.leaseExpiry => 'Lease Expiry & Renewal',
    };
    final values = data[key];
    final rows = values is List
        ? values
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : <Map<String, dynamic>>[];
    final headers = rows.isEmpty
        ? <String>['No records']
        : rows.first.keys.toList();
    return _WorkbookWriter.encode({
      title: [
        headers,
        for (final row in rows)
          [for (final header in headers) _cell(row[header])],
      ],
    });
  }

  YorksV1BoqWorkbookSheet? _sheet(
    YorksV1BoqParsedWorkbook workbook,
    String name,
    List<YorksV1RentalImportIssue> issues,
  ) {
    for (final sheet in workbook.sheets) {
      if (sheet.name.trim().toLowerCase() == name.toLowerCase()) return sheet;
    }
    issues.add(
      YorksV1RentalImportIssue(
        sheet: name,
        rowNumber: 1,
        message: 'Required worksheet “$name” is missing.',
      ),
    );
    return null;
  }

  List<YorksV1RentalImportRow> _propertyRows(
    YorksV1BoqWorkbookSheet? sheet,
    YorksV1RentalPortfolio portfolio,
    List<YorksV1RentalImportIssue> allIssues,
  ) {
    if (sheet == null) return const [];
    final table = _table(sheet, propertyHeaders, allIssues);
    final existing = {
      for (final property in portfolio.properties)
        property.unitCode.trim().toUpperCase(): property,
    };
    final seen = <String>{};
    return [
      for (final entry in table.entries)
        _propertyRow(entry.key, entry.value, existing, seen, allIssues),
    ];
  }

  YorksV1RentalImportRow _propertyRow(
    int rowNumber,
    Map<String, String> row,
    Map<String, YorksV1RentalProperty> existing,
    Set<String> seen,
    List<YorksV1RentalImportIssue> allIssues,
  ) {
    final issues = <YorksV1RentalImportIssue>[];
    void error(String message) => issues.add(
      YorksV1RentalImportIssue(
        sheet: propertySheet,
        rowNumber: rowNumber,
        message: message,
      ),
    );
    String choice(String field, Set<String> supported, {String fallback = ''}) {
      final value = row[field]!.trim();
      final result = value.isEmpty ? fallback : _wire(value);
      if (!supported.contains(result)) {
        error('${field.replaceAll(' *', '')} is not supported.');
      }
      return result;
    }

    double number(
      String field, {
      double fallback = 0,
      double minimum = 0,
      double? maximum,
      bool integer = false,
    }) {
      final text = row[field]!.trim();
      if (text.isEmpty) return fallback;
      final value = _parsedNumber(text);
      final label = field.replaceAll(' *', '');
      if (value == null || (integer && value != value.truncateToDouble())) {
        error('$label must be a valid ${integer ? 'whole number' : 'number'}.');
        return fallback;
      }
      if (value < minimum || (maximum != null && value > maximum)) {
        error(
          maximum == null
              ? '$label cannot be negative.'
              : '$label must be between ${minimum.toInt()} and ${maximum.toInt()}.',
        );
      }
      return value;
    }

    String? date(String field) {
      final text = row[field]!.trim();
      final value = _date(text);
      if (text.isNotEmpty && value == null) {
        error('$field must be a valid date.');
      }
      return value;
    }

    final action = row['Import Action *']!.trim().toLowerCase();
    final code = row['Unit Code *']!.trim().toUpperCase();
    if (!{'create', 'update'}.contains(action)) {
      error('Import Action must be Create or Update.');
    }
    if (code.isEmpty) error('Unit Code is required.');
    if (!seen.add(code)) error('Unit Code is duplicated in this workbook.');
    if (action == 'create' && existing.containsKey(code)) {
      error('Create cannot use an existing Unit Code. Choose Update.');
    }
    if (action == 'update' && !existing.containsKey(code)) {
      error('Update requires an existing Unit Code.');
    }
    for (final field in [
      'Property Name *',
      'Property Type *',
      'Location *',
      'Occupancy *',
    ]) {
      if (row[field]!.trim().isEmpty) {
        error('${field.replaceAll(' *', '')} is required.');
      }
    }
    final propertyType = choice('Property Type *', const {
      'shop',
      'store',
      'office_store',
      'warehouse',
      'office',
      'labour_camp',
      'villa',
      'other',
    });
    final occupancy = choice('Occupancy *', const {'occupied', 'vacant'});
    final occupied = occupancy == 'occupied';
    final contractType = choice('Contract Type', const {
      'tenancy_contract',
      'lease',
      'licence',
      'other',
    }, fallback: 'tenancy_contract');
    final contractStatus = choice('Contract Status', const {
      'draft',
      'active',
      'notice_due',
      'expired',
      'renewed',
      'terminated',
    }, fallback: 'draft');
    final paymentMethod = choice('Default Payment Method', const {
      'bank_transfer',
      'cash',
      'cdc',
      'pdc',
      'other',
    }, fallback: 'bank_transfer');
    final paymentFrequency = choice('Payment Frequency', const {
      'monthly',
      'annual',
    }, fallback: 'monthly');
    if (occupied &&
        (row['Tenant / Company Name']!.trim().isEmpty ||
            row['Contract No.']!.trim().isEmpty ||
            row['Lease Start']!.trim().isEmpty ||
            row['Lease End']!.trim().isEmpty)) {
      error(
        'Occupied properties require tenant, contract number, lease start and lease end.',
      );
    }
    final monthlyRent = number('Monthly Rent AED');
    final dueDay = number(
      'Monthly Due Day',
      fallback: 1,
      minimum: 1,
      maximum: 31,
      integer: true,
    ).toInt();
    final graceDays = number(
      'Grace Period Days',
      fallback: 5,
      maximum: 90,
      integer: true,
    ).toInt();
    final securityDeposit = number('Security Deposit AED');
    final chequeCount = number(
      'No. of Contract Cheques',
      maximum: 240,
      integer: true,
    ).toInt();
    final escalation = number('Annual Escalation %', maximum: 100);
    final noticeDays = number(
      'Renewal Notice Days',
      fallback: 90,
      maximum: 730,
      integer: true,
    ).toInt();
    final signedDate = date('Contract Signed Date');
    final leaseStart = date('Lease Start');
    final leaseEnd = date('Lease End');
    if (leaseStart != null &&
        leaseEnd != null &&
        leaseEnd.compareTo(leaseStart) < 0) {
      error('Lease End cannot be before Lease Start.');
    }
    allIssues.addAll(issues);
    final existingProperty = existing[code];
    return YorksV1RentalImportRow(
      sheet: propertySheet,
      rowNumber: rowNumber,
      action: action,
      label: '$code · ${row['Property Name *']}',
      issues: issues,
      payload: {
        'source_row': rowNumber,
        'action': action,
        if (existingProperty != null) 'property_id': existingProperty.id,
        if (existingProperty?.leaseId != null)
          'lease_id': existingProperty!.leaseId,
        if (existingProperty != null)
          'expected_version': existingProperty.recordVersion,
        'unit_code': code,
        'property_name': row['Property Name *']!.trim(),
        'property_type': propertyType,
        'municipality_number': _null(row['Property / Municipality No.']),
        'location': row['Location *']!.trim(),
        'occupied': occupied,
        'tenant_name': _null(row['Tenant / Company Name']),
        'contact_number': _null(row['Tenant Contact']),
        'email': _null(row['Tenant Email']),
        'trade_licence_number': _null(row['Trade Licence No.']),
        'contract_number': _null(row['Contract No.']),
        'contract_type': contractType,
        'contract_status': contractStatus,
        'signed_date': signedDate,
        'lease_start': leaseStart,
        'lease_end': leaseEnd,
        'monthly_rent': monthlyRent,
        'monthly_due_day': dueDay,
        'grace_period_days': graceDays,
        'security_deposit': securityDeposit,
        'default_payment_method': paymentMethod,
        'payment_frequency': paymentFrequency,
        'contract_cheque_count': chequeCount,
        'annual_escalation_percent': escalation,
        'renewal_notice_days': noticeDays,
        'lease_notes': _null(row['Notes']),
      },
    );
  }

  List<YorksV1RentalImportRow> _paymentRows(
    YorksV1BoqWorkbookSheet? sheet,
    Set<String> knownCodes,
    List<YorksV1RentalImportIssue> allIssues,
  ) {
    final seenReferences = <String>{};
    final seenReceipts = <String>{};
    return _simpleRows(sheet, paymentHeaders, paymentSheet, allIssues, (
      rowNumber,
      row,
      issues,
    ) {
      final code = row['Unit Code *']!.trim().toUpperCase();
      final amount = _number(row['Amount Received AED *']);
      final method = _wire(row['Payment Method *']!);
      final rentPeriod = _date(row['Rent Period *']);
      final paymentDate = _date(row['Payment Date *']);
      final reference = row['Receipt / Bank / Cheque Reference']!.trim();
      if (!knownCodes.contains(code)) issues.add('Unknown Unit Code.');
      if (rentPeriod == null) {
        issues.add('Rent Period must be a valid date.');
      }
      if (amount <= 0) {
        issues.add('Amount Received must be greater than zero.');
      }
      if (paymentDate == null) {
        issues.add('Payment Date must be valid.');
      }
      if (!{'bank_transfer', 'cash', 'cdc', 'pdc', 'other'}.contains(method)) {
        issues.add('Payment Method is not supported.');
      }
      if ({'cdc', 'pdc'}.contains(method) && reference.isEmpty) {
        issues.add('CDC/PDC payments require a reference.');
      }
      if (reference.isNotEmpty &&
          !seenReferences.add(reference.toLowerCase())) {
        issues.add('Payment reference is duplicated in this workbook.');
      }
      final receiptIdentity = [
        code,
        rentPeriod ?? '',
        amount.toStringAsFixed(2),
        paymentDate ?? '',
        method,
        reference.toLowerCase(),
      ].join('|');
      if (!seenReceipts.add(receiptIdentity)) {
        issues.add('The same rent receipt is duplicated in this workbook.');
      }
      return {
        'source_row': rowNumber,
        'unit_code': code,
        'rent_period': rentPeriod,
        'amount_received': amount,
        'payment_date': paymentDate,
        'payment_method': method,
        'reference': _null(reference),
        'note': _null(row['Payment Note']),
      };
    });
  }

  List<YorksV1RentalImportRow> _chequeRows(
    YorksV1BoqWorkbookSheet? sheet,
    Set<String> knownCodes,
    List<YorksV1RentalImportIssue> allIssues,
  ) {
    final seen = <String>{};
    return _simpleRows(sheet, chequeHeaders, chequeSheet, allIssues, (
      rowNumber,
      row,
      issues,
    ) {
      final code = row['Unit Code *']!.trim().toUpperCase();
      final bank = row['Bank *']!.trim();
      final number = row['Cheque Number *']!.trim();
      if (!knownCodes.contains(code)) issues.add('Unknown Unit Code.');
      if (number.isEmpty || bank.isEmpty) {
        issues.add('Cheque Number and Bank are required.');
      }
      if (!seen.add('$code|${bank.toLowerCase()}|${number.toLowerCase()}')) {
        issues.add('Cheque is duplicated in this workbook.');
      }
      if (_number(row['Amount AED *']) <= 0) {
        issues.add('Cheque amount must be greater than zero.');
      }
      if (!{'cdc', 'pdc'}.contains(_wire(row['Cheque Type *']!))) {
        issues.add('Cheque Type is not supported.');
      }
      if (!{
        'scheduled',
        'received',
        'deposited',
        'cleared',
        'returned',
        'cancelled',
      }.contains(_wire(row['Status *']!))) {
        issues.add('Cheque Status is not supported.');
      }
      if (_date(row['Cheque Date *']) == null) {
        issues.add('Cheque Date must be valid.');
      }
      if (row['Linked Rent Period *']!.isNotEmpty &&
          _date(row['Linked Rent Period *']) == null) {
        issues.add('Linked Rent Period must be a valid date.');
      }
      return {
        'source_row': rowNumber,
        'unit_code': code,
        'cheque_type': _wire(row['Cheque Type *']!),
        'cheque_number': number,
        'bank_name': bank,
        'rent_period': _date(row['Linked Rent Period *']),
        'cheque_date': _date(row['Cheque Date *']),
        'amount': _number(row['Amount AED *']),
        'status': _wire(row['Status *']!),
        'note': _null(row['Note']),
      };
    });
  }

  List<YorksV1RentalImportRow> _simpleRows(
    YorksV1BoqWorkbookSheet? sheet,
    List<String> headers,
    String sheetName,
    List<YorksV1RentalImportIssue> allIssues,
    Map<String, Object?> Function(int, Map<String, String>, List<String>) build,
  ) {
    if (sheet == null) return const [];
    final table = _table(sheet, headers, allIssues);
    return [
      for (final entry in table.entries)
        (() {
          final messages = <String>[];
          final payload = build(entry.key, entry.value, messages);
          final issues = [
            for (final message in messages)
              YorksV1RentalImportIssue(
                sheet: sheetName,
                rowNumber: entry.key,
                message: message,
              ),
          ];
          allIssues.addAll(issues);
          return YorksV1RentalImportRow(
            sheet: sheetName,
            rowNumber: entry.key,
            action: 'append',
            label: payload['unit_code']?.toString() ?? sheetName,
            payload: payload,
            issues: issues,
          );
        })(),
    ];
  }

  Map<int, Map<String, String>> _table(
    YorksV1BoqWorkbookSheet sheet,
    List<String> requiredHeaders,
    List<YorksV1RentalImportIssue> issues,
  ) {
    final header = sheet.rows.isEmpty
        ? <String>[]
        : sheet.rows.first.map((value) => value.trim()).toList();
    var validHeaders = true;
    for (final required in requiredHeaders) {
      if (!header.contains(required)) {
        validHeaders = false;
        issues.add(
          YorksV1RentalImportIssue(
            sheet: sheet.name,
            rowNumber: 1,
            message: 'Required column “$required” is missing.',
          ),
        );
      } else if (header.where((value) => value == required).length > 1) {
        validHeaders = false;
        issues.add(
          YorksV1RentalImportIssue(
            sheet: sheet.name,
            rowNumber: 1,
            message: 'Required column “$required” is duplicated.',
          ),
        );
      }
    }
    // A malformed header cannot safely identify any record fields.
    if (!validHeaders) return const {};
    final result = <int, Map<String, String>>{};
    for (var index = 1; index < sheet.rows.length; index++) {
      final source = sheet.rows[index];
      if (source.every((cell) => cell.trim().isEmpty)) continue;
      result[index + 1] = {
        for (final required in requiredHeaders)
          required: _sourceValue(header, source, required),
      };
    }
    return result;
  }

  static String _sourceValue(
    List<String> header,
    List<String> source,
    String required,
  ) {
    final column = header.indexOf(required);
    return column >= 0 && column < source.length ? source[column].trim() : '';
  }

  static String? _null(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  static String _wire(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  static double? _parsedNumber(String? value) {
    final text = (value ?? '').trim();
    if (!RegExp(
      r'^[+-]?(?:(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$',
    ).hasMatch(text)) {
      return null;
    }
    final number = double.tryParse(text.replaceAll(',', ''));
    return number != null && number.isFinite ? number : null;
  }

  static double _number(String? value) => _parsedNumber(value) ?? 0;
  static String? _date(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final isoDate = RegExp(r'^(\d{4}-\d{2}-\d{2})(?:$|[T ])').firstMatch(text);
    if (isoDate != null) {
      try {
        // DateTime.tryParse normalizes impossible days, such as February 30.
        DateFormat('yyyy-MM-dd').parseStrict(isoDate.group(1)!);
        final direct = DateTime.tryParse(text);
        if (direct != null) return DateFormat('yyyy-MM-dd').format(direct);
      } catch (_) {}
      return null;
    }
    final serial = double.tryParse(text);
    if (serial != null && serial.isFinite && serial > 0 && serial < 2958466) {
      return DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime(1899, 12, 30).add(Duration(days: serial.floor())));
    }
    for (final pattern in ['dd/MM/yyyy', 'MM/dd/yyyy', 'dd MMM yyyy']) {
      try {
        return DateFormat(
          'yyyy-MM-dd',
        ).format(DateFormat(pattern).parseStrict(text));
      } catch (_) {}
    }
    return null;
  }

  static String _cell(Object? value) {
    if (value == null) return '';
    if (value is Map || value is List) return jsonEncode(value);
    return value.toString();
  }
}

class _WorkbookWriter {
  static Uint8List encode(Map<String, List<List<String>>> sheets) {
    final names = sheets.keys.toList();
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('[Content_Types].xml', _contentTypes(names.length)),
      )
      ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
      ..addFile(ArchiveFile.string('xl/workbook.xml', _workbook(names)))
      ..addFile(
        ArchiveFile.string(
          'xl/_rels/workbook.xml.rels',
          _workbookRels(names.length),
        ),
      )
      ..addFile(ArchiveFile.string('xl/styles.xml', _styles));
    for (var index = 0; index < names.length; index++) {
      archive.addFile(
        ArchiveFile.string(
          'xl/worksheets/sheet${index + 1}.xml',
          _sheet(sheets[names[index]]!),
        ),
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _sheet(List<List<String>> rows) {
    final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetData>',
    );
    for (var r = 0; r < rows.length; r++) {
      out.write('<row r="${r + 1}">');
      for (var c = 0; c < rows[r].length; c++) {
        final value = _xml(rows[r][c]);
        out.write(
          '<c r="${_column(c)}${r + 1}" s="${r == 0 ? 1 : 2}" t="inlineStr"><is><t xml:space="preserve">$value</t></is></c>',
        );
      }
      out.write('</row>');
    }
    out.write(
      '</sheetData><autoFilter ref="A1:${_column(rows.fold<int>(1, (max, row) => row.length > max ? row.length : max) - 1)}${rows.isEmpty ? 1 : rows.length}"/></worksheet>',
    );
    return out.toString();
  }

  static String _contentTypes(int count) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>${[for (var i = 1; i <= count; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}</Types>';
  static const _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>';
  static String _workbook(List<String> names) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${[for (var i = 0; i < names.length; i++) '<sheet name="${_xml(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets></workbook>';
  static String _workbookRels(int count) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${[for (var i = 1; i <= count; i++) '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}<Relationship Id="rId${count + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>';
  static const _styles =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Aptos"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Aptos"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF12365F"/></patternFill></fill></fills><borders count="2"><border/><border><left style="thin"><color rgb="FFD7E0EB"/></left><right style="thin"><color rgb="FFD7E0EB"/></right><top style="thin"><color rgb="FFD7E0EB"/></top><bottom style="thin"><color rgb="FFD7E0EB"/></bottom></border></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="3"><xf/><xf fontId="1" fillId="2" borderId="1" applyFont="1" applyFill="1" applyBorder="1"/><xf borderId="1" applyBorder="1"/></cellXfs></styleSheet>';
  static String _column(int index) {
    var value = index + 1;
    var result = '';
    while (value > 0) {
      value--;
      result = String.fromCharCode(65 + value % 26) + result;
      value ~/= 26;
    }
    return result;
  }

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
