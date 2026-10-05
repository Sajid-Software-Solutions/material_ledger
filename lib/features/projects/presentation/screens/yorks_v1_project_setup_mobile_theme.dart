import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import 'yorks_v1_project_setup_desktop_theme.dart';

/// Scoped phone/tablet tokens; project state and commands remain shared.
abstract final class YorksProjectSetupMobileTheme {
  static const navy = AppColors.navy;
  static const blue = Color(0xFF006BFF);
  static const muted = Color(0xFF5D749B);
  static const border = Color(0xFFDCE5EF);
  static const inputBorder = Color(0xFFCAD6E5);
  static const help = Color(0xFFEEF5FD);
  static const selected = Color(0xFFE7F0FC);
  static const success = Color(0xFF008F70);

  static TextStyle get body =>
      AppTypography.bodyMedium.copyWith(fontSize: 14, height: 1.3, color: navy);
  static TextStyle get small => body.copyWith(fontSize: 11.5, color: muted);
  static TextStyle get label => body.copyWith(fontWeight: FontWeight.w500);
  static TextStyle get title =>
      body.copyWith(fontSize: 18, fontWeight: FontWeight.w700);

  static bool isMobileLayout(BuildContext context) =>
      !YorksProjectSetupDesktopTheme.isDesktop(context);

  static bool showColumns(BuildContext context, double availableWidth) =>
      MediaQuery.sizeOf(context).width >= 400 &&
      availableWidth >= 340 &&
      MediaQuery.textScalerOf(context).scale(1) <= 1.1;

  static InputDecoration inputDecoration({
    String? hint,
    Widget? prefix,
    Widget? suffix,
  }) => InputDecoration(
    hintText: hint,
    hintStyle: body.copyWith(color: muted),
    prefixIcon: prefix,
    suffixIcon: suffix,
    prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
    textStyle: label,
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    side: const BorderSide(color: inputBorder),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  static ButtonStyle get blueButton => FilledButton.styleFrom(
    foregroundColor: Colors.white,
    backgroundColor: blue,
    textStyle: label.copyWith(fontWeight: FontWeight.w600),
    minimumSize: const Size(44, 44),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
  static ButtonStyle get navyButton =>
      blueButton.copyWith(backgroundColor: const WidgetStatePropertyAll(navy));
}
