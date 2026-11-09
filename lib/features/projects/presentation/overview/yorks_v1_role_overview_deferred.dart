/// Role-based Overview — loaded on demand so its cards and copy stay out of
/// the code every session downloads at startup (the web startup budget).
library;

import 'package:flutter/material.dart';

import '../../../../core/constants/constants.dart';
import 'yorks_v1_role_overview_screen.dart' deferred as overview;

class YorksV1RoleOverviewDeferred extends StatefulWidget {
  const YorksV1RoleOverviewDeferred({super.key});

  @override
  State<YorksV1RoleOverviewDeferred> createState() =>
      _YorksV1RoleOverviewDeferredState();
}

class _YorksV1RoleOverviewDeferredState
    extends State<YorksV1RoleOverviewDeferred> {
  static Future<void>? _sharedLoad;
  late Future<void> _load;

  @override
  void initState() {
    super.initState();
    _load = _sharedLoad ??= overview.loadLibrary();
  }

  void _retry() {
    setState(() {
      _load = _sharedLoad = overview.loadLibrary();
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _load,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return overview.YorksV1RoleOverviewScreen();
      }
      return ColoredBox(
        color: AppColors.surface,
        child: Center(
          child: snapshot.hasError
              ? IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).refreshIndicatorSemanticLabel,
                  onPressed: _retry,
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
