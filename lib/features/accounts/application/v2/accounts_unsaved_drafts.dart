/// R39 Accounts Workspace V2 — unsaved edits kept while a person looks
/// elsewhere.
///
/// The Contract and Progress & claims tabs edit in place and save only on
/// Save. Only the open tab is built, so leaving a tab (or the project, or one
/// claim for another) would otherwise throw its typing away. Each tab hands its
/// unsaved form here when it closes and takes it back when it opens again.
///
/// The drafts live in memory only, for the signed-in person and one project:
/// nothing is written to the device or sent anywhere, and signing out (or a
/// different person signing in) starts empty. While any draft or open edit
/// exists, the browser warns before the page is closed or reloaded.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/services/yorks_v1_procurement_unload_guard.dart';

/// The section keys tabs use.
abstract final class YorksAccountsDraftSection {
  static const contract = 'contract';

  /// One claim's progress; `claims:new` is a claim not yet saved.
  static String claim(String? claimId) => 'claims:${claimId ?? 'new'}';
  static const claimsPrefix = 'claims:';
}

class YorksAccountsUnsavedDrafts extends ChangeNotifier {
  YorksAccountsUnsavedDrafts({YorksV1ProcurementUnloadGuard? unloadGuard})
    : _guard = unloadGuard ?? createYorksV1ProcurementUnloadGuard();

  final YorksV1ProcurementUnloadGuard _guard;
  final Map<String, Object> _kept = {};
  final Set<String> _editing = {};

  /// The draft a tab left for [section], or null.
  T? kept<T extends Object>(String section) {
    final draft = _kept[section];
    return draft is T ? draft : null;
  }

  /// Keeps [draft] for [section] until the tab takes it back or saves.
  void keep(String section, Object draft) {
    _kept[section] = draft;
    _changed();
  }

  /// Forgets the draft for [section] (saved, discarded or taken back).
  void drop(String section) {
    if (_kept.remove(section) != null) _changed();
  }

  /// Whether the open tab has unsaved edits in [section] right now.
  void setEditing(String section, bool editing) {
    final changed = editing ? _editing.add(section) : _editing.remove(section);
    if (changed) _changed();
  }

  /// Whether [prefix] (a section or `claims:`) has unsaved work, open or kept.
  bool has(String prefix) =>
      _kept.keys.any((k) => k.startsWith(prefix)) ||
      _editing.any((k) => k.startsWith(prefix));

  bool get isEmpty => _kept.isEmpty && _editing.isEmpty;

  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Tabs report from build and dispose, when other widgets can't rebuild, so
  /// listeners hear once, after the current frame's work.
  void _changed() {
    _guard.setActive(!isEmpty);
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _guard.dispose();
    super.dispose();
  }
}

/// One store per project for the signed-in person. Watching the auth user id
/// rebuilds it (empty) when the person signs out or someone else signs in.
final yorksAccountsUnsavedDraftsProvider =
    ChangeNotifierProvider.family<YorksAccountsUnsavedDrafts, String>((
      ref,
      projectId,
    ) {
      ref.watch(yorksV1AuthUserIdProvider);
      return YorksAccountsUnsavedDrafts();
    });
