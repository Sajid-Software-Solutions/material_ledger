/// Bulk upload: a whole folder of scans attached at once, each file matched
/// to a person (People) or company record (Company documents) and to one of
/// their documents from its file name (PRODUCT_DECISIONS section 49).
///
/// Every match is shown first and can be changed; nothing is sent until
/// Upload. Files are uploaded one at a time with the same commands as a
/// single attachment, each under its own idempotency key, so a retry never
/// stores a file twice. A file that fails keeps its row and can be tried
/// again; the others stay attached. Files are read only when uploaded.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_attachments.dart';
import '../../../shared/models/yorks_v1_people.dart' show PeopleDocumentStatus;
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../shared/services/yorks_v1_bulk_attach.dart';
import '../../../shared/services/yorks_v1_multi_file_service.dart';
import 'people_kit.dart';

/// One file to upload, as the dialog hands it to the repository.
typedef BulkAttachUpload = ({
  String ownerId,
  Uint8List bytes,
  String fileName,
  String contentType,
  String? documentId,
  String idempotencyKey,
});

/// Opens bulk upload. Resolves to how many files were attached.
Future<int?> showBulkAttachDialog(
  BuildContext context, {
  required String keyPrefix,
  required String hint,
  required String chooseOwnerLabel,
  required Future<List<BulkAttachOwner>> Function() loadOwners,
  required Map<String, List<String>> kinds,
  required String Function(BulkAttachDocument document) documentLabel,
  required Future<void> Function(BulkAttachUpload upload) upload,
}) {
  final phone = MediaQuery.sizeOf(context).width < 760;
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BulkAttachDialog(
      keyPrefix: keyPrefix,
      hint: hint,
      chooseOwnerLabel: chooseOwnerLabel,
      loadOwners: loadOwners,
      kinds: kinds,
      documentLabel: documentLabel,
      upload: upload,
      fullScreen: phone,
    ),
  );
}

enum _State { ready, needsOwner, unsupported, uploading, done, failed }

final class _Row {
  _Row(this.file, this.guess)
    : ownerId = guess.ownerId,
      documentId = guess.documentId;

  final YorksV1PickedFile file;
  final BulkAttachGuess guess;
  String? ownerId;
  String? documentId;
  bool chosenByHand = false;
  _State uploadState = _State.ready;
  String? error;

  /// Stable while the file, owner and document stay the same, so a retry
  /// reuses the stored file.
  String key = const Uuid().v4();

  _State get state {
    if (!file.attachable) return _State.unsupported;
    if (uploadState != _State.ready) return uploadState;
    return ownerId == null ? _State.needsOwner : _State.ready;
  }
}

class BulkAttachDialog extends ConsumerStatefulWidget {
  const BulkAttachDialog({
    super.key,
    required this.keyPrefix,
    required this.hint,
    required this.chooseOwnerLabel,
    required this.loadOwners,
    required this.kinds,
    required this.documentLabel,
    required this.upload,
    this.fullScreen = false,
  });

  final String keyPrefix;
  final String hint;
  final String chooseOwnerLabel;
  final Future<List<BulkAttachOwner>> Function() loadOwners;
  final Map<String, List<String>> kinds;
  final String Function(BulkAttachDocument document) documentLabel;
  final Future<void> Function(BulkAttachUpload upload) upload;
  final bool fullScreen;

  @override
  ConsumerState<BulkAttachDialog> createState() => _BulkAttachDialogState();
}

class _BulkAttachDialogState extends ConsumerState<BulkAttachDialog> {
  late Future<List<BulkAttachOwner>> _owners = widget.loadOwners();
  List<BulkAttachOwner> _loaded = const [];
  final _rows = <_Row>[];
  bool _uploading = false;
  int _progress = 0;
  int _batch = 0;
  int _attached = 0;

  AppLanguage get _language => ref.read(languageProvider);
  String get _prefix => widget.keyPrefix;

  BulkAttachOwner? _owner(String? id) =>
      _loaded.where((owner) => owner.id == id).firstOrNull;

  int _count(_State state) => _rows.where((row) => row.state == state).length;

  Future<void> _choose() async {
    final files = await ref.read(yorksV1MultiFileServiceProvider).selectFiles();
    if (files.isEmpty || !mounted) return;
    setState(() {
      for (final file in files) {
        // The same file chosen twice is kept once.
        if (_rows.any(
          (row) => row.file.name == file.name && row.file.size == file.size,
        )) {
          continue;
        }
        _rows.add(
          _Row(file, bulkAttachGuess(file.name, _loaded, kinds: widget.kinds)),
        );
      }
    });
  }

  Future<void> _pickOwner(_Row row) async {
    final owner = await showDialog<BulkAttachOwner>(
      context: context,
      builder: (_) => _OwnerPicker(
        keyPrefix: _prefix,
        title: widget.chooseOwnerLabel,
        owners: _loaded,
        language: _language,
      ),
    );
    if (owner == null || !mounted) return;
    setState(() {
      row
        ..ownerId = owner.id
        ..chosenByHand = true
        ..key = const Uuid().v4()
        ..documentId = row.guess.kind == null
            ? null
            : bulkAttachDocumentFor(owner, row.guess.kind!);
      if (row.uploadState == _State.failed) row.uploadState = _State.ready;
    });
  }

  Future<void> _uploadAll() async {
    final queue = [
      for (final row in _rows)
        if (row.state == _State.ready || row.state == _State.failed) row,
    ];
    if (queue.isEmpty) return;
    setState(() {
      _uploading = true;
      _progress = 0;
      _batch = queue.length;
    });
    for (final row in queue) {
      if (!mounted) return;
      setState(() {
        _progress++;
        row
          ..uploadState = _State.uploading
          ..error = null;
      });
      try {
        final bytes = await row.file.read();
        await widget.upload((
          ownerId: row.ownerId!,
          bytes: bytes,
          fileName: row.file.name,
          contentType: row.file.contentType!,
          documentId: row.documentId,
          idempotencyKey: row.key,
        ));
        if (!mounted) return;
        setState(() {
          row.uploadState = _State.done;
          _attached++;
        });
      } catch (error) {
        if (!mounted) return;
        setState(() {
          row
            ..uploadState = _State.failed
            ..error = peopleErrorText(error, _language);
        });
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  String _matchNote(_Row row) {
    final language = _language;
    if (row.chosenByHand) return PS.t(PS.bulkChosen, language);
    return PS.t(switch (row.guess.by) {
      BulkAttachBy.number => PS.bulkByNumber,
      BulkAttachBy.name => PS.bulkByName,
      BulkAttachBy.ambiguous => PS.bulkAmbiguous,
      BulkAttachBy.none => PS.bulkNotMatched,
    }, language);
  }

  Widget _statusChip(_Row row) {
    final language = _language;
    final (text, colors) = switch (row.state) {
      _State.ready => (
        PS.t(PS.bulkWaiting, language),
        peopleStatusColors(PeopleDocumentStatus.noExpiry),
      ),
      // Not matched, or more than one match: the badge says which.
      _State.needsOwner => (
        _matchNote(row),
        peopleStatusColors(PeopleDocumentStatus.expiring),
      ),
      _State.unsupported => (
        PS.t(PS.bulkUnsupported, language),
        peopleStatusColors(PeopleDocumentStatus.expired),
      ),
      _State.uploading => (
        PS.t(PS.uploading, language),
        peopleStatusColors(PeopleDocumentStatus.noExpiry),
      ),
      _State.done => (
        PS.t(PS.bulkUploaded, language),
        peopleStatusColors(PeopleDocumentStatus.ok),
      ),
      _State.failed => (
        row.error ?? PS.t(PS.bulkFailedCount, language, {'n': 1}),
        peopleStatusColors(PeopleDocumentStatus.expired),
      ),
    };
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall.copyWith(
          color: colors.color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _rowTile(_Row row) {
    final language = _language;
    final owner = _owner(row.ownerId);
    final locked =
        _uploading ||
        row.state == _State.done ||
        row.state == _State.unsupported;
    return Container(
      key: ValueKey('$_prefix-bulk-row-${row.file.name}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                row.state == _State.done
                    ? Icons.check_circle_rounded
                    : Icons.insert_drive_file_outlined,
                size: 20,
                color: row.state == _State.done
                    ? AppColors.success
                    : AppColors.blue,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  row.file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                recordAttachmentSize(row.file.size),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.muted,
                ),
              ),
              IconButton(
                key: ValueKey('$_prefix-bulk-remove-${row.file.name}'),
                tooltip: PS.t(PS.remove, language),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: _uploading || row.state == _State.done
                    ? null
                    : () => setState(() => _rows.remove(row)),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          if (row.state != _State.unsupported) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    key: ValueKey('$_prefix-bulk-owner-${row.file.name}'),
                    onPressed: locked ? null : () => _pickOwner(row),
                    icon: Icon(
                      owner == null
                          ? Icons.person_search_outlined
                          : Icons.person_outline_rounded,
                      size: 18,
                    ),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: Text(
                        owner?.name ?? widget.chooseOwnerLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                if (owner != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 200,
                      maxWidth: 340,
                    ),
                    child: DropdownButtonFormField<String?>(
                      key: ValueKey(
                        '$_prefix-bulk-document-${row.file.name}-${owner.id}',
                      ),
                      initialValue: row.documentId,
                      isExpanded: true,
                      isDense: true,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.ink,
                      ),
                      decoration: InputDecoration(
                        labelText: PS.t(PS.copyOf, language),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(PS.t(PS.notADocument, language)),
                        ),
                        for (final document in owner.documents)
                          DropdownMenuItem<String?>(
                            value: document.id,
                            child: Text(
                              widget.documentLabel(document),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: locked
                          ? null
                          : (value) => setState(() {
                              row
                                ..documentId = value
                                ..key = const Uuid().v4();
                            }),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _statusChip(row),
              if (row.ownerId != null &&
                  row.state != _State.unsupported &&
                  row.state != _State.done)
                Text(
                  _matchNote(row),
                  style: AppTypography.labelSmall.copyWith(
                    color: row.ownerId == null
                        ? AppColors.warning
                        : AppColors.muted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final language = _language;
    return FutureBuilder<List<BulkAttachOwner>>(
      future: _owners,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: PeopleMessage(
              icon: Icons.cloud_off_outlined,
              title: peopleErrorText(snapshot.error, language),
              action: PS.t(PS.retry, language),
              onPressed: () => setState(() => _owners = widget.loadOwners()),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        _loaded = snapshot.data!;
        return ListView(
          key: ValueKey('$_prefix-bulk-list'),
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.hint,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        key: ValueKey('$_prefix-bulk-choose'),
                        onPressed: _uploading ? null : _choose,
                        icon: const Icon(Icons.drive_folder_upload_outlined),
                        label: Text(
                          PS.t(
                            _rows.isEmpty ? PS.bulkChoose : PS.bulkAddMore,
                            language,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_rows.isNotEmpty)
              const Divider(height: 1, color: AppColors.line),
            for (final row in _rows) _rowTile(row),
          ],
        );
      },
    );
  }

  Widget _footer() {
    final language = _language;
    final ready = _count(_State.ready) + _count(_State.failed);
    final parts = [
      if (_attached > 0) PS.t(PS.bulkAttached, language, {'n': _attached}),
      if (ready > 0) PS.t(PS.bulkReady, language, {'n': ready}),
      if (_count(_State.needsOwner) > 0)
        PS.t(PS.bulkToMatch, language, {'n': _count(_State.needsOwner)}),
      if (_count(_State.unsupported) > 0)
        PS.t(PS.bulkCannot, language, {'n': _count(_State.unsupported)}),
      if (_count(_State.failed) > 0)
        PS.t(PS.bulkFailedCount, language, {'n': _count(_State.failed)}),
    ];
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (parts.isNotEmpty) ...[
                Text(
                  parts.join(' · '),
                  key: ValueKey('$_prefix-bulk-summary'),
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: [
                  TextButton(
                    key: ValueKey('$_prefix-bulk-close'),
                    onPressed: _uploading
                        ? null
                        : () => Navigator.of(context).pop(_attached),
                    child: Text(PS.t(PS.close, language)),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 44,
                    child: FilledButton.icon(
                      key: ValueKey('$_prefix-bulk-upload'),
                      onPressed: _uploading || ready == 0 ? null : _uploadAll,
                      icon: _uploading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        _uploading
                            ? PS.t(PS.bulkUploading, language, {
                                'i': _progress,
                                'n': _batch,
                              })
                            : PS.t(PS.bulkUploadN, language, {'n': ready}),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    final title = PS.t(PS.bulkTitle, _language);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _body()),
        _footer(),
      ],
    );
    if (widget.fullScreen) {
      return Dialog.fullscreen(
        key: ValueKey('$_prefix-bulk-dialog'),
        backgroundColor: AppColors.surface,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(automaticallyImplyLeading: false, title: Text(title)),
          body: content,
        ),
      );
    }
    return Dialog(
      key: ValueKey('$_prefix-bulk-dialog'),
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                0,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.drive_folder_upload_outlined,
                    color: AppColors.blue,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

/// Choosing the person or record for one file, by name or number.
class _OwnerPicker extends StatefulWidget {
  const _OwnerPicker({
    required this.keyPrefix,
    required this.title,
    required this.owners,
    required this.language,
  });

  final String keyPrefix;
  final String title;
  final List<BulkAttachOwner> owners;
  final AppLanguage language;

  @override
  State<_OwnerPicker> createState() => _OwnerPickerState();
}

class _OwnerPickerState extends State<_OwnerPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<BulkAttachOwner> get _matches {
    final words = bulkAttachWords(_search.text);
    if (words.isEmpty) return widget.owners;
    return [
      for (final owner in widget.owners)
        if (words.every((word) {
          final haystack = bulkAttachWords(
            '${owner.name} ${owner.subtitle} ${owner.codes.join(' ')}',
          ).join(' ');
          return haystack.contains(word);
        }))
          owner,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return AlertDialog(
      key: ValueKey('${widget.keyPrefix}-bulk-owner-picker'),
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: ValueKey('${widget.keyPrefix}-bulk-owner-search'),
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: PS.t(PS.bulkSearch, widget.language),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final owner = matches[index];
                  return ListTile(
                    key: ValueKey('${widget.keyPrefix}-bulk-owner-${owner.id}'),
                    minTileHeight: 48,
                    title: Text(owner.name),
                    subtitle: owner.subtitle.isEmpty
                        ? null
                        : Text(owner.subtitle),
                    onTap: () => Navigator.of(context).pop(owner),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(PS.t(PS.cancel, widget.language)),
        ),
      ],
    );
  }
}
