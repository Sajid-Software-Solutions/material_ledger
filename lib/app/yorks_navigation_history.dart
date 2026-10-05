import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/providers/language_provider.dart';

class YorksNavigationHistory {
  const YorksNavigationHistory(this.entries, {required this.cursor});

  const YorksNavigationHistory.empty() : entries = const [], cursor = -1;

  final List<String> entries;
  final int cursor;

  List<String> get locations =>
      cursor < 0 ? const [] : entries.sublist(0, cursor + 1);

  List<String> get forwardLocations => cursor >= entries.length - 1
      ? const []
      : entries.sublist(cursor + 1).reversed.toList(growable: false);

  bool canGoBack(String currentLocation) {
    final normalized = _normalize(currentLocation);
    if (cursor < 0) return false;
    if (entries[cursor] == normalized) return cursor > 0;
    return true;
  }

  bool canGoForward(String currentLocation) =>
      cursor >= 0 &&
      entries[cursor] == _normalize(currentLocation) &&
      cursor < entries.length - 1;

  String? previousLocation(String currentLocation) {
    final normalized = _normalize(currentLocation);
    if (cursor < 0) return null;
    if (entries[cursor] != normalized) return entries[cursor];
    return cursor > 0 ? entries[cursor - 1] : null;
  }

  String? get nextLocation =>
      cursor < entries.length - 1 ? entries[cursor + 1] : null;
}

class YorksNavigationHistoryNotifier
    extends StateNotifier<YorksNavigationHistory> {
  YorksNavigationHistoryNotifier()
    : super(const YorksNavigationHistory.empty());

  static const _limit = 30;

  void record(String location) {
    final normalized = _normalize(location);
    if (normalized.isEmpty) return;
    if (state.cursor >= 0 && state.entries[state.cursor] == normalized) return;
    if (state.cursor < state.entries.length - 1 &&
        state.entries[state.cursor + 1] == normalized) {
      state = YorksNavigationHistory(state.entries, cursor: state.cursor + 1);
      return;
    }

    final next = [
      if (state.cursor >= 0) ...state.entries.sublist(0, state.cursor + 1),
      normalized,
    ];
    if (next.length > _limit) next.removeAt(0);
    state = YorksNavigationHistory(
      List.unmodifiable(next),
      cursor: next.length - 1,
    );
  }

  /// Anchoring a mounted fresh setup is the same place. Replace only the
  /// expected current entry so Back never reopens an unselected fresh URL.
  void replaceCurrent(String expectedLocation, String replacement) {
    if (state.cursor < 0 ||
        state.entries[state.cursor] != _normalize(expectedLocation)) {
      return;
    }
    final normalized = _normalize(replacement);
    if (normalized.isEmpty || normalized == state.entries[state.cursor]) return;
    final entries = [...state.entries];
    entries[state.cursor] = normalized;
    state = YorksNavigationHistory(
      List.unmodifiable(entries),
      cursor: state.cursor,
    );
  }

  String? takePrevious(String currentLocation) {
    final normalized = _normalize(currentLocation);
    if (state.cursor < 0) return null;
    if (state.entries[state.cursor] != normalized) record(normalized);
    if (state.cursor <= 0) return null;
    final nextCursor = state.cursor - 1;
    state = YorksNavigationHistory(state.entries, cursor: nextCursor);
    return state.entries[nextCursor];
  }

  String? takeNext(String currentLocation) {
    final normalized = _normalize(currentLocation);
    if (state.cursor < 0 ||
        state.entries[state.cursor] != normalized ||
        state.cursor >= state.entries.length - 1) {
      return null;
    }
    final nextCursor = state.cursor + 1;
    state = YorksNavigationHistory(state.entries, cursor: nextCursor);
    return state.entries[nextCursor];
  }
}

String _normalize(String location) {
  final uri = Uri.tryParse(location);
  if (uri == null) return '';
  // A notification acknowledgement is transient transport metadata, not part
  // of a place the person should return to.
  final query = {...uri.queryParameters}..remove('notificationId');
  return uri.replace(queryParameters: query.isEmpty ? null : query).toString();
}

final yorksNavigationHistoryProvider =
    StateNotifierProvider<
      YorksNavigationHistoryNotifier,
      YorksNavigationHistory
    >((ref) {
      // Recreate history for each authenticated session so one person's route
      // cannot become another person's Back destination on a shared device.
      ref.watch(authSessionProvider);
      return YorksNavigationHistoryNotifier();
    });

bool yorksCanNavigateBack(
  BuildContext context,
  WidgetRef ref,
  String currentLocation,
) =>
    (Navigator.maybeOf(context)?.canPop() ?? false) ||
    ref.watch(yorksNavigationHistoryProvider).canGoBack(currentLocation);

void yorksNavigateBack(
  BuildContext context,
  WidgetRef ref,
  String currentLocation, {
  String? fallback,
}) {
  final history = ref.read(yorksNavigationHistoryProvider.notifier);
  final previous = ref
      .read(yorksNavigationHistoryProvider)
      .previousLocation(currentLocation);
  if (Navigator.maybeOf(context)?.canPop() ?? false) {
    Navigator.of(context).pop();
    history.takePrevious(currentLocation);
    return;
  }
  if (previous != null && previous != currentLocation) {
    context.go(previous);
    history.takePrevious(currentLocation);
    return;
  }
  if (fallback != null && fallback != currentLocation) context.go(fallback);
}

void yorksNavigateForward(
  BuildContext context,
  WidgetRef ref,
  String currentLocation,
) {
  final snapshot = ref.read(yorksNavigationHistoryProvider);
  if (!snapshot.canGoForward(currentLocation)) return;
  final next = snapshot.nextLocation!;
  context.go(next);
  ref.read(yorksNavigationHistoryProvider.notifier).takeNext(currentLocation);
}
