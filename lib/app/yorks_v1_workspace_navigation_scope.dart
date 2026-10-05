import 'package:flutter/widgets.dart';

/// Shared Yorks navigation for focused features that draw their own header.
/// The workspace shell owns the permitted destinations, drawer and search;
/// feature headers only invoke these existing actions.
class YorksV1WorkspaceNavigationScope extends InheritedWidget {
  const YorksV1WorkspaceNavigationScope({
    super.key,
    required this.openNavigation,
    required this.openSearch,
    required super.child,
  });

  final VoidCallback openNavigation;
  final VoidCallback openSearch;

  static YorksV1WorkspaceNavigationScope? maybeOf(
    BuildContext context,
  ) => context
      .dependOnInheritedWidgetOfExactType<YorksV1WorkspaceNavigationScope>();

  @override
  bool updateShouldNotify(YorksV1WorkspaceNavigationScope oldWidget) =>
      openNavigation != oldWidget.openNavigation ||
      openSearch != oldWidget.openSearch;
}
