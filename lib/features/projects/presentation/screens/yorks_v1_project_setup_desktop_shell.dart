import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_project_creation_draft.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_project_setup_shell_strings.dart';

/// Project setup content inside the shared Yorks workspace chrome. Controllers,
/// guards, operation journals and navigation remain owned by the feature screen.
class YorksV1ProjectSetupDesktopShell extends ConsumerStatefulWidget {
  const YorksV1ProjectSetupDesktopShell({
    super.key,
    required this.language,
    required this.stage,
    required this.visitedStages,
    required this.completeStages,
    required this.reference,
    required this.projectName,
    required this.localStatus,
    required this.saving,
    required this.readOnly,
    required this.body,
    required this.scrollController,
    required this.onSelectStage,
    required this.onSaveDraft,
    required this.onBack,
    required this.onReturnToProjects,
    required this.onContinue,
    required this.onSkip,
    required this.onFinalAction,
    required this.primaryLabel,
    this.notices = const [],
    this.headerActions = const [],
    this.completed = false,
    this.isEditing = false,
    this.savedOnDevice = false,
    this.footerHint,
  });

  final AppLanguage language;
  final YorksV1ProjectCreationStage stage;
  final Set<YorksV1ProjectCreationStage> visitedStages;
  final Set<YorksV1ProjectCreationStage> completeStages;
  final String reference, projectName, localStatus;
  final bool saving, readOnly, completed, isEditing, savedOnDevice;
  final Widget body;
  final ScrollController scrollController;
  final ValueChanged<YorksV1ProjectCreationStage> onSelectStage;
  final VoidCallback? onSaveDraft, onContinue, onSkip, onFinalAction;
  final VoidCallback onBack, onReturnToProjects;
  final TranslatableString primaryLabel;
  final TranslatableString? footerHint;
  final List<Widget> notices, headerActions;

  @override
  ConsumerState<YorksV1ProjectSetupDesktopShell> createState() =>
      _YorksV1ProjectSetupDesktopShellState();
}

class _YorksV1ProjectSetupDesktopShellState
    extends ConsumerState<YorksV1ProjectSetupDesktopShell> {
  final _nodes = [
    for (final stage in YorksV1ProjectCreationStage.values)
      FocusNode(debugLabel: 'project-setup-${stage.name}'),
  ];

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  static const _ink = Color(0xff08244d);
  static const _muted = Color(0xff607aa5);
  static const _line = Color(0xffdbe5ef);
  static const _blue = Color(0xff0065ff);
  static const _rail = Color(0xfff2f6f9);
  static TextStyle _text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = _ink,
  }) => AppTypography.bodyMedium.copyWith(
    fontSize: size,
    height: 1.4,
    fontWeight: weight,
    color: color,
  );

  KeyEventResult _moveFocus(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final eligible = [
      for (final stage in YorksV1ProjectCreationStage.values)
        if (widget.visitedStages.contains(stage)) stage.index,
    ];
    if (eligible.isEmpty) return KeyEventResult.ignored;
    final current = eligible.indexOf(_nodes.indexWhere((n) => n.hasFocus));
    final key = event.logicalKey;
    int? destination;
    if (key == LogicalKeyboardKey.home) {
      destination = eligible.first;
    } else if (key == LogicalKeyboardKey.end) {
      destination = eligible.last;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      destination = eligible[(current + 1).clamp(0, eligible.length - 1)];
    } else if (key == LogicalKeyboardKey.arrowUp) {
      destination = eligible[(current - 1).clamp(0, eligible.length - 1)];
    }
    if (destination == null) return KeyEventResult.ignored;
    _nodes[destination].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    final review = widget.stage == YorksV1ProjectCreationStage.reviewAndCreate;
    final subtitle = [
      widget.reference.trim(),
      widget.projectName.trim(),
    ].where((s) => s.isNotEmpty).join(' · ');
    final theme = Theme.of(context);
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: _ink,
      side: const BorderSide(color: Color(0xffbdcee4)),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      minimumSize: const Size(44, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      textStyle: _text(14, weight: FontWeight.w600),
    );
    return Theme(
      data: theme.copyWith(
        // The desktop references use explicit control dimensions. Applying
        // adaptive compact density would subtract pixels on browser builds.
        visualDensity: VisualDensity.standard,
        outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xff084477),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xffd9dee6),
            disabledForegroundColor: const Color(0xff7488a5),
            minimumSize: const Size(44, 46),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            textStyle: _text(14, weight: FontWeight.w600),
          ),
        ),
      ),
      child: Scaffold(
        key: const ValueKey('project-setup-desktop-shell'),
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    key: const ValueKey('project-setup-desktop-rail'),
                    width: 196,
                    decoration: const BoxDecoration(
                      color: _rail,
                      border: BorderDirectional(end: BorderSide(color: _line)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(
                            26,
                            28,
                            12,
                            widget.stage ==
                                        YorksV1ProjectCreationStage
                                            .projectDetails &&
                                    widget.visitedStages.length == 1
                                ? 14
                                : 10,
                          ),
                          child: Text(
                            YorksV1ProjectSetupShellStrings.setup.active(
                              language,
                            ),
                            style: _text(12, weight: FontWeight.w600),
                          ),
                        ),
                        FocusTraversalGroup(
                          policy: OrderedTraversalPolicy(),
                          child: Focus(
                            canRequestFocus: false,
                            onKeyEvent: _moveFocus,
                            child: Column(
                              children: [
                                for (final stage
                                    in YorksV1ProjectCreationStage.values)
                                  _stageItem(stage),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: widget.completed
                              ? 127
                              : switch (widget.stage) {
                                  YorksV1ProjectCreationStage.projectDetails =>
                                    124,
                                  YorksV1ProjectCreationStage.buildings => 127,
                                  YorksV1ProjectCreationStage.reviewAndCreate =>
                                    119,
                                  _ => 126,
                                },
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            30,
                            17,
                            21,
                            14,
                          ),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: _line)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          YorksV1ProjectStrings.projects.active(
                                            language,
                                          ),
                                          style: _text(14),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Text(
                                            '/',
                                            style: _text(14, color: _muted),
                                          ),
                                        ),
                                        Text(
                                          (widget.isEditing
                                                  ? YorksV1ProjectStrings
                                                        .editProject
                                                  : YorksV1ProjectSetupShellStrings
                                                        .create)
                                              .active(language),
                                          style: _text(14, color: _muted),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      (widget.isEditing
                                              ? YorksV1ProjectStrings
                                                    .editProject
                                              : review && !widget.completed
                                              ? YorksV1ProjectStrings
                                                    .reviewAndCreate
                                              : YorksV1ProjectSetupShellStrings
                                                    .create)
                                          .active(language),
                                      style: _text(
                                        32,
                                        weight: FontWeight.w700,
                                      ).copyWith(height: 1.2),
                                    ),
                                    Text(
                                      subtitle.isEmpty ||
                                              (!widget.completed &&
                                                  !widget.isEditing &&
                                                  widget.stage ==
                                                      YorksV1ProjectCreationStage
                                                          .projectDetails)
                                          ? YorksV1ProjectSetupShellStrings
                                                .description
                                                .active(language)
                                          : subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _text(16, color: _muted),
                                    ),
                                  ],
                                ),
                              ),
                              if (!widget.completed) ...[
                                const SizedBox(width: 16),
                                Semantics(
                                  liveRegion: true,
                                  child: Row(
                                    children: [
                                      Icon(
                                        widget.savedOnDevice
                                            ? Icons.laptop_mac
                                            : widget.saving
                                            ? Icons.sync
                                            : Icons.info_outline,
                                        color: _ink,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 10),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 270,
                                        ),
                                        child: Text(
                                          widget.savedOnDevice
                                              ? YorksV1ProjectSetupShellStrings
                                                    .saved
                                                    .active(language)
                                              : widget.localStatus,
                                          style: _text(13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 24),
                                ...widget.headerActions,
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(114, 40),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 22,
                                      vertical: 9,
                                    ),
                                  ),
                                  key: const ValueKey(
                                    'project-setup-save-draft',
                                  ),
                                  onPressed: widget.saving || widget.readOnly
                                      ? null
                                      : widget.onSaveDraft,
                                  child: Text(
                                    YorksV1ProjectStrings.saveDraft.active(
                                      language,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) =>
                                SingleChildScrollView(
                                  controller: widget.scrollController,
                                  padding: EdgeInsets.fromLTRB(
                                    widget.completed
                                        ? 29
                                        : switch (widget.stage) {
                                            YorksV1ProjectCreationStage
                                                .projectDetails =>
                                              25,
                                            YorksV1ProjectCreationStage
                                                .buildings =>
                                              27,
                                            YorksV1ProjectCreationStage
                                                .attachments =>
                                              28,
                                            _ => 29,
                                          },
                                    widget.completed
                                        ? 15
                                        : switch (widget.stage) {
                                            YorksV1ProjectCreationStage
                                                .projectDetails =>
                                              0,
                                            YorksV1ProjectCreationStage
                                                .reviewAndCreate =>
                                              12,
                                            _ => 18,
                                          },
                                    widget.completed ? 26 : 22,
                                    18,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: (constraints.maxHeight - 36)
                                          .clamp(0, double.infinity),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ...widget.notices,
                                        widget.body,
                                      ],
                                    ),
                                  ),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.completed)
              Container(
                height: switch (widget.stage) {
                  YorksV1ProjectCreationStage.projectDetails ||
                  YorksV1ProjectCreationStage.attachments => 86,
                  YorksV1ProjectCreationStage.partiesAndAccess => 66,
                  YorksV1ProjectCreationStage.buildings => 92,
                  YorksV1ProjectCreationStage.reviewAndCreate => 74,
                },
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 10,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _line)),
                ),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: widget.saving
                          ? null
                          : widget.stage ==
                                YorksV1ProjectCreationStage.projectDetails
                          ? widget.onReturnToProjects
                          : widget.onBack,
                      icon: const Icon(Icons.arrow_back, size: 20),
                      label: Text(
                        (widget.stage ==
                                    YorksV1ProjectCreationStage.projectDetails
                                ? YorksV1ProjectSetupShellStrings
                                      .returnToProjects
                                : YorksV1ProjectStrings.back)
                            .active(language),
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: widget.footerHint != null || review
                            ? Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 28,
                                ),
                                child: Text(
                                  (widget.footerHint ??
                                          YorksV1ProjectSetupShellStrings
                                              .reviewHint)
                                      .active(language),
                                  style: _text(12, color: _muted),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    if (widget.stage ==
                        YorksV1ProjectCreationStage.attachments) ...[
                      OutlinedButton(
                        onPressed: widget.saving ? null : widget.onSkip,
                        child: Text(
                          YorksV1ProjectStrings.skipForNow.active(language),
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                    FilledButton(
                      key: ValueKey(
                        'yorks-v1-project-${review ? 'create' : 'continue'}',
                      ),
                      onPressed: widget.saving
                          ? null
                          : review
                          ? widget.onFinalAction
                          : widget.onContinue,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.saving) ...[
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            (review
                                    ? widget.primaryLabel
                                    : switch (widget.stage) {
                                        YorksV1ProjectCreationStage
                                            .projectDetails =>
                                          YorksV1ProjectSetupShellStrings
                                              .continueParties,
                                        YorksV1ProjectCreationStage
                                            .partiesAndAccess =>
                                          YorksV1ProjectSetupShellStrings
                                              .continueBuildings,
                                        YorksV1ProjectCreationStage.buildings =>
                                          YorksV1ProjectSetupShellStrings
                                              .continueAttachments,
                                        _ =>
                                          YorksV1ProjectSetupShellStrings
                                              .continueLabel,
                                      })
                                .active(language),
                          ),
                          if (!review &&
                              widget.stage !=
                                  YorksV1ProjectCreationStage.attachments) ...[
                            const SizedBox(width: 16),
                            const Icon(Icons.arrow_forward, size: 20),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stageItem(YorksV1ProjectCreationStage stage) {
    final selected = widget.stage == stage && !widget.completed;
    final initialDetails =
        !widget.completed &&
        widget.stage == YorksV1ProjectCreationStage.projectDetails &&
        widget.visitedStages.length == 1;
    final complete =
        !initialDetails &&
        (widget.completed || widget.completeStages.contains(stage));
    final enabled =
        !widget.saving &&
        !widget.completed &&
        widget.visitedStages.contains(stage);
    final copy = switch (stage) {
      YorksV1ProjectCreationStage.projectDetails =>
        YorksV1ProjectStrings.projectDetails,
      YorksV1ProjectCreationStage.partiesAndAccess =>
        YorksV1ProjectStrings.partiesAndAccess,
      YorksV1ProjectCreationStage.buildings => YorksV1ProjectStrings.buildings,
      YorksV1ProjectCreationStage.attachments =>
        YorksV1ProjectStrings.attachments,
      YorksV1ProjectCreationStage.reviewAndCreate =>
        YorksV1ProjectStrings.reviewAndCreate,
    };
    return FocusTraversalOrder(
      order: NumericFocusOrder(stage.index.toDouble()),
      child: Semantics(
        selected: selected,
        button: true,
        enabled: enabled,
        label:
            '${copy.active(widget.language)}${complete ? ', ${YorksV1ProjectSetupShellStrings.completed.active(widget.language)}' : ''}',
        child: Material(
          color: selected ? const Color(0xffe3efff) : Colors.transparent,
          child: InkWell(
            key: ValueKey('yorks-v1-project-stage-${stage.name}'),
            focusNode: _nodes[stage.index],
            onTap: enabled ? () => widget.onSelectStage(stage) : null,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(
                    width: 8,
                    color: selected ? _blue : Colors.transparent,
                  ),
                ),
              ),
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 10, 0),
              child: Row(
                children: [
                  if (initialDetails) ...[
                    Container(
                      width: 27,
                      height: 27,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? _blue : const Color(0xffd8e1eb),
                      ),
                      child: Text(
                        '${stage.index + 1}',
                        style: _text(13, color: selected ? Colors.white : _ink),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          copy.active(widget.language),
                          style: _text(
                            14,
                            weight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected ? _blue : _ink,
                          ),
                        ),
                        if (!complete &&
                            stage == YorksV1ProjectCreationStage.attachments)
                          Text(
                            YorksV1ProjectStrings.optional.active(
                              widget.language,
                            ),
                            style: _text(12, color: _muted),
                          ),
                      ],
                    ),
                  ),
                  if (complete)
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xff008c69),
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
