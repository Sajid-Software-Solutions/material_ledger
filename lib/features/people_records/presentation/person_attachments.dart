/// People — a person's Attachments: copies of their passport, visa,
/// Emirates ID, labour card and passes, and any other paper
/// (PRODUCT_DECISIONS section 47). Built on the shared record attachments
/// so People and Company documents behave alike.
///
/// Everyone who may read People records sees and opens them; PR, Admin and
/// the Accountant add and remove them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_people_provider.dart';
import 'people_kit.dart';
import 'record_attachments.dart';

export 'record_attachments.dart'
    show RecordAttachmentCount, yorksV1OpenLinkProvider;

/// "Passport · P123" for the document a file copies.
String? peopleAttachmentDocument(PeopleAttachment item, AppLanguage language) {
  final kind = item.documentKind;
  if (kind == null) return null;
  return [
    peopleKindLabel(
      PeopleDocumentKind.from(kind),
      language,
      label: item.documentLabel,
    ),
    if (item.documentNumber != null) item.documentNumber!,
  ].join(' · ');
}

/// Opens the add dialog for [person], optionally for one [documentId].
Future<bool?> showPeopleAttachmentDialog(
  BuildContext context, {
  required PeoplePerson person,
  String? documentId,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final language = container.read(languageProvider);
  String label(PeopleDocument document) => [
    peopleKindLabel(document.kind, language, label: document.label),
    if (document.number != null) document.number!,
    if (document.expiryDate != null) peopleDate(document.expiryDate),
    if (!document.isCurrent) PS.t(PS.endedShort, language),
  ].join(' · ');
  return showRecordAttachmentDialog(
    context,
    keyPrefix: 'people',
    ownerName: person.name,
    documentId: documentId,
    documents: [
      for (final document in [...person.documents, ...person.previousDocuments])
        (document.id, label(document)),
    ],
    upload: (upload) => container
        .read(yorksV1PeopleRepositoryProvider)
        .addAttachment(
          workerId: person.id,
          bytes: upload.bytes,
          fileName: upload.fileName,
          contentType: upload.contentType,
          documentId: upload.documentId,
          title: upload.title,
          idempotencyKey: upload.idempotencyKey,
        ),
  );
}

/// The Attachments section on a person's record.
class PeopleAttachmentsSection extends ConsumerWidget {
  const PeopleAttachmentsSection({
    super.key,
    required this.person,
    required this.language,
  });

  final PeoplePerson person;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.read(yorksV1PeopleRepositoryProvider);
    return RecordAttachmentsSection(
      keyPrefix: 'people',
      attachments: ref.watch(yorksV1PeopleAttachmentsProvider(person.id)),
      canManage: person.canManage,
      language: language,
      description: PS.t(PS.attachmentsDescription, language),
      documentText: (item) => peopleAttachmentDocument(item, language),
      onRetry: () =>
          ref.invalidate(yorksV1PeopleAttachmentsProvider(person.id)),
      onAdd: () async {
        final added = await showPeopleAttachmentDialog(context, person: person);
        if (added == true) yorksV1RefreshPeople(ref, workerId: person.id);
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
            person.name,
            ?peopleAttachmentDocument(item, language),
          ].join(' · '),
          remove: (reason, key) => repository.removeAttachment(
            attachmentId: item.id,
            reason: reason,
            idempotencyKey: key,
          ),
        );
        if (removed) yorksV1RefreshPeople(ref, workerId: person.id);
      },
    );
  }
}
