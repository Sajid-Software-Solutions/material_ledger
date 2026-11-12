/// R39 Accounts Workspace V2 — loads the workspace only when someone opens it.
///
/// Most people using the app never open project Accounts, so its six tabs stay out
/// of the code every session downloads at startup.
library;

import 'package:flutter/material.dart';
import '../../../../core/web/stale_build_recovery.dart';

import 'accounts_v2_common.dart';
import 'yorks_accounts_workspace_v2_screen.dart' deferred as workspace;

/// The workspace inside the project shell.
class YorksAccountsWorkspaceV2Deferred extends StatelessWidget {
  const YorksAccountsWorkspaceV2Deferred({
    super.key,
    required this.projectId,
    required this.initialTab,
  });

  final String projectId;
  final YorksAccountsWorkspaceV2Tab initialTab;

  @override
  Widget build(BuildContext context) => _WorkspaceLoader(
    builder: () => workspace.YorksAccountsWorkspaceV2Screen(
      projectId: projectId,
      initialTab: initialTab,
    ),
  );
}

/// The workspace on its own page, for an Accountant.
class YorksAccountsProjectPageDeferred extends StatelessWidget {
  const YorksAccountsProjectPageDeferred({
    super.key,
    required this.projectId,
    required this.initialTab,
  });

  final String projectId;
  final YorksAccountsWorkspaceV2Tab initialTab;

  @override
  Widget build(BuildContext context) => _WorkspaceLoader(
    builder: () => workspace.YorksAccountsProjectPage(
      projectId: projectId,
      initialTab: initialTab,
    ),
  );
}

class _WorkspaceLoader extends StatefulWidget {
  const _WorkspaceLoader({required this.builder});

  final Widget Function() builder;

  @override
  State<_WorkspaceLoader> createState() => _WorkspaceLoaderState();
}

class _WorkspaceLoaderState extends State<_WorkspaceLoader> {
  static Future<void>? _sharedLoad;
  late Future<void> _load;

  @override
  void initState() {
    super.initState();
    _load = _sharedLoad ??= loadOrRecover(workspace.loadLibrary());
  }

  void _retry() {
    setState(() {
      _load = _sharedLoad = loadOrRecover(workspace.loadLibrary());
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return widget.builder();
        }
        if (snapshot.hasError) {
          return Center(
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: MaterialLocalizations.of(
                context,
              ).refreshIndicatorSemanticLabel,
              onPressed: _retry,
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}
