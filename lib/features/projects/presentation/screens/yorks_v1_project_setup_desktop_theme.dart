import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';

/// Available workspace content width after the universal sidebar and zoom.
/// Stage widgets use this scope rather than treating the whole browser as
/// available form space.
class YorksProjectSetupLayoutScope extends InheritedWidget {
  const YorksProjectSetupLayoutScope({
    super.key,
    required this.availableWidth,
    required super.child,
  });

  final double availableWidth;

  static double? maybeWidthOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<YorksProjectSetupLayoutScope>()
      ?.availableWidth;

  @override
  bool updateShouldNotify(YorksProjectSetupLayoutScope oldWidget) =>
      oldWidget.availableWidth != availableWidth;
}

/// Scoped desktop tokens for the approved project setup reference.
abstract final class YorksProjectSetupDesktopTheme {
  static const navy = AppColors.navy;
  static const blue = Color(0xFF006BFF);
  static const muted = Color(0xFF5D749B);
  static const border = Color(0xFFDCE5EF);
  static const inputBorder = Color(0xFFCAD6E5);
  static const tableHeader = Color(0xFFF4F7FA);
  static const selected = Color(0xFFE7F0FC);
  static const help = Color(0xFFEEF5FD);
  static const success = Color(0xFF008F70);

  static TextStyle get body => AppTypography.bodyMedium.copyWith(
    fontSize: 14,
    height: 1.35,
    color: navy,
  );
  static TextStyle get small => body.copyWith(fontSize: 12.5, color: muted);
  static TextStyle get label => body.copyWith(fontWeight: FontWeight.w500);
  static TextStyle get title =>
      body.copyWith(fontSize: 26, fontWeight: FontWeight.w700, height: 1.25);
  static TextStyle get section =>
      body.copyWith(fontSize: 20, fontWeight: FontWeight.w700);

  static bool isDesktop(BuildContext context) => isDesktopForWidth(
    context,
    YorksProjectSetupLayoutScope.maybeWidthOf(context) ??
        MediaQuery.sizeOf(context).width,
  );

  static bool isDesktopForWidth(BuildContext context, double availableWidth) =>
      availableWidth >= 1100 &&
      MediaQuery.textScalerOf(context).scale(1) <= 1.1;

  static InputDecoration inputDecoration({
    String? hint,
    Widget? prefix,
    Widget? suffix,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: small.copyWith(fontSize: 14),
    prefixIcon: prefix,
    suffixIcon: suffix,
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    suffixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: const BorderSide(color: inputBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: const BorderSide(color: inputBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(5),
      borderSide: const BorderSide(color: blue, width: 1.5),
    ),
  );

  static ButtonStyle get outlineButton => OutlinedButton.styleFrom(
    foregroundColor: navy,
    backgroundColor: Colors.white,
    textStyle: label.copyWith(fontWeight: FontWeight.w600),
    minimumSize: const Size(0, 38),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    side: const BorderSide(color: inputBorder),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
  );
  static ButtonStyle get blueButton => FilledButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: blue,
    textStyle: label.copyWith(fontWeight: FontWeight.w600),
    minimumSize: const Size(0, 40),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
  );
  static ButtonStyle get navyButton =>
      blueButton.copyWith(backgroundColor: const WidgetStatePropertyAll(navy));
}
