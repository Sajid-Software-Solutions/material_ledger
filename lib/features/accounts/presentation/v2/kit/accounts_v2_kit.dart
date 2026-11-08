/// R39 Accounts Workspace V2 — the prototype's building blocks, measured.
///
/// Every size, colour and spacing here is copied from the approved prototype
/// (`docs/yorks-v1/designs/accounts-workspace-v2-prototype.html`), so the six
/// tabs read as one design: cards, KPI tiles, card and tile headings, buttons,
/// chips, outlined fields, tables, key/value rows, notes and empty states.
///
/// Colours come from [AppColors] where the app already has them. The handful
/// the app does not (card border, table header, tile tints) live in
/// [AccountsV2Colors] and are used only by the Accounts workspace.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/constants/app_typography.dart';
import 'accounts_v2_icon_paths.dart';

// ─── Tokens ──────────────────────────────────────────────────────────────────

/// The prototype's palette. Names follow its CSS variables.
abstract final class AccountsV2Colors {
  static const bg = AppColors.surfaceContainerLow; // --bg #F5F8FC
  static const card = Colors.white;
  static const line = Color(0xFFE0E6ED); // --line
  static const line2 = Color(0xFFEDF1F6); // --line2
  static const lineS = AppColors.lineStrong; // --lineS #C8D2DF
  static const cardBorder = Color(0xFFD8E2EE); // --cardb
  static const ink = AppColors.ink; // --ink #132033
  static const ink2 = AppColors.inkSecondary; // --ink2 #34435A
  static const mut = AppColors.muted; // --mut #6B788C
  static const mut2 = AppColors.mutedLight; // --mut2 #8F9AAE
  static const navy = AppColors.navy; // --navy #0D2F57
  static const pri = AppColors.blue; // --pri #1D68D9
  static const priDark = Color(0xFF1757B8); // --pri-d
  static const pri50 = AppColors.blueContainer; // --pri-50 #EAF2FF
  static const pri100 = AppColors.blueContainerStrong; // --pri-100 #C9DCFF
  static const priInk = Color(0xFF1F55B8); // --pri-ink
  static const priLight = Color(0xFF8FB4F0); // --pri-l
  static const ok = AppColors.success; // --ok #0D8B63
  static const ok50 = AppColors.successContainer; // --ok-50 #E9F8F2
  static const okIcon = Color(0xFF2E9A63); // --okI
  static const warn = AppColors.warning; // --warn #AD6A00
  static const warn50 = AppColors.warningContainer; // --warn-50 #FFF5DF
  static const org = Color(0xFFD2742C); // --org
  static const bad = AppColors.error; // --bad #C23737
  static const bad50 = AppColors.errorContainer; // --bad-50 #FFF0F0
  static const vio = AppColors.purple; // --vio #6D4BD1
  static const vio50 = AppColors.purpleContainer; // --vio-50 #F2EDFF
  static const neu = AppColors.neutralContainer; // --neu #F1F4F7
  static const neuText = AppColors.neutralText; // --neuT #536175
  static const tableHead = Color(0xFFF7F9FC);
  static const track = Color(0xFFDFE7F0); // bar background
  static const hover = Color(0xFFEEF3FA); // tab hover
  static const buttonHover = Color(0xFFF3F7FC);
  static const rowHover = Color(0xFFF8FBFF);
  static const quietPanel = Color(0xFFFAFCFE); // workbench inner rows
  static const heatEmpty = Color(0xFFF1F4F7);
  static const heatDone = Color(0xFFDDF2E8);
}

/// Tinted square behind an icon (`.ti.t-*` in the prototype).
enum AccountsV2Tone {
  blue(Color(0xFFEAF1FB), AccountsV2Colors.pri),
  green(Color(0xFFE9F6F0), AccountsV2Colors.okIcon),
  vio(Color(0xFFF1EEFB), AccountsV2Colors.vio),
  org(Color(0xFFFBF1E8), AccountsV2Colors.org),
  red(Color(0xFFFCEDED), AccountsV2Colors.bad),
  neu(AccountsV2Colors.neu, AccountsV2Colors.neuText);

  const AccountsV2Tone(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// Colour of a KPI value or a key/value amount (`.kn.ok`, `b.bad` …).
enum AccountsV2ValueTone {
  plain(AccountsV2Colors.ink),
  ok(AccountsV2Colors.ok),
  bad(AccountsV2Colors.bad),
  warn(AccountsV2Colors.warn),
  vio(AccountsV2Colors.vio);

  const AccountsV2ValueTone(this.color);

  final Color color;
}

/// The width the prototype's breakpoints are measured against.
///
/// The prototype sits beside a 56px rail, so its layouts change with the
/// window width. The app's sidebar is wider, so the workspace publishes the
/// window width the prototype would need to give it the same room; layouts
/// then change when the space does, not when the window does.
class AccountsV2Viewport extends InheritedWidget {
  const AccountsV2Viewport({
    super.key,
    required this.width,
    required super.child,
  });

  /// The equivalent prototype window width.
  final double width;

  /// The prototype window width that leaves [workspaceWidth] for its content:
  /// the rail is added back above 1050px, where the prototype shows it.
  static double fromWorkspace(double workspaceWidth) =>
      workspaceWidth + 56 > 1050 ? workspaceWidth + 56 : workspaceWidth;

  @override
  bool updateShouldNotify(AccountsV2Viewport oldWidget) =>
      oldWidget.width != width;
}

/// The prototype's viewport breakpoints, read from [AccountsV2Viewport] inside
/// the workspace and from the window elsewhere (dialogs, drawers).
abstract final class AccountsV2Breakpoints {
  static double _width(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountsV2Viewport>()?.width ??
      MediaQuery.sizeOf(context).width;

  /// `max-width:640px` — phones.
  static bool isPhone(BuildContext context) => _width(context) <= 640;

  /// `max-width:760px` — small tablets in portrait.
  static bool isNarrow(BuildContext context) => _width(context) <= 760;

  /// `max-width:1050px` — the app sidebar collapses.
  static bool isCompact(BuildContext context) => _width(context) <= 1050;

  /// `max-width:1180px` — side panels drop below the main column.
  static bool isMedium(BuildContext context) => _width(context) <= 1180;

  /// `max-width:1320px` — three-up overview rows become two-up.
  static bool isWide(BuildContext context) => _width(context) > 1320;
}

/// Gap between stacked cards and grid tiles (`--gap`).
const double accountsV2Gap = 14;

/// Card corner radius (`--r`).
const double accountsV2Radius = 14;

/// A text style in the app font at an exact prototype size.
TextStyle v2Style(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = AccountsV2Colors.ink,
  double height = 1.45,
  double letterSpacing = 0,
  bool tabular = false,
}) => AppTypography.bodyMedium.copyWith(
  fontSize: size,
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
);

// ─── Icons ───────────────────────────────────────────────────────────────────

/// One of the prototype's stroke icons, at its stroke weight.
class AccountsV2Icon extends StatelessWidget {
  const AccountsV2Icon(this.name, {super.key, this.size = 18, this.color});

  final String name;
  final double size;

  /// Defaults to the surrounding text colour, as `currentColor` does.
  final Color? color;

  static final Map<String, String> _cache = {};

  static String _svg(String name, Color color) {
    final hex = color.toARGB32().toRadixString(16).padLeft(8, '0');
    final rgb = '#${hex.substring(2)}';
    final opacity = (color.a).toStringAsFixed(3);
    return _cache.putIfAbsent('$name|$hex', () {
      final body = (accountsV2IconPaths[name] ?? '').replaceAll(
        'currentColor',
        rgb,
      );
      return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
          'fill="none" stroke="$rgb" stroke-opacity="$opacity" '
          'stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">'
          '$body</svg>';
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolved =
        color ??
        DefaultTextStyle.of(context).style.color ??
        AccountsV2Colors.ink2;
    return SizedBox.square(
      dimension: size,
      child: SvgPicture.string(
        _svg(name, resolved),
        width: size,
        height: size,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// A 42×42 tinted tile holding an icon (`.ti`).
class AccountsV2IconTile extends StatelessWidget {
  const AccountsV2IconTile({
    super.key,
    required this.icon,
    this.tone = AccountsV2Tone.blue,
    this.size = 42,
    this.radius = 11,
    this.iconSize = 21,
  });

  final String icon;
  final AccountsV2Tone tone;
  final double size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: AccountsV2Icon(icon, size: iconSize, color: tone.foreground),
    );
  }
}

// ─── Cards ───────────────────────────────────────────────────────────────────

/// A white card with the prototype's border and radius (`.card`).
class AccountsV2Panel extends StatelessWidget {
  const AccountsV2Panel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.clip = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: AccountsV2Colors.card,
        borderRadius: BorderRadius.circular(accountsV2Radius),
        border: Border.all(color: AccountsV2Colors.cardBorder),
      ),
      child: child,
    );
  }
}

/// A card heading with a plain blue icon (`.ch`).
class AccountsV2CardHead extends StatelessWidget {
  const AccountsV2CardHead({
    super.key,
    required this.title,
    this.icon,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? icon;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    final heading = _HeadingText(title: title, subtitle: subtitle);
    return Padding(
      padding: phone
          ? const EdgeInsets.fromLTRB(14, 14, 14, 8)
          : const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: _HeadRow(
        leading: icon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 1),
                child: AccountsV2Icon(
                  icon!,
                  size: 21,
                  color: AccountsV2Colors.pri,
                ),
              ),
        heading: heading,
        actions: actions,
        alignTop: true,
        wrap: phone,
      ),
    );
  }
}

/// A card heading with a tinted icon tile and a rule below (`.ch.tile`).
class AccountsV2TileHead extends StatelessWidget {
  const AccountsV2TileHead({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = AccountsV2Tone.blue,
    this.actions = const [],
    this.divider = true,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final AccountsV2Tone tone;
  final List<Widget> actions;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    return Container(
      padding: phone
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        border: divider
            ? const Border(bottom: BorderSide(color: AccountsV2Colors.line))
            : null,
      ),
      child: _HeadRow(
        leading: AccountsV2IconTile(icon: icon, tone: tone),
        heading: _HeadingText(title: title, subtitle: subtitle),
        actions: actions,
        gap: 14,
        wrap: phone,
      ),
    );
  }
}

class _HeadingText extends StatelessWidget {
  const _HeadingText({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: v2Style(16, weight: FontWeight.w700, height: 1.3)),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: v2Style(12.5, color: AccountsV2Colors.ink2, height: 1.4),
            ),
          ),
      ],
    );
  }
}

class _HeadRow extends StatelessWidget {
  const _HeadRow({
    required this.heading,
    this.leading,
    this.actions = const [],
    this.gap = 12,
    this.alignTop = false,
    this.wrap = false,
  });

  final Widget? leading;
  final Widget heading;
  final List<Widget> actions;
  final double gap;
  final bool alignTop;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final actionRow = actions.isEmpty
        ? null
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: actions,
          );
    final head = Row(
      crossAxisAlignment: alignTop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[leading!, SizedBox(width: gap)],
        Expanded(child: heading),
        if (actionRow != null && !wrap) ...[
          const SizedBox(width: 8),
          actionRow,
        ],
      ],
    );
    if (actionRow == null || !wrap) return head;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [head, const SizedBox(height: 8), actionRow],
    );
  }
}

/// Card body padding (`.cb`).
class AccountsV2CardBody extends StatelessWidget {
  const AccountsV2CardBody({super.key, required this.child, this.top = 8});

  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    return Padding(
      padding: phone
          ? EdgeInsets.fromLTRB(14, top, 14, 14)
          : EdgeInsets.fromLTRB(18, top, 18, 16),
      child: child,
    );
  }
}

/// Cards stacked with the prototype gap (`.stack`).
class AccountsV2Stack extends StatelessWidget {
  const AccountsV2Stack({
    super.key,
    required this.children,
    this.gap = accountsV2Gap,
  });

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) SizedBox(height: gap),
          child,
        ],
      ],
    );
  }
}

// ─── KPI tiles ───────────────────────────────────────────────────────────────

/// One KPI card: tinted icon, label, value and a line beneath (`.card.kpi`).
class AccountsV2KpiCard extends StatelessWidget {
  const AccountsV2KpiCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.tone = AccountsV2Tone.blue,
    this.valueTone = AccountsV2ValueTone.plain,
  });

  final String icon;
  final AccountsV2Tone tone;
  final String label;
  final String value;
  final String caption;
  final AccountsV2ValueTone valueTone;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    final small = phone ? 11.5 : 12.0;
    return AccountsV2Panel(
      padding: phone
          ? const EdgeInsets.all(10)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (phone ? 74 : 86) - (phone ? 20 : 28),
        ),
        child: Row(
          children: [
            AccountsV2IconTile(
              icon: icon,
              tone: tone,
              size: phone ? 32 : 42,
              radius: phone ? 9 : 11,
              iconSize: phone ? 17 : 21,
            ),
            SizedBox(width: phone ? 9 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: v2Style(
                      small,
                      color: AccountsV2Colors.ink2,
                      height: 1.35,
                    ),
                  ),
                  Tooltip(
                    message: value,
                    waitDuration: const Duration(milliseconds: 600),
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: v2Style(
                        phone ? 14 : 16,
                        weight: FontWeight.w700,
                        color: valueTone.color,
                        height: 1.4,
                        tabular: true,
                      ),
                    ),
                  ),
                  Text(
                    caption,
                    style: v2Style(
                      small,
                      color: AccountsV2Colors.ink2,
                      height: 1.35,
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
}

/// KPI cards laid out like CSS `repeat(auto-fit, minmax(188px, 1fr))`: as many
/// equal columns as fit, never more than there are cards. Phones use two.
class AccountsV2KpiRow extends StatelessWidget {
  const AccountsV2KpiRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    final gap = phone ? 10.0 : accountsV2Gap;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = phone
            ? 2
            : ((constraints.maxWidth + gap) / (188 + gap)).floor().clamp(
                1,
                children.length,
              );
        // Balanced rows: six tiles that cannot sit in one row become 3 + 3,
        // never 5 + 1.
        final rows = (children.length / fit).ceil();
        final columns = (children.length / rows).ceil();
        return AccountsV2Grid(columns: columns, gap: gap, children: children);
      },
    );
  }
}

/// Equal columns with rows stretched to their tallest cell, like CSS grid.
class AccountsV2Grid extends StatelessWidget {
  const AccountsV2Grid({
    super.key,
    required this.columns,
    required this.children,
    this.gap = accountsV2Gap,
    this.flexes,
  });

  final int columns;
  final List<Widget> children;
  final double gap;

  /// Relative widths per column; equal when null.
  final List<int>? flexes;

  @override
  Widget build(BuildContext context) {
    final cols = columns.clamp(1, children.isEmpty ? 1 : children.length);
    final rows = <List<Widget>>[
      for (var i = 0; i < children.length; i += cols)
        children.sublist(i, (i + cols).clamp(0, children.length)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (r, row) in rows.indexed) ...[
          if (r > 0) SizedBox(height: gap),
          _EqualHeightRow(
            gap: gap,
            flexes: [
              for (var c = 0; c < cols; c++)
                flexes != null && c < flexes!.length ? flexes![c] : 1,
            ],
            children: [
              for (var c = 0; c < cols; c++)
                c < row.length ? row[c] : const SizedBox.shrink(),
            ],
          ),
        ],
      ],
    );
  }
}

/// A row whose cells share the tallest cell's height. Cells are laid out once
/// to measure and once at that height, so no intrinsic measuring is involved
/// (it can come out a pixel short of the real layout).
class _EqualHeightRow extends MultiChildRenderObjectWidget {
  const _EqualHeightRow({
    required this.gap,
    required this.flexes,
    required super.children,
  });

  final double gap;
  final List<int> flexes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightRow(gap: gap, flexes: flexes);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderEqualHeightRow renderObject,
  ) {
    renderObject
      ..gap = gap
      ..flexes = flexes;
  }
}

class _EqualHeightRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EqualHeightRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EqualHeightRowParentData> {
  _RenderEqualHeightRow({required double gap, required List<int> flexes})
    : _gap = gap,
      _flexes = flexes;

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  List<int> _flexes;
  set flexes(List<int> value) {
    if (listEquals(value, _flexes)) return;
    _flexes = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualHeightRowParentData) {
      child.parentData = _EqualHeightRowParentData();
    }
  }

  List<double> _widths(double total) {
    final count = childCount;
    final flexSum = [
      for (var i = 0; i < count; i++) i < _flexes.length ? _flexes[i] : 1,
    ].fold<int>(0, (a, f) => a + f);
    final room = (total - _gap * (count - 1)).clamp(0.0, double.infinity);
    return [
      for (var i = 0; i < count; i++)
        flexSum == 0
            ? 0
            : room * (i < _flexes.length ? _flexes[i] : 1) / flexSum,
    ];
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final widths = _widths(width);
    var height = 0.0;
    var child = firstChild;
    var i = 0;
    while (child != null) {
      child.layout(
        BoxConstraints.tightFor(width: widths[i]),
        parentUsesSize: true,
      );
      if (child.size.height > height) height = child.size.height;
      child = childAfter(child);
      i++;
    }
    height = constraints.constrainHeight(height);
    var x = 0.0;
    child = firstChild;
    i = 0;
    while (child != null) {
      // Not quite tight: a cell laid out under tight constraints becomes its
      // own layout boundary, and a later change inside it (new text, a value
      // typed) would never reach this row to re-measure. The sliver of slack
      // keeps every cell reporting up.
      child.layout(
        BoxConstraints(
          minWidth: widths[i],
          maxWidth: widths[i],
          minHeight: height,
          maxHeight: height + 0.001,
        ),
        parentUsesSize: true,
      );
      (child.parentData! as _EqualHeightRowParentData).offset = Offset(x, 0);
      x += widths[i] + _gap;
      child = childAfter(child);
      i++;
    }
    size = constraints.constrain(Size(width, height));
  }

  double _maxChildHeight(double width, bool min) {
    final widths = _widths(width);
    var height = 0.0;
    var child = firstChild;
    var i = 0;
    while (child != null) {
      final h = min
          ? child.getMinIntrinsicHeight(widths[i])
          : child.getMaxIntrinsicHeight(widths[i]);
      if (h > height) height = h;
      child = childAfter(child);
      i++;
    }
    return height;
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _maxChildHeight(width, true);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _maxChildHeight(width, false);

  @override
  double computeMinIntrinsicWidth(double height) {
    var total = 0.0;
    var child = firstChild;
    while (child != null) {
      total += child.getMinIntrinsicWidth(height);
      child = childAfter(child);
    }
    return total + _gap * (childCount - 1).clamp(0, 1 << 20);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var total = 0.0;
    var child = firstChild;
    while (child != null) {
      total += child.getMaxIntrinsicWidth(height);
      child = childAfter(child);
    }
    return total + _gap * (childCount - 1).clamp(0, 1 << 20);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final widths = _widths(constraints.maxWidth);
    var height = 0.0;
    var child = firstChild;
    var i = 0;
    while (child != null) {
      final h = child
          .getDryLayout(BoxConstraints.tightFor(width: widths[i]))
          .height;
      if (h > height) height = h;
      child = childAfter(child);
      i++;
    }
    return constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

// ─── Buttons ─────────────────────────────────────────────────────────────────

enum AccountsV2ButtonKind { normal, primary, ok, ghost, danger, ghostDanger }

enum AccountsV2ButtonSize { small, medium, large }

/// The prototype's `.btn` in each of its variants.
class AccountsV2Button extends StatelessWidget {
  const AccountsV2Button({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.kind = AccountsV2ButtonKind.normal,
    this.size = AccountsV2ButtonSize.medium,
    this.block = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? icon;
  final AccountsV2ButtonKind kind;
  final AccountsV2ButtonSize size;
  final bool block;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final small = size == AccountsV2ButtonSize.small;
    final large = size == AccountsV2ButtonSize.large;
    final primary = kind == AccountsV2ButtonKind.primary;
    final okKind = kind == AccountsV2ButtonKind.ok;
    final ghost =
        kind == AccountsV2ButtonKind.ghost ||
        kind == AccountsV2ButtonKind.ghostDanger;
    final danger =
        kind == AccountsV2ButtonKind.danger ||
        kind == AccountsV2ButtonKind.ghostDanger;
    final height = small ? 30.0 : (large ? 44.0 : 36.0);
    final radius = primary ? 999.0 : (small ? 8.0 : (large ? 12.0 : 10.0));
    final hPad = primary
        ? (small ? 14.0 : (large ? 24.0 : 18.0))
        : (small ? 11.0 : (large ? 18.0 : 14.0));
    final fontSize = small ? 12.0 : (large ? 13.5 : 13.0);
    final iconSize = small ? 15.0 : (large ? 19.0 : 17.0);
    final gap = small ? 6.0 : (large ? 10.0 : 8.0);
    final Color background = primary
        ? AccountsV2Colors.pri
        : okKind
        ? AccountsV2Colors.ok
        : ghost
        ? Colors.transparent
        : Colors.white;
    final Color foreground = (primary || okKind)
        ? Colors.white
        : danger
        ? AccountsV2Colors.bad
        : ghost
        ? AccountsV2Colors.pri
        : AccountsV2Colors.ink2;
    final Color border = primary
        ? AccountsV2Colors.pri
        : okKind
        ? AccountsV2Colors.ok
        : ghost
        ? Colors.transparent
        : AccountsV2Colors.line;
    final Color hoverFill = primary
        ? AccountsV2Colors.priDark
        : okKind
        ? AccountsV2Colors.ok
        : ghost
        ? AccountsV2Colors.pri50
        : AccountsV2Colors.buttonHover;
    final enabled = onPressed != null;

    final content = Row(
      mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          AccountsV2Icon(icon!, size: iconSize, color: foreground),
          if (label.isNotEmpty) SizedBox(width: gap),
        ],
        if (label.isNotEmpty)
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: v2Style(
                fontSize,
                weight: FontWeight.w700,
                color: foreground,
                height: 1.2,
              ),
            ),
          ),
      ],
    );

    Widget button = Opacity(
      opacity: enabled ? 1 : .45,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          hoverColor: hoverFill.withValues(alpha: primary ? 1 : .9),
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.forbidden,
          // Aligned only as a block: an aligned box grows to fill any width it
          // is offered, which would stretch a button placed in an Align.
          child: Container(
            height: height,
            constraints: BoxConstraints(minWidth: label.isEmpty ? height : 0),
            padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 0 : hPad),
            alignment: block || label.isEmpty ? Alignment.center : null,
            child: content,
          ),
        ),
      ),
    );
    if (block) button = SizedBox(width: double.infinity, child: button);
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: button,
    );
  }
}

// ─── Chips ───────────────────────────────────────────────────────────────────

enum AccountsV2ChipTone {
  neutral(AccountsV2Colors.neu, AccountsV2Colors.neuText),
  ok(AccountsV2Colors.ok50, AccountsV2Colors.ok),
  warn(AccountsV2Colors.warn50, AccountsV2Colors.warn),
  bad(AccountsV2Colors.bad50, AccountsV2Colors.bad),
  pri(AccountsV2Colors.pri50, AccountsV2Colors.pri),
  vio(AccountsV2Colors.vio50, AccountsV2Colors.vio);

  const AccountsV2ChipTone(this.background, this.foreground);

  final Color background;
  final Color foreground;
}

/// A pill label (`.chip`).
class AccountsV2Chip extends StatelessWidget {
  const AccountsV2Chip(
    this.label, {
    super.key,
    this.tone = AccountsV2ChipTone.neutral,
    this.icon,
  });

  final String label;
  final AccountsV2ChipTone tone;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AccountsV2Icon(icon!, size: 13, color: tone.foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: v2Style(
                11.5,
                weight: FontWeight.w700,
                color: tone.foreground,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small count or word badge on a sub-tab (`.atab .bdg`).
class AccountsV2TabBadge extends StatelessWidget {
  const AccountsV2TabBadge(this.label, {super.key, this.bad = false});

  final String label;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bad ? AccountsV2Colors.bad50 : AccountsV2Colors.warn50,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: v2Style(
          10,
          weight: FontWeight.w700,
          color: bad ? AccountsV2Colors.bad : AccountsV2Colors.warn,
          height: 1,
        ),
      ),
    );
  }
}

// ─── Outlined fields ─────────────────────────────────────────────────────────

/// Field height variants (`.of.sm`, `.of`, `.of.lg`).
enum AccountsV2FieldSize { small, medium, large }

InputDecoration _outlinedDecoration({
  required String label,
  required AccountsV2FieldSize size,
  Widget? prefix,
  bool error = false,
}) {
  final height = switch (size) {
    AccountsV2FieldSize.small => 32.0,
    AccountsV2FieldSize.medium => 36.0,
    AccountsV2FieldSize.large => 42.0,
  };
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    isDense: true,
    // The label floats over the border, as in the prototype; the text keeps
    // the field at its exact height.
    floatingLabelBehavior: FloatingLabelBehavior.always,
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    labelStyle: v2Style(14, color: AccountsV2Colors.mut, height: 1),
    floatingLabelStyle: v2Style(14, color: AccountsV2Colors.mut, height: 1),
    constraints: BoxConstraints(minHeight: height, maxHeight: height),
    contentPadding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: (height - 20) / 2,
    ),
    prefixIcon: prefix,
    prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 20),
    filled: true,
    fillColor: error ? AccountsV2Colors.bad50 : Colors.white,
    hoverColor: Colors.white,
    border: border(AccountsV2Colors.lineS),
    enabledBorder: border(
      error ? AccountsV2Colors.bad : AccountsV2Colors.lineS,
    ),
    disabledBorder: border(AccountsV2Colors.line),
    focusedBorder: border(AccountsV2Colors.pri, 2),
  );
}

/// An outlined dropdown with its label on the border (`.of select`).
class AccountsV2Select<T> extends StatelessWidget {
  const AccountsV2Select({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.width,
    this.size = AccountsV2FieldSize.medium,
  });

  final String label;
  final T value;
  final List<(T value, String text)> options;
  final ValueChanged<T>? onChanged;
  final double? width;
  final AccountsV2FieldSize size;

  @override
  Widget build(BuildContext context) {
    final small = size == AccountsV2FieldSize.small;
    final field = DropdownButtonFormField<T>(
      initialValue: options.any((o) => o.$1 == value)
          ? value
          : (options.isEmpty ? null : options.first.$1),
      key: ValueKey('$label|$value'),
      isExpanded: true,
      isDense: true,
      icon: const AccountsV2Icon(
        'caret',
        size: 20,
        color: AccountsV2Colors.ink2,
      ),
      decoration: _outlinedDecoration(label: label, size: size).copyWith(
        contentPadding: EdgeInsets.fromLTRB(
          12,
          small ? 6 : 8,
          9,
          small ? 6 : 8,
        ),
      ),
      style: v2Style(
        small ? 12.5 : 14,
        weight: small ? FontWeight.w600 : FontWeight.w500,
        height: 1.3,
      ),
      borderRadius: BorderRadius.circular(10),
      dropdownColor: Colors.white,
      items: [
        for (final (v, text) in options)
          DropdownMenuItem<T>(
            value: v,
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != null) onChanged!(v);
            },
    );
    return SizedBox(width: width, child: field);
  }
}

/// An outlined text field with its label on the border (`.of input`).
class AccountsV2TextField extends StatelessWidget {
  const AccountsV2TextField({
    super.key,
    required this.label,
    required this.controller,
    this.onChanged,
    this.numeric = false,
    this.size = AccountsV2FieldSize.medium,
    this.width,
    this.hint,
    this.search = false,
    this.enabled = true,
    this.error = false,
    this.suffix,
    this.onTap,
    this.readOnly = false,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool numeric;
  final AccountsV2FieldSize size;
  final double? width;
  final String? hint;
  final bool search;
  final bool enabled;
  final bool error;
  final Widget? suffix;
  final VoidCallback? onTap;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      enabled: enabled,
      readOnly: readOnly,
      onTap: onTap,
      onChanged: onChanged,
      textAlign: numeric ? TextAlign.right : TextAlign.start,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: v2Style(
        14,
        weight: FontWeight.w500,
        color: enabled ? AccountsV2Colors.ink : AccountsV2Colors.ink2,
        height: 1.3,
        tabular: numeric,
      ),
      decoration:
          _outlinedDecoration(
            label: label,
            size: size,
            error: error,
            prefix: search
                ? const Padding(
                    padding: EdgeInsets.only(left: 10, right: 2),
                    child: AccountsV2Icon(
                      'search',
                      size: 15,
                      color: AccountsV2Colors.mut,
                    ),
                  )
                : null,
          ).copyWith(
            hintText: hint,
            hintStyle: v2Style(14, color: AccountsV2Colors.mut2),
            suffixIcon: suffix,
            fillColor: enabled ? null : AccountsV2Colors.bg,
          ),
    );
    return SizedBox(width: width, child: field);
  }
}

/// A plain bordered input used inside tables (`input.in`).
class AccountsV2CellInput extends StatelessWidget {
  const AccountsV2CellInput({
    super.key,
    required this.controller,
    this.onChanged,
    this.numeric = false,
    this.bold = false,
    this.hint,
    this.enabled = true,
    this.error = false,
    this.focusNode,
    this.onSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool numeric;
  final bool bold;
  final String? hint;
  final bool enabled;
  final bool error;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: color, width: width),
        );
    return SizedBox(
      height: 34,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: textInputAction,
        textAlign: numeric ? TextAlign.right : TextAlign.start,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: v2Style(
          13,
          weight: bold ? FontWeight.w700 : FontWeight.w400,
          color: enabled ? AccountsV2Colors.ink : AccountsV2Colors.ink2,
          height: 1.2,
          tabular: numeric,
        ),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: v2Style(13, color: AccountsV2Colors.mut2),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 9,
          ),
          filled: true,
          fillColor: error
              ? AccountsV2Colors.bad50
              : enabled
              ? Colors.white
              : AccountsV2Colors.bg,
          border: border(AccountsV2Colors.line),
          enabledBorder: border(
            error ? AccountsV2Colors.bad : AccountsV2Colors.line,
          ),
          disabledBorder: border(Colors.transparent),
          focusedBorder: border(AccountsV2Colors.pri, 2),
        ),
      ),
    );
  }
}

// ─── Tables ──────────────────────────────────────────────────────────────────

/// A table column: a fixed width, or a share of what is left.
final class AccountsV2Column {
  const AccountsV2Column(
    this.label, {
    this.width,
    this.flex = 1,
    this.numeric = false,
    this.center = false,
  });

  final String label;
  final double? width;
  final int flex;
  final bool numeric;
  final bool center;

  Alignment get alignment => numeric
      ? Alignment.centerRight
      : center
      ? Alignment.center
      : Alignment.centerLeft;
}

/// One table row.
final class AccountsV2Row {
  const AccountsV2Row(this.cells, {this.onTap, this.key});

  final List<Widget> cells;
  final VoidCallback? onTap;
  final Key? key;
}

/// The prototype's table: uppercase header on a pale band, roomy rows with a
/// faint rule, optional footer band. Scrolls sideways below [minWidth].
class AccountsV2Table extends StatelessWidget {
  const AccountsV2Table({
    super.key,
    required this.columns,
    required this.rows,
    this.footer,
    this.minWidth = 0,
    this.boxed = false,
    this.emptyRow,
    this.footerSpans,
  });

  final List<AccountsV2Column> columns;
  final List<AccountsV2Row> rows;
  final List<Widget>? footer;

  /// How many columns each footer cell spans (`colspan`); one each when null.
  final List<int>? footerSpans;
  final double minWidth;

  /// Bordered, rounded box used inside the workbench (`.tw.boxed`).
  final bool boxed;

  /// Shown across the whole table when there are no rows.
  final Widget? emptyRow;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    // Never narrower than the fixed columns plus some room for each flexible
    // one: below that the table scrolls sideways instead of crushing a column.
    final fixed = columns.fold<double>(0, (a, c) => a + (c.width ?? 0));
    final flexible = columns.where((c) => c.width == null).length;
    final needed = fixed + flexible * 96;
    final requested = phone ? (minWidth > 0 ? minWidth : 600.0) : minWidth;
    final floor = requested > needed ? requested : needed;
    return LayoutBuilder(
      builder: (context, constraints) {
        // A boxed table's border takes a pixel each side.
        final available = constraints.maxWidth - (boxed ? 2 : 0);
        final width = available < floor ? floor : available;
        final table = SizedBox(width: width, child: _body(width));
        final content = width > available
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              )
            : table;
        if (!boxed) return content;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AccountsV2Colors.line),
          ),
          child: content,
        );
      },
    );
  }

  List<double> _widths(double total) {
    final fixed = columns.fold<double>(0, (a, c) => a + (c.width ?? 0));
    final flexTotal = columns.fold<int>(
      0,
      (a, c) => a + (c.width == null ? c.flex : 0),
    );
    final rest = (total - fixed).clamp(0, double.infinity);
    return [
      for (final c in columns)
        c.width ?? (flexTotal == 0 ? 0 : rest * c.flex / flexTotal),
    ];
  }

  Widget _body(double width) {
    final widths = _widths(width);
    Widget cellBox(int i, Widget child, {bool head = false}) => SizedBox(
      width: widths[i],
      child: Padding(
        padding: head
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Align(alignment: columns[i].alignment, child: child),
      ),
    );
    final header = Container(
      decoration: const BoxDecoration(
        color: AccountsV2Colors.tableHead,
        border: Border(bottom: BorderSide(color: AccountsV2Colors.line)),
      ),
      child: Row(
        children: [
          for (final (i, c) in columns.indexed)
            cellBox(
              i,
              Text(
                c.label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: c.numeric
                    ? TextAlign.right
                    : c.center
                    ? TextAlign.center
                    : TextAlign.left,
                style: v2Style(
                  11,
                  weight: FontWeight.w700,
                  color: AccountsV2Colors.mut,
                  letterSpacing: .44,
                  height: 1.4,
                ),
              ),
              head: true,
            ),
        ],
      ),
    );
    final body = <Widget>[
      for (final (r, row) in rows.indexed)
        _TableRow(
          key: row.key,
          onTap: row.onTap,
          last: r == rows.length - 1 && footer == null,
          child: Row(
            children: [
              for (final (i, cell) in row.cells.indexed)
                if (i < columns.length) cellBox(i, cell),
            ],
          ),
        ),
      if (rows.isEmpty && emptyRow != null) emptyRow!,
    ];
    final foot = footer == null
        ? null
        : Container(
            constraints: const BoxConstraints(minHeight: 42),
            decoration: const BoxDecoration(
              color: AccountsV2Colors.tableHead,
              border: Border(top: BorderSide(color: AccountsV2Colors.line)),
            ),
            child: DefaultTextStyle.merge(
              style: v2Style(12.5, weight: FontWeight.w700),
              child: Row(children: _footerCells(widths, cellBox)),
            ),
          );
    return DefaultTextStyle.merge(
      style: v2Style(12.5, height: 1.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, ...body, ?foot],
      ),
    );
  }
}

extension on AccountsV2Table {
  List<Widget> _footerCells(
    List<double> widths,
    Widget Function(int i, Widget child, {bool head}) cellBox,
  ) {
    final spans = footerSpans;
    if (spans == null) {
      return [
        for (final (i, cell) in footer!.indexed)
          if (i < columns.length) cellBox(i, cell),
      ];
    }
    final out = <Widget>[];
    var column = 0;
    for (final (i, cell) in footer!.indexed) {
      final span = i < spans.length ? spans[i] : 1;
      if (column >= columns.length) break;
      final last = (column + span).clamp(0, columns.length);
      final width = widths
          .sublist(column, last)
          .fold<double>(0, (a, w) => a + w);
      out.add(
        SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Align(alignment: columns[last - 1].alignment, child: cell),
          ),
        ),
      );
      column = last;
    }
    return out;
  }
}

class _TableRow extends StatefulWidget {
  const _TableRow({
    super.key,
    required this.child,
    required this.last,
    this.onTap,
  });

  final Widget child;
  final bool last;
  final VoidCallback? onTap;

  @override
  State<_TableRow> createState() => _TableRowState();
}

class _TableRowState extends State<_TableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 46),
      decoration: BoxDecoration(
        color: _hover && widget.onTap != null
            ? AccountsV2Colors.rowHover
            : Colors.transparent,
        border: widget.last
            ? null
            : const Border(bottom: BorderSide(color: AccountsV2Colors.line2)),
      ),
      alignment: Alignment.centerLeft,
      child: widget.child,
    );
    if (widget.onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: row,
      ),
    );
  }
}

/// Bold first line with a small muted line beneath, for a table cell.
class AccountsV2CellStack extends StatelessWidget {
  const AccountsV2CellStack({
    super.key,
    required this.primary,
    this.secondary,
    this.primaryStyle,
    this.secondaryColor = AccountsV2Colors.mut,
    this.end = false,
  });

  final String primary;
  final String? secondary;
  final TextStyle? primaryStyle;
  final Color secondaryColor;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(primary, style: primaryStyle, maxLines: 2),
        if (secondary != null && secondary!.isNotEmpty)
          Text(
            secondary!,
            style: v2Style(12, color: secondaryColor, height: 1.4),
          ),
      ],
    );
  }
}

// ─── Key/value rows ──────────────────────────────────────────────────────────

/// A label and a bold amount on one line (`.kvr`, `.kvr.sum`).
class AccountsV2KeyValue extends StatelessWidget {
  const AccountsV2KeyValue({
    super.key,
    required this.label,
    required this.value,
    this.tone = AccountsV2ValueTone.plain,
    this.sum = false,
  });

  final String label;
  final String value;
  final AccountsV2ValueTone tone;
  final bool sum;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: sum ? 4 : 0),
      padding: EdgeInsets.only(top: sum ? 10 : 6, bottom: 6),
      constraints: const BoxConstraints(minHeight: 31),
      decoration: sum
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: AccountsV2Colors.line)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: v2Style(
                12.5,
                color: sum ? AccountsV2Colors.ink : AccountsV2Colors.mut,
                weight: sum ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            value,
            style: v2Style(
              sum ? 13 : 12,
              weight: FontWeight.w700,
              color: tone.color,
              tabular: true,
            ),
          ),
        ],
      ),
    );
  }
}

/// A ruled label/value line in a side panel (`.ldr`).
class AccountsV2LedgerRow extends StatelessWidget {
  const AccountsV2LedgerRow({
    super.key,
    required this.label,
    required this.value,
    this.tone = AccountsV2ValueTone.plain,
  });

  final String label;
  final String value;
  final AccountsV2ValueTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AccountsV2Colors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 105,
            child: Text(
              label,
              style: v2Style(12.5, color: AccountsV2Colors.ink2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 100,
            child: Text(
              value,
              style: v2Style(
                12,
                weight: FontWeight.w700,
                color: tone.color,
                tabular: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Notes, explainers, empty states ─────────────────────────────────────────

enum AccountsV2NoteTone { info, warn, bad, ok }

/// The left-ruled information band (`.note`).
class AccountsV2Note extends StatelessWidget {
  const AccountsV2Note({
    super.key,
    required this.child,
    this.tone = AccountsV2NoteTone.info,
    this.trailing,
  });

  /// Usually a [Text] or [Text.rich]; styled to the note's text colour.
  final Widget child;
  final AccountsV2NoteTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final (bg, border, rule, iconColor, icon) = switch (tone) {
      AccountsV2NoteTone.info => (
        const Color(0xFFF1F6FE),
        const Color(0xFFDCE8FB),
        const Color(0xFF7BA8EE),
        AccountsV2Colors.pri,
        'info',
      ),
      AccountsV2NoteTone.warn => (
        const Color(0xFFFFF8EA),
        const Color(0xFFF6E2B8),
        const Color(0xFFE0A33A),
        AccountsV2Colors.warn,
        'alert',
      ),
      AccountsV2NoteTone.bad => (
        const Color(0xFFFFF4F4),
        const Color(0xFFF6D3D3),
        const Color(0xFFE07A7A),
        AccountsV2Colors.bad,
        'alert',
      ),
      AccountsV2NoteTone.ok => (
        const Color(0xFFF0FAF6),
        const Color(0xFFCDEBDD),
        const Color(0xFF5DBB93),
        AccountsV2Colors.ok,
        'check',
      ),
    };
    // A rounded box cannot take a differently coloured side, so the accent
    // rule is painted over the left edge inside the same rounded clip.
    final text = DefaultTextStyle.merge(
      style: v2Style(12.5, color: AccountsV2Colors.ink2),
      child: child,
    );
    // On a phone the buttons go under the words rather than squeezing them.
    final stacked = trailing != null && AccountsV2Breakpoints.isPhone(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
            ),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AccountsV2Icon(icon, color: iconColor),
                          const SizedBox(width: 10),
                          Expanded(child: text),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: trailing,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      AccountsV2Icon(icon, color: iconColor),
                      const SizedBox(width: 10),
                      Expanded(child: text),
                      if (trailing != null) ...[
                        const SizedBox(width: 10),
                        trailing!,
                      ],
                    ],
                  ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: rule),
          ),
        ],
      ),
    );
  }
}

/// The grey explainer strip with inline formula chips (`.how`).
class AccountsV2How extends StatelessWidget {
  const AccountsV2How({super.key, required this.spans});

  /// Plain text and `code` pieces, in order: (text, isCode).
  final List<(String text, bool code)> spans;

  @override
  Widget build(BuildContext context) {
    final base = v2Style(12.5, color: AccountsV2Colors.ink2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AccountsV2Colors.bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            for (final (text, code) in spans)
              if (code)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AccountsV2Colors.line),
                    ),
                    child: Text(text, style: v2Style(12)),
                  ),
                )
              else
                TextSpan(text: text),
          ],
        ),
      ),
    );
  }
}

/// Centred icon, heading and line for "nothing here yet" (`.empty`).
class AccountsV2Empty extends StatelessWidget {
  const AccountsV2Empty({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final String icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AccountsV2IconTile(icon: icon, size: 46),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: v2Style(16, weight: FontWeight.w700),
              ),
              if (body != null && body!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: v2Style(13, color: AccountsV2Colors.ink2),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 10), action!],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Bars ────────────────────────────────────────────────────────────────────

/// A rounded progress track filled by one or more coloured segments (`.pbar`).
class AccountsV2Bar extends StatelessWidget {
  const AccountsV2Bar({
    super.key,
    required this.segments,
    this.height = 8,
    this.radius,
  });

  /// (fraction of the whole 0..1, colour), drawn left to right.
  final List<(double fraction, Color color)> segments;
  final double height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    // Flex shares, not measured widths, so the bar can sit inside rows that
    // size themselves to their content (equal-height card rows).
    var used = 0;
    final flexes = <(int, Color)>[];
    for (final (fraction, color) in segments) {
      final share = (fraction.clamp(0.0, 1.0) * 10000).round().clamp(
        0,
        10000 - used,
      );
      if (share > 0) flexes.add((share, color));
      used += share;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? height),
      child: Container(
        height: height,
        color: AccountsV2Colors.track,
        child: Row(
          // Segments fill the track's height; a bare colour box has none.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (flex, color) in flexes)
              Expanded(
                flex: flex,
                child: ColoredBox(color: color),
              ),
            if (used < 10000) Spacer(flex: 10000 - used),
          ],
        ),
      ),
    );
  }
}

/// A two-column layout with a fixed side panel that stacks below on narrower
/// windows (`.split`, 330px side; one column at ≤1180px).
class AccountsV2Split extends StatelessWidget {
  const AccountsV2Split({
    super.key,
    required this.main,
    required this.side,
    this.sideWidth = 330,
  });

  final Widget main;
  final Widget side;
  final double sideWidth;

  @override
  Widget build(BuildContext context) {
    if (AccountsV2Breakpoints.isMedium(context)) {
      return AccountsV2Stack(children: [main, side]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        const SizedBox(width: accountsV2Gap),
        SizedBox(width: sideWidth, child: side),
      ],
    );
  }
}

/// The white "Report actions" strip at the top of a register (`.card.ra`).
class AccountsV2ReportActions extends StatelessWidget {
  const AccountsV2ReportActions({
    super.key,
    required this.title,
    required this.actions,
    this.primary,
  });

  final String title;
  final List<Widget> actions;
  final Widget? primary;

  @override
  Widget build(BuildContext context) {
    final phone = AccountsV2Breakpoints.isPhone(context);
    final heading = Text(title, style: v2Style(16, weight: FontWeight.w700));
    return AccountsV2Panel(
      padding: phone
          ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [...actions, ?primary],
                ),
              ],
            )
          : Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: heading,
                ),
                for (final (i, action) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  action,
                ],
                const Spacer(),
                ?primary,
              ],
            ),
    );
  }
}

// ─── Drawer, sections and mini stats ────────────────────────────────────────

/// Opens a right-hand drawer as the prototype does (`.ov.drawer .md`): 600px
/// wide, full height, rounded on the left, over a dimmed page. Phones get the
/// whole width. [builder] draws the body; the header and close are provided.
Future<T?> showAccountsV2Drawer<T>(
  BuildContext context, {
  required Widget title,
  required WidgetBuilder builder,
  String closeLabel = 'Close',
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: closeLabel,
    barrierColor: const Color(0x61132033),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, _, _) {
      final width = MediaQuery.sizeOf(dialogContext).width;
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Material(
          color: Colors.white,
          elevation: 12,
          shadowColor: const Color(0x40132033),
          borderRadius: const BorderRadiusDirectional.horizontal(
            start: Radius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width < 600 ? width : 600,
            height: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AccountsV2Colors.line),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DefaultTextStyle.merge(
                          style: v2Style(17, weight: FontWeight.w700),
                          child: title,
                        ),
                      ),
                      Tooltip(
                        message: closeLabel,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.of(dialogContext).pop(),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: AccountsV2Icon(
                              'x',
                              size: 20,
                              color: AccountsV2Colors.mut,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: builder(dialogContext)),
              ],
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, animation, _, child) {
      final reduce = MediaQuery.of(context).disableAnimations;
      if (reduce) return child;
      return SlideTransition(
        position: Tween(begin: const Offset(.08, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

/// A small uppercase section label inside a drawer (`.sect`).
class AccountsV2Section extends StatelessWidget {
  const AccountsV2Section(this.label, {super.key, this.first = false});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 20, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: v2Style(
          11.5,
          weight: FontWeight.w700,
          color: AccountsV2Colors.mut,
          letterSpacing: .58,
        ),
      ),
    );
  }
}

/// One of the three bordered figures at the top of a drawer (`.mstats>div`).
class AccountsV2MiniStat extends StatelessWidget {
  const AccountsV2MiniStat({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    this.tone = AccountsV2ValueTone.plain,
  });

  final String label;
  final String value;
  final String caption;
  final AccountsV2ValueTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AccountsV2Colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: v2Style(11.5, color: AccountsV2Colors.ink2)),
          const SizedBox(height: 1),
          Text(
            value,
            style: v2Style(
              15,
              weight: FontWeight.w700,
              color: tone.color,
              tabular: true,
            ),
          ),
          const SizedBox(height: 1),
          Text(caption, style: v2Style(11, color: AccountsV2Colors.mut)),
        ],
      ),
    );
  }
}

/// A vertical list of steps with a joining rule (`.timeline .tl`). Each step is
/// 0 = to do, 1 = current, 2 = done.
class AccountsV2Timeline extends StatelessWidget {
  const AccountsV2Timeline({super.key, required this.steps});

  final List<({String title, String detail, int state})> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, step) in steps.indexed)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 24,
                  child: Stack(
                    children: [
                      if (i < steps.length - 1)
                        const Positioned(
                          left: 7,
                          top: 6,
                          bottom: 0,
                          child: SizedBox(
                            width: 2,
                            child: ColoredBox(color: AccountsV2Colors.line),
                          ),
                        ),
                      Positioned(
                        left: 3,
                        top: 4,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: switch (step.state) {
                              2 => AccountsV2Colors.ok,
                              1 => AccountsV2Colors.pri,
                              _ => Colors.white,
                            },
                            border: Border.all(
                              width: 2,
                              color: switch (step.state) {
                                2 => AccountsV2Colors.ok,
                                1 => AccountsV2Colors.pri,
                                _ => AccountsV2Colors.line,
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: v2Style(13, weight: FontWeight.w700),
                        ),
                        Text(
                          step.detail,
                          style: v2Style(12.5, color: AccountsV2Colors.ink2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A file pill (`.file`).
class AccountsV2FilePill extends StatelessWidget {
  const AccountsV2FilePill({
    super.key,
    required this.label,
    this.onTap,
    this.icon = 'doc',
    this.accent = false,
  });

  final String label;
  final VoidCallback? onTap;
  final String icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ? AccountsV2Colors.pri : AccountsV2Colors.ink2;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AccountsV2Colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: AccountsV2Colors.buttonHover,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AccountsV2Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: v2Style(12, color: color, height: 1.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Display numbers and dates ───────────────────────────────────────────────

/// A decimal or number as a double, for display arithmetic only. Stored and
/// sent values always stay exact decimals.
double v2Number(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

/// Rounds money to fils, halves away from zero (as Postgres `round` and Excel).
/// The small nudge keeps a value such as 1.005 (stored as 1.00499…) from
/// rounding down; it is far below a fil.
double accountsV2RoundFils(double value) {
  final rounded = (value.abs() * 100 + 1e-6).round() / 100;
  return value < 0 ? -rounded : rounded;
}

/// The Yorks workbook's rule for a claim or invoice: gross, VAT and total are
/// each rounded once from the exact gross, so the total can differ from
/// gross + VAT by a fil (as on the signed invoices). Display preview only; the
/// server's figures are the record.
({double gross, double vat, double net}) accountsV2ExcelAmounts(
  double exactGross,
  double vatRatePercent,
) => (
  gross: accountsV2RoundFils(exactGross),
  vat: accountsV2RoundFils(exactGross * vatRatePercent / 100),
  net: accountsV2RoundFils(exactGross * (1 + vatRatePercent / 100)),
);

/// `1,234,567.89` with en-US grouping and [digits] decimals (prototype `fmt`).
String v2Fmt(double value, [int digits = 2]) {
  final fixed = value.abs().toStringAsFixed(digits);
  // "-0.00" never shows: only a value that rounds away from zero is negative.
  final negative = value < 0 && fixed.contains(RegExp('[1-9]'));
  final parts = fixed.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final body = parts.length > 1 ? '$whole.${parts[1]}' : whole;
  return negative ? '-$body' : body;
}

/// `AED 1,234,567` (prototype `aed`).
String v2Money(double value, {int digits = 2, String currency = 'AED'}) =>
    '$currency ${v2Fmt(value, digits)}';

/// `44.8%` (prototype `pc`).
String v2Pct(double value, [int digits = 1]) => '${v2Fmt(value, digits)}%';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

DateTime? _v2Date(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('$value');
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// `19 Oct 2026` (prototype `fDate`); `—` when missing.
String v2Date(Object? value) {
  final d = _v2Date(value);
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
}

/// `Oct 2026` (prototype `fMonth`).
String v2Month(Object? value) {
  final d = _v2Date(value);
  if (d == null) return '—';
  return '${_months[d.month - 1]} ${d.year}';
}

/// Whole days from today to [value]; negative when it has passed.
int v2DaysFromToday(Object? value, {DateTime? today}) {
  final d = _v2Date(value);
  if (d == null) return 0;
  final now = today ?? DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  return DateTime(d.year, d.month, d.day).difference(start).inDays;
}

/// An amount in words, as the prototype writes it under Net payable:
/// `UAE Dirham Twenty Seven Thousand Five Hundred Seven & 35/100 Only`.
String v2AmountInWords(double value) {
  const ones = [
    '',
    'One',
    'Two',
    'Three',
    'Four',
    'Five',
    'Six',
    'Seven',
    'Eight',
    'Nine',
    'Ten',
    'Eleven',
    'Twelve',
    'Thirteen',
    'Fourteen',
    'Fifteen',
    'Sixteen',
    'Seventeen',
    'Eighteen',
    'Nineteen',
  ];
  const tens = [
    '',
    '',
    'Twenty',
    'Thirty',
    'Forty',
    'Fifty',
    'Sixty',
    'Seventy',
    'Eighty',
    'Ninety',
  ];
  String hundreds(int x) {
    final parts = <String>[];
    if (x >= 100) {
      parts.add('${ones[x ~/ 100]} Hundred');
      x %= 100;
    }
    if (x >= 20) {
      parts.add(
        x % 10 == 0 ? tens[x ~/ 10] : '${tens[x ~/ 10]} ${ones[x % 10]}',
      );
    } else if (x > 0) {
      parts.add(ones[x]);
    }
    return parts.join(' ');
  }

  final cents = (value.abs() * 100).round();
  var whole = cents ~/ 100;
  final fraction = cents % 100;
  final parts = <String>[];
  for (final (size, label) in const [
    (1000000000, 'Billion'),
    (1000000, 'Million'),
    (1000, 'Thousand'),
  ]) {
    if (whole >= size) {
      parts.add('${hundreds(whole ~/ size)} $label');
      whole %= size;
    }
  }
  if (whole > 0) parts.add(hundreds(whole));
  final words = parts.isEmpty ? 'Zero' : parts.join(' ');
  final cent = fraction == 0
      ? ''
      : ' & ${fraction.toString().padLeft(2, '0')}/100';
  return 'UAE Dirham $words$cent Only';
}
