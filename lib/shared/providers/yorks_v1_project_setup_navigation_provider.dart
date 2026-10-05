import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef YorksV1ProjectSetupCreationSelection = ({
  String? draftId,
  bool legacyRecovery,
});

/// Lets route changes await the mounted editor's pending local write.
/// The callback owns the editor buffer; the router never reconstructs it.
class YorksV1ProjectSetupNavigationGuard {
  Future<bool> Function()? _guard;
  YorksV1ProjectSetupCreationSelection? Function()? _creationSelection;

  void register(
    Future<bool> Function() guard, {
    YorksV1ProjectSetupCreationSelection? Function()? creationSelection,
  }) {
    _guard = guard;
    _creationSelection = creationSelection;
  }

  void unregister(Future<bool> Function() guard) {
    if (identical(_guard, guard)) {
      _guard = null;
      _creationSelection = null;
    }
  }

  Future<bool> canLeave() async {
    final guard = _guard;
    return guard == null || await guard();
  }

  /// The URL may still be unanchored or an imperative push's parent location.
  /// Only the mounted editor can identify whether this is its own proposal.
  Future<bool> canSelectCreation(
    String? draftId, {
    bool legacyRecovery = false,
  }) async {
    final selected = _creationSelection?.call();
    if (selected != null &&
        selected.draftId == draftId &&
        selected.legacyRecovery == legacyRecovery) {
      return true;
    }
    return canLeave();
  }
}

final yorksV1ProjectSetupNavigationGuardProvider =
    Provider<YorksV1ProjectSetupNavigationGuard>((ref) {
      return YorksV1ProjectSetupNavigationGuard();
    });
