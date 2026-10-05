import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_project.dart';
import '../../../../shared/models/yorks_v1_project_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import 'yorks_v1_project_create_flow_screen.dart' deferred as project_setup;

typedef YorksV1ProjectSetupLibraryLoader = Future<void> Function();

/// Asset loading only: no draft, ownership or server work happens here.
Future<void> loadYorksV1ProjectSetupLibrary() => project_setup.loadLibrary();

final yorksV1ProjectSetupLibraryLoaderProvider =
    Provider<YorksV1ProjectSetupLibraryLoader>(
      (ref) => loadYorksV1ProjectSetupLibrary,
    );

/// One small entry for the entire candidate wizard. Keeping the loaded child
/// at one stable position preserves its state during same-ID URL anchoring.
class YorksV1ProjectSetupEntryScreen extends ConsumerStatefulWidget {
  const YorksV1ProjectSetupEntryScreen({
    super.key,
    this.resumeDraftId,
    this.newDraftId,
    this.legacyRecovery = false,
    this.editProjectId,
    this.onProjectCreated,
  }) : assert(resumeDraftId == null || newDraftId == null),
       assert(!legacyRecovery || (resumeDraftId == null && newDraftId == null)),
       assert(
         editProjectId == null ||
             (resumeDraftId == null && newDraftId == null && !legacyRecovery),
       );

  final String? resumeDraftId;
  final String? newDraftId;
  final bool legacyRecovery;
  final String? editProjectId;
  final ValueChanged<YorksV1Project>? onProjectCreated;

  @override
  ConsumerState<YorksV1ProjectSetupEntryScreen> createState() =>
      _YorksV1ProjectSetupEntryScreenState();
}

class _YorksV1ProjectSetupEntryScreenState
    extends ConsumerState<YorksV1ProjectSetupEntryScreen> {
  static Future<void>? _sharedLoad;
  static YorksV1ProjectSetupLibraryLoader? _sharedLoader;
  late final YorksV1ProjectSetupLibraryLoader _loader;
  late Future<void> _load;

  @override
  void initState() {
    super.initState();
    _loader = ref.read(yorksV1ProjectSetupLibraryLoaderProvider);
    if (!identical(_sharedLoader, _loader)) {
      _sharedLoader = _loader;
      _sharedLoad = null;
    }
    _load = _sharedLoad ??= Future<void>.sync(_loader);
  }

  void _retry() {
    setState(() {
      _sharedLoader = _loader;
      _load = _sharedLoad = Future<void>.sync(_loader);
    });
  }

  static const _loadFailed = TranslatableString(
    en: 'Project setup could not be loaded.',
    ar: 'تعذر تحميل إعداد المشروع.',
    ur: 'پراجیکٹ سیٹ اپ لوڈ نہیں ہو سکا۔',
    hi: 'प्रोजेक्ट सेटअप लोड नहीं हो सका।',
  );

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    return FutureBuilder<void>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          final projectId = widget.editProjectId;
          if (projectId != null) {
            return project_setup.YorksV1ProjectEditFlowScreen(
              projectId: projectId,
            );
          }
          return project_setup.YorksV1ProjectCreateFlowScreen(
            resumeDraftId: widget.resumeDraftId,
            newDraftId: widget.newDraftId,
            legacyRecovery: widget.legacyRecovery,
            onProjectCreated: widget.onProjectCreated,
          );
        }
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasError) {
          return Center(
            key: const ValueKey('yorks-v1-project-setup-load-failed'),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _loadFailed.active(language),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    key: const ValueKey('yorks-v1-project-setup-load-retry'),
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(YorksV1ProjectStrings.retry.active(language)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return const Center(
          key: ValueKey('yorks-v1-project-setup-loading'),
          child: CircularProgressIndicator(),
        );
      },
    );
  }
}
