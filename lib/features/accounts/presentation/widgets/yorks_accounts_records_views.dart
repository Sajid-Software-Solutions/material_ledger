import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/yorks_v1_accounts_strings.dart';
import '../../../../shared/models/yorks_v1_document.dart';
import '../../../../shared/models/yorks_v1_domain_error.dart';
import '../../../../shared/providers/yorks_v1_document_file_service_provider.dart';
import '../../application/accounts_controller.dart';
import '../../application/accounts_records_providers.dart';
import '../../data/accounts_report_service.dart';
import '../../domain/accounts_records_models.dart';

class YorksAccountsDocumentsView extends ConsumerStatefulWidget {
  const YorksAccountsDocumentsView({
    super.key,
    required this.projectId,
    required this.language,
  });

  final String projectId;
  final AppLanguage language;

  @override
  ConsumerState<YorksAccountsDocumentsView> createState() =>
      _YorksAccountsDocumentsViewState();
}

class _YorksAccountsDocumentsViewState
    extends ConsumerState<YorksAccountsDocumentsView> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  YorksV1AccountsDocumentType? _documentType;
  String? _actionMessage;

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _searchChanged(String _) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 320), _load);
  }

  void _load() => ref
      .read(yorksAccountsDocumentsControllerProvider(widget.projectId).notifier)
      .load(search: _searchController.text, documentType: _documentType);

  Future<void> _upload({YorksV1Document? revisionOf}) async {
    final workspace = ref
        .read(yorksAccountsDocumentsControllerProvider(widget.projectId))
        .workspace;
    if (workspace == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AccountsDocumentUploadDialog(
        projectId: widget.projectId,
        language: widget.language,
        workspace: workspace,
        revisionOf: revisionOf,
      ),
    );
    if (!mounted || saved == null) return;
    setState(() {
      _actionMessage = _text(
        widget.language,
        saved ? 'document_saved' : 'document_failed',
      );
    });
  }

  Future<void> _download(YorksV1DocumentVersion version) async {
    try {
      final bytes = await ref
          .read(
            yorksAccountsDocumentsControllerProvider(widget.projectId).notifier,
          )
          .download(version);
      final saved = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .saveDocument(
            bytes: bytes,
            fileName: version.fileName,
            mimeType: version.mimeType,
          );
      if (!mounted) return;
      setState(() {
        _actionMessage = saved
            ? _text(widget.language, 'document_saved')
            : _text(widget.language, 'document_cancelled');
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _actionMessage = _text(widget.language, 'document_failed'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      yorksAccountsDocumentsControllerProvider(widget.projectId),
    );
    final workspace = state.workspace;
    final busy = state.status == YorksAccountsViewStatus.loading;
    return _RecordPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.folder_copy_outlined,
            title: _text(widget.language, 'accounts_evidence_register'),
            body: _text(widget.language, 'accounts_evidence_body'),
            trailing: workspace?.canUpload == true
                ? FilledButton.icon(
                    onPressed: state.isUploading ? null : () => _upload(),
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(_text(widget.language, 'upload_document')),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                controller: _searchController,
                onChanged: _searchChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: _text(widget.language, 'search_documents'),
                  border: const OutlineInputBorder(),
                ),
              );
              final type =
                  DropdownButtonFormField<YorksV1AccountsDocumentType?>(
                    isExpanded: true,
                    initialValue: _documentType,
                    decoration: InputDecoration(
                      labelText: _text(widget.language, 'document_type'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(
                          _text(widget.language, 'all_document_types'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      for (final value in YorksV1AccountsDocumentType.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            _documentTypeLabel(widget.language, value),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _documentType = value);
                      _load();
                    },
                  );
              if (constraints.maxWidth < 700) {
                return Column(
                  children: [search, const SizedBox(height: 12), type],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 2, child: search),
                  const SizedBox(width: 12),
                  Expanded(child: type),
                ],
              );
            },
          ),
          if (_actionMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            _InlineMessage(message: _actionMessage!),
          ],
          if (state.error != null) ...[
            const SizedBox(height: AppSpacing.md),
            _InlineMessage(
              message: _withSupportReference(
                widget.language,
                _text(widget.language, 'document_failed'),
                state.error,
              ),
              isError: true,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (busy && workspace == null)
            const Center(child: CircularProgressIndicator())
          else if (workspace == null)
            _RetryState(
              language: widget.language,
              onRetry: _load,
              message: _text(widget.language, 'load_failed'),
            )
          else if (workspace.documents.isEmpty)
            _EmptyState(
              icon: Icons.folder_off_outlined,
              message: _text(widget.language, 'no_documents'),
            )
          else ...[
            for (final document in workspace.documents)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _DocumentRow(
                  document: document,
                  language: widget.language,
                  onDownload: () => _download(document.currentVersion),
                  onRevision: workspace.canUpload
                      ? () => _upload(revisionOf: document)
                      : null,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class YorksAccountsActivityView extends ConsumerStatefulWidget {
  const YorksAccountsActivityView({
    super.key,
    required this.projectId,
    required this.language,
  });

  final String projectId;
  final AppLanguage language;

  @override
  ConsumerState<YorksAccountsActivityView> createState() =>
      _YorksAccountsActivityViewState();
}

class _YorksAccountsActivityViewState
    extends ConsumerState<YorksAccountsActivityView> {
  final _actionController = TextEditingController();
  String? _entityType;

  @override
  void dispose() {
    _actionController.dispose();
    super.dispose();
  }

  void _load() => ref
      .read(yorksAccountsActivityControllerProvider(widget.projectId).notifier)
      .load(
        YorksAccountsActivityFilters(
          entityType: _entityType,
          action: _actionController.text,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      yorksAccountsActivityControllerProvider(widget.projectId),
    );
    final projection = state.projection;
    final busy = state.status == YorksAccountsViewStatus.loading;
    return _RecordPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.history_rounded,
            title: _text(widget.language, 'activity'),
            body: _text(widget.language, 'accounts_activity_body'),
            trailing: Chip(
              avatar: const Icon(Icons.lock_clock_outlined, size: 16),
              label: Text(_text(widget.language, 'append_only')),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final entity = DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _entityType,
                decoration: InputDecoration(
                  labelText: _text(widget.language, 'filter_entity'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      _text(widget.language, 'all_record_types'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final value in const [
                    'accounts_baseline_revision',
                    'accounts_billing_progress',
                    'accounts_client_claim',
                    'accounts_client_invoice',
                    'accounts_client_certification',
                    'accounts_client_payment',
                    'accounts_client_pdc',
                    'accounts_supplier_bill',
                    'accounts_supplier_payment',
                    'accounts_document',
                    'accounts_export',
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        _human(value),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  setState(() => _entityType = value);
                  _load();
                },
              );
              final action = TextField(
                controller: _actionController,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  labelText: _text(widget.language, 'filter_action'),
                  suffixIcon: IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.search_rounded),
                  ),
                  border: const OutlineInputBorder(),
                ),
              );
              if (constraints.maxWidth < 700) {
                return Column(
                  children: [entity, const SizedBox(height: 12), action],
                );
              }
              return Row(
                children: [
                  Expanded(child: entity),
                  const SizedBox(width: 12),
                  Expanded(flex: 2, child: action),
                ],
              );
            },
          ),
          if (state.error != null) ...[
            const SizedBox(height: AppSpacing.md),
            _InlineMessage(
              message: _withSupportReference(
                widget.language,
                _text(widget.language, 'load_failed'),
                state.error,
              ),
              isError: true,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (busy && projection == null)
            const Center(child: CircularProgressIndicator())
          else if (projection == null)
            _RetryState(
              language: widget.language,
              onRetry: _load,
              message: _text(widget.language, 'load_failed'),
            )
          else if (projection.entries.isEmpty)
            _EmptyState(
              icon: Icons.history_toggle_off_rounded,
              message: _text(widget.language, 'no_activity'),
            )
          else ...[
            for (final entry in projection.entries)
              _ActivityRow(entry: entry, language: widget.language),
            if (projection.hasMore)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: OutlinedButton.icon(
                  onPressed: state.isLoadingMore
                      ? null
                      : () => ref
                            .read(
                              yorksAccountsActivityControllerProvider(
                                widget.projectId,
                              ).notifier,
                            )
                            .loadMore(),
                  icon: state.isLoadingMore
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(_text(widget.language, 'load_more_activity')),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class YorksAccountsReportActions extends ConsumerStatefulWidget {
  const YorksAccountsReportActions({
    super.key,
    required this.kind,
    required this.language,
    this.projectId,
    this.compact = false,
    this.overviewToolbar = false,
  });

  final YorksAccountsReportKind kind;
  final String? projectId;
  final AppLanguage language;
  final bool compact;
  final bool overviewToolbar;

  @override
  ConsumerState<YorksAccountsReportActions> createState() =>
      _YorksAccountsReportActionsState();
}

class _YorksAccountsReportActionsState
    extends ConsumerState<YorksAccountsReportActions> {
  bool _busy = false;
  String? _message;

  Future<YorksAccountsReportProjection?> _report() async {
    setState(() {
      _busy = true;
      _message = _text(widget.language, 'preparing_report');
    });
    try {
      return await ref
          .read(yorksAccountsRecordsRepositoryProvider)
          .getReport(
            widget.kind,
            projectId: widget.projectId,
            idempotencyKey: const Uuid().v4(),
          );
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = _text(widget.language, 'report_failed');
        });
      }
      return null;
    }
  }

  Future<void> _excel() async {
    final report = await _report();
    if (report == null) return;
    try {
      final service = ref.read(yorksAccountsReportServiceProvider);
      final saved = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .saveDocument(
            bytes: service.buildExcel(report),
            fileName: service.excelFileName(report),
            mimeType: YorksAccountsReportService.xlsxMimeType,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _text(
          widget.language,
          saved ? 'report_saved' : 'document_cancelled',
        );
      });
    } catch (_) {
      _reportFailure();
    }
  }

  Future<void> _pdf({required bool print}) async {
    final report = await _report();
    if (report == null) return;
    try {
      final service = ref.read(yorksAccountsReportServiceProvider);
      if (print) {
        await service.printPdf(report);
        if (!mounted) return;
        setState(() {
          _busy = false;
          _message = null;
        });
        return;
      }
      final saved = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .saveDocument(
            bytes: await service.buildPdf(report),
            fileName: service.pdfFileName(report),
            mimeType: YorksAccountsReportService.pdfMimeType,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = _text(
          widget.language,
          saved ? 'report_saved' : 'document_cancelled',
        );
      });
    } catch (_) {
      _reportFailure();
    }
  }

  void _reportFailure() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = _text(widget.language, 'report_failed');
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.overviewToolbar) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _excel,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: Text(_text(widget.language, 'export_excel')),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pdf(print: true),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(_text(widget.language, 'print')),
          ),
          if (_message != null) Text(_message!, style: AppTypography.bodySmall),
        ],
      );
    }
    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<String>(
            enabled: !_busy,
            tooltip: _text(widget.language, 'report_actions'),
            onSelected: (value) {
              if (value == 'excel') {
                unawaited(_excel());
              } else if (value == 'pdf') {
                unawaited(_pdf(print: false));
              } else if (value == 'print') {
                unawaited(_pdf(print: true));
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'excel',
                child: Text(_text(widget.language, 'export_excel')),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: Text(_text(widget.language, 'save_pdf')),
              ),
              PopupMenuItem(
                value: 'print',
                child: Text(_text(widget.language, 'print')),
              ),
            ],
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.download_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(_text(widget.language, 'export_excel')),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                ],
              ),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(width: 8),
            Flexible(child: Text(_message!, style: AppTypography.bodySmall)),
          ],
        ],
      );
    }
    return _RecordPanel(
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          Text(
            _text(widget.language, 'report_actions'),
            style: AppTypography.titleSmall,
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _excel,
            icon: const Icon(Icons.table_view_outlined),
            label: Text(_text(widget.language, 'export_excel')),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pdf(print: false),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_text(widget.language, 'save_pdf')),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _pdf(print: true),
            icon: const Icon(Icons.print_outlined),
            label: Text(_text(widget.language, 'print')),
          ),
          if (_message != null)
            Text(
              _message!,
              style: AppTypography.bodySmall.copyWith(
                color: _message == _text(widget.language, 'report_failed')
                    ? AppColors.error
                    : AppColors.muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountsDocumentUploadDialog extends ConsumerStatefulWidget {
  const _AccountsDocumentUploadDialog({
    required this.projectId,
    required this.language,
    required this.workspace,
    this.revisionOf,
  });

  final String projectId;
  final AppLanguage language;
  final YorksV1AccountsDocumentWorkspace workspace;
  final YorksV1Document? revisionOf;

  @override
  ConsumerState<_AccountsDocumentUploadDialog> createState() =>
      _AccountsDocumentUploadDialogState();
}

class _AccountsDocumentUploadDialogState
    extends ConsumerState<_AccountsDocumentUploadDialog> {
  YorksV1AccountsDocumentTarget? _target;
  YorksV1AccountsDocumentType? _type;
  YorksV1DocumentClassification _classification =
      YorksV1DocumentClassification.commercial;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final revision = widget.revisionOf;
    if (revision != null) {
      _type = revision.accountsDocumentType;
      _classification = revision.classification;
      final link = revision.links.first;
      _target = YorksV1AccountsDocumentTarget(
        entityType: link.entityType,
        entityId: link.entityId,
        label: revision.currentVersion.fileName,
      );
    } else if (widget.workspace.uploadTargets.isNotEmpty) {
      _target = widget.workspace.uploadTargets.first;
      _type = YorksV1AccountsDocumentType.other;
    }
  }

  Future<void> _submit() async {
    final target = _target;
    final type = _type;
    if (target == null || type == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final selected = await ref
          .read(yorksV1DocumentFileServiceProvider)
          .selectDocument();
      if (selected == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final saved = await ref
          .read(
            yorksAccountsDocumentsControllerProvider(widget.projectId).notifier,
          )
          .upload(
            YorksV1DocumentUploadInput(
              projectId: widget.projectId,
              entityType: target.entityType,
              entityId: target.entityId,
              classification: _classification,
              fileName: selected.fileName,
              mimeType: selected.mimeType,
              bytes: selected.bytes,
              idempotencyKey: const Uuid().v4(),
              documentId: widget.revisionOf?.id,
              accountsDocumentType: type,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _text(widget.language, 'document_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final revision = widget.revisionOf != null;
    return AlertDialog(
      title: Text(
        _text(
          widget.language,
          revision ? 'upload_revision' : 'upload_document',
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<YorksV1AccountsDocumentTarget>(
              initialValue: _target,
              decoration: InputDecoration(
                labelText: _text(widget.language, 'linked_record'),
                border: const OutlineInputBorder(),
              ),
              items: revision
                  ? [
                      DropdownMenuItem(
                        value: _target,
                        child: Text(_target?.label ?? ''),
                      ),
                    ]
                  : [
                      for (final target in widget.workspace.uploadTargets)
                        DropdownMenuItem(
                          value: target,
                          child: Text(
                            target.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
              onChanged: revision
                  ? null
                  : (value) => setState(() => _target = value),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<YorksV1AccountsDocumentType>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: _text(widget.language, 'document_type'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final value in YorksV1AccountsDocumentType.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(_documentTypeLabel(widget.language, value)),
                  ),
              ],
              onChanged: revision
                  ? null
                  : (value) {
                      setState(() {
                        _type = value;
                        _classification =
                            value ==
                                YorksV1AccountsDocumentType.progressEvidence
                            ? YorksV1DocumentClassification.operational
                            : YorksV1DocumentClassification.commercial;
                      });
                    },
            ),
            if (_type == YorksV1AccountsDocumentType.progressEvidence &&
                !revision) ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<YorksV1DocumentClassification>(
                initialValue: _classification,
                decoration: InputDecoration(
                  labelText: _text(widget.language, 'classification'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: YorksV1DocumentClassification.operational,
                    child: Text(_text(widget.language, 'operational_evidence')),
                  ),
                  DropdownMenuItem(
                    value: YorksV1DocumentClassification.commercial,
                    child: Text(_text(widget.language, 'commercial_evidence')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _classification = value);
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              _InlineMessage(message: _error!, isError: true),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(_text(widget.language, 'cancel')),
        ),
        FilledButton.icon(
          onPressed: _busy || _target == null || _type == null ? null : _submit,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_open_outlined),
          label: Text(
            _text(widget.language, _busy ? 'uploading' : 'select_file'),
          ),
        ),
      ],
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.document,
    required this.language,
    required this.onDownload,
    this.onRevision,
  });

  final YorksV1Document document;
  final AppLanguage language;
  final VoidCallback onDownload;
  final VoidCallback? onRevision;

  @override
  Widget build(BuildContext context) {
    final version = document.currentVersion;
    final uploaded = DateFormat(
      'dd MMM yyyy, HH:mm',
    ).format(version.uploadedAt.toLocal());
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(version.fileName, style: AppTypography.titleSmall),
              const SizedBox(height: 4),
              Text(
                '${_documentTypeLabel(language, document.accountsDocumentType)} · '
                '${_text(language, 'revision')} ${version.revisionNumber}',
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                '${_text(language, 'uploaded_by')} ${version.uploadedByDisplayName} · $uploaded',
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: 4),
              SelectableText(
                '${_text(language, 'checksum')} ${version.sha256.substring(0, 12)}…',
                style: AppTypography.labelSmall,
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download_outlined),
                label: Text(_text(language, 'download')),
              ),
              if (onRevision != null)
                OutlinedButton.icon(
                  onPressed: onRevision,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(_text(language, 'upload_revision')),
                ),
            ],
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [details, const SizedBox(height: 12), actions],
            );
          }
          return Row(
            children: [
              Icon(
                Icons.description_outlined,
                color: AppColors.primary,
                size: 28,
              ),
              const SizedBox(width: 14),
              Expanded(child: details),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry, required this.language});

  final YorksAccountsActivityEntry entry;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.line)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.shield_outlined, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_human(entry.eventType), style: AppTypography.titleSmall),
              const SizedBox(height: 3),
              Text(
                '${entry.actorDisplayName} · ${_human(entry.actorExactRole)} · '
                '${DateFormat('dd MMM yyyy, HH:mm').format(entry.occurredAt.toLocal())}',
                style: AppTypography.bodySmall,
              ),
              if (entry.reason != null) ...[
                const SizedBox(height: 6),
                Text(entry.reason!, style: AppTypography.bodyMedium),
              ],
              if (entry.beforeData == null && entry.afterData == null) ...[
                const SizedBox(height: 5),
                Text(
                  _text(language, 'before_after_protected'),
                  style: AppTypography.labelSmall,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _RecordPanel extends StatelessWidget {
  const _RecordPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A12365E),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final copy = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.headlineSmall),
                const SizedBox(height: 4),
                Text(body, style: AppTypography.bodyMedium),
              ],
            ),
          ),
        ],
      );
      if (constraints.maxWidth < 700 || trailing == null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            copy,
            if (trailing != null) ...[const SizedBox(height: 12), trailing!],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: copy),
          const SizedBox(width: 16),
          trailing!,
        ],
      );
    },
  );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: isError ? AppColors.errorContainer : AppColors.surface,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(message, style: AppTypography.bodySmall),
  );
}

String _withSupportReference(
  AppLanguage language,
  String message,
  YorksV1DomainException? error,
) {
  final reference = error?.supportReference;
  return reference == null
      ? message
      : '$message ${_text(language, 'support_reference')}: $reference';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 46, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(message, style: AppTypography.titleSmall),
        ],
      ),
    ),
  );
}

class _RetryState extends StatelessWidget {
  const _RetryState({
    required this.language,
    required this.onRetry,
    required this.message,
  });

  final AppLanguage language;
  final VoidCallback onRetry;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      children: [
        Text(message),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onRetry,
          child: Text(_text(language, 'retry')),
        ),
      ],
    ),
  );
}

String _text(AppLanguage language, String key) =>
    YorksV1AccountsStrings.text(language, key);

String _documentTypeLabel(
  AppLanguage language,
  YorksV1AccountsDocumentType? type,
) => switch (type) {
  YorksV1AccountsDocumentType.contract => _text(language, 'contract_document'),
  YorksV1AccountsDocumentType.contractVariation => _text(
    language,
    'contract_variation_document',
  ),
  YorksV1AccountsDocumentType.progressEvidence => _text(
    language,
    'progress_evidence_document',
  ),
  YorksV1AccountsDocumentType.clientClaim => _text(
    language,
    'client_claim_document',
  ),
  YorksV1AccountsDocumentType.clientInvoice => _text(
    language,
    'client_invoice_document',
  ),
  YorksV1AccountsDocumentType.clientCertification => _text(
    language,
    'client_certification_document',
  ),
  YorksV1AccountsDocumentType.paymentCertificate => _text(
    language,
    'payment_certificate_document',
  ),
  YorksV1AccountsDocumentType.pdcCopy => _text(language, 'pdc_copy_document'),
  YorksV1AccountsDocumentType.paymentReceipt => _text(
    language,
    'payment_receipt_document',
  ),
  YorksV1AccountsDocumentType.supplierInvoice => _text(
    language,
    'supplier_invoice_document',
  ),
  YorksV1AccountsDocumentType.poLpo => _text(language, 'po_lpo_document'),
  YorksV1AccountsDocumentType.deliveryReceipt => _text(
    language,
    'delivery_receipt_document',
  ),
  YorksV1AccountsDocumentType.paymentAdvice => _text(
    language,
    'payment_advice_document',
  ),
  YorksV1AccountsDocumentType.commercialCorrespondence => _text(
    language,
    'commercial_correspondence_document',
  ),
  YorksV1AccountsDocumentType.other ||
  null => _text(language, 'other_document'),
};

String _human(String value) => value
    .replaceAll('.', ' ')
    .replaceAll('_', ' ')
    .split(' ')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
