import 'dart:async';

import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/zoom/yorks_workspace_zoom.dart';
import '../../../../core/constants/constants.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/models/yorks_v1_command_outcome.dart';
import '../../../../shared/models/yorks_v1_document_strings.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/models/yorks_v1_shell_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_provider.dart';
import '../../../../shared/providers/yorks_v1_documents_repository_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/services/yorks_v1_document_file_service.dart';

/// Controlled documents are created as immutable Storage versions. The screen
/// never receives a signed path: every read and write remains server-authorized.
class YorksV1DocumentsScreen extends ConsumerStatefulWidget {
  const YorksV1DocumentsScreen({
    super.key,
    required this.projectId,
    this.focusEntityType,
    this.focusEntityId,
    this.embedded = false,
  });

  final String projectId;
  final String? focusEntityType;
  final String? focusEntityId;
  final bool embedded;

  @override
  ConsumerState<YorksV1DocumentsScreen> createState() =>
      _YorksV1DocumentsScreenState();
}

class _YorksV1DocumentsScreenState
    extends ConsumerState<YorksV1DocumentsScreen> {
  bool _working = false;
  YorksV1DocumentUploadInput? _activeUpload;
  String? _uploadOwner;

  YorksV1DocumentEntityType get _targetEntityType =>
      YorksV1DocumentEntityType.fromWireValue(widget.focusEntityType) ??
      YorksV1DocumentEntityType.project;

  String get _targetEntityId => widget.focusEntityId ?? widget.projectId;

  bool get _hasFocusedRecord =>
      widget.focusEntityId != null &&
      YorksV1DocumentEntityType.fromWireValue(widget.focusEntityType) != null;

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final workspace = ref.watch(
      yorksV1DocumentWorkspaceProvider(widget.projectId),
    );
    final mobile = YorksMobileUi.isActive(context);
    final compactRoute =
        MediaQuery.sizeOf(context).width < AppSpacing.yorksV1DesktopBreakpoint;
    final content = workspace.when(
      loading: () => mobile
          ? const _MobileDocumentsLoading()
          : const Center(child: CircularProgressIndicator()),
      error: (_, _) => mobile
          ? _MobileDocumentsError(onRetry: _refresh)
          : _ErrorState(onRetry: _refresh),
      data: (value) => mobile
          ? _MobileDocumentsBody(
              workspace: value,
              targetEntityType: _targetEntityType,
              targetEntityId: _targetEntityId,
              focusedRecord: _hasFocusedRecord,
              busy: _working,
              onCreateDocument: () => _uploadNewVersion(),
              onUploadVersion: (document) =>
                  _uploadNewVersion(document: document),
              onDownload: _download,
              onShare: _share,
              onReadBytes: _readBytes,
              onLink: _link,
              onRemove: _remove,
            )
          : _WorkspaceBody(
              workspace: value,
              language: language,
              targetEntityType: _targetEntityType,
              targetEntityId: _targetEntityId,
              focusedRecord: _hasFocusedRecord,
              busy: _working,
              onUploadVersion: (document) =>
                  _uploadNewVersion(document: document),
              onDownload: _download,
              onLink: _link,
              onRemove: _remove,
              showPageHeader: widget.embedded || !compactRoute,
              onCreateDocument: () => _uploadNewVersion(),
              onDropDocuments: _uploadDroppedDocuments,
              onDropError: () =>
                  _snack(context, YorksV1DocumentStrings.uploadFailed.primary),
              onLinkExisting: () => _linkExistingDocument(value),
            ),
    );
    final owner = ref.watch(yorksV1AuthUserIdProvider);
    Map<String, dynamic>? pending;
    try {
      pending = ref
          .watch(yorksV1DocumentUploadJournalProvider)
          .pending(widget.projectId)
          .where(
            (item) =>
                item['operation'] == 'v1_prepare_document_upload' &&
                item['entity_type'] == _targetEntityType.wireValue &&
                item['entity_id'] == _targetEntityId,
          )
          .firstOrNull;
    } catch (_) {
      // A corrupt/unknown journal is never overwritten to make the UI recover.
      // The repository fails closed before starting a new transfer.
    }
    final active = _uploadOwner == owner ? _activeUpload : null;
    final showUploadStatus =
        workspace.hasValue &&
        !workspace.hasError &&
        (active != null || pending != null);
    final body = showUploadStatus
        ? Column(
            children: [
              Expanded(child: content),
              Padding(
                padding: const EdgeInsets.all(16),
                child: _uploadStatus(language, active, pending),
              ),
            ],
          )
        : content;
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: mobile
          ? PreferredSize(
              preferredSize: const Size.fromHeight(YorksMobileUi.appBarHeight),
              child: YorksMobileAppBar(
                title: YorksV1DocumentStrings.documents.primary,
                leading: YorksMobileIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    YorksMobileIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: YorksV1DocumentStrings.retry.primary,
                      onPressed: _working ? () {} : _refresh,
                    ),
                    YorksMobileIconButton(
                      icon: Icons.add_rounded,
                      tooltip: YorksV1DocumentStrings.addDocument.primary,
                      onPressed: _working ? () {} : () => _uploadNewVersion(),
                    ),
                  ],
                ),
              ),
            )
          : compactRoute
          ? AppBar(
              backgroundColor: AppColors.surface,
              surfaceTintColor: Colors.transparent,
              title: _CopyText(
                copy: YorksV1DocumentStrings.documents,
                language: language,
                style: AppTypography.titleLarge.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: YorksV1DocumentStrings.retry.primary,
                  onPressed: _working ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            )
          : null,
      floatingActionButton: compactRoute && !mobile && !showUploadStatus
          ? FloatingActionButton.extended(
              onPressed: _working ? null : () => _uploadNewVersion(),
              icon: _working
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(YorksV1DocumentStrings.addDocument.primary),
            )
          : null,
      body: body,
    );
  }

  Future<void> _uploadNewVersion({YorksV1Document? document}) async {
    if (_working) return;
    final role = ref.read(yorksV1CurrentRoleProvider);
    final classification =
        document?.classification ?? await _classification(role);
    if (classification == null) return;
    final selected = await ref
        .read(yorksV1DocumentFileServiceProvider)
        .selectDocument();
    if (selected == null || !mounted) return;
    await _uploadSelectedDocument(
      selected,
      classification: classification,
      document: document,
    );
  }

  Future<void> _uploadSelectedDocument(
    YorksV1SelectedDocument selected, {
    required YorksV1DocumentClassification classification,
    YorksV1Document? document,
    String? documentId,
    String? idempotencyKey,
  }) async {
    if (_working) return;
    final owner = ref.read(yorksV1AuthUserIdProvider);
    final input = YorksV1DocumentUploadInput(
      projectId: widget.projectId,
      entityType: _targetEntityType,
      entityId: _targetEntityId,
      classification: classification,
      fileName: selected.fileName,
      mimeType: selected.mimeType,
      bytes: selected.bytes,
      documentId: documentId ?? document?.id,
      idempotencyKey: idempotencyKey ?? const Uuid().v4(),
    );
    setState(() {
      _working = true;
      _activeUpload = input;
      _uploadOwner = owner;
    });
    try {
      await ref.read(yorksV1DocumentsRepositoryProvider).upload(input);
      if (!mounted || owner != ref.read(yorksV1AuthUserIdProvider)) return;
      _refresh();
      _snack(context, YorksV1DocumentStrings.uploadSucceeded.primary);
    } on YorksV1CommittedViewUnavailable {
      if (!mounted || owner != ref.read(yorksV1AuthUserIdProvider)) return;
      _refresh();
      _snack(
        context,
        YorksV1DocumentStrings.uploadConfirmedRefreshPending.primary,
      );
    } on YorksV1DocumentUploadNotSent {
      if (mounted && owner == ref.read(yorksV1AuthUserIdProvider)) {
        _snack(context, YorksV1DocumentStrings.uploadNotSent.primary);
      }
    } catch (error) {
      if (mounted && owner == ref.read(yorksV1AuthUserIdProvider)) {
        _snack(
          context,
          (error is YorksV1DomainException &&
                  {
                    YorksV1DomainErrorCode.unauthorized,
                    YorksV1DomainErrorCode.invalidInput,
                    YorksV1DomainErrorCode.featureDisabled,
                  }.contains(error.code))
              ? YorksV1DocumentStrings.uploadFailed.primary
              : YorksV1DocumentStrings.uploadOutcomeUnknown.primary,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _activeUpload = null;
        });
      }
    }
  }

  Widget _uploadStatus(
    AppLanguage language,
    YorksV1DocumentUploadInput? active,
    Map<String, dynamic>? pending,
  ) {
    final fileName = active?.fileName ?? pending?['file_name'] as String? ?? '';
    final bytes = active?.bytes.length ?? pending?['byte_size'] as int? ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$fileName · ${_documentSize(bytes)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              (active != null
                      ? YorksV1DocumentStrings.uploadInProgress
                      : YorksV1DocumentStrings.uploadOutcomeUnknown)
                  .active(language),
            ),
            if (active != null) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ] else if (pending != null)
              TextButton.icon(
                onPressed: _working ? null : () => _resumeUpload(pending),
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  YorksV1DocumentStrings.reselectUpload.active(language),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _resumeUpload(Map<String, dynamic> pending) async {
    if (_working) return;
    final owner = ref.read(yorksV1AuthUserIdProvider);
    final selected = await ref
        .read(yorksV1DocumentFileServiceProvider)
        .selectDocument();
    if (!mounted ||
        selected == null ||
        owner != ref.read(yorksV1AuthUserIdProvider)) {
      return;
    }
    if (selected.fileName != pending['file_name'] ||
        selected.mimeType != pending['mime_type'] ||
        selected.bytes.length != pending['byte_size'] ||
        sha256.convert(selected.bytes).toString() != pending['content_hash']) {
      _snack(context, YorksV1DocumentStrings.uploadFileMismatch.primary);
      return;
    }
    final classification = YorksV1DocumentClassification.fromWireValue(
      pending['classification'],
    );
    if (classification == null || pending['key'] is! String) return;
    await _uploadSelectedDocument(
      selected,
      classification: classification,
      documentId: pending['document_id'] as String?,
      idempotencyKey: pending['key'] as String,
    );
  }

  Future<void> _uploadDroppedDocuments(
    List<YorksV1SelectedDocument> selectedDocuments,
  ) async {
    if (selectedDocuments.isEmpty || _working) return;
    final classification = await _classification(
      ref.read(yorksV1CurrentRoleProvider),
    );
    if (classification == null || !mounted) return;
    setState(() => _working = true);
    final owner = ref.read(yorksV1AuthUserIdProvider);
    var uploaded = 0;
    try {
      for (final selected in selectedDocuments) {
        if (!mounted || owner != ref.read(yorksV1AuthUserIdProvider)) return;
        final input = YorksV1DocumentUploadInput(
          projectId: widget.projectId,
          entityType: _targetEntityType,
          entityId: _targetEntityId,
          classification: classification,
          fileName: selected.fileName,
          mimeType: selected.mimeType,
          bytes: selected.bytes,
          idempotencyKey: const Uuid().v4(),
        );
        setState(() {
          _activeUpload = input;
          _uploadOwner = owner;
        });
        try {
          await ref.read(yorksV1DocumentsRepositoryProvider).upload(input);
        } on YorksV1CommittedViewUnavailable {
          // Keep processing other explicitly selected files; this version is
          // already committed and must not be uploaded as a new revision.
        }
        uploaded++;
      }
      if (!mounted) return;
      _refresh();
      _snack(context, YorksV1DocumentStrings.uploadSucceeded.primary);
    } catch (_) {
      if (mounted) {
        _refresh();
        _snack(context, YorksV1DocumentStrings.uploadOutcomeUnknown.primary);
      }
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _activeUpload = null;
        });
      }
    }
    // A partial browser drop is intentionally visible after refresh. Each
    // accepted file is its own idempotent controlled-document command.
    if (uploaded < selectedDocuments.length && mounted) _refresh();
  }

  Future<void> _linkExistingDocument(YorksV1DocumentWorkspace workspace) async {
    final available = workspace.documents
        .where(
          (document) =>
              !document.isLinkedTo(_targetEntityType, _targetEntityId),
        )
        .toList(growable: false);
    if (available.isEmpty) return;
    final selected = await showDialog<YorksV1Document>(
      context: context,
      animationStyle: AnimationStyle.noAnimation,
      builder: (dialogContext) => AlertDialog(
        title: Text(YorksV1DocumentStrings.linkExistingDocument.primary),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 520),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: available.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final document = available[index];
              return ListTile(
                leading: Icon(
                  _iconForMime(document.currentVersion.mimeType),
                  color: AppColors.primary,
                ),
                title: Text(document.currentVersion.fileName),
                subtitle: Text(
                  '${YorksV1DocumentStrings.revision.primary} '
                  '${document.currentVersion.revisionNumber}',
                ),
                onTap: () => Navigator.of(dialogContext).pop(document),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(YorksV1DocumentStrings.cancel.primary),
          ),
        ],
      ),
    );
    if (selected != null && mounted) await _link(selected);
  }

  Future<YorksV1DocumentClassification?> _classification(
    YorksV1Role? role,
  ) async {
    final available = [
      YorksV1DocumentClassification.operational,
      if (role == YorksV1Role.procurement || role == YorksV1Role.admin)
        YorksV1DocumentClassification.commercial,
      if (role == YorksV1Role.admin)
        YorksV1DocumentClassification.adminRestricted,
    ];
    var selected = available.first;
    return showDialog<YorksV1DocumentClassification>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(YorksV1DocumentStrings.selectClassification.primary),
          content: DropdownButtonFormField<YorksV1DocumentClassification>(
            initialValue: selected,
            decoration: InputDecoration(
              labelText: YorksV1DocumentStrings.classification.primary,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final value in available)
                DropdownMenuItem(
                  value: value,
                  child: Text(yorksV1DocumentClassificationCopy(value).primary),
                ),
            ],
            onChanged: (value) {
              if (value != null) setDialogState(() => selected = value);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(YorksV1DocumentStrings.cancel.primary),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(selected),
              child: Text(YorksV1DocumentStrings.confirm.primary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(YorksV1Document document) async {
    setState(() => _working = true);
    try {
      final version = document.currentVersion;
      final bytes = await ref
          .read(yorksV1DocumentsRepositoryProvider)
          .downloadDocument(
            bucketId: version.bucketId,
            objectPath: version.objectPath,
          );
      final saved = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .saveDocument(
            bytes: bytes,
            fileName: version.fileName,
            mimeType: version.mimeType,
          );
      if (mounted && saved) {
        _snack(context, YorksV1DocumentStrings.download.primary);
      }
    } catch (_) {
      if (mounted) {
        _snack(context, YorksV1DocumentStrings.downloadFailed.primary);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Shares only bytes returned by the same authorized repository download
  /// used by the normal Download action. This keeps mobile preview/share from
  /// learning Storage paths or creating a second document-read path.
  Future<void> _share(YorksV1Document document) async {
    final version = document.currentVersion;
    if (version.mimeType != 'application/pdf') {
      await _download(document);
      return;
    }
    setState(() => _working = true);
    try {
      final bytes = await ref
          .read(yorksV1DocumentsRepositoryProvider)
          .downloadDocument(
            bucketId: version.bucketId,
            objectPath: version.objectPath,
          );
      await Printing.sharePdf(bytes: bytes, filename: version.fileName);
    } catch (_) {
      if (mounted) {
        _snack(context, YorksV1DocumentStrings.downloadFailed.primary);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<Uint8List> _readBytes(YorksV1Document document) {
    final version = document.currentVersion;
    return ref
        .read(yorksV1DocumentsRepositoryProvider)
        .downloadDocument(
          bucketId: version.bucketId,
          objectPath: version.objectPath,
        );
  }

  Future<void> _link(YorksV1Document document) async {
    setState(() => _working = true);
    try {
      await ref
          .read(yorksV1DocumentsRepositoryProvider)
          .linkDocument(
            YorksV1DocumentLinkInput(
              documentId: document.id,
              entityType: _targetEntityType,
              entityId: _targetEntityId,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      if (!mounted) return;
      _refresh();
      _snack(context, YorksV1DocumentStrings.documentLinked.primary);
    } catch (_) {
      if (mounted) _snack(context, YorksV1DocumentStrings.linkFailed.primary);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _remove(YorksV1Document document) async {
    final link = document.links.where(
      (value) =>
          value.entityType == _targetEntityType &&
          value.entityId == _targetEntityId,
    );
    if (link.isEmpty) return;
    final reason = await _removalReason();
    if (reason == null || !mounted) return;
    setState(() => _working = true);
    try {
      await ref
          .read(yorksV1DocumentsRepositoryProvider)
          .removeDocumentLink(
            YorksV1DocumentLinkRemovalInput(
              documentLinkId: link.first.id,
              reason: reason,
              idempotencyKey: const Uuid().v4(),
            ),
          );
      if (!mounted) return;
      _refresh();
      _snack(context, YorksV1DocumentStrings.linkRemoved.primary);
    } catch (_) {
      if (mounted) {
        _snack(context, YorksV1DocumentStrings.removeFailed.primary);
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _removalReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(YorksV1DocumentStrings.removeLink.primary),
        content: TextField(
          controller: controller,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: YorksV1DocumentStrings.removalReason.primary,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(YorksV1DocumentStrings.cancel.primary),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(YorksV1DocumentStrings.removeLink.primary),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return null;
    return result;
  }

  void _refresh() =>
      ref.invalidate(yorksV1DocumentWorkspaceProvider(widget.projectId));
}

enum _MobileDocumentScope { all, project, boq, materialRequests }

/// Phone-first document register. It deliberately consumes the same workspace
/// data and command callbacks as the office list; no document metadata, file
/// bytes or classification information is synthesized for the mobile view.
class _MobileDocumentsBody extends StatefulWidget {
  const _MobileDocumentsBody({
    required this.workspace,
    required this.targetEntityType,
    required this.targetEntityId,
    required this.focusedRecord,
    required this.busy,
    required this.onCreateDocument,
    required this.onUploadVersion,
    required this.onDownload,
    required this.onShare,
    required this.onReadBytes,
    required this.onLink,
    required this.onRemove,
  });

  final YorksV1DocumentWorkspace workspace;
  final YorksV1DocumentEntityType targetEntityType;
  final String targetEntityId;
  final bool focusedRecord;
  final bool busy;
  final VoidCallback onCreateDocument;
  final ValueChanged<YorksV1Document> onUploadVersion;
  final ValueChanged<YorksV1Document> onDownload;
  final Future<void> Function(YorksV1Document) onShare;
  final Future<Uint8List> Function(YorksV1Document) onReadBytes;
  final ValueChanged<YorksV1Document> onLink;
  final ValueChanged<YorksV1Document> onRemove;

  @override
  State<_MobileDocumentsBody> createState() => _MobileDocumentsBodyState();
}

class _MobileDocumentsBodyState extends State<_MobileDocumentsBody> {
  _MobileDocumentScope _scope = _MobileDocumentScope.all;

  @override
  Widget build(BuildContext context) {
    final documents = widget.focusedRecord
        ? widget.workspace.documents
              .where(
                (document) => document.isLinkedTo(
                  widget.targetEntityType,
                  widget.targetEntityId,
                ),
              )
              .toList(growable: false)
        : widget.workspace.documents;
    final filtered = documents
        .where((document) => _inScope(document, _scope))
        .toList(growable: false);
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 96),
        children: [
          const YorksMobilePageTitle(
            eyebrow: 'Project workspace',
            title: 'Documents',
            description:
                'Controlled versions and authorized links for this project.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: AppSpacing.minTapTarget,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _scopePill(_MobileDocumentScope.all, 'All'),
                _scopePill(_MobileDocumentScope.project, 'Project'),
                _scopePill(_MobileDocumentScope.boq, 'BOQ'),
                _scopePill(_MobileDocumentScope.materialRequests, 'Requests'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          YorksMobileCallout(
            icon: Icons.verified_user_outlined,
            title: 'Controlled document register',
            message:
                'Every file version and link remains authorized by the server.',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: YorksMobileSectionHeader(
                  title:
                      '${filtered.length} document${filtered.length == 1 ? '' : 's'}',
                  subtitle: widget.focusedRecord
                      ? 'Linked to this record'
                      : 'Visible to your current role',
                ),
              ),
              SizedBox(
                height: AppSpacing.minTapTarget,
                child: FilledButton.icon(
                  onPressed: widget.busy ? null : widget.onCreateDocument,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            _MobileDocumentsEmpty(
              onAdd: widget.busy ? null : widget.onCreateDocument,
            )
          else
            for (final document in filtered) ...[
              _MobileDocumentCard(
                document: document,
                busy: widget.busy,
                onOpen: () => _open(document),
                onUploadVersion: () => widget.onUploadVersion(document),
                onDownload: () => widget.onDownload(document),
                onLink: () => widget.onLink(document),
                onRemove: () => widget.onRemove(document),
                canLink:
                    widget.focusedRecord &&
                    !document.isLinkedTo(
                      widget.targetEntityType,
                      widget.targetEntityId,
                    ),
                canRemove:
                    widget.focusedRecord &&
                    document.isLinkedTo(
                      widget.targetEntityType,
                      widget.targetEntityId,
                    ) &&
                    document.links.length > 1,
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _scopePill(_MobileDocumentScope scope, String label) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: YorksMobilePill(
      label: label,
      selected: _scope == scope,
      onTap: () => setState(() => _scope = scope),
    ),
  );

  bool _inScope(YorksV1Document document, _MobileDocumentScope scope) =>
      switch (scope) {
        _MobileDocumentScope.all => true,
        _MobileDocumentScope.project => document.links.any(
          (link) => link.entityType == YorksV1DocumentEntityType.project,
        ),
        _MobileDocumentScope.boq => document.links.any(
          (link) => link.entityType == YorksV1DocumentEntityType.boqGroup,
        ),
        _MobileDocumentScope.materialRequests => document.links.any(
          (link) =>
              link.entityType == YorksV1DocumentEntityType.materialRequest,
        ),
      };

  Future<void> _open(YorksV1Document document) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _MobileDocumentViewer(
        document: document,
        onDownload: () => widget.onDownload(document),
        onShare: () => widget.onShare(document),
        onReadBytes: () => widget.onReadBytes(document),
      ),
    ),
  );
}

class _MobileDocumentCard extends StatelessWidget {
  const _MobileDocumentCard({
    required this.document,
    required this.busy,
    required this.onOpen,
    required this.onUploadVersion,
    required this.onDownload,
    required this.onLink,
    required this.onRemove,
    required this.canLink,
    required this.canRemove,
  });

  final YorksV1Document document;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onUploadVersion;
  final VoidCallback onDownload;
  final VoidCallback onLink;
  final VoidCallback onRemove;
  final bool canLink;
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    final version = document.currentVersion;
    return YorksMobileCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.blueContainer,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: SizedBox.square(
                  dimension: 42,
                  child: Icon(
                    _iconForMime(version.mimeType),
                    color: AppColors.blue,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      version.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Revision ${version.revisionNumber} · ${_documentSize(version.byteSize)}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MobileDocumentChip(
                label: yorksV1DocumentClassificationCopy(
                  document.classification,
                ).primary,
                icon: Icons.verified_user_outlined,
              ),
              _MobileDocumentChip(
                label:
                    '${document.links.length} link${document.links.length == 1 ? '' : 's'}',
                icon: Icons.link_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${version.uploadedByDisplayName} · ${DateFormat('d MMM yyyy').format(version.uploadedAt)}',
            style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onDownload,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(YorksV1DocumentStrings.download.primary),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Document actions',
                onSelected: (value) {
                  switch (value) {
                    case 'version':
                      onUploadVersion();
                    case 'link':
                      onLink();
                    case 'remove':
                      onRemove();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'version',
                    enabled: !busy,
                    child: Text(YorksV1DocumentStrings.uploadVersion.primary),
                  ),
                  if (canLink)
                    PopupMenuItem(
                      value: 'link',
                      enabled: !busy,
                      child: Text(YorksV1DocumentStrings.linkDocument.primary),
                    ),
                  if (canRemove)
                    PopupMenuItem(
                      value: 'remove',
                      enabled: !busy,
                      child: Text(YorksV1DocumentStrings.removeLink.primary),
                    ),
                ],
                child: const SizedBox.square(
                  dimension: AppSpacing.minTapTarget,
                  child: Icon(Icons.more_horiz_rounded),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileDocumentChip extends StatelessWidget {
  const _MobileDocumentChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(100),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.inkSecondary),
          const SizedBox(width: 4),
          Text(label, style: AppTypography.labelSmall),
        ],
      ),
    ),
  );
}

class _MobileDocumentsEmpty extends StatelessWidget {
  const _MobileDocumentsEmpty({required this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => YorksMobileCard(
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
    child: Column(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.blueContainer,
            shape: BoxShape.circle,
          ),
          child: const SizedBox.square(
            dimension: 48,
            child: Icon(Icons.folder_open_outlined, color: AppColors.blue),
          ),
        ),
        const SizedBox(height: 13),
        Text('No authorized documents yet', style: AppTypography.titleMedium),
        const SizedBox(height: 5),
        Text(
          'Add a controlled version when a project file is ready to share.',
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: AppSpacing.minTapTarget,
          child: FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(YorksV1DocumentStrings.addDocument.primary),
          ),
        ),
      ],
    ),
  );
}

class _MobileDocumentsLoading extends StatelessWidget {
  const _MobileDocumentsLoading();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _MobileDocumentsError extends StatelessWidget {
  const _MobileDocumentsError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: YorksMobileCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.warning),
            const SizedBox(height: 10),
            Text('Documents are unavailable', style: AppTypography.titleMedium),
            const SizedBox(height: 5),
            Text(
              'Check your connection, then retry the authorized document list.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(YorksV1DocumentStrings.retry.primary),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A controlled mobile viewer. PDFs are rendered only from bytes delivered by
/// the existing authorized repository read; all other supported file types
/// remain explicitly download-only rather than being represented as a fake
/// preview.
class _MobileDocumentViewer extends StatefulWidget {
  const _MobileDocumentViewer({
    required this.document,
    required this.onDownload,
    required this.onShare,
    required this.onReadBytes,
  });

  final YorksV1Document document;
  final VoidCallback onDownload;
  final Future<void> Function() onShare;
  final Future<Uint8List> Function() onReadBytes;

  @override
  State<_MobileDocumentViewer> createState() => _MobileDocumentViewerState();
}

class _MobileDocumentViewerState extends State<_MobileDocumentViewer> {
  late Future<Uint8List>? _pdf;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  void _loadPdf() {
    _pdf = widget.document.currentVersion.mimeType == 'application/pdf'
        ? widget.onReadBytes()
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final version = widget.document.currentVersion;
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(YorksMobileUi.appBarHeight),
        child: YorksMobileAppBar(
          title: 'Document viewer',
          leading: YorksMobileIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  Icon(_iconForMime(version.mimeType), color: AppColors.blue),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      version.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall,
                    ),
                  ),
                  _MobileDocumentChip(
                    label: 'R${version.revisionNumber}',
                    icon: Icons.history_rounded,
                  ),
                ],
              ),
            ),
            Expanded(child: _preview(version)),
            YorksMobileStickyActions(
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onDownload,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(YorksV1DocumentStrings.download.primary),
                ),
                FilledButton.icon(
                  onPressed: version.mimeType == 'application/pdf'
                      ? widget.onShare
                      : widget.onDownload,
                  icon: Icon(
                    version.mimeType == 'application/pdf'
                        ? Icons.ios_share_rounded
                        : Icons.open_in_new_rounded,
                  ),
                  label: Text(
                    version.mimeType == 'application/pdf' ? 'Share' : 'Open',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(YorksV1DocumentVersion version) {
    final pdf = _pdf;
    if (pdf == null) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: YorksMobileCard(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _iconForMime(version.mimeType),
                  size: 44,
                  color: AppColors.blue,
                ),
                const SizedBox(height: 12),
                Text(
                  'Preview is available for PDF files',
                  style: AppTypography.titleMedium,
                ),
                const SizedBox(height: 5),
                Text(
                  'Download this controlled ${_documentTypeLabel(version.mimeType)} to open it with an authorized app.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return FutureBuilder<Uint8List>(
      future: pdf,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(14),
            child: _MobileDocumentsError(onRetry: () => setState(_loadPdf)),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return YorksWorkspaceZoomExclusion(
          child: PdfPreview(
            build: (_) async => snapshot.data!,
            canChangePageFormat: false,
            canDebug: false,
            allowPrinting: false,
            allowSharing: false,
          ),
        );
      },
    );
  }
}

String _documentSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _documentTypeLabel(String mimeType) => switch (mimeType) {
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
    'Excel workbook',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
    'Word document',
  'image/jpeg' || 'image/png' => 'image file',
  _ => 'file',
};

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({
    required this.workspace,
    required this.language,
    required this.targetEntityType,
    required this.targetEntityId,
    required this.focusedRecord,
    required this.busy,
    required this.onUploadVersion,
    required this.onDownload,
    required this.onLink,
    required this.onRemove,
    required this.showPageHeader,
    required this.onCreateDocument,
    required this.onDropDocuments,
    required this.onDropError,
    required this.onLinkExisting,
  });

  final YorksV1DocumentWorkspace workspace;
  final AppLanguage language;
  final YorksV1DocumentEntityType targetEntityType;
  final String targetEntityId;
  final bool focusedRecord;
  final bool busy;
  final ValueChanged<YorksV1Document> onUploadVersion;
  final ValueChanged<YorksV1Document> onDownload;
  final ValueChanged<YorksV1Document> onLink;
  final ValueChanged<YorksV1Document> onRemove;
  final bool showPageHeader;
  final VoidCallback onCreateDocument;
  final Future<void> Function(List<YorksV1SelectedDocument>) onDropDocuments;
  final VoidCallback onDropError;
  final VoidCallback onLinkExisting;

  @override
  Widget build(BuildContext context) {
    final documents = focusedRecord
        ? workspace.documents
              .where(
                (document) =>
                    document.isLinkedTo(targetEntityType, targetEntityId),
              )
              .toList(growable: false)
        : workspace.documents;
    final hasLinkableDocument =
        focusedRecord &&
        workspace.documents.any(
          (document) => !document.isLinkedTo(targetEntityType, targetEntityId),
        );
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSpacing.pageMaxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showPageHeader) ...[
                    YorksR35PageHeader(
                      eyebrow: YorksV1ShellStrings.operationalWorkspace.primary,
                      title: YorksV1DocumentStrings.documents.primary,
                      description:
                          YorksV1DocumentStrings.documentsDescription.primary,
                      actions: [
                        if (hasLinkableDocument)
                          SizedBox(
                            height: AppSpacing.minTapTarget,
                            child: OutlinedButton.icon(
                              onPressed: busy ? null : onLinkExisting,
                              icon: const Icon(Icons.link_rounded),
                              label: Text(
                                YorksV1DocumentStrings
                                    .linkExistingDocument
                                    .primary,
                              ),
                            ),
                          ),
                        SizedBox(
                          height: AppSpacing.minTapTarget,
                          child: FilledButton.icon(
                            onPressed: busy ? null : onCreateDocument,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: Text(
                              YorksV1DocumentStrings.addDocument.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                  _DocumentDropzone(
                    language: language,
                    busy: busy,
                    onPick: onCreateDocument,
                    onDropped: onDropDocuments,
                    onDropError: onDropError,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  NexusSectionCard(
                    child: _CopyText(
                      copy: YorksV1DocumentStrings.documentsDescription,
                      language: language,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  NexusSectionCard(
                    title: YorksV1DocumentStrings.documents.primary,
                    child: documents.isEmpty
                        ? _CopyText(
                            copy: YorksV1DocumentStrings.noDocuments,
                            language: language,
                            center: true,
                          )
                        : Column(
                            children: [
                              for (final document in documents)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.md,
                                  ),
                                  child: _DocumentCard(
                                    document: document,
                                    language: language,
                                    focusedRecord: focusedRecord,
                                    targetEntityType: targetEntityType,
                                    targetEntityId: targetEntityId,
                                    busy: busy,
                                    onUploadVersion: onUploadVersion,
                                    onDownload: onDownload,
                                    onLink: onLink,
                                    onRemove: onRemove,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  NexusSectionCard(
                    title: YorksV1DocumentStrings.activity.primary,
                    child: _AuditList(
                      entries: workspace.auditEntries,
                      language: language,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentDropzone extends StatefulWidget {
  const _DocumentDropzone({
    required this.language,
    required this.busy,
    required this.onPick,
    required this.onDropped,
    required this.onDropError,
  });

  final AppLanguage language;
  final bool busy;
  final VoidCallback onPick;
  final Future<void> Function(List<YorksV1SelectedDocument>) onDropped;
  final VoidCallback onDropError;

  @override
  State<_DocumentDropzone> createState() => _DocumentDropzoneState();
}

class _DocumentDropzoneState extends State<_DocumentDropzone> {
  DropzoneViewController? _controller;
  bool _dragging = false;

  static const _acceptedMimeTypes = <String>[
    'application/pdf',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'image/jpeg',
    'image/png',
  ];

  Future<void> _handleDrop(List<DropzoneFileInterface>? files) async {
    final controller = _controller;
    if (controller == null || files == null || files.isEmpty || widget.busy) {
      return;
    }
    if (mounted) setState(() => _dragging = false);
    final selected = <YorksV1SelectedDocument>[];
    var invalid = false;
    for (final file in files) {
      try {
        selected.add(
          YorksV1SelectedDocument.checked(
            fileName: await controller.getFilename(file),
            bytes: await controller.getFileData(file),
          ),
        );
      } on YorksV1DomainException {
        invalid = true;
      } catch (_) {
        invalid = true;
      }
    }
    if (selected.isNotEmpty) await widget.onDropped(selected);
    if (invalid) widget.onDropError();
  }

  @override
  Widget build(BuildContext context) {
    final content = Semantics(
      button: true,
      label: YorksV1DocumentStrings.dropDocuments.primary,
      child: InkWell(
        key: const ValueKey('yorks-v1-document-dropzone'),
        onTap: widget.busy ? null : widget.onPick,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: CustomPaint(
          painter: _DocumentDropBorderPainter(
            color: _dragging
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: .48),
            radius: AppSpacing.radiusMd,
          ),
          child: AnimatedContainer(
            duration: Duration.zero,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.xl,
            ),
            decoration: BoxDecoration(
              color: _dragging
                  ? AppColors.blueContainer.withValues(alpha: .72)
                  : AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_upload_outlined,
                  color: AppColors.primary,
                  size: 30,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dragging
                            ? YorksV1DocumentStrings.dropDocumentsActive.primary
                            : YorksV1DocumentStrings.dropDocuments.primary,
                        style: AppTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      _CopyText(
                        copy: YorksV1DocumentStrings.dropDocumentsPrompt,
                        language: widget.language,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 600) ...[
                  const SizedBox(width: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: widget.busy ? null : widget.onPick,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(YorksV1DocumentStrings.addDocument.primary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (!kIsWeb) return content;
    return Stack(
      children: [
        Positioned.fill(
          child: DropzoneView(
            mime: _acceptedMimeTypes,
            operation: DragOperation.copy,
            cursor: CursorType.grab,
            onCreated: (controller) => _controller = controller,
            onHover: () {
              if (mounted && !widget.busy) setState(() => _dragging = true);
            },
            onLeave: () {
              if (mounted) setState(() => _dragging = false);
            },
            onDropInvalid: (_) => widget.onDropError(),
            onDropFiles: (files) => unawaited(_handleDrop(files)),
          ),
        ),
        content,
      ],
    );
  }
}

class _DocumentDropBorderPainter extends CustomPainter {
  const _DocumentDropBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 7.0;
    const gap = 5.0;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(
            distance,
            (distance + dash).clamp(0, metric.length),
          ),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DocumentDropBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.language,
    required this.focusedRecord,
    required this.targetEntityType,
    required this.targetEntityId,
    required this.busy,
    required this.onUploadVersion,
    required this.onDownload,
    required this.onLink,
    required this.onRemove,
  });

  final YorksV1Document document;
  final AppLanguage language;
  final bool focusedRecord;
  final YorksV1DocumentEntityType targetEntityType;
  final String targetEntityId;
  final bool busy;
  final ValueChanged<YorksV1Document> onUploadVersion;
  final ValueChanged<YorksV1Document> onDownload;
  final ValueChanged<YorksV1Document> onLink;
  final ValueChanged<YorksV1Document> onRemove;

  @override
  Widget build(BuildContext context) {
    final version = document.currentVersion;
    final linkedHere = document.isLinkedTo(targetEntityType, targetEntityId);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(_iconForMime(version.mimeType), color: AppColors.primary),
                Text(
                  version.fileName,
                  style: AppTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                _ClassificationChip(classification: document.classification),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${YorksV1DocumentStrings.currentVersion.primary} · '
              '${YorksV1DocumentStrings.revision.primary} ${version.revisionNumber}',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${version.uploadedByDisplayName} · ${version.uploadedByRole} · '
              '${DateFormat('d MMM yyyy, HH:mm').format(version.uploadedAt)}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${YorksV1DocumentStrings.linkedTo.primary}: '
              '${document.links.map((link) => yorksV1DocumentEntityLabel(link.entityType)).join(', ')}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SecondaryButton(
                  label: YorksV1DocumentStrings.download.primary,
                  isExpanded: false,
                  icon: Icons.download_outlined,
                  onPressed: busy ? null : () => onDownload(document),
                ),
                if (!focusedRecord || linkedHere)
                  SecondaryButton(
                    label: YorksV1DocumentStrings.uploadVersion.primary,
                    isExpanded: false,
                    icon: Icons.upload_file_outlined,
                    onPressed: busy ? null : () => onUploadVersion(document),
                  ),
                if (focusedRecord && !linkedHere)
                  SecondaryButton(
                    label: YorksV1DocumentStrings.linkDocument.primary,
                    isExpanded: false,
                    icon: Icons.link_rounded,
                    onPressed: busy ? null : () => onLink(document),
                  ),
                if (focusedRecord && linkedHere && document.links.length > 1)
                  SecondaryButton(
                    label: YorksV1DocumentStrings.removeLink.primary,
                    isExpanded: false,
                    icon: Icons.link_off_rounded,
                    onPressed: busy ? null : () => onRemove(document),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassificationChip extends StatelessWidget {
  const _ClassificationChip({required this.classification});
  final YorksV1DocumentClassification classification;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(yorksV1DocumentClassificationCopy(classification).primary),
    visualDensity: VisualDensity.compact,
  );
}

class _AuditList extends StatelessWidget {
  const _AuditList({required this.entries, required this.language});
  final List<YorksV1AuditEvent> entries;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return _CopyText(
        copy: YorksV1DocumentStrings.auditSafeNotice,
        language: language,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CopyText(
          copy: YorksV1DocumentStrings.auditSafeNotice,
          language: language,
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final entry in entries.take(20))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              '${entry.eventType.replaceAll('_', ' ')} · '
              '${entry.actorDisplayName} (${entry.actorRole}) · '
              '${DateFormat('d MMM yyyy, HH:mm').format(entry.occurredAt)}',
              style: AppTypography.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: SecondaryButton(
      label: YorksV1DocumentStrings.retry.primary,
      icon: Icons.refresh_rounded,
      onPressed: onRetry,
    ),
  );
}

class _CopyText extends StatelessWidget {
  const _CopyText({
    required this.copy,
    required this.language,
    this.style,
    this.center = false,
  });

  final TranslatableString copy;
  final AppLanguage language;
  final TextStyle? style;
  final bool center;

  @override
  Widget build(BuildContext context) => YorksV1ActiveText(
    copy: copy,
    language: language,
    style: style ?? AppTypography.bodyMedium,
    textAlign: center ? TextAlign.center : null,
  );
}

IconData _iconForMime(String mimeType) => switch (mimeType) {
  'application/pdf' => Icons.picture_as_pdf_outlined,
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
    Icons.table_chart_outlined,
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
    Icons.description_outlined,
  _ => Icons.image_outlined,
};

void _snack(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));
