/// Attachments on a record — a person (People records) or a company record
/// (Company documents): the same section, file list, paperclip count and
/// add dialog on both, so they look and behave alike
/// (PRODUCT_DECISIONS sections 47 and 48).
///
/// A file opens through a five-minute link that storage rechecks. Nothing
/// is shown as attached until the server confirms; removing needs a reason
/// and keeps the file and the history.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_attachments.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../shared/services/yorks_v1_document_file_service.dart';
import '../../workforce/presentation/attendance/attendance_dialogs.dart'
    show showAttendanceCommandDialog;
import 'people_kit.dart';

/// Opens a link in a new tab or the device's viewer (overridden in tests).
final yorksV1OpenLinkProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) =>
      (uri) => launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      ),
);

IconData recordAttachmentIcon(RecordAttachment item) => item.isPdf
    ? Icons.picture_as_pdf_outlined
    : item.isImage
    ? Icons.image_outlined
    : item.isSheet
    ? Icons.table_chart_outlined
    : Icons.description_outlined;

/// Opens a stored file through a short-lived [link].
Future<void> openRecordAttachment(
  BuildContext context,
  WidgetRef ref,
  Future<String> Function() link,
) async {
  final language = ref.read(languageProvider);
  try {
    final url = await link();
    final opened = await ref.read(yorksV1OpenLinkProvider)(Uri.parse(url));
    if (!opened && context.mounted) {
      peopleToast(context, PS.t(PS.errOpenFile, language));
    }
  } catch (error) {
    if (context.mounted) peopleToast(context, peopleErrorText(error, language));
  }
}

/// Asks for a reason, then runs [remove]. Resolves to true once removed.
Future<bool> confirmRemoveRecordAttachment(
  BuildContext context, {
  required AppLanguage language,
  required RecordAttachment item,
  required String summary,
  required Future<void> Function(String reason, String idempotencyKey) remove,
}) async {
  final key = const Uuid().v4();
  final reason = await showAttendanceCommandDialog(
    context,
    language: language,
    title: PS.t(PS.removeAttachmentTitle, language, {
      'file': item.title ?? item.fileName,
    }),
    summary: summary,
    body: PS.t(PS.removeAttachmentBody, language),
    fieldLabel: PS.t(PS.reason, language),
    confirmLabel: PS.t(PS.remove, language),
    destructive: true,
    command: (text) async {
      try {
        await remove(text, key);
        return null;
      } catch (error) {
        return peopleErrorText(error, language);
      }
    },
  );
  if (reason == null) return false;
  if (context.mounted) {
    peopleToast(context, PS.t(PS.attachmentRemoved, language));
  }
  return true;
}

/// The Attachments section of a record.
class RecordAttachmentsSection extends StatelessWidget {
  const RecordAttachmentsSection({
    super.key,
    required this.keyPrefix,
    required this.attachments,
    required this.canManage,
    required this.language,
    required this.description,
    required this.documentText,
    required this.onAdd,
    required this.onOpen,
    required this.onRemove,
    required this.onRetry,
  });

  /// `people` or `company`, for the widget keys.
  final String keyPrefix;
  final AsyncValue<RecordAttachments> attachments;
  final bool canManage;
  final AppLanguage language;
  final String description;

  /// "Passport · P123" for the document a file copies, or null.
  final String? Function(RecordAttachment item) documentText;
  final VoidCallback onAdd;
  final ValueChanged<RecordAttachment> onOpen;
  final ValueChanged<RecordAttachment> onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final manage = attachments.valueOrNull?.canManage ?? canManage;
    return Column(
      key: ValueKey('$keyPrefix-attachments'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PeopleSectionHeading(
          title: PS.t(PS.attachments, language),
          description: description,
          trailing: manage
              ? FilledButton.tonalIcon(
                  key: ValueKey('$keyPrefix-attachment-add'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(44, 44),
                  ),
                  onPressed: onAdd,
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: Text(PS.t(PS.addAttachment, language)),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        PeopleSurface(
          padding: EdgeInsets.zero,
          child: attachments.when(
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
                    onPressed: onRetry,
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
                          keyPrefix: keyPrefix,
                          item: item,
                          document: documentText(item),
                          language: language,
                          canManage: data.canManage,
                          onOpen: () => onOpen(item),
                          onRemove: () => onRemove(item),
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
    required this.keyPrefix,
    required this.item,
    required this.document,
    required this.language,
    required this.canManage,
    required this.onOpen,
    required this.onRemove,
  });

  final String keyPrefix;
  final RecordAttachment item;
  final String? document;
  final AppLanguage language;
  final bool canManage;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final document = this.document;
    return InkWell(
      key: ValueKey('$keyPrefix-attachment-${item.id}'),
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
                recordAttachmentIcon(item),
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
              key: ValueKey('$keyPrefix-attachment-open-${item.id}'),
              tooltip: PS.t(PS.openFile, language),
              onPressed: onOpen,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
            ),
            if (canManage)
              IconButton(
                key: ValueKey('$keyPrefix-attachment-remove-${item.id}'),
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

/// A paperclip and how many files a record (or one document) has.
class RecordAttachmentCount extends StatelessWidget {
  const RecordAttachmentCount({
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

/// What the add dialog hands to the repository.
typedef RecordAttachmentUpload = ({
  Uint8List bytes,
  String fileName,
  String contentType,
  String? documentId,
  String? title,
  String idempotencyKey,
});

/// Opens the add dialog. [documents] are the record's documents a file may
/// copy, as (id, label). Resolves to true once the server recorded the file.
Future<bool?> showRecordAttachmentDialog(
  BuildContext context, {
  required String keyPrefix,
  required String ownerName,
  required List<(String, String)> documents,
  required Future<void> Function(RecordAttachmentUpload upload) upload,
  String? documentId,
}) {
  final phone = MediaQuery.sizeOf(context).width < 600;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RecordAttachmentDialog(
      keyPrefix: keyPrefix,
      ownerName: ownerName,
      documents: documents,
      upload: upload,
      documentId: documentId,
      fullScreen: phone,
    ),
  );
}

class RecordAttachmentDialog extends ConsumerStatefulWidget {
  const RecordAttachmentDialog({
    super.key,
    required this.keyPrefix,
    required this.ownerName,
    required this.documents,
    required this.upload,
    this.documentId,
    this.fullScreen = false,
  });

  final String keyPrefix;
  final String ownerName;
  final List<(String, String)> documents;
  final Future<void> Function(RecordAttachmentUpload upload) upload;

  /// The document the file copies, when opened from that document's row.
  final String? documentId;
  final bool fullScreen;

  @override
  ConsumerState<RecordAttachmentDialog> createState() =>
      _RecordAttachmentDialogState();
}

class _RecordAttachmentDialogState
    extends ConsumerState<RecordAttachmentDialog> {
  final _title = TextEditingController();
  YorksV1SelectedDocument? _file;
  late String? _documentId = widget.documentId;
  bool _busy = false;
  String? _error;

  /// Kept across retries of the same file, so a retry never stores twice.
  String? _key;

  AppLanguage get _language => ref.read(languageProvider);
  String get _prefix => widget.keyPrefix;

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
      await widget.upload((
        bytes: file.bytes,
        fileName: file.fileName,
        contentType: file.mimeType,
        documentId: _documentId,
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
        idempotencyKey: key,
      ));
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

  Widget _fields() {
    final language = _language;
    final file = _file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.ownerName,
          style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.md),
        if (file != null)
          Container(
            key: ValueKey('$_prefix-attachment-chosen'),
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
                  recordAttachmentSize(file.bytes.lengthInBytes),
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
            key: ValueKey('$_prefix-attachment-choose'),
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
          key: ValueKey('$_prefix-attachment-document'),
          initialValue: _documentId,
          isExpanded: true,
          decoration: InputDecoration(labelText: PS.t(PS.copyOf, language)),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(PS.t(PS.notADocument, language)),
            ),
            for (final (id, label) in widget.documents)
              DropdownMenuItem<String?>(
                value: id,
                child: Text(label, overflow: TextOverflow.ellipsis),
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
          key: ValueKey('$_prefix-attachment-title'),
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
            key: ValueKey('$_prefix-attachment-error'),
            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }

  Widget _saveButton() => FilledButton.icon(
    key: ValueKey('$_prefix-attachment-save'),
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
        key: ValueKey('$_prefix-attachment-dialog'),
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
      key: ValueKey('$_prefix-attachment-dialog'),
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
