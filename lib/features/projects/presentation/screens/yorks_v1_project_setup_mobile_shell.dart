import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_project_creation_draft.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/models/yorks_v1_project_setup_shell_strings.dart';

/// Phone and tablet presentation of the same server-authoritative setup flow.
/// Safe areas belong to the device; the reference's OS chrome is not drawn.
class YorksV1ProjectSetupMobileShell extends ConsumerStatefulWidget {
  const YorksV1ProjectSetupMobileShell({
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
  final Set<YorksV1ProjectCreationStage> visitedStages, completeStages;
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
  ConsumerState<YorksV1ProjectSetupMobileShell> createState() =>
      _YorksV1ProjectSetupMobileShellState();
}

class _YorksV1ProjectSetupMobileShellState
    extends ConsumerState<YorksV1ProjectSetupMobileShell> {
  final _stageNodes = [
    for (final stage in YorksV1ProjectCreationStage.values)
      FocusNode(debugLabel: 'project-setup-mobile-${stage.name}'),
  ];
  static const _ink = Color(0xff08244d);
  static const _muted = Color(0xff607aa5);
  static const _line = Color(0xffdbe5ef);
  static const _blue = Color(0xff0065ff);

  static TextStyle _text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = _ink,
  }) => AppTypography.bodyMedium.copyWith(
    fontSize: size,
    height: 1.35,
    fontWeight: weight,
    color: color,
  );

  @override
  void dispose() {
    for (final node in _stageNodes) {
      node.dispose();
    }
    super.dispose();
  }

  TranslatableString _stageCopy(YorksV1ProjectCreationStage stage) =>
      switch (stage) {
        YorksV1ProjectCreationStage.projectDetails =>
          YorksV1ProjectStrings.projectDetails,
        YorksV1ProjectCreationStage.partiesAndAccess =>
          YorksV1ProjectStrings.partiesAndAccess,
        YorksV1ProjectCreationStage.buildings =>
          YorksV1ProjectStrings.buildings,
        YorksV1ProjectCreationStage.attachments =>
          YorksV1ProjectStrings.attachments,
        YorksV1ProjectCreationStage.reviewAndCreate =>
          YorksV1ProjectStrings.reviewAndCreate,
      };

  KeyEventResult _moveFocus(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.completed || widget.saving) {
      return KeyEventResult.ignored;
    }
    final eligible = [
      for (final stage in YorksV1ProjectCreationStage.values)
        if (widget.visitedStages.contains(stage)) stage.index,
    ];
    if (eligible.isEmpty) return KeyEventResult.ignored;
    final current = eligible.indexOf(_stageNodes.indexWhere((n) => n.hasFocus));
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final key = event.logicalKey;
    int? destination;
    if (key == LogicalKeyboardKey.home) {
      destination = eligible.first;
    } else if (key == LogicalKeyboardKey.end) {
      destination = eligible.last;
    } else if (key ==
        (rtl ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight)) {
      destination = eligible[(current + 1).clamp(0, eligible.length - 1)];
    } else if (key ==
        (rtl ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft)) {
      destination = eligible[(current - 1).clamp(0, eligible.length - 1)];
    }
    if (destination == null) return KeyEventResult.ignored;
    _stageNodes[destination].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        visualDensity: VisualDensity.standard,
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.all(7),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _ink,
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xffbdcee4)),
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            textStyle: _text(12, weight: FontWeight.w600),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xff084477),
            foregroundColor: Colors.white,
            disabledBackgroundColor: const Color(0xffdfe5ed),
            disabledForegroundColor: const Color(0xff7488a5),
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            textStyle: _text(12, weight: FontWeight.w600),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Web navigation may report a transient 1×1 surface before
            // its real viewport arrives. Defer only the chrome; keep
            // the flow, scaffold and messenger registered for outcomes.
            if (constraints.maxWidth < AppSpacing.minTapTarget ||
                constraints.maxHeight < AppSpacing.minTapTarget * 2) {
              return const SizedBox.shrink();
            }
            return KeyedSubtree(
              key: const ValueKey('project-setup-mobile-shell'),
              child: Column(
                children: [
                  Expanded(
                    child: SafeArea(
                      top: false,
                      bottom: widget.completed,
                      child: SingleChildScrollView(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _heading(),
                            const SizedBox(height: 12),
                            _stepper(),
                            const SizedBox(height: 18),
                            ...widget.notices,
                            widget.body,
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!widget.completed) _footer(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _heading() {
    final language = widget.language;
    final review = widget.stage == YorksV1ProjectCreationStage.reviewAndCreate;
    final subtitle = [
      widget.reference.trim(),
      widget.projectName.trim(),
    ].where((s) => s.isNotEmpty).join(' · ');
    final title = Text(
      (widget.isEditing
              ? YorksV1ProjectStrings.editProject
              : review && !widget.completed
              ? YorksV1ProjectStrings.reviewAndCreate
              : YorksV1ProjectSetupShellStrings.create)
          .active(language),
      style: _text(21, weight: FontWeight.w700).copyWith(height: 1.2),
    );
    final localStatus = Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            widget.savedOnDevice
                ? Icons.laptop_mac
                : widget.saving
                ? Icons.sync
                : Icons.info_outline,
            size: 14,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              widget.savedOnDevice
                  ? YorksV1ProjectSetupShellStrings.saved.active(language)
                  : widget.localStatus,
              style: _text(10.5),
            ),
          ),
        ],
      ),
    );
    final save = OutlinedButton(
      key: const ValueKey('project-setup-save-draft'),
      onPressed: widget.saving || widget.readOnly ? null : widget.onSaveDraft,
      child: Text(YorksV1ProjectStrings.saveDraft.active(language)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              textStyle: _text(12, color: _muted),
            ),
            onPressed: widget.saving ? null : widget.onReturnToProjects,
            icon: const Icon(Icons.chevron_left, size: 20),
            label: Text(YorksV1ProjectStrings.projects.active(language)),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 385 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.1 ||
                !widget.savedOnDevice;
            if (widget.completed) return title;
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (MediaQuery.textScalerOf(context).scale(1) > 1.1) ...[
                    title,
                    const SizedBox(height: 8),
                    save,
                  ] else
                    Row(
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 8),
                        save,
                      ],
                    ),
                  const SizedBox(height: 6),
                  localStatus,
                ],
              );
            }
            return Row(
              children: [
                title,
                const SizedBox(width: 8),
                Expanded(child: localStatus),
                const SizedBox(width: 8),
                save,
              ],
            );
          },
        ),
        if (subtitle.isNotEmpty &&
            (widget.completed ||
                widget.isEditing ||
                widget.stage !=
                    YorksV1ProjectCreationStage.projectDetails)) ...[
          const SizedBox(height: 6),
          Text(subtitle, style: _text(12, color: _muted)),
        ],
        if (!widget.completed && widget.headerActions.isNotEmpty)
          Wrap(spacing: 8, children: widget.headerActions),
      ],
    );
  }

  Widget _stepper() {
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.1;
    return FocusTraversalGroup(
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _moveFocus,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stages = YorksV1ProjectCreationStage.values;
            return Column(
              key: const ValueKey('project-setup-mobile-stepper'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    PositionedDirectional(
                      top: 21,
                      start: constraints.maxWidth / 10,
                      end: constraints.maxWidth / 10,
                      child: Row(
                        children: [
                          for (var i = 0; i < stages.length - 1; i++)
                            Expanded(
                              child: Container(
                                height: 1,
                                color: widget.completed
                                    ? const Color(0xff008f70)
                                    : widget.completeStages.contains(
                                            stages[i],
                                          ) &&
                                          widget.visitedStages.contains(
                                            stages[i + 1],
                                          )
                                    ? _blue
                                    : _line,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final stage in stages)
                          Expanded(child: _stageItem(stage, largeText)),
                      ],
                    ),
                  ],
                ),
                if (largeText) ...[
                  const SizedBox(height: 6),
                  Text(
                    _stageCopy(widget.stage).active(widget.language),
                    textAlign: TextAlign.center,
                    style: _text(14, weight: FontWeight.w600),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stageItem(YorksV1ProjectCreationStage stage, bool largeText) {
    final selected = stage == widget.stage && !widget.completed;
    final complete =
        widget.completed ||
        (!selected && widget.completeStages.contains(stage));
    final enabled =
        !widget.saving &&
        !widget.completed &&
        widget.visitedStages.contains(stage);
    final copy = _stageCopy(stage).active(widget.language);
    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      label: copy,
      child: TextButton(
        key: ValueKey('project-setup-mobile-step-${stage.name}'),
        focusNode: _stageNodes[stage.index],
        onPressed: enabled ? () => widget.onSelectStage(stage) : null,
        style: TextButton.styleFrom(
          foregroundColor: _blue,
          minimumSize: const Size(44, 44),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 44,
              child: Center(
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.completed
                        ? const Color(0xff008f70)
                        : selected || complete
                        ? _blue
                        : const Color(0xffe5eaf0),
                  ),
                  alignment: Alignment.center,
                  child: complete
                      ? const Icon(Icons.check, color: Colors.white, size: 17)
                      : Text(
                          '${stage.index + 1}',
                          style: _text(
                            12,
                            color: selected ? Colors.white : _muted,
                            weight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
            if (!largeText)
              Text(
                copy,
                textAlign: TextAlign.center,
                softWrap: stage != YorksV1ProjectCreationStage.attachments,
                overflow: TextOverflow.visible,
                style: _text(
                  stage == YorksV1ProjectCreationStage.attachments ? 10 : 11,
                  color: selected ? _blue : _muted,
                  weight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    final language = widget.language;
    final review = widget.stage == YorksV1ProjectCreationStage.reviewAndCreate;
    final files = widget.stage == YorksV1ProjectCreationStage.attachments;
    final back = OutlinedButton.icon(
      onPressed: widget.saving
          ? null
          : widget.stage == YorksV1ProjectCreationStage.projectDetails
          ? widget.onReturnToProjects
          : widget.onBack,
      icon: const Icon(Icons.arrow_back, size: 18),
      label: Text(
        (widget.stage == YorksV1ProjectCreationStage.projectDetails
                ? YorksV1ProjectSetupShellStrings.returnToProjects
                : YorksV1ProjectStrings.back)
            .active(language),
        textAlign: TextAlign.center,
      ),
    );
    final skip = OutlinedButton(
      onPressed: widget.saving ? null : widget.onSkip,
      child: Text(YorksV1ProjectStrings.skipForNow.active(language)),
    );
    final next = FilledButton(
      key: ValueKey('yorks-v1-project-${review ? 'create' : 'continue'}'),
      onPressed: widget.saving
          ? null
          : review
          ? widget.onFinalAction
          : widget.onContinue,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.saving) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              (review
                      ? widget.primaryLabel
                      : switch (widget.stage) {
                          YorksV1ProjectCreationStage.projectDetails =>
                            YorksV1ProjectSetupShellStrings.continueParties,
                          YorksV1ProjectCreationStage.partiesAndAccess =>
                            YorksV1ProjectSetupShellStrings.continueBuildings,
                          YorksV1ProjectCreationStage.buildings =>
                            YorksV1ProjectSetupShellStrings.continueAttachments,
                          _ => YorksV1ProjectSetupShellStrings.continueLabel,
                        })
                  .active(language),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward, size: 18),
        ],
      ),
    );
    return Container(
      key: const ValueKey('project-setup-mobile-footer'),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 364 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.1;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.footerHint != null || review) ...[
                    Text(
                      (widget.footerHint ??
                              YorksV1ProjectSetupShellStrings.reviewHint)
                          .active(language),
                      style: _text(11, color: _muted),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (stacked) ...[
                    next,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: back),
                        if (files) ...[
                          const SizedBox(width: 8),
                          Expanded(child: skip),
                        ],
                      ],
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(child: back),
                        if (files) ...[
                          const SizedBox(width: 8),
                          Expanded(child: skip),
                        ],
                        const SizedBox(width: 8),
                        Expanded(child: next),
                      ],
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
