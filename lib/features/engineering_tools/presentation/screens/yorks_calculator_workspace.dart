import 'dart:async';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/constants.dart';
import '../../../../shared/controllers/yorks_v1_calculator_controller.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_calculator_strings.dart';
import '../../../../shared/models/yorks_v1_calculator_workspace.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_calculator_provider.dart';
import 'yorks_v1_engineering_calculator_screens.dart';

const yorksCalculatorsPath = '/tools/calculators';
typedef S = YorksCalculatorStrings;

class YorksCalculatorWorkspace extends ConsumerWidget {
  const YorksCalculatorWorkspace({super.key, this.recordId, this.initial});
  final String? recordId;
  final Map<String, dynamic>? initial;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(
      yorksCalculatorControllerProvider(recordId ?? 'library'),
    );
    return _Workspace(
      key: ObjectKey(controller),
      controller: controller,
      recordId: recordId,
      initial: initial,
    );
  }
}

class _Workspace extends ConsumerStatefulWidget {
  const _Workspace({
    super.key,
    required this.controller,
    this.recordId,
    this.initial,
  });
  final YorksCalculatorController controller;
  final String? recordId;
  final Map<String, dynamic>? initial;
  @override
  ConsumerState<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends ConsumerState<_Workspace> {
  YorksCalculatorController get c => widget.controller;
  final title = TextEditingController();
  final search = TextEditingController();
  YorksCalculatorEditorSession? editor;
  String kind = 'duct', id = '', filter = 'all', scopeFilter = 'all';
  String? projectId, projectName;
  String baseline = '', lastFingerprint = '';
  bool dirty = false, allowPop = false, firstSnapshot = true;
  int editorGeneration = 0;
  Timer? refreshTimer, searchTimer;
  YorksCalculatorExitGuard? exitGuard;
  String t(TranslatableString s) => s.active(ref.read(languageProvider));
  @override
  void initState() {
    super.initState();
    title.addListener(_changed);
    if (widget.recordId != null) {
      exitGuard = ref.read(yorksCalculatorExitGuardProvider);
      exitGuard!.check = _canLeave;
    }
    Future<void>.microtask(_initialize);
    refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) c.checkAccess();
    });
  }

  Future<void> _initialize() async {
    if (widget.recordId == null) {
      await c.load();
      return;
    }
    final pending = c.recoverPending();
    if (pending != null) {
      if ((pending['expected_version'] as int? ?? 0) > 0) {
        await c.open(pending['id'] as String);
        if (!mounted || c.record == null) return;
      } else {
        await c.load();
        if (!mounted || !c.canCreate) return;
      }
      id = pending['id'] as String;
      kind = pending['kind'] as String;
      projectId = pending['project_id'] as String?;
      title.text = pending['title'] as String;
      _setEditor(
        Map<String, dynamic>.from(pending['payload'] as Map),
        unsaved: true,
      );
      return;
    }
    if (widget.recordId == 'new') {
      await c.load();
      if (!mounted || !c.canCreate) {
        setState(() {});
        return;
      }
      final initial = widget.initial ?? {};
      id = const Uuid().v4();
      kind = initial['kind'] as String? ?? 'duct';
      projectId = initial['project_id'] as String?;
      projectName = initial['project_name'] as String?;
      title.text = initial['title'] as String? ?? '';
      _setEditor(
        Map<String, dynamic>.from(
          initial['payload'] as Map? ?? YorksCalculatorFiles.fresh(kind),
        ),
        unsaved: true,
      );
    } else {
      await c.open(widget.recordId!);
      if (!mounted) return;
      final record = c.record;
      if (record != null) {
        id = record.id;
        kind = record.kind;
        projectId = record.projectId;
        projectName = record.projectName;
        title.text = record.title;
        _setEditor(record.payload);
      }
    }
  }

  void _setEditor(Map<String, dynamic> data, {bool unsaved = false}) {
    if (!mounted) return;
    firstSnapshot = true;
    editorGeneration++;
    editor = YorksCalculatorEditorSession(
      initialData: data,
      onChanged: _changed,
    );
    baseline = '';
    lastFingerprint = '';
    dirty = unsaved;
    setState(() {});
  }

  void _changed() {
    if (!mounted || editor?.snapshot == null || editor?.ready != true) return;
    final fingerprint =
        '${title.text.trim()}|${YorksCalculatorFiles.fingerprint(Map<String, dynamic>.from(editor!.snapshot!()))}';
    if (firstSnapshot) {
      baseline = fingerprint;
      firstSnapshot = false;
    }
    final next = c.record == null || fingerprint != baseline;
    if (lastFingerprint == fingerprint && next == dirty) return;
    lastFingerprint = fingerprint;
    setState(() => dirty = next);
  }

  @override
  void dispose() {
    if (exitGuard?.check == _canLeave) exitGuard!.check = null;
    refreshTimer?.cancel();
    searchTimer?.cancel();
    title.dispose();
    search.dispose();
    super.dispose();
  }

  Future<bool> _canLeave() async {
    if (allowPop || (!dirty && !c.hasPending)) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t(S.leave)),
            content: Text(t(c.hasPending ? S.pending : S.leaveHelp)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t(S.stay)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t(c.hasPending ? S.leavePending : S.discard)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _back() async {
    if (await _canLeave() && mounted) {
      setState(() => allowPop = true);
      context.go(yorksCalculatorsPath);
    }
  }

  Future<void> _save() async {
    if (editor?.snapshot == null || title.text.trim().isEmpty) return;
    final result = await c.save({
      'id': id,
      'title': title.text.trim(),
      'kind': kind,
      'project_id': projectId,
      'expected_version': c.record?.version ?? 0,
      'payload': editor!.snapshot!(),
    });
    if (result != null && mounted) {
      ref.invalidate(yorksCalculatorControllerProvider('library'));
      baseline =
          '${title.text.trim()}|${YorksCalculatorFiles.fingerprint(Map<String, dynamic>.from(editor!.snapshot!()))}';
      setState(() => dirty = false);
      if (widget.recordId == 'new') {
        allowPop = true;
        context.go('$yorksCalculatorsPath/${result.id}');
      }
    }
  }

  Future<void> _new({String? type, Map<String, dynamic>? payload}) async {
    try {
      await c.loadOptions();
    } catch (_) {
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) return;
    final name = TextEditingController();
    String selected = type ?? 'duct';
    String? project;
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(t(S.newCalculation)),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t(S.startHelp)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: name,
                    autofocus: true,
                    maxLength: 160,
                    onChanged: (_) => setDialog(() {}),
                    decoration: InputDecoration(labelText: t(S.name)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    items: [
                      DropdownMenuItem(value: 'duct', child: Text(t(S.duct))),
                      DropdownMenuItem(value: 'esp', child: Text(t(S.esp))),
                    ],
                    onChanged: payload != null
                        ? null
                        : (v) => setDialog(() => selected = v!),
                    decoration: InputDecoration(labelText: t(S.calculators)),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: 'general',
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(
                        value: 'general',
                        child: Text(t(S.general)),
                      ),
                      for (final p in c.options['projects'] as List? ?? [])
                        DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(
                            p['name'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => project = v == 'general' ? null : v,
                    decoration: InputDecoration(labelText: t(S.scope)),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t(S.cancel)),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, {
                      'title': name.text.trim(),
                      'kind': selected,
                      'project_id': project,
                      'project_name': (c.options['projects'] as List? ?? [])
                          .where((p) => p['id'] == project)
                          .firstOrNull?['name'],
                      'payload':
                          payload ??
                          {
                            ...YorksCalculatorFiles.fresh(selected),
                            if (selected == 'esp' && project != null)
                              'header': {
                                'projectName':
                                    (c.options['projects'] as List? ?? [])
                                        .where((p) => p['id'] == project)
                                        .firstOrNull?['name'] ??
                                    '',
                              },
                          },
                    }),
              child: Text(t(S.create)),
            ),
          ],
        ),
      ),
    );
    // The dialog's exit animation can still reference its controller.
    Future<void>.delayed(const Duration(milliseconds: 300), name.dispose);
    if (value != null && mounted) {
      context.go('$yorksCalculatorsPath/new', extra: value);
    }
  }

  Future<void> _import({bool legacy = false}) async {
    try {
      String? raw;
      if (legacy) {
        final selected = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(t(S.legacy)),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'duct'),
                child: Text(t(S.duct)),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'esp'),
                child: Text(t(S.esp)),
              ),
            ],
          ),
        );
        if (selected == null) return;
        raw = ref
            .read(sharedPreferencesProvider)
            .getString('yorks_r35_${selected}_calculation');
        if (raw == null) throw const FormatException();
      } else {
        final file = await openFile(
          acceptedTypeGroups: const [
            XTypeGroup(label: 'JSON', extensions: ['json']),
          ],
        );
        if (file == null) return;
        if (await file.length() > YorksCalculatorFiles.maximumBytes) {
          throw const FormatException();
        }
        raw = await file.readAsString();
      }
      final data = YorksCalculatorFiles.decode(raw);
      if (mounted) {
        await _new(
          type: data['app'] == 'duct-calc' ? 'duct' : 'esp',
          payload: data,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t(S.invalidFile))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => PopScope(
        canPop: allowPop || (!dirty && !c.hasPending),
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _back();
        },
        child: Material(
          color: AppColors.surfaceContainerLowest,
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: Theme.of(context).inputDecorationTheme
                  .copyWith(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                    constraints: const BoxConstraints(
                      minHeight: AppSpacing.minTapTarget,
                    ),
                  ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  minimumSize: const Size(0, AppSpacing.minTapTarget),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.inkSecondary,
                  minimumSize: const Size(0, AppSpacing.minTapTarget),
                ),
              ),
              iconButtonTheme: IconButtonThemeData(
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.inkSecondary,
                  minimumSize: const Size(
                    AppSpacing.minTapTarget,
                    AppSpacing.minTapTarget,
                  ),
                ),
              ),
            ),
            child: widget.recordId == null ? _home() : _record(),
          ),
        ),
      ),
    );
  }

  Widget _home() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < AppSpacing.compactBreakpoint;
      final gutter = compact ? AppSpacing.lg : AppSpacing.xxxl;
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.xxl, gutter, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t(S.calculators),
                      style: AppTypography.titleLarge,
                    ),
                  ),
                  _importMenu(),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: c.canCreate ? () => _new() : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(t(S.newCalculation)),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    AppSpacing.huge,
                    gutter,
                    AppSpacing.xxxl,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t(S.start), style: AppTypography.headlineMedium),
                      const SizedBox(height: AppSpacing.sm),
                      Text(t(S.subtitle), style: AppTypography.bodyMedium),
                      const SizedBox(height: AppSpacing.xxl),
                      LayoutBuilder(
                        builder: (context, box) {
                          final duct = _typeCard(
                            'duct',
                            Icons.air_outlined,
                            S.duct,
                            S.ductHelp,
                          );
                          final esp = _typeCard(
                            'esp',
                            Icons.speed_outlined,
                            S.esp,
                            S.espHelp,
                          );
                          return box.maxWidth < 560
                              ? Column(
                                  children: [
                                    duct,
                                    const SizedBox(height: AppSpacing.md),
                                    esp,
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(child: duct),
                                    const SizedBox(width: AppSpacing.lg),
                                    Expanded(child: esp),
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: AppSpacing.huge),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              t(S.recent),
                              style: AppTypography.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: t(S.refresh),
                            onPressed: c.loading ? null : () => c.load(),
                            icon: const Icon(Icons.refresh, size: 19),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: search,
                        onChanged: (v) {
                          searchTimer?.cancel();
                          searchTimer = Timer(
                            const Duration(milliseconds: 250),
                            () {
                              c.search = v;
                              c.load();
                            },
                          );
                        },
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, size: 19),
                          hintText: t(S.search),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          _filterMenu(
                            label: t(
                              filter == 'all'
                                  ? S.all
                                  : filter == 'duct'
                                  ? S.duct
                                  : S.esp,
                            ),
                            value: filter,
                            choices: {
                              'all': S.all,
                              'duct': S.duct,
                              'esp': S.esp,
                            },
                            onChanged: (v) {
                              setState(() => filter = v);
                              c.kind = v;
                              c.load();
                            },
                          ),
                          _filterMenu(
                            label: t(
                              scopeFilter == 'all'
                                  ? S.allScopes
                                  : scopeFilter == 'general'
                                  ? S.general
                                  : S.project,
                            ),
                            value: scopeFilter,
                            choices: {
                              'all': S.allScopes,
                              'general': S.general,
                              'project': S.project,
                            },
                            onChanged: (v) {
                              setState(() => scopeFilter = v);
                              c.scope = v;
                              c.load();
                            },
                          ),
                          _filterMenu(
                            label: t(c.archived ? S.archived : S.active),
                            value: c.archived ? 'archived' : 'active',
                            choices: {
                              'active': S.active,
                              'archived': S.archived,
                            },
                            onChanged: (v) {
                              c.archived = v == 'archived';
                              c.load();
                            },
                          ),
                        ],
                      ),
                      if (c.error != null) _error(),
                      if (c.loading)
                        const Padding(
                          padding: EdgeInsets.only(top: AppSpacing.lg),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      _recordList(),
                      if (c.hasMore)
                        Center(
                          child: TextButton(
                            onPressed: c.loading
                                ? null
                                : () => c.load(more: true),
                            child: Text(t(S.more)),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.huge),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _importMenu() => PopupMenuButton<String>(
    tooltip: t(S.import),
    icon: const Icon(Icons.file_upload_outlined, size: 20),
    onSelected: (v) => _import(legacy: v == 'legacy'),
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'file',
        enabled: c.canCreate,
        child: Text(t(S.import)),
      ),
      PopupMenuItem(
        value: 'legacy',
        enabled: c.canCreate,
        child: Text(t(S.legacy)),
      ),
    ],
  );

  Widget _filterMenu({
    required String label,
    required String value,
    required Map<String, TranslatableString> choices,
    required ValueChanged<String> onChanged,
  }) => PopupMenuButton<String>(
    tooltip: label,
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final entry in choices.entries)
        CheckedPopupMenuItem(
          value: entry.key,
          checked: value == entry.key,
          child: Text(t(entry.value)),
        ),
    ],
    child: Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(
            Icons.keyboard_arrow_down,
            size: 16,
            color: AppColors.muted,
          ),
        ],
      ),
    ),
  );

  Widget _recordList() {
    final visible = c.items
        .where(
          (r) =>
              (filter == 'all' || r.kind == filter) &&
              (scopeFilter == 'all' ||
                  (scopeFilter == 'general'
                      ? r.projectId == null
                      : r.projectId != null)),
        )
        .toList();
    if (visible.isEmpty && !c.loading) {
      final filtered =
          c.search.isNotEmpty ||
          filter != 'all' ||
          scopeFilter != 'all' ||
          c.archived;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.huge,
          horizontal: AppSpacing.lg,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.folder_open_outlined,
              size: 30,
              color: AppColors.mutedLight,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              t(filtered ? S.noResults : S.empty),
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              t(filtered ? S.filteredHelp : S.emptyHelp),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
            if (filtered)
              TextButton(
                onPressed: () {
                  searchTimer?.cancel();
                  search.clear();
                  setState(() {
                    filter = 'all';
                    scopeFilter = 'all';
                  });
                  c
                    ..search = ''
                    ..kind = 'all'
                    ..scope = 'all'
                    ..archived = false;
                  c.load();
                },
                child: Text(t(S.clearFilters)),
              ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final r in visible)
          Material(
            color: AppColors.surfaceContainerLowest,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              onTap: () => context.go('$yorksCalculatorsPath/${r.id}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.lg,
                  horizontal: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    _toolIcon(
                      r.kind == 'duct'
                          ? Icons.air_outlined
                          : Icons.speed_outlined,
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.title,
                            style: AppTypography.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${t(r.kind == 'duct' ? S.duct : S.esp)} · ${r.projectName ?? t(S.general)}',
                            style: AppTypography.bodySmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${r.owner} · ${_date(r.updatedAt)} · ${t(r.archived
                                ? S.archived
                                : r.canEdit
                                ? S.edit
                                : S.viewOnly)}',
                            style: AppTypography.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.mutedLight,
                    ),
                  ],
                ),
              ),
            ),
          ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _toolIcon(IconData icon) => Container(
    width: AppSpacing.massive,
    height: AppSpacing.massive,
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
    ),
    child: Icon(icon, size: 22, color: AppColors.inkSecondary),
  );

  Widget _typeCard(
    String type,
    IconData icon,
    TranslatableString label,
    TranslatableString help,
  ) => Material(
    color: AppColors.surfaceContainerLowest,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.line),
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: c.canCreate ? () => _new(type: type) : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _toolIcon(icon),
                const Spacer(),
                const Icon(Icons.add, size: 20, color: AppColors.muted),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(t(label), style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(t(help), style: AppTypography.bodyMedium),
          ],
        ),
      ),
    ),
  );
  Widget _record() {
    if (c.denied) return Column(children: [_backButton(), _error()]);
    if (editor == null) {
      return Column(
        children: [
          _backButton(),
          if (c.busy) const LinearProgressIndicator(),
          if (c.error != null) _error(),
        ],
      );
    }
    final canEdit = (c.record?.canEdit ?? true) && !c.busy && !c.hasPending;
    editor!.readOnly = !canEdit;
    editor!
      ..title = title.text
      ..scope = projectName ?? t(S.general)
      ..revision = dirty
          ? t(S.unsaved)
          : '${t(S.revision)} ${c.record?.version ?? 0}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < AppSpacing.compactBreakpoint;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _backButton(),
                      if (!compact) ...[
                        const Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: AppColors.mutedLight,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          t(kind == 'duct' ? S.duct : S.esp),
                          style: AppTypography.bodySmall,
                        ),
                      ],
                      const Spacer(),
                      if (!compact) _printButton(),
                      _recordMenu(canEdit, compact: compact),
                      if (c.record?.canManage == true)
                        IconButton(
                          tooltip: t(S.share),
                          onPressed: c.busy || dirty || c.hasPending
                              ? null
                              : _sharing,
                          icon: const Icon(Icons.group_outlined, size: 20),
                        ),
                      const SizedBox(width: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed:
                            !c.busy &&
                                ((canEdit && dirty) || c.hasPending) &&
                                title.text.trim().isNotEmpty
                            ? _save
                            : null,
                        icon: Icon(
                          c.hasPending ? Icons.refresh : Icons.check,
                          size: 18,
                        ),
                        label: Text(
                          t(
                            c.busy
                                ? S.saving
                                : c.hasPending
                                ? S.retry
                                : S.save,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Semantics(
                    label: t(S.name),
                    child: TextField(
                      controller: title,
                      readOnly: !canEdit,
                      maxLength: 160,
                      style: AppTypography.headlineMedium,
                      decoration: InputDecoration(
                        hintText: t(S.name),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.blue),
                        ),
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.sm,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            projectId == null
                                ? Icons.folder_outlined
                                : Icons.apartment_outlined,
                            size: 16,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth - 100,
                            ),
                            child: Text(
                              projectName ?? t(S.general),
                              style: AppTypography.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            c.busy
                                ? Icons.sync
                                : c.hasPending
                                ? Icons.cloud_off_outlined
                                : c.record?.archived == true
                                ? Icons.archive_outlined
                                : !canEdit
                                ? Icons.lock_outline
                                : dirty
                                ? Icons.circle_outlined
                                : Icons.check_circle_outline,
                            size: 14,
                            color: c.hasPending && !c.busy
                                ? AppColors.warning
                                : AppColors.muted,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              t(
                                c.busy
                                    ? S.saving
                                    : c.hasPending
                                    ? S.pending
                                    : c.record?.archived == true
                                    ? S.archived
                                    : !canEdit
                                    ? S.viewOnly
                                    : dirty
                                    ? S.unsaved
                                    : S.saved,
                              ),
                              style: AppTypography.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      if (c.record != null)
                        Text(
                          '${t(S.revision)} ${c.record!.version} · ${c.record!.updatedBy} · ${_date(c.record!.updatedAt)}',
                          style: AppTypography.bodySmall,
                        ),
                    ],
                  ),
                  if (c.error != null) _error(),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: kind == 'duct'
                  ? YorksV1DuctSizerScreen(
                      key: ValueKey(editorGeneration),
                      session: editor,
                    )
                  : YorksV1EspCalculatorScreen(
                      key: ValueKey(editorGeneration),
                      session: editor,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _printButton() => TextButton.icon(
    onPressed: () => _output(print: true),
    icon: const Icon(Icons.print_outlined, size: 18),
    label: Text(t(S.print)),
  );

  Widget _recordMenu(bool canEdit, {required bool compact}) =>
      PopupMenuButton<String>(
        tooltip: t(S.actions),
        icon: const Icon(Icons.more_horiz, size: 20),
        onSelected: (value) async {
          switch (value) {
            case 'import':
              await editor!.importFile?.call();
            case 'export':
              await _output(print: false);
            case 'print':
              await _output(print: true);
            case 'fittings':
              await editor!.showFittings?.call();
            case 'archive':
              await _archive();
            case 'refresh':
              if (await _canLeave() && mounted) await _initialize();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'import',
            enabled: canEdit,
            child: Text(t(S.import)),
          ),
          PopupMenuItem(value: 'export', child: Text(t(S.export))),
          if (compact) PopupMenuItem(value: 'print', child: Text(t(S.print))),
          if (kind == 'esp')
            PopupMenuItem(value: 'fittings', child: Text(t(S.fittings))),
          if (c.error != null)
            PopupMenuItem(value: 'refresh', child: Text(t(S.refresh))),
          if (c.record?.canManage == true) ...[
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'archive',
              enabled: !dirty && !c.busy && !c.hasPending,
              child: Text(t(c.record!.archived ? S.restore : S.archive)),
            ),
          ],
        ],
      );

  Widget _backButton() => TextButton.icon(
    onPressed: _back,
    icon: const Icon(Icons.arrow_back, size: 18),
    label: Text(t(S.back)),
  );
  Widget _error() {
    final message = c.error.toString();
    final text =
        message.contains('INVALID_INPUT') || message.contains('FILE_TOO_LARGE')
        ? S.invalidInputs
        : c.denied
        ? S.denied
        : message.contains('VERSION_CONFLICT')
        ? S.conflict
        : c.hasPending
        ? S.pending
        : S.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        t(text),
        style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
      ),
    );
  }

  String _date(String value) {
    final d = DateTime.tryParse(value)?.toLocal();
    return d == null
        ? ''
        : MaterialLocalizations.of(context).formatShortDate(d);
  }

  Future<void> _output({required bool print}) async {
    if (c.record != null) {
      await c.checkAccess();
      if (c.denied || !mounted) return;
    }
    try {
      if (print) {
        await editor!.printFile?.call();
      } else {
        await editor!.exportFile?.call();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t(S.error))));
      }
    }
  }

  Future<bool> _manage(Map<String, dynamic> change) async {
    final ok = await c.manage(change);
    if (ok && mounted) {
      ref.invalidate(yorksCalculatorControllerProvider('library'));
    }
    return ok;
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t(c.record!.archived ? S.restore : S.archive)),
        content: Text(t(S.archiveHelp)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t(S.cancel)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t(S.confirm)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _manage({'action': 'archive', 'archived': !c.record!.archived});
    }
  }

  Future<void> _sharing() async {
    try {
      await c.loadOptions();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    String? person;
    String access = 'view';
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(t(S.access)),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t(S.sharingHelp)),
                  const SizedBox(height: 16),
                  for (final grant in c.record!.grants)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(grant['name'] as String),
                      subtitle: Text(
                        t(grant['access'] == 'edit' ? S.edit : S.view),
                      ),
                      trailing: IconButton(
                        tooltip: t(S.remove),
                        onPressed: saving
                            ? null
                            : () async {
                                setDialog(() => saving = true);
                                await _manage({
                                  'action': 'access',
                                  'user_id': grant['user_id'],
                                  'access': 'none',
                                });
                                if (context.mounted) {
                                  setDialog(() => saving = false);
                                }
                              },
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: InputDecoration(labelText: t(S.person)),
                    items: [
                      for (final p in c.options['people'] as List? ?? [])
                        DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(
                            p['name'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: saving
                        ? null
                        : (v) => setDialog(() => person = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: access,
                    items: [
                      DropdownMenuItem(value: 'view', child: Text(t(S.view))),
                      DropdownMenuItem(value: 'edit', child: Text(t(S.edit))),
                    ],
                    onChanged: saving
                        ? null
                        : (v) => setDialog(() => access = v!),
                  ),
                  if (c.error != null) _error(),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: Text(t(S.cancel)),
            ),
            FilledButton(
              onPressed: person == null || saving
                  ? null
                  : () async {
                      setDialog(() => saving = true);
                      final ok = await _manage({
                        'action': 'access',
                        'user_id': person,
                        'access': access,
                      });
                      if (dialogContext.mounted) {
                        if (ok) {
                          Navigator.pop(dialogContext);
                        } else {
                          setDialog(() => saving = false);
                        }
                      }
                    },
              child: Text(t(saving ? S.saving : S.apply)),
            ),
          ],
        ),
      ),
    );
  }
}
