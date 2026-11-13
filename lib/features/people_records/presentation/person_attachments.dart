/// People — a person's Attachments: copies of their passport, visa,
/// Emirates ID, labour card and passes, and any other paper
/// (PRODUCT_DECISIONS section 47).
///
/// Everyone who may read People records sees and opens them; PR, Admin and
/// the Accountant add and remove them. A file opens through a five-minute
/// link that storage rechecks. Nothing is shown as attached until the server
/// confirms; removing keeps the file and the history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../shared/providers/yorks_v1_people_provider.dart';
import '../../../shared/services/yorks_v1_document_file_service.dart';
import '../../workforce/presentation/attendance/attendance_dialogs.dart'
    show showAttendanceCommandDialog;
import 'people_kit.dart';

/// Opens a link in the browser or the device's viewer (overridden in tests).
final peopleOpenLinkProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) =>
      (uri) => launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      ),
);

IconData peopleAttachmentIcon(PeopleAttachment item) => item.isPdf
    ? Icons.picture_as_pdf_outlined
    : item.isImage
    ? Icons.image_outlined
    : item.isSheet
    ? Icons.table_chart_outlined
    : Icons.description_outlined;

/// "Passport · P123" for the document a file copies.
String? peopleAttachmentDocument(PeopleAttachment item, AppLanguage language) {
  final kind = item.documentKind;
  if (kind == null) return null;
  return [
    peopleKindLabel(kind, language, label: item.documentLabel),
    if (item.documentNumber != null) item.documentNumber!,
  ].join(' · ');
}

/// Opens a stored file in a new tab or the device's viewer.
Future<void> openPeopleAttachment(
  BuildContext context,
  WidgetRef ref,
  PeopleAttachment item,
) async {
  final language = ref.read(languageProvider);
  try {
    final url = await ref
        .read(yorksV1PeopleRepositoryProvider)
        .attachmentUrl(item.objectPath);
    final opened = await ref.read(peopleOpenLinkProvider)(Uri.parse(url));
    if (!opened && context.mounted) {
      peopleToast(context, PS.t(PS.errOpenFile, language));
    }
  } catch (error) {
    if (context.mounted) {
      peopleToast(context, peopleErrorText(error, language));
    }
  }
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

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    PeopleAttachment item,
  ) async {
    final repository = ref.read(yorksV1PeopleRepositoryProvider);
    final key = const Uuid().v4();
    final reason = await showAttendanceCommandDialog(
      context,
      language: language,
      title: PS.t(PS.removeAttachmentTitle, language, {
        'file': item.title ?? item.fileName,
      }),
      summary: [
        person.name,
        ?peopleAttachmentDocument(item, language),
      ].join(' · '),
      body: PS.t(PS.removeAttachmentBody, language),
      fieldLabel: PS.t(PS.reason, language),
      confirmLabel: PS.t(PS.remove, language),
      destructive: true,
      command: (text) async {
        try {
          await repository.removeAttachment(
            attachmentId: item.id,
            reason: text,
            idempotencyKey: key,
          );
          return null;
        } catch (error) {
          return peopleErrorText(error, language);
        }
      },
    );
    if (reason == null) return;
    yorksV1RefreshPeople(ref, workerId: person.id);
    if (context.mounted) {
      peopleToast(context, PS.t(PS.attachmentRemoved, language));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(yorksV1PeopleAttachmentsProvider(person.id));
    final canManage = async.valueOrNull?.canManage ?? person.canManage;
    return Column(
      key: const ValueKey('people-attachments'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PeopleSectionHeading(
          title: PS.t(PS.attachments, language),
          description: PS.t(PS.attachmentsDescription, language),
          trailing: canManage
              ? FilledButton.tonalIcon(
                  key: const ValueKey('people-attachment-add'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(44, 44),
                  ),
                  onPressed: () async {
                    final added = await showPeopleAttachmentDialog(
                      context,
                      person: person,
                    );
                    if (added == true) {
                      yorksV1RefreshPeople(ref, workerId: person.id);
                    }
                  },
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: Text(PS.t(PS.addAttachment, language)),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        PeopleSurface(
          padding: EdgeInsets.zero,
          child: async.when(
            skipLoadingOnRefresh: true,
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      peopleErrorText(error, language),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(
                      yorksV1PeopleAttachmentsProvider(person.id),
                    ),
                    child: Text(PS.t(PS.retry, language)),
                  ),
                ],
              ),
            ),
            data: (data) => data.items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.folder_open_outlined,
                          color: AppColors.mutedLight,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          PS.t(PS.noAttachments, language),
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, item) in data.items.indexed) ...[
                        if (index > 0)
                          const Divider(height: 1, color: AppColors.line),
                        _AttachmentTile(
                          item: item,
                          language: language,
                          canManage: data.canManage,
                          onOpen: () =>
                              openPeopleAttachment(context, ref, item),
                          onRemove: () => _remove(context, ref, item),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.item,
    required this.language,
    required this.canManage,
    required this.onOpen,
    required this.onRemove,
  });

  final PeopleAttachment item;
  final AppLanguage language;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final document = peopleAttachmentDocument(item, language);
    return InkWell(
      key: ValueKey('people-attachment-${item.id}'),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(
                peopleAttachmentIcon(item),
                size: 20,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title ?? document ?? item.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    [
                      if (item.title != null && document != null) document,
                      if (item.title != null || document != null) item.fileName,
                      item.sizeText,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  Text(
                    PS.t(PS.attachedBy, language, {
                      'name': item.uploadedBy,
                      'date': peopleStamp(item.uploadedAt),
                    }),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.mutedLight,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: ValueKey('people-attachment-open-${item.id}'),
              tooltip: PS.t(PS.openFile, language),
              onPressed: onOpen,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
            ),
            if (canManage)
              IconButton(
                key: ValueKey('people-attachment-remove-${item.id}'),
                tooltip: PS.t(PS.removeAttachment, language),
                onPressed: onRemove,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: AppColors.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A paperclip and how many files a person (or one document) has.
class PeopleAttachmentCount extends StatelessWidget {
  const PeopleAttachmentCount({
    super.key,
    required this.count,
    required this.language,
  });

  final int count;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = PS.t(PS.filesAttached, language, {'n': count});
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.attach_file_rounded,
              size: 15,
              color: AppColors.blue,
            ),
            Text(
              '$count',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.blue,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Resolves to true once the server recorded the file.
Future<bool?> showPeopleAttachmentDialog(
  BuildContext context, {
  required PeoplePerson person,
  String? documentId,
}) {
  final phone = MediaQuery.sizeOf(context).width < 600;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PeopleAttachmentDialog(
      person: person,
      documentId: documentId,
      fullScreen: phone,
    ),
  );
}

class PeopleAttachmentDialog extends ConsumerStatefulWidget {
  const PeopleAttachmentDialog({
    super.key,
    required this.person,
    this.documentId,
    this.fullScreen = false,
  });

  final PeoplePerson person;

  /// The document the file copies, when opened from that document's row.
  final String? documentId;
  final bool fullScreen;

  @override
  ConsumerState<PeopleAttachmentDialog> createState() =>
      _PeopleAttachmentDialogState();
}

class _PeopleAttachmentDialogState
    extends ConsumerState<PeopleAttachmentDialog> {
  final _title = TextEditingController();
  YorksV1SelectedDocument? _file;
  late String? _documentId = widget.documentId;
  bool _busy = false;
  String? _error;

  /// Kept across retries of the same file, so a retry never stores twice.
  String? _key;

  AppLanguage get _language => ref.read(languageProvider);

  List<PeopleDocument> get _documents => [
    ...widget.person.documents,
    ...widget.person.previousDocuments,
  ];

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _error = null;
    _key = null;
  });

  Future<void> _choose() async {
    try {
      final file = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .selectDocument();
      if (file == null || !mounted) return;
      setState(() {
        _file = file;
        _error = null;
        _key = null;
      });
    } on YorksV1DomainException {
      if (mounted) setState(() => _error = PS.t(PS.errFileType, _language));
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null || _busy) return;
    final key = _key ??= const Uuid().v4();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(yorksV1PeopleRepositoryProvider)
          .addAttachment(
            workerId: widget.person.id,
            bytes: file.bytes,
            fileName: file.fileName,
            contentType: file.mimeType,
            documentId: _documentId,
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
            idempotencyKey: key,
          );
      if (!mounted) return;
      peopleToast(context, PS.t(PS.attachmentAdded, _language));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            error is YorksV1DomainException &&
                error.code == YorksV1DomainErrorCode.invalidInput
            ? PS.t(PS.errFileType, _language)
            : peopleErrorText(error, _language);
      });
    }
  }

  String _documentText(PeopleDocument document) => [
    peopleKindLabel(document.kind, _language, label: document.label),
    if (document.number != null) document.number!,
    if (document.expiryDate != null) peopleDate(document.expiryDate),
    if (!document.isCurrent) PS.t(PS.endedShort, _language),
  ].join(' · ');

  Widget _fields() {
    final language = _language;
    final file = _file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.person.name,
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.md),
        if (file != null)
          Container(
            key: const ValueKey('people-attachment-chosen'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.insert_drive_file_outlined,
                  color: AppColors.blue,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    file.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  PeopleAttachment(
                    id: '',
                    fileName: file.fileName,
                    contentType: file.mimeType,
                    sizeBytes: file.bytes.lengthInBytes,
                    objectPath: '',
                  ).sizeText,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            key: const ValueKey('people-attachment-choose'),
            onPressed: _busy ? null : _choose,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(
              PS.t(
                file == null ? PS.chooseFile : PS.chooseAnotherFile,
                language,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          PS.t(PS.fileTypes, language),
          style: AppTypography.labelSmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String?>(
          key: const ValueKey('people-attachment-document'),
          initialValue: _documentId,
          isExpanded: true,
          decoration: InputDecoration(labelText: PS.t(PS.copyOf, language)),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(PS.t(PS.notADocument, language)),
            ),
            for (final document in _documents)
              DropdownMenuItem<String?>(
                value: document.id,
                child: Text(
                  _documentText(document),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) {
                  _documentId = value;
                  _changed();
                },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('people-attachment-title'),
          controller: _title,
          enabled: !_busy,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: PS.t(PS.attachmentTitle, language),
            hintText: PS.t(PS.attachmentTitleHint, language),
          ),
          onChanged: (_) => _changed(),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            key: const ValueKey('people-attachment-error'),
            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }

  Widget _saveButton() => FilledButton.icon(
    key: const ValueKey('people-attachment-save'),
    onPressed: _file == null || _busy ? null : _save,
    icon: _busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.attach_file_rounded),
    label: Text(
      _busy ? PS.t(PS.uploading, _language) : PS.t(PS.attach, _language),
    ),
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    final title = PS.t(PS.addAttachment, _language);
    if (widget.fullScreen) {
      return Dialog.fullscreen(
        key: const ValueKey('people-attachment-dialog'),
        backgroundColor: AppColors.surface,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            leading: IconButton(
              tooltip: PS.t(PS.cancel, _language),
              icon: const Icon(Icons.close_rounded),
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
            title: Text(title),
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [_fields()],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(height: 48, child: _saveButton()),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      key: const ValueKey('people-attachment-dialog'),
      title: Row(
        children: [
          const Icon(Icons.attach_file_rounded, color: AppColors.blue),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(title)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: _fields()),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(PS.t(PS.cancel, _language)),
        ),
        _saveButton(),
      ],
    );
  }
}
