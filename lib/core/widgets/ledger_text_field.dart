import 'package:flutter/material.dart';

import '../constants/constants.dart';

/// Input field following design spec:
/// Flat design. [surfaceContainerHighest] background with
/// bottom-only primary stroke (2px) on focus.
/// Bilingual: English label above, Urdu placeholder inside.
class LedgerTextField extends StatelessWidget {
  const LedgerTextField({
    super.key,
    this.controller,
    this.label,
    this.semanticsLabel,
    this.urduHint,
    this.hintText,
    this.helperText,
    this.prefixIcon,
    this.suffixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.readOnly = false,
    this.onTap,
  });

  final TextEditingController? controller;
  final String? label;

  /// Accessible input name when the visible label is rendered outside it.
  /// Opt-in to preserve the semantics of existing callers.
  final String? semanticsLabel;
  final String? urduHint;
  final String? hintText;
  final String? helperText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactBreakpoint;
    final controlHeight = compact ? AppSpacing.minTapTarget : 36.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.inkSecondary,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
        ],
        SizedBox(
          height: maxLines == 1 ? controlHeight : 88,
          child: _withInputSemantics(
            TextFormField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: keyboardType,
              obscureText: obscureText,
              maxLines: obscureText ? 1 : null,
              expands: !obscureText,
              textAlignVertical: maxLines == 1
                  ? TextAlignVertical.center
                  : TextAlignVertical.top,
              onChanged: onChanged,
              onFieldSubmitted: onSubmitted,
              validator: validator,
              enabled: enabled,
              autofocus: autofocus,
              readOnly: readOnly,
              onTap: onTap,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.ink,
                fontSize: 11.5,
                height: 1.35,
              ),
              decoration: InputDecoration(
                hintText: urduHint ?? hintText,
                hintTextDirection: urduHint != null ? TextDirection.rtl : null,
                prefixIcon: prefixIcon,
                suffixIcon: suffixIcon,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: compact ? 11 : 8,
                ),
              ),
            ),
          ),
        ),
        if (helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            helperText!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.muted,
              fontSize: 9,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }

  Widget _withInputSemantics(Widget input) => semanticsLabel == null
      ? input
      : Semantics(label: semanticsLabel, child: input);
}
