import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';

/// Presentation-only description of one role's Overview.
///
/// The role builders turn trusted server projections into this shape; the
/// layout renders it on desktop and phone. Nothing here owns workflow state:
/// every action navigates to the record that owns the transition.

/// The small coloured icon chip used by tiles, queue rows and list rows.
enum YorksOverviewTone { blue, green, violet, orange, red, neutral, gold }

extension YorksOverviewToneColors on YorksOverviewTone {
  Color get background => switch (this) {
    YorksOverviewTone.blue => AppColors.blueContainer,
    YorksOverviewTone.green => AppColors.successContainer,
    YorksOverviewTone.violet => AppColors.purpleContainer,
    YorksOverviewTone.orange => AppColors.warningContainer,
    YorksOverviewTone.red => AppColors.errorContainer,
    YorksOverviewTone.neutral => AppColors.neutralContainer,
    YorksOverviewTone.gold => AppColors.warningContainer,
  };

  Color get foreground => switch (this) {
    YorksOverviewTone.blue => AppColors.blue,
    YorksOverviewTone.green => AppColors.success,
    YorksOverviewTone.violet => AppColors.purple,
    YorksOverviewTone.orange => AppColors.warning,
    YorksOverviewTone.red => AppColors.error,
    YorksOverviewTone.neutral => AppColors.neutralText,
    YorksOverviewTone.gold => AppColors.onWarningContainer,
  };
}

/// Colour emphasis for a figure or a short trailing value.
enum YorksOverviewEmphasis { none, ok, warn, bad, violet, strong }

extension YorksOverviewEmphasisColor on YorksOverviewEmphasis {
  Color color([Color fallback = AppColors.ink]) => switch (this) {
    YorksOverviewEmphasis.none || YorksOverviewEmphasis.strong => fallback,
    YorksOverviewEmphasis.ok => AppColors.success,
    YorksOverviewEmphasis.warn => AppColors.warning,
    YorksOverviewEmphasis.bad => AppColors.error,
    YorksOverviewEmphasis.violet => AppColors.purple,
  };
}

/// Whether a card's server data is ready, still loading or failed.
enum YorksOverviewLoad { ready, loading, error }

class YorksOverviewAction {
  const YorksOverviewAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
}

class YorksOverviewKpi {
  const YorksOverviewKpi({
    required this.id,
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    required this.caption,
    this.valueSuffix,
    this.emphasis = YorksOverviewEmphasis.none,
    this.money = false,
    this.targetSection,
    this.queueTab,
    this.onTap,
    this.load = YorksOverviewLoad.ready,
  });

  final String id;
  final IconData icon;
  final YorksOverviewTone tone;
  final String label;
  final String value;
  final String? valueSuffix;
  final String caption;
  final YorksOverviewEmphasis emphasis;
  final bool money;

  /// Section to scroll to when the tile is selected.
  final String? targetSection;

  /// Queue filter to select when [targetSection] is a queue.
  final String? queueTab;

  /// Used instead of scrolling when the tile opens another workspace.
  final VoidCallback? onTap;
  final YorksOverviewLoad load;
}

/// Base for every Overview card.
sealed class YorksOverviewSection {
  const YorksOverviewSection({
    required this.id,
    required this.icon,
    required this.title,
    this.subtitle,
    this.linkLabel,
    this.onLink,
    this.load = YorksOverviewLoad.ready,
    this.onRetry,
  });

  final String id;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? linkLabel;
  final VoidCallback? onLink;
  final YorksOverviewLoad load;
  final VoidCallback? onRetry;
}

class YorksOverviewQueueTab {
  const YorksOverviewQueueTab(this.key, this.label);

  final String key;
  final String label;
}

class YorksOverviewQueueRow {
  const YorksOverviewQueueRow({
    required this.tab,
    required this.icon,
    required this.tone,
    required this.title,
    required this.meta,
    required this.actionLabel,
    required this.onTap,
    this.reference,
    this.tag,
    this.tagTone = YorksOverviewEmphasis.none,
    this.quote,
    this.byline,
    this.age,
    this.ageEmphasis = YorksOverviewEmphasis.none,
    this.primary = false,
  });

  final String tab;
  final IconData icon;
  final YorksOverviewTone tone;
  final String title;
  final String? reference;
  final String meta;
  final String? tag;
  final YorksOverviewEmphasis tagTone;
  final String? quote;
  final String? byline;
  final String? age;
  final YorksOverviewEmphasis ageEmphasis;
  final String actionLabel;
  final bool primary;
  final VoidCallback? onTap;
}

class YorksOverviewQueueSection extends YorksOverviewSection {
  const YorksOverviewQueueSection({
    required super.id,
    required super.icon,
    required super.title,
    required this.rows,
    required this.clearTitle,
    required this.clearBody,
    this.tabs = const [],
    this.footnote,
    this.total,
    this.openAllLabel,
    this.onOpenAll,
    super.subtitle,
    super.linkLabel,
    super.onLink,
    super.load,
    super.onRetry,
  });

  final List<YorksOverviewQueueTab> tabs;
  final List<YorksOverviewQueueRow> rows;
  final String clearTitle;
  final String clearBody;
  final String? footnote;

  /// The server total when it is larger than the rows returned.
  final int? total;
  final String? openAllLabel;
  final VoidCallback? onOpenAll;
}

class YorksOverviewCell {
  const YorksOverviewCell(
    this.text, {
    this.subtitle,
    this.emphasis = YorksOverviewEmphasis.none,
    this.chip = false,
  });

  final String text;
  final String? subtitle;
  final YorksOverviewEmphasis emphasis;

  /// Renders the text as a small state chip.
  final bool chip;
}

class YorksOverviewTableColumn {
  const YorksOverviewTableColumn(
    this.label, {
    this.numeric = false,
    this.flex = 10,
  });

  final String label;
  final bool numeric;
  final int flex;
}

class YorksOverviewTableRow {
  const YorksOverviewTableRow({required this.cells, this.onTap});

  final List<YorksOverviewCell> cells;
  final VoidCallback? onTap;
}

class YorksOverviewTableSection extends YorksOverviewSection {
  const YorksOverviewTableSection({
    required super.id,
    required super.icon,
    required super.title,
    required this.columns,
    required this.rows,
    required this.emptyText,
    this.mobileColumns = const [1, 2],
    super.subtitle,
    super.linkLabel,
    super.onLink,
    super.load,
    super.onRetry,
  });

  final List<YorksOverviewTableColumn> columns;
  final List<YorksOverviewTableRow> rows;
  final String emptyText;

  /// Column indexes shown under the title on phone cards.
  final List<int> mobileColumns;
}

class YorksOverviewStage {
  const YorksOverviewStage({
    required this.label,
    required this.count,
    required this.tone,
    this.hint,
    this.onTap,
  });

  final String label;
  final String? hint;
  final int count;
  final YorksOverviewTone tone;
  final VoidCallback? onTap;
}

class YorksOverviewPipelineSection extends YorksOverviewSection {
  const YorksOverviewPipelineSection({
    required super.id,
    required super.icon,
    required super.title,
    required this.stages,
    this.footnote,
    super.subtitle,
    super.linkLabel,
    super.onLink,
    super.load,
    super.onRetry,
  });

  final List<YorksOverviewStage> stages;
  final String? footnote;
}

class YorksOverviewListItem {
  const YorksOverviewListItem({
    required this.icon,
    required this.tone,
    required this.title,
    required this.detail,
    this.trailing,
    this.trailingSub,
    this.trailingEmphasis = YorksOverviewEmphasis.none,
    this.onTap,
  });

  final IconData icon;
  final YorksOverviewTone tone;
  final String title;
  final String detail;
  final String? trailing;
  final String? trailingSub;
  final YorksOverviewEmphasis trailingEmphasis;
  final VoidCallback? onTap;
}

class YorksOverviewListSection extends YorksOverviewSection {
  const YorksOverviewListSection({
    required super.id,
    required super.icon,
    required super.title,
    required this.items,
    required this.emptyText,
    this.limit = 6,
    super.subtitle,
    super.linkLabel,
    super.onLink,
    super.load,
    super.onRetry,
  });

  final List<YorksOverviewListItem> items;
  final String emptyText;
  final int limit;
}

class YorksOverviewTrackItem {
  const YorksOverviewTrackItem({
    required this.reference,
    required this.title,
    required this.stage,
    required this.stageLabel,
    required this.owner,
    this.age,
    this.note,
    this.noteEmphasis = YorksOverviewEmphasis.none,
    this.warning = false,
    this.onTap,
  });

  final String reference;
  final String title;

  /// 1-based position in the seven request stages.
  final int stage;
  final String stageLabel;
  final String owner;
  final String? age;
  final String? note;
  final YorksOverviewEmphasis noteEmphasis;
  final bool warning;
  final VoidCallback? onTap;
}

class YorksOverviewTrackSection extends YorksOverviewSection {
  const YorksOverviewTrackSection({
    required super.id,
    required super.icon,
    required super.title,
    required this.items,
    required this.stageNames,
    required this.emptyText,
    super.subtitle,
    super.linkLabel,
    super.onLink,
    super.load,
    super.onRetry,
  });

  final List<YorksOverviewTrackItem> items;
  final List<String> stageNames;
  final String emptyText;
}

class YorksOverviewMoneyRow {
  const YorksOverviewMoneyRow(
    this.label,
    this.value, {
    this.hint,
    this.emphasis = YorksOverviewEmphasis.none,
  });

  final String label;
  final String value;
  final String? hint;
  final YorksOverviewEmphasis emphasis;
}

class YorksOverviewMoneySection extends YorksOverviewSection {
  const YorksOverviewMoneySection({
    required super.id,
    required super.icon,
    required super.title,
    required this.rows,
    super.subtitle,
    super.linkLabel,
    super.onLink,
    super.load,
    super.onRetry,
  });

  final List<YorksOverviewMoneyRow> rows;
}

class YorksOverviewTool {
  const YorksOverviewTool({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback? onTap;
}

class YorksOverviewToolsSection extends YorksOverviewSection {
  const YorksOverviewToolsSection({
    required super.id,
    required super.icon,
    required super.title,
    required this.tools,
    super.subtitle,
  });

  final List<YorksOverviewTool> tools;
}

/// One complete role Overview.
class YorksRoleOverviewSpec {
  const YorksRoleOverviewSpec({
    required this.greeting,
    required this.title,
    required this.roleLabel,
    required this.description,
    required this.scope,
    required this.kpis,
    this.actions = const [],
    this.top = const [],
    this.left = const [],
    this.right = const [],
    this.full = const [],
    this.phoneOrder = const [],
    this.phoneKpis = const [0, 1, 2, 3],
  });

  final String greeting;
  final String title;
  final String roleLabel;
  final String description;
  final String scope;
  final List<YorksOverviewAction> actions;
  final List<YorksOverviewKpi> kpis;

  /// Full-width cards shown above the two columns.
  final List<YorksOverviewSection> top;
  final List<YorksOverviewSection> left;
  final List<YorksOverviewSection> right;

  /// Full-width cards shown below the two columns.
  final List<YorksOverviewSection> full;

  /// Card ids in phone order. Cards not listed are left off the phone.
  final List<String> phoneOrder;

  /// KPI indexes shown on the phone (a 2 × 2 grid).
  final List<int> phoneKpis;

  Iterable<YorksOverviewSection> get allSections => [
    ...top,
    ...left,
    ...right,
    ...full,
  ];
}
