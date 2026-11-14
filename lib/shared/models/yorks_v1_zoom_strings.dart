import 'app_strings.dart';

/// Localized vocabulary for the R35 workspace precision zoom controls.
///
/// The controls are shared shell chrome, rather than feature-specific copy,
/// so they remain consistent across the dense Yorks operational surfaces.
abstract final class YorksV1ZoomStrings {
  static const workspaceZoom = TranslatableString(
    en: 'Workspace zoom',
    ar: 'تكبير مساحة العمل',
    ur: 'ورک اسپیس زوم',
    hi: 'कार्यस्थान ज़ूम',
  );
  static const zoomPercentage = TranslatableString(
    en: 'Zoom level',
    ar: 'مستوى التكبير',
    ur: 'زوم لیول',
    hi: 'ज़ूम स्तर',
  );
  static const enterFullscreen = TranslatableString(
    en: 'Enter full screen',
    ar: 'دخول وضع ملء الشاشة',
    ur: 'فل اسکرین کھولیں',
    hi: 'फ़ुल स्क्रीन खोलें',
  );
  static const exitFullscreen = TranslatableString(
    en: 'Exit full screen',
    ar: 'الخروج من وضع ملء الشاشة',
    ur: 'فل اسکرین بند کریں',
    hi: 'फ़ुल स्क्रीन बंद करें',
  );
}
