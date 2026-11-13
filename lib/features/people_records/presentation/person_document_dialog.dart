/// People — add, correct, renew and end one document.
///
/// A dialog on desktop and a full screen on a phone. Nothing is shown as
/// saved until the server confirms; a refusal is shown in place with
/// everything typed still there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/constants.dart';
import '../../../shared/models/app_language.dart';
import '../../../shared/models/yorks_v1_domain_error.dart';
import '../../../shared/models/yorks_v1_people.dart';
import '../../../shared/providers/language_provider.dart';
import '../../../shared/providers/yorks_v1_people_provider.dart';
import '../../workforce/presentation/attendance/attendance_dialogs.dart'
    show showAttendanceCommandDialog;
import 'people_kit.dart';

/// Resolves to true once the server saved the document.
Future<bool?> showPeopleDocumentDialog(
  BuildContext context, {
  required PeoplePerson person,
  PeopleDocument? document,
  bool renew = false,
  PeopleDocumentKind? kind,
}) {
  final phone = MediaQuery.sizeOf(context).width < 600;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PeopleDocumentDialog(
      person: person,
      document: document,
      renew: renew,
      kind: kind,
      fullScreen: phone,
    ),
  );
}

/// Asks for a reason, then ends the document. Resolves to true once ended.
Future<bool?> showPeopleEndDocumentDialog(
  BuildContext context, {
  required PeoplePerson person,
  required PeopleDocument document,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final language = container.read(languageProvider);
  final repository = container.read(yorksV1PeopleRepositoryProvider);
  final doc = peopleKindLabel(document.kind, language, label: document.label);
  final idempotencyKey = const Uuid().v4();
  final reason = await showAttendanceCommandDialog(
    context,
    language: language,
    title: PS.t(PS.endTitle, language, {'doc': doc}),
    summary: [
      person.name,
      if (document.number != null) document.number!,
      if (document.expiryDate != null) peopleDate(document.expiryDate),
    ].join(' · '),
    body: PS.t(PS.endBody, language),
    fieldLabel: PS.t(PS.reason, language),
    confirmLabel: PS.t(PS.end, language),
    destructive: true,
    command: (text) async {
      try {
        await repository.endDocument(
          documentId: document.id,
          reason: text,
          expectedVersion: document.recordVersion,
          idempotencyKey: idempotencyKey,
        );
        return null;
      } catch (error) {
        return peopleErrorText(error, language);
      }
    },
  );
  if (reason == null) return null;
  if (context.mounted) {
    peopleToast(context, PS.t(PS.endedToast, language, {'doc': doc}));
  }
  return true;
}

class PeopleDocumentDialog extends ConsumerStatefulWidget {
  const PeopleDocumentDialog({
    super.key,
    required this.person,
    this.document,
    this.renew = false,
    this.kind,
    this.fullScreen = false,
  });

  final PeoplePerson person;

  /// The document to correct or renew; null to add one.
  final PeopleDocument? document;
  final bool renew;

  /// The kind to add, when the dialog opens from an empty row.
  final PeopleDocumentKind? kind;
  final bool fullScreen;

  @override
  ConsumerState<PeopleDocumentDialog> createState() =>
      _PeopleDocumentDialogState();
}

class _PeopleDocumentDialogState extends ConsumerState<PeopleDocumentDialog> {
  late PeopleDocumentKind _kind;
  late final TextEditingController _label;
  late final TextEditingController _number;
  late final TextEditingController _sites;
  late final TextEditingController _notes;
  String? _issue;
  String? _expiry;
  bool _busy = false;
  String? _error;
  String? _idempotencyKey;

  AppLanguage get _language => ref.read(languageProvider);
  PeopleDocument? get _document => widget.document;
  bool get _adding => _document == null;

  /// Single kinds already held are renewed from their row, not added again.
  List<PeopleDocumentKind> get _addable => [
    for (final kind in PeopleDocumentKind.values)
      if (!kind.single || widget.person.current(kind) == null) kind,
  ];

  @override
  void initState() {
    super.initState();
    final document = _document;
    _kind =
        document?.kind ??
        widget.kind ??
        _addable.firstOrNull ??
        PeopleDocumentKind.other;
    _label = TextEditingController(text: document?.label ?? '');
    _number = TextEditingController(text: document?.number ?? '');
    _sites = TextEditingController(text: document?.sites ?? '');
    _notes = TextEditingController(
      text: widget.renew ? '' : document?.notes ?? '',
    );
    // A renewal starts from a new issue and expiry.
    _issue = widget.renew ? null : document?.issueDate;
    _expiry = widget.renew ? null : document?.expiryDate;
  }

  @override
  void dispose() {
    _label.dispose();
    _number.dispose();
    _sites.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _changed() => setState(() {
    _error = null;
    _idempotencyKey = null;
  });

  String get _docName => peopleKindLabel(
    _kind,
    _language,
    label: _label.text.trim().isEmpty ? null : _label.text.trim(),
  );

  String get _title {
    if (_adding) return PS.t(PS.addDocumentTitle, _language);
    return PS.t(
      widget.renew ? PS.renewDocumentTitle : PS.editDocumentTitle,
      _language,
      {'doc': _docName},
    );
  }

  String? _validate() {
    if (_kind == PeopleDocumentKind.other && _label.text.trim().isEmpty) {
      return PS.t(PS.errLabel, _language);
    }
    final hasSites = _kind.isPass && _sites.text.trim().isNotEmpty;
    if (_number.text.trim().isEmpty && _expiry == null && !hasSites) {
      return PS.t(PS.errDocValue, _language);
    }
    if (_issue != null && _expiry != null && _expiry!.compareTo(_issue!) < 0) {
      return PS.t(PS.errDocDates, _language);
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final document = _document;
    _idempotencyKey ??= const Uuid().v4();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(yorksV1PeopleRepositoryProvider)
          .saveDocument(
            PeopleSaveDocumentInput(
              workerId: widget.person.id,
              documentId: document?.id,
              renew: widget.renew,
              kind: _kind,
              label: _kind == PeopleDocumentKind.other ? _label.text : null,
              number: _number.text,
              issueDate: _issue,
              expiryDate: _expiry,
              sites: _kind.isPass ? _sites.text : null,
              notes: _notes.text,
              expectedVersion: document?.recordVersion ?? 0,
              idempotencyKey: _idempotencyKey!,
            ),
          );
      if (!mounted) return;
      peopleToast(
        context,
        PS.t(widget.renew ? PS.renewedToast : PS.savedDocToast, _language, {
          'doc': _docName,
        }),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final exists =
          error is YorksV1DomainException && error.serverCode == '23505';
      setState(() {
        _busy = false;
        _error = exists
            ? PS.t(PS.errExists, _language, {'doc': _docName})
            : peopleErrorText(error, _language);
      });
    }
  }

  Future<void> _pickDate({required bool expiry}) async {
    final current = DateTime.tryParse((expiry ? _expiry : _issue) ?? '');
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(1990),
      lastDate: DateTime(now.year + 30),
    );
    if (picked == null) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      if (expiry) {
        _expiry = iso;
      } else {
        _issue = iso;
      }
      _error = null;
      _idempotencyKey = null;
    });
  }

  Widget _dateField({required bool expiry}) {
    final value = expiry ? _expiry : _issue;
    return InkWell(
      key: ValueKey(expiry ? 'people-doc-expiry' : 'people-doc-issue'),
      onTap: _busy ? null : () => _pickDate(expiry: expiry),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: PS.t(expiry ? PS.expiryDate : PS.issueDate, _language),
          suffixIcon: value != null && !_busy
              ? IconButton(
                  tooltip: PS.t(PS.clear, _language),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() {
                    if (expiry) {
                      _expiry = null;
                    } else {
                      _issue = null;
                    }
                    _idempotencyKey = null;
                  }),
                )
              : const Icon(Icons.event_outlined),
        ),
        child: Text(
          peopleDate(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.ink),
        ),
      ),
    );
  }

  Widget _fields() {
    final current = _document;
    const gap = SizedBox(height: AppSpacing.md);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          [
            widget.person.name,
            widget.person.number,
            widget.person.company,
          ].join(' · '),
          style: AppTypography.bodySmall.copyWith(color: AppColors.muted),
        ),
        if (widget.renew && current != null) ...[
          gap,
          Container(
            key: const ValueKey('people-doc-renew-hint'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.blueContainer,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.autorenew_rounded,
                  size: 18,
                  color: AppColors.blue,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    [
                      PS.t(PS.renewHint, _language, {'doc': _docName}),
                      [
                        if (current.number != null) current.number!,
                        if (current.expiryDate != null)
                          peopleDate(current.expiryDate),
                      ].join(' · '),
                    ].where((part) => part.isNotEmpty).join('\n'),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        gap,
        if (_adding)
          DropdownButtonFormField<PeopleDocumentKind>(
            key: const ValueKey('people-doc-kind'),
            initialValue: _kind,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: PS.t(PS.documentKind, _language),
              prefixIcon: Icon(peopleKindIcon(_kind), size: 20),
            ),
            items: [
              for (final kind in _addable)
                DropdownMenuItem(
                  value: kind,
                  child: Text(peopleKindLabel(kind, _language)),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value == null) return;
                    _kind = value;
                    _changed();
                  },
          ),
        if (_kind == PeopleDocumentKind.other) ...[
          if (_adding) gap,
          TextField(
            key: const ValueKey('people-doc-label'),
            controller: _label,
            enabled: !_busy && !widget.renew,
            onChanged: (_) => _changed(),
            decoration: InputDecoration(
              labelText: PS.t(PS.documentLabel, _language),
            ),
          ),
        ],
        if (_adding || _kind == PeopleDocumentKind.other) gap,
        TextField(
          key: const ValueKey('people-doc-number'),
          controller: _number,
          enabled: !_busy,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(
            labelText: PS.t(PS.documentNumber, _language),
          ),
        ),
        gap,
        LayoutBuilder(
          builder: (context, constraints) {
            final issue = _dateField(expiry: false);
            final expiry = _dateField(expiry: true);
            if (constraints.maxWidth < 420) {
              return Column(children: [issue, gap, expiry]);
            }
            return Row(
              children: [
                Expanded(child: issue),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: expiry),
              ],
            );
          },
        ),
        if (_kind.isPass) ...[
          gap,
          TextField(
            key: const ValueKey('people-doc-sites'),
            controller: _sites,
            enabled: !_busy,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => _changed(),
            decoration: InputDecoration(labelText: PS.t(PS.sites, _language)),
          ),
        ],
        gap,
        TextField(
          key: const ValueKey('people-doc-notes'),
          controller: _notes,
          enabled: !_busy,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => _changed(),
          decoration: InputDecoration(labelText: PS.t(PS.notes, _language)),
        ),
        if (_error != null) ...[
          gap,
          Semantics(
            liveRegion: true,
            child: Container(
              key: const ValueKey('people-doc-error'),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _actions() => [
    TextButton(
      key: const ValueKey('people-doc-cancel'),
      onPressed: _busy ? null : () => Navigator.of(context).pop(),
      child: Text(PS.t(PS.cancel, _language)),
    ),
    FilledButton.icon(
      key: const ValueKey('people-doc-save'),
      onPressed: _busy ? null : _save,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              widget.renew ? Icons.autorenew_rounded : Icons.check_rounded,
              size: 18,
            ),
      label: Text(
        _busy
            ? PS.t(PS.saving, _language)
            : PS.t(widget.renew ? PS.renew : PS.save, _language),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    if (widget.fullScreen) {
      return Dialog.fullscreen(
        key: const ValueKey('people-doc-dialog'),
        backgroundColor: AppColors.surface,
        child: Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            leading: IconButton(
              tooltip: PS.t(PS.cancel, _language),
              icon: const Icon(Icons.close_rounded),
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
            ),
            title: Text(_title),
          ),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [_fields()],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  key: const ValueKey('people-doc-save'),
                  onPressed: _busy ? null : _save,
                  icon: Icon(
                    widget.renew
                        ? Icons.autorenew_rounded
                        : Icons.check_rounded,
                  ),
                  label: Text(
                    _busy
                        ? PS.t(PS.saving, _language)
                        : PS.t(widget.renew ? PS.renew : PS.save, _language),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      key: const ValueKey('people-doc-dialog'),
      title: Row(
        children: [
          Icon(peopleKindIcon(_kind), color: AppColors.blue),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(_title)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(child: _fields()),
      ),
      actions: _actions(),
    );
  }
}
