import 'package:flutter/material.dart';

import '../constants/constants.dart';
import '../web/stale_build_recovery.dart';

/// Shows a screen from a deferred library, loading its code on first use.
///
/// Screens that most sessions never open are kept out of the startup bundle
/// so the app reaches Home sooner, especially on phones. `load` is the
/// library's `loadLibrary`; the runtime caches it, so later visits build
/// immediately.
class YorksDeferredScreen extends StatefulWidget {
  const YorksDeferredScreen({
    super.key,
    required this.load,
    required this.builder,
  });

  final Future<void> Function() load;
  final Widget Function() builder;

  @override
  State<YorksDeferredScreen> createState() => _YorksDeferredScreenState();
}

class _YorksDeferredScreenState extends State<YorksDeferredScreen> {
  late Future<void> _loaded = _load();

  /// A failed download usually means this tab runs an earlier release; one
  /// automatic reload fixes it. Otherwise the retry button stays.
  Future<void> _load() => widget.load().catchError((Object error) {
    recoverFromStaleBuild();
    throw error;
  });

  /// Builds directly when the library is already loaded. The runtime keeps
  /// one load future per library; listening to it again from a later zone
  /// (a test, or an isolate restart) can stall, so a loaded library never
  /// waits on it.
  Widget? _buildIfLoaded() {
    try {
      return widget.builder();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) =>
      _buildIfLoaded() ?? _buildWhenLoaded(context);

  Widget _buildWhenLoaded(BuildContext context) => FutureBuilder<void>(
    future: _loaded,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return widget.builder();
      }
      return ColoredBox(
        color: AppColors.surface,
        child: Center(
          child: snapshot.hasError
              ? IconButton(
                  key: const ValueKey('deferred-screen-retry'),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: MaterialLocalizations.of(
                    context,
                  ).refreshIndicatorSemanticLabel,
                  onPressed: () => setState(() => _loaded = _load()),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}
