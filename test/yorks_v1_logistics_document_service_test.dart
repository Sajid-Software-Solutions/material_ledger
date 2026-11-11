import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/models/yorks_v1_company_document_strings.dart';
import 'package:material_ledger/shared/models/yorks_v1_logistics.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_return_candidates.dart';
import 'package:material_ledger/shared/models/yorks_v1_material_return_workflow.dart';
import 'package:material_ledger/shared/services/yorks_v1_boq_workbook_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_logistics_document_service.dart';
import 'package:pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = YorksV1LogisticsDocumentService();
  final revision = YorksV1DeliveryOrderRevision(
    id: 'revision-1',
    revisionNumber: 2,
    isCurrent: true,
    generatedAt: DateTime.utc(2026, 8, 2),
    generatedByDisplayName: 'Procurement User',
    lines: const [
      YorksV1DeliveryOrderLine(
        serialNumber: 1,
        description: 'Copper pipe',
        size: '50x50mm',
        model: 'GI',
        quantity: '3',
        unit: 'Mtr',
      ),
      YorksV1DeliveryOrderLine(
        serialNumber: 2,
        description: 'Refrigerant valve',
        quantity: '1',
        unit: 'Nos',
      ),
    ],
  );
  final deliveryOrder = YorksV1DeliveryOrder(
    id: 'order-1',
    dispatchId: 'dispatch-1',
    reference: 'Y-DO-001',
    recordVersion: 2,
    currentRevisionId: revision.id,
    revisions: [revision],
  );
  final dispatch = YorksV1DeliveryOrderDispatch(
    dispatchId: 'dispatch-1',
    dispatchNumber: 'Y-DSP-001',
    dispatchDate: DateTime.utc(2026, 8, 2),
    dispatchRecordVersion: 1,
    canGenerate: true,
    deliveryOrder: deliveryOrder,
  );
  final workspace = YorksV1ReturnsDocumentsWorkspace(
    requestId: 'request-1',
    projectId: 'project-1',
    requestNumber: 'Y-MR-001',
    requestState: 'received',
    requestRecordVersion: 1,
    projectName: 'Yorks Project',
    projectReference: 'Y-001',
    jobContractReference: 'N-19957.2',
    scopeName: 'Building A',
    scopeCode: 'B-01',
    canGenerateDeliveryOrder: true,
    canSubmitMaterialReturn: true,
    canConfirmMaterialReturn: true,
    deliveryOrderDispatches: [dispatch],
    returnCandidates: const [],
    materialReturns: const [],
    returnInventoryItems: const [],
  );
  final projectReturn = YorksV1ProjectMaterialReturn(
    id: 'project-return-1',
    number: 'Y-001-RTN001',
    state: YorksV1ProjectMaterialReturnState.dispatched,
    recordVersion: 4,
    projectId: 'project-1',
    projectReference: 'Y-001',
    projectName: 'Yorks Project',
    scopeId: 'scope-1',
    scopeName: 'Building A',
    purpose: 'Project close-out surplus',
    draftedAt: DateTime.utc(2026, 8, 24),
    draftedByAuthUserId: 'site-engineer-1',
    draftedByDisplayName: 'Site Engineer',
    draftedByRole: 'site_engineer',
    driverName: 'Taimoor Shah',
    vehicleReference: 'AD-12345',
    deliveryNoteReference: 'RTN-DN-001',
    canEdit: false,
    canSubmit: false,
    canApprove: false,
    canReturnForChanges: false,
    canDispatch: false,
    canConfirm: true,
    canCancel: false,
    lines: const [
      YorksV1MaterialReturnLineRecord(
        id: 'return-line-1',
        origin: YorksV1ReturnLineOrigin.delivered,
        receiptReviewLineId: 'receipt-line-1',
        sourceRequestId: 'request-1',
        sourceRequestNumber: 'Y-MR-001',
        sourceDispatchId: 'dispatch-1',
        sourceDispatchNumber: 'Y-DSP-001',
        basisKind: YorksV1ReturnBasisKind.dispatchedUnconfirmed,
        displayOrder: 1,
        description: 'Copper pipe',
        size: '15mm',
        model: 'Type L',
        equipmentTag: 'CH-01',
        brandOrigin: 'UAE',
        unit: 'Mtr',
        sourceKind: 'warehouse',
        returnQuantity: '3',
        lineNote: 'Unused length',
      ),
      YorksV1MaterialReturnLineRecord(
        id: 'return-line-2',
        origin: YorksV1ReturnLineOrigin.custom,
        displayOrder: 2,
        description: 'Site ladder',
        unit: 'Nos',
        sourceKind: 'custom',
        returnQuantity: '1',
        lineNote: 'Historical MR unavailable',
      ),
    ],
    inventoryItems: const [],
  );

  test(
    'Delivery Order export has only the frozen four operational columns',
    () {
      final bytes = service.buildDeliveryOrderExcel(
        workspace: workspace,
        dispatch: dispatch,
        revision: revision,
      );
      final workbook = const YorksV1BoqWorkbookCodec().decode(
        bytes: bytes,
        fileName: 'delivery-order.xlsx',
      );

      expect(workbook.sheets, hasLength(1));
      expect(
        workbook.sheets.single.rows[1],
        equals(const ['S:No', 'Item Description', 'Qty', 'Unit']),
      );
      expect(
        workbook.sheets.single.rows[2],
        equals(const [
          '1',
          'Copper pipe\nSize: 50x50mm · Model: GI',
          '3',
          'Mtr',
        ]),
      );
    },
  );

  test('Project Material Return Excel preserves source trace and notes', () {
    final workbook = const YorksV1BoqWorkbookCodec().decode(
      bytes: service.buildProjectMaterialReturnExcel(projectReturn),
      fileName: 'project-return.xlsx',
    );

    expect(
      workbook.sheets.single.rows[1],
      equals(const [
        'No.',
        'Item Description',
        'Size',
        'Model / Equipment tag',
        'Brand / Origin',
        'Qty.',
        'Unit',
        'Source trace',
        'Note',
      ]),
    );
    expect(workbook.sheets.single.rows[2][2], '15mm');
    expect(workbook.sheets.single.rows[2][3], 'Type L · CH-01');
    expect(
      workbook.sheets.single.rows[2][7],
      'Y-MR-001 · Y-DSP-001 · Not yet confirmed by site',
    );
    expect(workbook.sheets.single.rows[3][7], 'Custom / unmatched');
  });

  test(
    'Project Material Return PDF is printable in Yorks form style',
    () async {
      final bytes = await service.buildProjectMaterialReturnPdf(
        projectReturn,
        format: PdfPageFormat.a4,
      );
      expect(bytes.length, greaterThan(500));
      expect(utf8.decode(bytes.take(4).toList()), equals('%PDF'));
      expect(_generatedPdfPageCount(bytes), 1);
    },
  );

  test(
    'receipt-reviewed Delivery Report exports confirmed good quantities without dropping exception lines',
    () async {
      final reviewedRevision = YorksV1DeliveryOrderRevision(
        id: 'revision-receipt-reviewed',
        revisionNumber: 3,
        isCurrent: true,
        generatedAt: DateTime.utc(2026, 8, 10),
        generatedByDisplayName: 'Project Engineer',
        snapshotKind: YorksV1DeliveryOrderSnapshotKind.receiptReview,
        lines: const [
          YorksV1DeliveryOrderLine(
            serialNumber: 1,
            description: 'Copper pipe',
            size: '50x50mm',
            model: 'GI',
            quantity: '8',
            unit: 'Mtr',
          ),
          YorksV1DeliveryOrderLine(
            serialNumber: 2,
            description: 'Refrigerant valve',
            size: '25mm',
            model: 'RV-25',
            quantity: '0',
            unit: 'Nos',
          ),
        ],
      );

      final workbook = const YorksV1BoqWorkbookCodec().decode(
        bytes: service.buildDeliveryOrderExcel(
          workspace: workspace,
          dispatch: dispatch,
          revision: reviewedRevision,
        ),
        fileName: 'delivery-report.xlsx',
      );
      expect(
        workbook.sheets.single.rows[2],
        equals(const [
          '1',
          'Copper pipe\nSize: 50x50mm · Model: GI',
          '8',
          'Mtr',
        ]),
      );
      expect(
        workbook.sheets.single.rows[3],
        equals(const [
          '2',
          'Refrigerant valve\nSize: 25mm · Model: RV-25',
          '0',
          'Nos',
        ]),
      );

      final bytes = await service.buildDeliveryOrderPdf(
        workspace: workspace,
        dispatch: dispatch,
        revision: reviewedRevision,
        format: PdfPageFormat.a4,
      );
      expect(bytes, isNotEmpty);
      if (const bool.fromEnvironment('R35_CAPTURE_EVIDENCE')) {
        await Directory('output/pdf').create(recursive: true);
        await File(
          'output/pdf/r35-delivery-report-receipt-reviewed.pdf',
        ).writeAsBytes(bytes, flush: true);
      }
    },
  );

  test('Delivery Order PDF supports the printable snapshot', () async {
    final bytes = await service.buildDeliveryOrderPdf(
      workspace: workspace,
      dispatch: dispatch,
      revision: revision,
      format: PdfPageFormat.a4,
    );

    expect(bytes.length, greaterThan(500));
    expect(utf8.decode(bytes.take(4).toList()), equals('%PDF'));
    expect(
      YorksV1CompanyDocumentStrings.legalName.ar,
      'يوركس للتكييف والتبريد - ذ.م.م - ش.ش.و',
    );
    expect(
      YorksV1CompanyDocumentStrings.contactLine.en,
      'Tel.: 02-5509788 - Fax: 02-5509688 - P.O. Box: 4757 - Abu Dhabi - United Arab Emirates',
    );
    expect(YorksV1CompanyDocumentStrings.email, 'yorks_sk@yorks.ae');
    if (const bool.fromEnvironment('R35_CAPTURE_EVIDENCE')) {
      await Directory('output/pdf').create(recursive: true);
      await File(
        'output/pdf/r35-delivery-order-dispatch.pdf',
      ).writeAsBytes(bytes, flush: true);
    }
  });

  test(
    'short Delivery Report with a wrapped project heading stays on one page',
    () async {
      final wrappedProjectWorkspace = YorksV1ReturnsDocumentsWorkspace(
        requestId: 'request-wrapped-project',
        projectId: 'project-wrapped-project',
        requestNumber: 'YRA313-MR012',
        requestState: 'received',
        requestRecordVersion: 1,
        projectName:
            'N-19957.2-PROJECT NEXUS (POWER) BULK TRANSMISSION SCHEME PHASE 1: '
            'SUPPLY AND INSTALLATION OF 132/33KV SUBSTATION & RELATED '
            'INTERCONNECTION 132KV CABLES AT AL DHAFRA AREA '
            '(DF3W, DF4W, DF6W, DF7W)',
        projectReference: 'N-19957.2',
        jobContractReference: 'N-19957.2',
        scopeName: 'Common',
        mainContractorName: 'M/s. Larsen & Toubro Limited- (L&T)',
        materialContext: 'test',
        canGenerateDeliveryOrder: true,
        canSubmitMaterialReturn: true,
        canConfirmMaterialReturn: true,
        deliveryOrderDispatches: [dispatch],
        returnCandidates: const [],
        materialReturns: const [],
        returnInventoryItems: const [],
      );
      final wrappedProjectRevision = YorksV1DeliveryOrderRevision(
        id: 'revision-wrapped-project',
        revisionNumber: 1,
        isCurrent: true,
        generatedAt: DateTime.utc(2026, 8, 14),
        generatedByDisplayName: 'Owner',
        generatedByRole: 'admin',
        snapshotKind: YorksV1DeliveryOrderSnapshotKind.receiptReview,
        lines: const [
          YorksV1DeliveryOrderLine(
            serialNumber: 1,
            description: 'Nsnsns',
            size: '10x10',
            model: 'Sjja',
            quantity: '1',
            unit: 'Nos',
          ),
        ],
      );

      final bytes = await service.buildDeliveryOrderPdf(
        workspace: wrappedProjectWorkspace,
        dispatch: dispatch,
        revision: wrappedProjectRevision,
        format: PdfPageFormat.a4,
      );

      expect(_generatedPdfPageCount(bytes), 1);
      if (const bool.fromEnvironment('R35_CAPTURE_EVIDENCE')) {
        await Directory('output/pdf').create(recursive: true);
        await File(
          'output/pdf/r35-delivery-report-wrapped-project.pdf',
        ).writeAsBytes(bytes, flush: true);
      }
    },
  );

  test('Delivery Order paginates 11 rows without clipping sign-off', () async {
    final multiLineRevision = YorksV1DeliveryOrderRevision(
      id: 'revision-compact',
      revisionNumber: 3,
      isCurrent: true,
      generatedAt: DateTime.utc(2026, 8, 10),
      generatedByDisplayName: 'Procurement User',
      lines: List.generate(
        11,
        (index) => YorksV1DeliveryOrderLine(
          serialNumber: index + 1,
          description: 'Dispatched material ${index + 1}',
          quantity: '${index + 1}',
          unit: 'Nos',
        ),
      ),
    );
    final bytes = await service.buildDeliveryOrderPdf(
      workspace: workspace,
      dispatch: dispatch,
      revision: multiLineRevision,
      format: PdfPageFormat.a4,
    );

    expect(bytes.length, greaterThan(500));
    expect(utf8.decode(bytes.take(4).toList()), equals('%PDF'));
    expect(_generatedPdfPageCount(bytes), 2);
    if (const bool.fromEnvironment('R35_CAPTURE_EVIDENCE')) {
      await Directory('output/pdf').create(recursive: true);
      await File(
        'output/pdf/r35-delivery-order-compact.pdf',
      ).writeAsBytes(bytes, flush: true);
    }
  });

  test(
    'Delivery Report keeps its fixed contact footer on every page of a long receipt',
    () async {
      final longReceiptRevision = YorksV1DeliveryOrderRevision(
        id: 'revision-long-receipt',
        revisionNumber: 4,
        isCurrent: true,
        generatedAt: DateTime.utc(2026, 8, 11),
        generatedByDisplayName: 'Project Engineer',
        snapshotKind: YorksV1DeliveryOrderSnapshotKind.receiptReview,
        lines: List.generate(
          32,
          (index) => YorksV1DeliveryOrderLine(
            serialNumber: index + 1,
            description: 'Received material ${index + 1}',
            quantity: '${index + 1}',
            unit: 'Nos',
          ),
        ),
      );
      final bytes = await service.buildDeliveryOrderPdf(
        workspace: workspace,
        dispatch: dispatch,
        revision: longReceiptRevision,
        format: PdfPageFormat.a4,
      );

      expect(bytes.length, greaterThan(500));
      expect(utf8.decode(bytes.take(4).toList()), equals('%PDF'));
      if (const bool.fromEnvironment('R35_CAPTURE_EVIDENCE')) {
        await Directory('output/pdf').create(recursive: true);
        await File(
          'output/pdf/r35-delivery-report-multipage.pdf',
        ).writeAsBytes(bytes, flush: true);
      }
    },
  );
}

int _generatedPdfPageCount(List<int> bytes) => RegExp(
  r'/Type/Page(?=/)',
).allMatches(latin1.decode(bytes, allowInvalid: true)).length;
