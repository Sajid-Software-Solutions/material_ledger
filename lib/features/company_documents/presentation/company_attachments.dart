/// Company documents — a record's Attachments: copies of its trade licence,
/// establishment card, vehicle registration, Asateel permit, CICPA pass or
/// LOA, insurance policy and certificates, and any other paper
/// (PRODUCT_DECISIONS section 48). Built on the shared record attachments,
/// so it looks and behaves exactly like People.
///
/// Everyone who may read Company documents sees and opens them; PR, Admin
/// and the Accountant add and remove them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_company_documents.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_company_documents_provider.dart';
import '../../people_records/presentation/record_attachments.dart';
import 'company_kit.dart';

export '../../people_records/presentation/record_attachments.dart'
    show RecordAttachmentCount;

/// "Trade licence · CN-123" for the document a file copies.
String? companyAttachmentDocument(
  CompanyAttachment item,
  AppLanguage language,
) {
  final kind = item.documentKind;
  if (kind == null) return null;
  return [
    companyDocumentLabel(
      CompanyDocumentKind.from(kind),
      language,
      label: item.documentLabel,
    ),
    if (item.documentNumber != null) item.documentNumber!,
  ].join(' · ');
}

/// Opens the add dialog for [record], optionally for one [documentId].
Future<bool?> showCompanyAttachmentDialog(
  BuildContext context, {
  required CompanyRecord record,
  String? documentId,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final language = container.read(languageProvider);
  String label(CompanyDocument document) => [
    companyDocumentLabel(document.kind, language, label: document.label),
    if (document.number != null) document.number!,
    if (document.expiryDate != null) peopleDate(document.expiryDate),
    if (!document.isCurrent) PS.t(PS.endedShort, language),
  ].join(' · ');
  return showRecordAttachmentDialog(
    context,
    keyPrefix: 'company',
    ownerName: record.name,
    documentId: documentId,
    documents: [
      for (final document in [...record.documents, ...record.previousDocuments])
        (document.id, label(document)),
    ],
    upload: (upload) => container
        .read(yorksV1CompanyDocumentsRepositoryProvider)
        .addAttachment(
          recordId: record.id,
          bytes: upload.bytes,
          fileName: upload.fileName,
          contentType: upload.contentType,
          documentId: upload.documentId,
          title: upload.title,
          idempotencyKey: upload.idempotencyKey,
        ),
  );
}

/// The Attachments section on a company record.
class CompanyAttachmentsSection extends ConsumerWidget {
  const CompanyAttachmentsSection({
    super.key,
    required this.record,
    required this.language,
  });

  final CompanyRecord record;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(yorksV1CompanyDocumentsRepositoryProvider);
    return RecordAttachmentsSection(
      keyPrefix: 'company',
      attachments: ref.watch(yorksV1CompanyAttachmentsProvider(record.id)),
      canManage: record.canManage,
      language: language,
      description: CS.t(CS.attachmentsDescription, language),
      documentText: (item) => companyAttachmentDocument(item, language),
      onRetry: () =>
          ref.invalidate(yorksV1CompanyAttachmentsProvider(record.id)),
      onAdd: () async {
        final added = await showCompanyAttachmentDialog(
          context,
          record: record,
        );
        if (added == true) {
          yorksV1RefreshCompanyDocuments(ref, recordId: record.id);
        }
      },
      onOpen: (item) => openRecordAttachment(
        context,
        ref,
        () => repository.attachmentUrl(item.objectPath),
      ),
      onRemove: (item) async {
        final removed = await confirmRemoveRecordAttachment(
          context,
          language: language,
          item: item,
          summary: [
            record.name,
            ?companyAttachmentDocument(item, language),
          ].join(' · '),
          remove: (reason, key) => repository.removeAttachment(
            attachmentId: item.id,
            reason: reason,
            idempotencyKey: key,
          ),
        );
        if (removed) yorksV1RefreshCompanyDocuments(ref, recordId: record.id);
      },
    );
  }
}
