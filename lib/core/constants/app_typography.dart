import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Yorks Nexus V7 type scale.
///
/// The bundled Noto Sans family is deliberately neutral, browser-dense and
/// deterministic offline. Arabic keeps its dedicated family and line height.
abstract final class AppTypography {
  // Constants, not getters: a getter that builds a TextStyle is inlined by
  // the web compiler at every one of the ~2,900 call sites, which added
  // about 180 KB to the startup bundle. A const is a single shared object.
  static const TextStyle displayLarge = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 40,
    fontWeight: FontWeight.w700,
    height: 1.08,
    letterSpacing: -1.2,
    color: AppColors.onSurface,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 36,
    fontWeight: FontWeight.w700,
    height: 1.08,
    letterSpacing: -1,
    color: AppColors.onSurface,
  );

  static const TextStyle displaySmall = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.08,
    letterSpacing: -1.12,
    color: AppColors.onSurface,
  );

  static const TextStyle headlineLarge = displaySmall;

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.18,
    letterSpacing: -0.48,
    color: AppColors.onSurface,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 21,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: -0.42,
    color: AppColors.onSurface,
  );

  static const TextStyle titleLarge = headlineSmall;

  static const TextStyle titleMedium = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.1,
    color: AppColors.onSurface,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.35,
    letterSpacing: 0,
    color: AppColors.onSurface,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
    color: AppColors.onSurface,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0,
    color: AppColors.inkSecondary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.45,
    letterSpacing: 0,
    color: AppColors.muted,
  );

  static const TextStyle labelLarge = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0,
    color: AppColors.onSurface,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: 0,
    color: AppColors.muted,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: 0.2,
    color: AppColors.muted,
  );

  static const TextStyle eyebrow = TextStyle(
    fontFamily: 'NexusSans',
    fontFamilyFallback: ['NotoSansArabic'],
    fontSize: 10,
    fontWeight: FontWeight.w800,
    height: 1.2,
    letterSpacing: 1,
    color: AppColors.blue,
  );

  static TextStyle urduStyle({required double englishFontSize}) => TextStyle(
    fontFamily: 'NotoSansArabic',
    fontSize: englishFontSize - 2,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.onSurfaceVariant,
  );

  static const TextTheme textTheme = TextTheme(
    displayLarge: displayLarge,
    displayMedium: displayMedium,
    displaySmall: displaySmall,
    headlineLarge: headlineLarge,
    headlineMedium: headlineMedium,
    headlineSmall: headlineSmall,
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    titleSmall: titleSmall,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelMedium: labelMedium,
    labelSmall: labelSmall,
  );
}
