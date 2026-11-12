import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/push_bridge.dart';
import '../../../../app/router.dart';
import '../../../../core/constants/constants.dart';
import '../../../../shared/models/app_language.dart';
import '../../../../shared/models/app_strings.dart';
import '../../../../shared/models/yorks_v1_role.dart';
import '../../../../shared/models/yorks_v1_team_chat.dart';
import '../../../../shared/models/yorks_v1_team_chat_strings.dart';
import '../../../../shared/providers/language_provider.dart';
import '../../../../shared/providers/yorks_v1_identity_provider.dart';
import '../../../../shared/providers/yorks_v1_team_chat_provider.dart';
import '../../../../shared/services/push_service.dart';
import '../../../../shared/widgets/notification_delivery_card.dart';

class YorksV1TeamChatScreen extends ConsumerStatefulWidget {
  const YorksV1TeamChatScreen({super.key, this.initialConversationId});

  final String? initialConversationId;

  @override
  ConsumerState<YorksV1TeamChatScreen> createState() =>
      _YorksV1TeamChatScreenState();
}

class _YorksV1TeamChatScreenState extends ConsumerState<YorksV1TeamChatScreen> {
  static const _detailsPanelPreferenceKey =
      'yorks_v1_team_chat_details_panel_visible';

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  YorksV1ChatFilter _filter = YorksV1ChatFilter.all;
  String? _openedInitialId;
  String? _focusMessageId;
  Timer? _searchDebounce;
  late bool _detailsPanelVisible;

  @override
  void initState() {
    super.initState();
    _detailsPanelVisible =
        ref
            .read(sharedPreferencesProvider)
            .getBool(_detailsPanelPreferenceKey) ??
        true;
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInitial());
  }

  @override
  void didUpdateWidget(covariant YorksV1TeamChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialConversationId != widget.initialConversationId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openInitial());
    }
  }

  void _openInitial() {
    final id = widget.initialConversationId?.trim();
    if (!mounted || id == null || id.isEmpty || id == _openedInitialId) return;
    _openedInitialId = id;
    unawaited(ref.read(yorksV1TeamChatProvider.notifier).openConversation(id));
  }

  void _onSearchChanged() {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      unawaited(
        ref
            .read(yorksV1TeamChatProvider.notifier)
            .search(_searchController.text),
      );
    });
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _searchDebounce?.cancel();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<YorksV1ChatConversation> _visibleConversations(
    YorksV1TeamChatState state,
  ) {
    return state.conversations
        .where((conversation) {
          final archiveMatch = _filter == YorksV1ChatFilter.archived
              ? conversation.isArchived
              : !conversation.isArchived;
          if (!archiveMatch) return false;
          final filterMatch = switch (_filter) {
            YorksV1ChatFilter.all || YorksV1ChatFilter.archived => true,
            YorksV1ChatFilter.unread => conversation.hasUnread,
            YorksV1ChatFilter.projects =>
              conversation.kind == YorksV1ChatKind.project,
            YorksV1ChatFilter.requests =>
              conversation.kind == YorksV1ChatKind.materialRequest,
            YorksV1ChatFilter.direct =>
              conversation.kind == YorksV1ChatKind.direct,
            YorksV1ChatFilter.groups =>
              conversation.kind == YorksV1ChatKind.group,
            YorksV1ChatFilter.announcements =>
              conversation.kind == YorksV1ChatKind.announcement,
          };
          return filterMatch;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);
    final state = ref.watch(yorksV1TeamChatProvider);
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width <= AppSpacing.compactBreakpoint;
    final canDockInfo = size.width >= 1250;
    final showInfo = canDockInfo && _detailsPanelVisible;
    final selected = state.selectedConversationId != null;

    if (state.error != null &&
        state.conversations.isEmpty &&
        !state.loadingList) {
      return _ChatLoadFailure(
        language: language,
        onRetry: () =>
            ref.read(yorksV1TeamChatProvider.notifier).refreshConversations(),
      );
    }

    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(mobile ? 0 : 12),
        boxShadow: mobile
            ? null
            : const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(mobile ? 0 : 12),
        child: mobile
            ? (selected
                  ? _ConversationPane(
                      language: language,
                      state: state,
                      mobile: true,
                      showInfoPanel: false,
                      focusMessageId: _focusMessageId,
                      onFocusHandled: _clearFocusedMessage,
                      onBack: _closeMobileConversation,
                      onInfo: () => _showInfo(context, state, language),
                    )
                  : _ConversationListPane(
                      language: language,
                      state: state,
                      conversations: _visibleConversations(state),
                      searchController: _searchController,
                      searchFocusNode: _searchFocusNode,
                      filter: _filter,
                      mobile: true,
                      onFilterChanged: (value) =>
                          setState(() => _filter = value),
                      onOpen: _openConversation,
                      onCreate: () => _showCreateConversation(language),
                    ))
            : Row(
                children: [
                  SizedBox(
                    width: size.width <= 980 ? 285 : 320,
                    child: _ConversationListPane(
                      language: language,
                      state: state,
                      conversations: _visibleConversations(state),
                      searchController: _searchController,
                      searchFocusNode: _searchFocusNode,
                      filter: _filter,
                      mobile: false,
                      onFilterChanged: (value) =>
                          setState(() => _filter = value),
                      onOpen: _openConversation,
                      onCreate: () => _showCreateConversation(language),
                    ),
                  ),
                  const VerticalDivider(width: 1, thickness: 1),
                  Expanded(
                    child: selected
                        ? _ConversationPane(
                            language: language,
                            state: state,
                            mobile: false,
                            showInfoPanel: showInfo,
                            focusMessageId: _focusMessageId,
                            onFocusHandled: _clearFocusedMessage,
                            onInfo: canDockInfo
                                ? _toggleDetailsPanel
                                : () => _showInfo(context, state, language),
                          )
                        : _ConversationEmptyState(
                            language: language,
                            onCreate: () => _showCreateConversation(language),
                          ),
                  ),
                  if (canDockInfo && selected)
                    ClipRect(
                      child: AnimatedSize(
                        alignment: AlignmentDirectional.centerEnd,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 160),
                        curve: Curves.easeOutCubic,
                        child: showInfo
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const VerticalDivider(width: 1, thickness: 1),
                                  SizedBox(
                                    width: 316,
                                    child: _ConversationInfoPanel(
                                      language: language,
                                      state: state,
                                      onSelectPinnedMessage: _focusMessage,
                                    ),
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
      ),
    );

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _FocusChatSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _FocusChatSearchIntent(),
      },
      child: Actions(
        actions: {
          _FocusChatSearchIntent: CallbackAction<_FocusChatSearchIntent>(
            onInvoke: (_) {
              if (!selected || !mobile) _searchFocusNode.requestFocus();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: !mobile,
          child: ColoredBox(
            color: AppColors.surface,
            child: Padding(
              padding: mobile
                  ? EdgeInsets.zero
                  : EdgeInsets.fromLTRB(
                      size.width <= 980 ? 12 : 20,
                      size.width <= 980 ? 12 : 16,
                      size.width <= 980 ? 12 : 20,
                      size.width <= 980 ? 16 : 20,
                    ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }

  void _toggleDetailsPanel() {
    setState(() => _detailsPanelVisible = !_detailsPanelVisible);
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setBool(_detailsPanelPreferenceKey, _detailsPanelVisible),
    );
  }

  void _openConversation(String id) {
    ref.read(yorksV1TeamChatProvider.notifier).openConversation(id);
    if (MediaQuery.sizeOf(context).width <= AppSpacing.compactBreakpoint) {
      context.go(RoutePaths.yorksV1TeamChatPath(id));
    }
  }

  void _closeMobileConversation() {
    ref.read(yorksV1TeamChatProvider.notifier).closeConversation();
    context.go(RoutePaths.yorksV1TeamChat);
  }

  void _focusMessage(String messageId) {
    setState(() => _focusMessageId = messageId);
  }

  void _clearFocusedMessage() {
    if (mounted && _focusMessageId != null) {
      setState(() => _focusMessageId = null);
    }
  }

  Future<void> _showCreateConversation(AppLanguage language) async {
    final controller = ref.read(yorksV1TeamChatProvider.notifier);
    await controller.loadDirectory();
    if (!mounted) return;
    final created = await showModalBottomSheet<YorksV1ChatConversation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CreateConversationSheet(language: language),
    );
    if (created != null && mounted) {
      _openConversation(created.id);
    }
  }

  Future<void> _showInfo(
    BuildContext context,
    YorksV1TeamChatState state,
    AppLanguage language,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .9,
        ),
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        child: _ConversationInfoPanel(
          language: language,
          state: state,
          showClose: true,
          onSelectPinnedMessage: (messageId) {
            Navigator.pop(sheetContext);
            _focusMessage(messageId);
          },
        ),
      ),
    ),
  );
}

class _ConversationListPane extends ConsumerWidget {
  const _ConversationListPane({
    required this.language,
    required this.state,
    required this.conversations,
    required this.searchController,
    required this.searchFocusNode,
    required this.filter,
    required this.mobile,
    required this.onFilterChanged,
    required this.onOpen,
    required this.onCreate,
  });

  final AppLanguage language;
  final YorksV1TeamChatState state;
  final List<YorksV1ChatConversation> conversations;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final YorksV1ChatFilter filter;
  final bool mobile;
  final ValueChanged<YorksV1ChatFilter> onFilterChanged;
  final ValueChanged<String> onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPushStatus = ref.watch(pushDeliveryStatusProvider);
    final pushStatus =
        asyncPushStatus.valueOrNull ?? ref.watch(pushServiceProvider).status;
    final needsAlertSetup = switch (pushStatus.authorization) {
      PushAuthorizationState.checking ||
      PushAuthorizationState.unsupported => false,
      PushAuthorizationState.authorized ||
      PushAuthorizationState.provisional => !pushStatus.deviceRegistered,
      _ => true,
    };
    final conversationEntries = _conversationListEntries(conversations);
    return Column(
      children: [
        SizedBox(
          height: mobile ? 58 : 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.blueContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.forum_outlined,
                    color: AppColors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    YorksV1TeamChatStrings.teamChat.active(language),
                    style: AppTypography.titleMedium,
                  ),
                ),
                _CountBadge(count: state.unreadCount),
                const SizedBox(width: 6),
                if (needsAlertSetup) ...[
                  _ChatIconButton(
                    tooltip: AppStrings.enableAlerts.active(language),
                    icon:
                        pushStatus.authorization ==
                            PushAuthorizationState.denied
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_none_rounded,
                    onPressed: () => _showChatAlertSetup(context),
                  ),
                  const SizedBox(width: 2),
                ],
                _ChatIconButton(
                  tooltip: YorksV1TeamChatStrings.newConversation.active(
                    language,
                  ),
                  icon: Icons.add_rounded,
                  onPressed: onCreate,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: searchController,
            focusNode: searchFocusNode,
            decoration: InputDecoration(
              isDense: true,
              hintText: YorksV1TeamChatStrings.search.active(language),
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: YorksV1TeamChatStrings.close.active(language),
                      onPressed: searchController.clear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.line),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        SizedBox(
          height: 39,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            scrollDirection: Axis.horizontal,
            itemCount: YorksV1ChatFilter.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final value = YorksV1ChatFilter.values[index];
              return ChoiceChip(
                label: Text(_filterLabel(value, language)),
                selected: filter == value,
                onSelected: (_) => onFilterChanged(value),
                visualDensity: VisualDensity.compact,
                labelStyle: AppTypography.labelSmall.copyWith(
                  color: filter == value ? AppColors.navy : AppColors.muted,
                ),
                side: const BorderSide(color: AppColors.line),
                selectedColor: AppColors.blueContainer,
                backgroundColor: AppColors.surfaceContainerLowest,
                padding: const EdgeInsets.symmetric(horizontal: 5),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: state.loadingList && conversations.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : conversations.isEmpty
              ? _SmallEmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: YorksV1TeamChatStrings.noConversations.active(
                    language,
                  ),
                  body: YorksV1TeamChatStrings.noConversationsBody.active(
                    language,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => context
                      .readProvider(yorksV1TeamChatProvider.notifier)
                      .refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: conversationEntries.length,
                    itemBuilder: (context, index) {
                      final entry = conversationEntries[index];
                      if (entry.conversation == null) {
                        return _ConversationSectionHeading(
                          label:
                              (entry.pinned
                                      ? YorksV1TeamChatStrings.pinned
                                      : YorksV1TeamChatStrings.recent)
                                  .active(language),
                        );
                      }
                      final conversation = entry.conversation!;
                      return _ConversationListTile(
                        conversation: conversation,
                        selected:
                            state.selectedConversationId == conversation.id,
                        language: language,
                        onTap: () => onOpen(conversation.id),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _FocusChatSearchIntent extends Intent {
  const _FocusChatSearchIntent();
}

class _ConversationListEntry {
  const _ConversationListEntry.heading({required this.pinned})
    : conversation = null;

  const _ConversationListEntry.conversation(this.conversation) : pinned = false;

  final bool pinned;
  final YorksV1ChatConversation? conversation;
}

List<_ConversationListEntry> _conversationListEntries(
  List<YorksV1ChatConversation> conversations,
) {
  final pinned = conversations.where((item) => item.isPinned).toList();
  final recent = conversations.where((item) => !item.isPinned).toList();
  return [
    if (pinned.isNotEmpty) ...[
      const _ConversationListEntry.heading(pinned: true),
      ...pinned.map(_ConversationListEntry.conversation),
    ],
    if (recent.isNotEmpty) ...[
      const _ConversationListEntry.heading(pinned: false),
      ...recent.map(_ConversationListEntry.conversation),
    ],
  ];
}

class _ConversationSectionHeading extends StatelessWidget {
  const _ConversationSectionHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 5),
    child: Text(
      label.toUpperCase(),
      style: AppTypography.labelSmall.copyWith(
        color: AppColors.muted,
        fontWeight: FontWeight.w800,
        letterSpacing: .75,
      ),
    ),
  );
}

Future<void> _showChatAlertSetup(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: const NotificationDeliveryCard(compact: true),
      ),
    ),
  );
}

extension on BuildContext {
  T readProvider<T>(ProviderListenable<T> provider) =>
      ProviderScope.containerOf(this, listen: false).read(provider);
}

class _ConversationListTile extends StatelessWidget {
  const _ConversationListTile({
    required this.conversation,
    required this.selected,
    required this.language,
    required this.onTap,
  });

  final YorksV1ChatConversation conversation;
  final bool selected;
  final AppLanguage language;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final last = conversation.lastMessage;
    final preview =
        conversation.searchPreview ??
        (last == null
            ? conversation.description ?? ''
            : _messagePreview(last, language));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.blueContainer.withValues(alpha: .78)
                : AppColors.surfaceContainerLowest,
            border: BorderDirectional(
              start: BorderSide(
                color: selected ? AppColors.blue : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              _ConversationAvatar(conversation: conversation, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        if (conversation.isPinned) ...[
                          const Icon(
                            Icons.push_pin_rounded,
                            size: 13,
                            color: AppColors.blue,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleSmall.copyWith(
                              fontWeight: conversation.hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          _compactTime(
                            conversation.lastMessageAt ??
                                conversation.createdAt,
                          ),
                          style: AppTypography.labelSmall.copyWith(
                            color: conversation.hasUnread
                                ? AppColors.blue
                                : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodySmall.copyWith(
                              color: conversation.hasUnread
                                  ? AppColors.inkSecondary
                                  : AppColors.muted,
                              fontWeight: conversation.hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (conversation.isMuted)
                          const Padding(
                            padding: EdgeInsetsDirectional.only(start: 6),
                            child: Icon(
                              Icons.notifications_off_outlined,
                              size: 14,
                              color: AppColors.muted,
                            ),
                          ),
                        if (conversation.hasUnread) ...[
                          const SizedBox(width: 7),
                          _CountBadge(count: conversation.unreadCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationPane extends ConsumerStatefulWidget {
  const _ConversationPane({
    required this.language,
    required this.state,
    required this.mobile,
    required this.showInfoPanel,
    required this.focusMessageId,
    required this.onFocusHandled,
    required this.onInfo,
    this.onBack,
  });

  final AppLanguage language;
  final YorksV1TeamChatState state;
  final bool mobile;
  final bool showInfoPanel;
  final String? focusMessageId;
  final VoidCallback onFocusHandled;
  final VoidCallback onInfo;
  final VoidCallback? onBack;

  @override
  ConsumerState<_ConversationPane> createState() => _ConversationPaneState();
}

class _ConversationPaneState extends ConsumerState<_ConversationPane> {
  final _scrollController = ScrollController();
  final _messageKeys = <String, GlobalKey>{};
  final _draftBodies = <String, String>{};
  YorksV1ChatMessage? _replyingTo;
  bool _nearBottom = true;
  bool _loadingOlder = false;
  int _newMessageCount = 0;
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void didUpdateWidget(covariant _ConversationPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldThread = oldWidget.state.thread;
    final newThread = widget.state.thread;
    if (newThread == null) return;
    if (widget.focusMessageId != null &&
        widget.focusMessageId != oldWidget.focusMessageId) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focusRequestedMessage(),
      );
    }
    if (oldThread?.conversation.id != newThread.conversation.id) {
      _newMessageCount = 0;
      _nearBottom = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      return;
    }
    final oldLast = oldThread?.messages.lastOrNull?.id;
    final newLast = newThread.messages.lastOrNull?.id;
    if (newLast != null && newLast != oldLast) {
      final oldIds = oldThread?.messages.map((item) => item.id).toSet() ?? {};
      final appended = newThread.messages
          .where((message) => !oldIds.contains(message.id))
          .length;
      if (_nearBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      } else if (appended > 0) {
        _newMessageCount += appended;
      }
    }
  }

  Future<void> _focusRequestedMessage() async {
    final messageId = widget.focusMessageId;
    if (!mounted || messageId == null) return;
    await _revealMessage(messageId);
    widget.onFocusHandled();
  }

  Future<void> _revealMessage(String messageId) async {
    if (!mounted) return;
    final messageContext = _messageKeys[messageId]?.currentContext;
    if (messageContext == null && _scrollController.hasClients) {
      final messages = widget.state.thread?.messages ?? const [];
      final index = messages.indexWhere((message) => message.id == messageId);
      if (index >= 0 && messages.length > 1) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent *
              (index / (messages.length - 1)),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    }
    if (!mounted) return;
    final revealedContext = _messageKeys[messageId]?.currentContext;
    if (revealedContext != null && revealedContext.mounted) {
      await Scrollable.ensureVisible(
        revealedContext,
        alignment: .35,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
    if (!mounted) return;
    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _highlightedMessageId == messageId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final nowNearBottom = position.maxScrollExtent - position.pixels < 120;
    if (nowNearBottom != _nearBottom ||
        (nowNearBottom && _newMessageCount > 0)) {
      setState(() {
        _nearBottom = nowNearBottom;
        if (nowNearBottom) _newMessageCount = 0;
      });
    }
    if (position.pixels <= 72 && !_loadingOlder) {
      unawaited(_loadOlder());
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !widget.state.hasOlderMessages) return;
    _loadingOlder = true;
    final beforeExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final beforePixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final added = await ref
        .read(yorksV1TeamChatProvider.notifier)
        .loadOlderMessages();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients || added == 0) return;
      final delta = _scrollController.position.maxScrollExtent - beforeExtent;
      _scrollController.jumpTo(
        (beforePixels + delta).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
      );
    });
    _loadingOlder = false;
  }

  void _jumpToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.state.thread;
    if (widget.state.loadingThread && thread == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (thread == null) {
      return _SmallEmptyState(
        icon: Icons.cloud_off_outlined,
        title: YorksV1TeamChatStrings.couldNotLoad.active(widget.language),
        body: YorksV1TeamChatStrings.retry.active(widget.language),
      );
    }
    final conversation = thread.conversation;
    final outgoing = widget.state.outgoingInput;
    final showOutgoing = outgoing?.conversationId == conversation.id;
    return Column(
      children: [
        SizedBox(
          height: widget.mobile ? 58 : 66,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                if (widget.mobile)
                  _ChatIconButton(
                    tooltip: YorksV1TeamChatStrings.close.active(
                      widget.language,
                    ),
                    icon: Icons.arrow_back_rounded,
                    onPressed: widget.onBack,
                  ),
                _ConversationAvatar(conversation: conversation, size: 38),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleSmall,
                      ),
                      Text(
                        _conversationSubtitle(
                          conversation,
                          thread.participants.length,
                          widget.language,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (conversation.projectId != null ||
                    conversation.materialRequestId != null)
                  _ChatIconButton(
                    tooltip: YorksV1TeamChatStrings.openRecord.active(
                      widget.language,
                    ),
                    icon: Icons.open_in_new_rounded,
                    onPressed: () =>
                        _openConversationRecord(context, conversation),
                  ),
                _ChatIconButton(
                  tooltip: YorksV1TeamChatStrings.searchConversation.active(
                    widget.language,
                  ),
                  icon: Icons.search_rounded,
                  onPressed: () => _showMessageSearch(thread),
                ),
                _ChatIconButton(
                  key: const ValueKey('chat-details-panel-toggle'),
                  tooltip:
                      (widget.showInfoPanel
                              ? YorksV1TeamChatStrings.hideConversationDetails
                              : YorksV1TeamChatStrings.showConversationDetails)
                          .active(widget.language),
                  icon: widget.showInfoPanel
                      ? Icons.last_page_rounded
                      : Icons.info_outline_rounded,
                  onPressed: widget.onInfo,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Container(
          width: double.infinity,
          margin: EdgeInsets.fromLTRB(
            widget.mobile ? 8 : 14,
            8,
            widget.mobile ? 8 : 14,
            0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.blueContainer.withValues(alpha: .62),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.blueContainerStrong),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 17,
                color: AppColors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  YorksV1TeamChatStrings.authorizedMembersOnly.active(
                    widget.language,
                  ),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: thread.messages.isEmpty && !showOutgoing
              ? _SmallEmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: YorksV1TeamChatStrings.noMessages.active(
                    widget.language,
                  ),
                  body: YorksV1TeamChatStrings.noMessagesBody.active(
                    widget.language,
                  ),
                )
              : Stack(
                  children: [
                    ListView.builder(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        widget.mobile ? 10 : 18,
                        14,
                        widget.mobile ? 10 : 18,
                        14,
                      ),
                      itemCount:
                          thread.messages.length +
                          (showOutgoing ? 1 : 0) +
                          (widget.state.loadingOlder ? 1 : 0),
                      itemBuilder: (context, rawIndex) {
                        if (widget.state.loadingOlder && rawIndex == 0) {
                          return const Padding(
                            padding: EdgeInsets.all(10),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }
                        final index =
                            rawIndex - (widget.state.loadingOlder ? 1 : 0);
                        if (index >= thread.messages.length) {
                          return _OutgoingAttemptBubble(
                            input: outgoing!,
                            status: widget.state.outgoingStatus!,
                            language: widget.language,
                          );
                        }
                        final message = thread.messages[index];
                        final previous = index == 0
                            ? null
                            : thread.messages[index - 1];
                        final showDate =
                            previous == null ||
                            !_sameDay(previous.createdAt, message.createdAt);
                        return KeyedSubtree(
                          key: _messageKeys.putIfAbsent(
                            message.id,
                            GlobalKey.new,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: _highlightedMessageId == message.id
                                  ? AppColors.blueContainer.withValues(
                                      alpha: .62,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                if (showDate)
                                  _DateSeparator(
                                    date: message.createdAt,
                                    language: widget.language,
                                  ),
                                if (message.isSystem)
                                  _SystemMessage(
                                    message: message,
                                    language: widget.language,
                                  )
                                else
                                  _MessageBubble(
                                    message: message,
                                    language: widget.language,
                                    mobile: widget.mobile,
                                    onReply: () =>
                                        setState(() => _replyingTo = message),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    if (_newMessageCount > 0)
                      Positioned(
                        right: 14,
                        bottom: 12,
                        child: FilledButton.icon(
                          onPressed: _scrollToBottom,
                          icon: const Icon(Icons.arrow_downward_rounded),
                          label: Text(
                            '$_newMessageCount ${YorksV1TeamChatStrings.newMessages.active(widget.language)}',
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        _ChatComposer(
          key: ValueKey('chat-composer-${conversation.id}'),
          language: widget.language,
          thread: thread,
          replyingTo: _replyingTo,
          initialDraft: _draftBodies[conversation.id] ?? '',
          onDraftChanged: (value) {
            if (value.trim().isEmpty) {
              _draftBodies.remove(conversation.id);
            } else {
              _draftBodies[conversation.id] = value;
            }
          },
          onCancelReply: () => setState(() => _replyingTo = null),
          onSent: () => setState(() => _replyingTo = null),
        ),
      ],
    );
  }

  Future<void> _showMessageSearch(YorksV1ChatThread thread) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ConversationMessageSearchSheet(
        language: widget.language,
        messages: thread.messages,
      ),
    );
    if (selected != null && mounted) await _revealMessage(selected);
  }
}

class _ConversationMessageSearchSheet extends StatefulWidget {
  const _ConversationMessageSearchSheet({
    required this.language,
    required this.messages,
  });

  final AppLanguage language;
  final List<YorksV1ChatMessage> messages;

  @override
  State<_ConversationMessageSearchSheet> createState() =>
      _ConversationMessageSearchSheetState();
}

class _ConversationMessageSearchSheetState
    extends State<_ConversationMessageSearchSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<YorksV1ChatMessage> get _results {
    final query = _controller.text.trim().toLowerCase();
    final searchable = widget.messages.where((message) => !message.isSystem);
    final values = query.isEmpty
        ? searchable.toList()
        : searchable.where((message) {
            final content = [
              message.senderDisplayName,
              message.body,
              ...message.attachments.map((item) => item.fileName),
            ].whereType<String>().join(' ').toLowerCase();
            return content.contains(query);
          }).toList();
    return values.reversed.take(30).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .78,
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        YorksV1TeamChatStrings.searchConversation.active(
                          widget.language,
                        ),
                        style: AppTypography.titleMedium,
                      ),
                    ),
                    _ChatIconButton(
                      tooltip: YorksV1TeamChatStrings.close.active(
                        widget.language,
                      ),
                      icon: Icons.close_rounded,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: TextField(
                  key: const ValueKey('chat-message-search-field'),
                  controller: _controller,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: YorksV1TeamChatStrings.searchRecentMessages
                        .active(widget.language),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: YorksV1TeamChatStrings.close.active(
                              widget.language,
                            ),
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: results.isEmpty
                    ? _SmallEmptyState(
                        icon: Icons.search_off_rounded,
                        title: YorksV1TeamChatStrings.noMatchingMessages.active(
                          widget.language,
                        ),
                        body: YorksV1TeamChatStrings.searchRecentMessages
                            .active(widget.language),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: results.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 62),
                        itemBuilder: (context, index) {
                          final message = results[index];
                          final preview =
                              message.body ??
                              message.attachments.firstOrNull?.fileName ??
                              '';
                          return Material(
                            key: ValueKey(
                              'chat-message-search-result-${message.id}',
                            ),
                            color: Colors.transparent,
                            child: ListTile(
                              minTileHeight: 58,
                              leading: _PersonAvatar(
                                name: message.senderDisplayName ?? '',
                                size: 36,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      message.senderDisplayName ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.labelLarge,
                                    ),
                                  ),
                                  Text(
                                    _compactTime(message.createdAt),
                                    style: AppTypography.labelSmall,
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(context, message.id),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemMessage extends StatelessWidget {
  const _SystemMessage({required this.message, required this.language});

  final YorksV1ChatMessage message;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    YorksV1TeamChatStrings.systemEvent(
                      message.systemEventCode,
                    ).active(language),
                    textAlign: TextAlign.center,
                    style: AppTypography.labelSmall,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  DateFormat.jm().format(message.createdAt),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.mutedLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _OutgoingAttemptBubble extends StatelessWidget {
  const _OutgoingAttemptBubble({
    required this.input,
    required this.status,
    required this.language,
  });

  final YorksV1ChatSendInput input;
  final YorksV1ChatOutgoingStatus status;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerEnd,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
      decoration: BoxDecoration(
        color: status == YorksV1ChatOutgoingStatus.failed
            ? AppColors.errorContainer
            : AppColors.blueContainer,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: status == YorksV1ChatOutgoingStatus.failed
              ? AppColors.error
              : AppColors.blueContainerStrong,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (input.body?.trim().isNotEmpty == true)
            Text(input.body!.trim(), style: AppTypography.bodyMedium),
          if (input.attachmentIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.attach_file_rounded, size: 15),
                  Text('${input.attachmentIds.length}'),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Text(
            (status == YorksV1ChatOutgoingStatus.failed
                    ? YorksV1TeamChatStrings.failed
                    : YorksV1TeamChatStrings.sending)
                .active(language),
            style: AppTypography.labelSmall.copyWith(
              color: status == YorksV1ChatOutgoingStatus.failed
                  ? AppColors.error
                  : AppColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.language,
    required this.mobile,
    required this.onReply,
  });

  final YorksV1ChatMessage message;
  final AppLanguage language;
  final bool mobile;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final own = message.isMine;
    final bubbleColor = message.isDeleted
        ? AppColors.surfaceContainer
        : own
        ? AppColors.blueContainer
        : AppColors.surfaceContainerLow;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: mobile ? 430 : 520),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 6),
      decoration: BoxDecoration(
        color: bubbleColor,
        border: Border.all(
          color: own && !message.isDeleted
              ? AppColors.blueContainerStrong
              : AppColors.line,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(own ? 12 : 4),
          topRight: Radius.circular(own ? 4 : 12),
          bottomLeft: const Radius.circular(12),
          bottomRight: const Radius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!own)
            Text(
              message.senderDisplayName!,
              style: AppTypography.labelLarge.copyWith(color: AppColors.blue),
            ),
          if (message.isDeleted)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.block_rounded,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      YorksV1TeamChatStrings.messageDeleted.active(language),
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.muted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            if (message.replyPreview != null) ...[
              const SizedBox(height: 5),
              _ReplyPreview(
                preview: message.replyPreview!,
                dark: false,
                language: language,
              ),
            ],
            if (message.body != null) ...[
              const SizedBox(height: 4),
              SelectableText(
                message.body!,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.inkSecondary,
                  height: 1.42,
                ),
              ),
            ],
            if (message.attachments.isNotEmpty) ...[
              const SizedBox(height: 7),
              for (final attachment in message.attachments)
                _AttachmentTile(
                  attachment: attachment,
                  dark: false,
                  language: language,
                ),
            ],
            if (message.linkedEntityId != null) ...[
              const SizedBox(height: 7),
              _LinkedRecordChip(
                message: message,
                dark: false,
                language: language,
              ),
            ],
          ],
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat.jm().format(message.createdAt),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.muted,
                ),
              ),
              if (message.isEdited) ...[
                const SizedBox(width: 5),
                Text(
                  YorksV1TeamChatStrings.edited.active(language),
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
              if (message.isPinned) ...[
                const SizedBox(width: 5),
                const Icon(
                  Icons.push_pin_rounded,
                  size: 12,
                  color: AppColors.blue,
                ),
              ],
              if (message.acknowledgementCount > 0) ...[
                const SizedBox(width: 5),
                const Icon(
                  Icons.check_circle_rounded,
                  size: 13,
                  color: AppColors.success,
                ),
                const SizedBox(width: 2),
                Text(
                  '${message.acknowledgementCount}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.success,
                  ),
                ),
              ],
              if (own) ...[
                const SizedBox(width: 5),
                _MessageReceipt(message: message, language: language),
              ],
              if (!message.isDeleted) ...[
                const SizedBox(width: 2),
                PopupMenuButton<String>(
                  key: ValueKey('chat-message-menu-${message.id}'),
                  tooltip: YorksV1TeamChatStrings.conversationInfo.active(
                    language,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: AppSpacing.minTapTarget,
                    minHeight: AppSpacing.minTapTarget,
                  ),
                  iconSize: 17,
                  color: AppColors.surfaceContainerLowest,
                  icon: const Icon(
                    Icons.more_horiz_rounded,
                    color: AppColors.muted,
                  ),
                  onSelected: (value) {
                    if (value == 'reply') onReply();
                    if (value == 'ack') {
                      ref
                          .read(yorksV1TeamChatProvider.notifier)
                          .toggleAcknowledgement(message.id);
                    }
                    if (value == 'pin') {
                      ref
                          .read(yorksV1TeamChatProvider.notifier)
                          .toggleMessagePin(message.id);
                    }
                    if (value == 'edit') {
                      _showEditMessage(context, ref, message, language);
                    }
                    if (value == 'delete') {
                      _showDeleteMessage(context, ref, message, language);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'reply',
                      child: _MenuLabel(
                        icon: Icons.reply_rounded,
                        label: YorksV1TeamChatStrings.reply.active(language),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'ack',
                      child: _MenuLabel(
                        icon: Icons.check_circle_outline_rounded,
                        label: YorksV1TeamChatStrings.acknowledge.active(
                          language,
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'pin',
                      child: _MenuLabel(
                        icon: Icons.push_pin_outlined,
                        label:
                            (message.isPinned
                                    ? YorksV1TeamChatStrings.unpinMessage
                                    : YorksV1TeamChatStrings.pinMessage)
                                .active(language),
                      ),
                    ),
                    if (message.canEdit)
                      PopupMenuItem(
                        value: 'edit',
                        child: _MenuLabel(
                          icon: Icons.edit_outlined,
                          label: YorksV1TeamChatStrings.editMessage.active(
                            language,
                          ),
                        ),
                      ),
                    if (message.canDelete)
                      PopupMenuItem(
                        value: 'delete',
                        child: _MenuLabel(
                          icon: Icons.delete_outline_rounded,
                          label: YorksV1TeamChatStrings.deleteMessage.active(
                            language,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        mainAxisAlignment: own
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!own) ...[
            _PersonAvatar(
              name: message.senderDisplayName ?? '',
              size: mobile ? 26 : 30,
            ),
            const SizedBox(width: 7),
          ],
          Flexible(child: bubble),
          if (own) ...[
            const SizedBox(width: 7),
            _PersonAvatar(
              name: message.senderDisplayName ?? '',
              size: mobile ? 26 : 30,
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageReceipt extends StatelessWidget {
  const _MessageReceipt({required this.message, required this.language});

  final YorksV1ChatMessage message;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    final status = message.receiptStatus ?? YorksV1ChatReceiptStatus.sent;
    final label = switch (status) {
      YorksV1ChatReceiptStatus.sent => YorksV1TeamChatStrings.sent,
      YorksV1ChatReceiptStatus.delivered => YorksV1TeamChatStrings.delivered,
      YorksV1ChatReceiptStatus.read => YorksV1TeamChatStrings.read,
    }.active(language);
    final count = status == YorksV1ChatReceiptStatus.read
        ? message.readCount
        : message.deliveredCount;
    final semanticLabel = message.recipientCount > 1
        ? '$label · $count/${message.recipientCount}'
        : label;
    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        label: semanticLabel,
        child: Icon(
          status == YorksV1ChatReceiptStatus.sent
              ? Icons.done_rounded
              : Icons.done_all_rounded,
          size: 15,
          color: status == YorksV1ChatReceiptStatus.read
              ? AppColors.blue
              : AppColors.muted,
        ),
      ),
    );
  }
}

Future<void> _showEditMessage(
  BuildContext context,
  WidgetRef ref,
  YorksV1ChatMessage message,
  AppLanguage language,
) async {
  final updatedBody = await showDialog<String>(
    context: context,
    builder: (_) =>
        _EditMessageDialog(initialBody: message.body ?? '', language: language),
  );
  if (updatedBody == null || !context.mounted) return;
  final saved = await ref
      .read(yorksV1TeamChatProvider.notifier)
      .editMessage(
        YorksV1ChatEditInput(
          messageId: message.id,
          body: updatedBody,
          expectedVersion: message.version,
          idempotencyKey: const Uuid().v4(),
        ),
      );
  if (!saved && context.mounted) {
    _showChatSnackBar(
      context,
      YorksV1TeamChatStrings.couldNotEdit.active(language),
    );
  }
}

class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initialBody, required this.language});

  final String initialBody;
  final AppLanguage language;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialBody);
  }

  bool get _canSave {
    final value = _controller.text.trim();
    return value.isNotEmpty && value != widget.initialBody;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(YorksV1TeamChatStrings.editMessage.active(widget.language)),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 8,
        maxLength: 4000,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: YorksV1TeamChatStrings.messageHint.active(widget.language),
          border: const OutlineInputBorder(),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(YorksV1TeamChatStrings.cancel.active(widget.language)),
      ),
      FilledButton(
        onPressed: _canSave
            ? () => Navigator.pop(context, _controller.text.trim())
            : null,
        child: Text(YorksV1TeamChatStrings.saveChanges.active(widget.language)),
      ),
    ],
  );
}

Future<void> _showDeleteMessage(
  BuildContext context,
  WidgetRef ref,
  YorksV1ChatMessage message,
  AppLanguage language,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(YorksV1TeamChatStrings.deleteMessage.active(language)),
      content: Text(YorksV1TeamChatStrings.deleteMessageBody.active(language)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(YorksV1TeamChatStrings.cancel.active(language)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(YorksV1TeamChatStrings.deleteMessage.active(language)),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final deleted = await ref
      .read(yorksV1TeamChatProvider.notifier)
      .deleteMessage(
        YorksV1ChatDeleteInput(
          messageId: message.id,
          expectedVersion: message.version,
          idempotencyKey: const Uuid().v4(),
        ),
      );
  if (!deleted && context.mounted) {
    _showChatSnackBar(
      context,
      YorksV1TeamChatStrings.couldNotDelete.active(language),
    );
  }
}

void _showChatSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
}

class _ChatComposer extends ConsumerStatefulWidget {
  const _ChatComposer({
    super.key,
    required this.language,
    required this.thread,
    required this.replyingTo,
    required this.initialDraft,
    required this.onDraftChanged,
    required this.onCancelReply,
    required this.onSent,
  });

  final AppLanguage language;
  final YorksV1ChatThread thread;
  final YorksV1ChatMessage? replyingTo;
  final String initialDraft;
  final ValueChanged<String> onDraftChanged;
  final VoidCallback onCancelReply;
  final VoidCallback onSent;

  @override
  ConsumerState<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends ConsumerState<_ChatComposer> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _pending = <YorksV1PendingChatAttachment>[];
  final _mentions = <String>{};
  bool _uploading = false;
  YorksV1ChatContextTarget? _linkedTarget;
  String? _messageIdempotencyKey;
  String? _attemptFingerprint;
  String? _mentionQuery;
  int? _mentionStart;

  @override
  void initState() {
    super.initState();
    _textController.text = widget.initialDraft;
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canSend =>
      _textController.text.trim().isNotEmpty ||
      _pending.isNotEmpty ||
      _linkedTarget != null;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(yorksV1TeamChatProvider);
    final conversation = widget.thread.conversation;
    final adminOnly =
        conversation.kind == YorksV1ChatKind.announcement &&
        ref.watch(yorksV1CurrentRoleProvider) != YorksV1Role.admin;
    final failedAttempt =
        state.outgoingStatus == YorksV1ChatOutgoingStatus.failed &&
        state.outgoingInput?.conversationId == conversation.id;
    final mentionSuggestions = _mentionQuery == null
        ? const <YorksV1ChatParticipant>[]
        : widget.thread.participants
              .where((person) {
                if (person.authUserId == ref.watch(yorksV1AuthUserIdProvider)) {
                  return false;
                }
                final query = _mentionQuery!;
                return query.isEmpty ||
                    person.displayName.toLowerCase().contains(query);
              })
              .take(4)
              .toList(growable: false);
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (adminOnly)
              _ComposerContextStrip(
                icon: Icons.lock_outline_rounded,
                title: YorksV1TeamChatStrings.announcementLocked.active(
                  widget.language,
                ),
                body: '',
                onClose: () {},
                showClose: false,
              ),
            if (widget.replyingTo != null)
              _ComposerContextStrip(
                icon: Icons.reply_rounded,
                title: YorksV1TeamChatStrings.replyTo.active(widget.language),
                body: widget.replyingTo!.senderDisplayName!,
                onClose: widget.onCancelReply,
              ),
            if (_linkedTarget != null)
              _ComposerContextStrip(
                icon: Icons.link_rounded,
                title: YorksV1TeamChatStrings.linkedRecord.active(
                  widget.language,
                ),
                body: _linkedTarget!.title,
                onClose: () => setState(() => _linkedTarget = null),
              ),
            if (_pending.isNotEmpty || _uploading)
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pending.length + (_uploading ? 1 : 0),
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    if (index >= _pending.length) {
                      return const SizedBox(
                        width: 46,
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final attachment = _pending[index];
                    return InputChip(
                      avatar: const Icon(
                        Icons.insert_drive_file_outlined,
                        size: 17,
                      ),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          attachment.fileName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onDeleted: state.sending
                          ? null
                          : () => setState(() => _pending.removeAt(index)),
                    );
                  },
                ),
              ),
            if (mentionSuggestions.isNotEmpty)
              _ChatMentionSuggestions(
                people: mentionSuggestions,
                language: widget.language,
                onSelected: _selectMention,
              ),
            if (failedAttempt)
              Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      YorksV1TeamChatStrings.couldNotSend.active(
                        widget.language,
                      ),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: state.sending ? null : _send,
                    child: Text(
                      YorksV1TeamChatStrings.retry.active(widget.language),
                    ),
                  ),
                ],
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _ChatIconButton(
                  tooltip: YorksV1TeamChatStrings.attachFiles.active(
                    widget.language,
                  ),
                  icon: Icons.attach_file_rounded,
                  onPressed: adminOnly || state.sending || _uploading
                      ? null
                      : _attach,
                ),
                SizedBox(
                  width: AppSpacing.minTapTarget,
                  height: AppSpacing.minTapTarget,
                  child: PopupMenuButton<String>(
                    tooltip: YorksV1TeamChatStrings.addEmoji.active(
                      widget.language,
                    ),
                    enabled: !adminOnly && !state.sending,
                    icon: const Icon(Icons.sentiment_satisfied_alt_outlined),
                    onSelected: _insertEmoji,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: '👍', child: Text('👍')),
                      PopupMenuItem(value: '✅', child: Text('✅')),
                      PopupMenuItem(value: '🙏', child: Text('🙏')),
                      PopupMenuItem(value: '🙂', child: Text('🙂')),
                      PopupMenuItem(value: '📎', child: Text('📎')),
                      PopupMenuItem(value: '🚚', child: Text('🚚')),
                    ],
                  ),
                ),
                _ChatIconButton(
                  tooltip: YorksV1TeamChatStrings.choosePerson.active(
                    widget.language,
                  ),
                  icon: Icons.alternate_email_rounded,
                  onPressed: adminOnly || state.sending ? null : _mention,
                ),
                _ChatIconButton(
                  tooltip: YorksV1TeamChatStrings.linkRecord.active(
                    widget.language,
                  ),
                  icon: _linkedTarget == null
                      ? Icons.link_rounded
                      : Icons.link_off_rounded,
                  onPressed: adminOnly || state.sending ? null : _pickRecord,
                ),
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 126),
                    child: Shortcuts(
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.enter):
                            _SendMessageIntent(),
                      },
                      child: Actions(
                        actions: {
                          _SendMessageIntent:
                              CallbackAction<_SendMessageIntent>(
                                onInvoke: (_) {
                                  if (_canSend && !state.sending) _send();
                                  return null;
                                },
                              ),
                        },
                        child: TextField(
                          controller: _textController,
                          focusNode: _focusNode,
                          enabled: !adminOnly && !state.sending,
                          minLines: 1,
                          maxLines: 5,
                          onChanged: (value) {
                            widget.onDraftChanged(value);
                            _updateMentionQuery();
                          },
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: YorksV1TeamChatStrings.messageHint.active(
                              widget.language,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceContainerLow,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.line,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.line,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Semantics(
                  button: true,
                  label: YorksV1TeamChatStrings.send.active(widget.language),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: AppColors.blue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      onPressed:
                          adminOnly || !_canSend || state.sending || _uploading
                          ? null
                          : _send,
                      child: state.sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _attach() async {
    try {
      final files = await ref
          .read(yorksV1ChatFileServiceProvider)
          .selectFiles();
      if (files.isEmpty || !mounted) return;
      if (_pending.length + files.length > 10) {
        _showError(
          YorksV1TeamChatStrings.attachmentLimit.active(widget.language),
        );
        return;
      }
      setState(() => _uploading = true);
      final uploaded = await ref
          .read(yorksV1TeamChatProvider.notifier)
          .uploadFiles(widget.thread.conversation.id, files);
      if (!mounted) return;
      setState(() {
        _pending.addAll(uploaded);
        _uploading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _showError(
        YorksV1TeamChatStrings.attachmentFailed.active(widget.language),
      );
    }
  }

  Future<void> _mention() async {
    final text = _textController.text;
    final selection = _textController.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final prefix = cursor > 0 && !RegExp(r'\s').hasMatch(text[cursor - 1])
        ? ' @'
        : '@';
    final next = text.replaceRange(cursor, cursor, prefix);
    _textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
    );
    _updateMentionQuery();
    _focusNode.requestFocus();
  }

  void _insertEmoji(String emoji) {
    final text = _textController.text;
    final selection = _textController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final next = text.replaceRange(start, end, emoji);
    _textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    widget.onDraftChanged(next);
    setState(() {});
    _focusNode.requestFocus();
  }

  void _updateMentionQuery() {
    final selection = _textController.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      setState(() {
        _mentionQuery = null;
        _mentionStart = null;
      });
      return;
    }
    final cursor = selection.baseOffset;
    final before = _textController.text.substring(0, cursor);
    final match = RegExp(
      r'(^|\s)@([\p{L}\p{N}._-]*)$',
      unicode: true,
    ).firstMatch(before);
    setState(() {
      _mentionQuery = match?.group(2)?.toLowerCase();
      _mentionStart = match == null
          ? null
          : match.start + match.group(1)!.length;
    });
  }

  void _selectMention(YorksV1ChatParticipant participant) {
    final start = _mentionStart;
    final selection = _textController.selection;
    if (start == null || !selection.isValid) return;
    final current = _textController.text;
    final replacement = '@${participant.displayName} ';
    final next = current.replaceRange(start, selection.baseOffset, replacement);
    _mentions.add(participant.authUserId);
    _textController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    setState(() {
      _mentionQuery = null;
      _mentionStart = null;
    });
    _focusNode.requestFocus();
  }

  Future<void> _pickRecord() async {
    if (_linkedTarget != null) {
      setState(() => _linkedTarget = null);
      return;
    }
    final controller = ref.read(yorksV1TeamChatProvider.notifier);
    await controller.loadAllContextTargets();
    if (!mounted) return;
    final state = ref.read(yorksV1TeamChatProvider);
    final target = await showModalBottomSheet<YorksV1ChatContextTarget>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLowest,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            Text(
              YorksV1TeamChatStrings.linkRecord.active(widget.language),
              style: AppTypography.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final item in state.contextTargets)
              ListTile(
                minTileHeight: AppSpacing.minTapTarget,
                leading: Icon(_kindIcon(item.kind), color: AppColors.blue),
                title: Text(item.title),
                subtitle: Text(item.subtitle),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (target != null && mounted) setState(() => _linkedTarget = target);
  }

  Future<void> _send() async {
    final conversation = widget.thread.conversation;
    final fingerprint = <Object?>[
      _textController.text.trim(),
      widget.replyingTo?.id,
      _linkedTarget?.kind.wireValue,
      _linkedTarget?.id,
      ..._pending.map((item) => item.id),
      ...(_mentions.toList()..sort()),
    ].join('|');
    if (_messageIdempotencyKey == null || _attemptFingerprint != fingerprint) {
      _messageIdempotencyKey = const Uuid().v4();
      _attemptFingerprint = fingerprint;
    }
    final sent = await ref
        .read(yorksV1TeamChatProvider.notifier)
        .sendMessage(
          YorksV1ChatSendInput(
            conversationId: conversation.id,
            idempotencyKey: _messageIdempotencyKey!,
            body: _textController.text,
            replyToMessageId: widget.replyingTo?.id,
            linkedEntityType: _linkedTarget?.kind.wireValue,
            linkedEntityId: _linkedTarget?.id,
            attachmentIds: _pending.map((item) => item.id).toList(),
            mentionedAuthUserIds: _mentions.toList(),
          ),
        );
    if (!mounted) return;
    if (!sent) {
      _showError(YorksV1TeamChatStrings.couldNotSend.active(widget.language));
      return;
    }
    _textController.clear();
    widget.onDraftChanged('');
    _messageIdempotencyKey = null;
    _attemptFingerprint = null;
    _mentions.clear();
    setState(() {
      _pending.clear();
      _linkedTarget = null;
    });
    widget.onSent();
    _focusNode.requestFocus();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

class _ConversationInfoPanel extends ConsumerWidget {
  const _ConversationInfoPanel({
    required this.language,
    required this.state,
    required this.onSelectPinnedMessage,
    this.showClose = false,
  });

  final AppLanguage language;
  final YorksV1TeamChatState state;
  final ValueChanged<String> onSelectPinnedMessage;
  final bool showClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thread = state.thread;
    if (thread == null) return const SizedBox.shrink();
    final conversation = thread.conversation;
    final currentAuthUserId = ref.watch(yorksV1AuthUserIdProvider);
    final exactRole = ref.watch(yorksV1CurrentRoleProvider);
    final canManageGroup =
        conversation.kind == YorksV1ChatKind.group &&
        thread.participants.any(
          (participant) =>
              participant.authUserId == currentAuthUserId &&
              (participant.isOwner || exactRole == YorksV1Role.admin),
        );
    final files = [
      for (final message in thread.messages) ...message.attachments,
    ];
    final pinned = thread.messages
        .where((message) => message.isPinned)
        .toList();
    return Material(
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  YorksV1TeamChatStrings.conversationInfo.active(language),
                  style: AppTypography.titleMedium,
                ),
              ),
              if (showClose)
                _ChatIconButton(
                  tooltip: YorksV1TeamChatStrings.close.active(language),
                  icon: Icons.close_rounded,
                  onPressed: () => Navigator.pop(context),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: _ConversationAvatar(conversation: conversation, size: 58),
          ),
          const SizedBox(height: 8),
          Text(
            conversation.title,
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium,
          ),
          if (conversation.description != null) ...[
            const SizedBox(height: 4),
            Text(
              conversation.description!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall,
            ),
          ],
          if (conversation.projectId != null ||
              conversation.materialRequestId != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: AppSpacing.minTapTarget,
              child: OutlinedButton.icon(
                onPressed: () => _openConversationRecord(context, conversation),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(YorksV1TeamChatStrings.openRecord.active(language)),
              ),
            ),
          ],
          if (canManageGroup) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: AppSpacing.minTapTarget,
              child: OutlinedButton.icon(
                onPressed: () =>
                    _showManageGroup(context, ref, thread, language),
                icon: const Icon(Icons.manage_accounts_outlined),
                label: Text(
                  YorksV1TeamChatStrings.manageGroup.active(language),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _InfoHeading(
            icon: Icons.attach_file_rounded,
            title: YorksV1TeamChatStrings.sharedFiles.active(language),
            count: files.length,
          ),
          const SizedBox(height: 6),
          if (files.isEmpty)
            Text(
              YorksV1TeamChatStrings.noSharedFiles.active(language),
              style: AppTypography.bodySmall,
            )
          else
            for (final file in files)
              _AttachmentTile(
                attachment: file,
                dark: false,
                language: language,
              ),
          const Divider(height: 24),
          _InfoHeading(
            icon: Icons.push_pin_outlined,
            title: YorksV1TeamChatStrings.pinnedMessages.active(language),
            count: pinned.length,
          ),
          const SizedBox(height: 6),
          if (pinned.isEmpty)
            Text(
              YorksV1TeamChatStrings.noPinnedMessages.active(language),
              style: AppTypography.bodySmall,
            )
          else
            for (final message in pinned)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  key: ValueKey('chat-pinned-message-${message.id}'),
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onSelectPinnedMessage(message.id),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      message.body ??
                          message.attachments.firstOrNull?.fileName ??
                          '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall,
                    ),
                  ),
                ),
              ),
          const Divider(height: 24),
          _InfoHeading(
            icon: Icons.people_outline_rounded,
            title: YorksV1TeamChatStrings.participants.active(language),
            count: thread.participants.length,
          ),
          const SizedBox(height: 6),
          for (final participant in thread.participants)
            ListTile(
              dense: true,
              minTileHeight: AppSpacing.minTapTarget,
              contentPadding: EdgeInsets.zero,
              leading: _PersonAvatar(name: participant.displayName, size: 34),
              title: Text(
                participant.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(_roleLabel(participant.exactRole, language)),
              trailing: participant.isOwner
                  ? Text(
                      YorksV1TeamChatStrings.owner.active(language),
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.blue,
                      ),
                    )
                  : null,
            ),
          const Divider(height: 24),
          _InfoAction(
            icon: Icons.mark_email_unread_outlined,
            label: YorksV1TeamChatStrings.markUnread.active(language),
            onTap: () => ref
                .read(yorksV1TeamChatProvider.notifier)
                .markUnread(conversation.id),
          ),
          _InfoAction(
            icon: conversation.isPinned
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined,
            label:
                (conversation.isPinned
                        ? YorksV1TeamChatStrings.unpinConversation
                        : YorksV1TeamChatStrings.pinConversation)
                    .active(language),
            onTap: () => ref
                .read(yorksV1TeamChatProvider.notifier)
                .setPreference(
                  conversationId: conversation.id,
                  preference: 'pinned',
                  enabled: !conversation.isPinned,
                ),
          ),
          _InfoAction(
            icon: conversation.isMuted
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            label:
                (conversation.isMuted
                        ? YorksV1TeamChatStrings.unmute
                        : YorksV1TeamChatStrings.mute)
                    .active(language),
            onTap: () => ref
                .read(yorksV1TeamChatProvider.notifier)
                .setPreference(
                  conversationId: conversation.id,
                  preference: 'muted',
                  enabled: !conversation.isMuted,
                ),
          ),
          _InfoAction(
            icon: conversation.isArchived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined,
            label:
                (conversation.isArchived
                        ? YorksV1TeamChatStrings.restore
                        : YorksV1TeamChatStrings.archive)
                    .active(language),
            onTap: () => ref
                .read(yorksV1TeamChatProvider.notifier)
                .setPreference(
                  conversationId: conversation.id,
                  preference: 'archived',
                  enabled: !conversation.isArchived,
                ),
          ),
        ],
      ),
    );
  }
}

class _CreateConversationSheet extends ConsumerStatefulWidget {
  const _CreateConversationSheet({required this.language});
  final AppLanguage language;

  @override
  ConsumerState<_CreateConversationSheet> createState() =>
      _CreateConversationSheetState();
}

class _CreateConversationSheetState
    extends ConsumerState<_CreateConversationSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _selected = <String>{};
  YorksV1ChatContextTarget? _selectedTarget;
  YorksV1ChatKind? _kind;
  bool _creating = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(yorksV1TeamChatProvider);
    final role = ref.watch(yorksV1CurrentRoleProvider);
    final currentId = ref.watch(yorksV1AuthUserIdProvider);
    final canCreateGroup =
        role == YorksV1Role.admin ||
        role == YorksV1Role.projectManager ||
        role == YorksV1Role.seniorMechanicalEngineer ||
        role == YorksV1Role.workshopInCharge ||
        role == YorksV1Role.documentController;
    final directory = state.directory
        .where((person) => person.authUserId != currentId)
        .toList(growable: false);
    final allowedKinds = <YorksV1ChatKind>[
      YorksV1ChatKind.project,
      YorksV1ChatKind.materialRequest,
      YorksV1ChatKind.direct,
      if (canCreateGroup) YorksV1ChatKind.group,
      if (role == YorksV1Role.admin) YorksV1ChatKind.announcement,
    ];
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
          maxWidth: 560,
        ),
        margin: EdgeInsets.only(
          left: 10,
          right: 10,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 10,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      YorksV1TeamChatStrings.newConversation.active(
                        widget.language,
                      ),
                      style: AppTypography.titleMedium,
                    ),
                  ),
                  _ChatIconButton(
                    tooltip: YorksV1TeamChatStrings.close.active(
                      widget.language,
                    ),
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    YorksV1TeamChatStrings.chooseType.active(widget.language),
                    style: AppTypography.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in allowedKinds)
                        ChoiceChip(
                          selected: _kind == kind,
                          onSelected: (_) async {
                            setState(() {
                              _kind = kind;
                              _selected.clear();
                              _selectedTarget = null;
                            });
                            if (kind == YorksV1ChatKind.project ||
                                kind == YorksV1ChatKind.materialRequest) {
                              await ref
                                  .read(yorksV1TeamChatProvider.notifier)
                                  .loadContextTargets(kind);
                            }
                          },
                          avatar: Icon(_kindIcon(kind), size: 18),
                          label: Text(_kindLabel(kind, widget.language)),
                        ),
                    ],
                  ),
                  if (_kind == YorksV1ChatKind.group ||
                      _kind == YorksV1ChatKind.announcement) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      maxLength: 120,
                      decoration: InputDecoration(
                        labelText: YorksV1TeamChatStrings.groupName.active(
                          widget.language,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionController,
                      maxLength: 500,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: YorksV1TeamChatStrings.descriptionOptional
                            .active(widget.language),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (_kind == YorksV1ChatKind.project ||
                      _kind == YorksV1ChatKind.materialRequest) ...[
                    const SizedBox(height: 16),
                    Text(
                      (_kind == YorksV1ChatKind.project
                              ? YorksV1TeamChatStrings.chooseProject
                              : YorksV1TeamChatStrings.chooseRequest)
                          .active(widget.language),
                      style: AppTypography.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (_kind == YorksV1ChatKind.project
                              ? YorksV1TeamChatStrings.projectParticipantsHelper
                              : YorksV1TeamChatStrings
                                    .requestParticipantsHelper)
                          .active(widget.language),
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    if (state.loadingContextTargets)
                      const Center(child: CircularProgressIndicator())
                    else
                      for (final target in state.contextTargets)
                        Semantics(
                          selected: _selectedTarget?.id == target.id,
                          button: true,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () =>
                                setState(() => _selectedTarget = target),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    _kindIcon(target.kind),
                                    color: AppColors.blue,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(target.title),
                                        Text(
                                          target.subtitle,
                                          style: AppTypography.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    _selectedTarget?.id == target.id
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: AppColors.blue,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                  ],
                  if (_kind == YorksV1ChatKind.direct ||
                      _kind == YorksV1ChatKind.group) ...[
                    const SizedBox(height: 12),
                    Text(
                      (_kind == YorksV1ChatKind.direct
                              ? YorksV1TeamChatStrings.choosePerson
                              : YorksV1TeamChatStrings.chooseParticipants)
                          .active(widget.language),
                      style: AppTypography.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    if (state.loadingDirectory)
                      const Center(child: CircularProgressIndicator())
                    else
                      for (final person in directory)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.trailing,
                          value: _selected.contains(person.authUserId),
                          secondary: _PersonAvatar(
                            name: person.displayName,
                            size: 36,
                          ),
                          title: Text(person.displayName),
                          subtitle: Text(
                            _roleLabel(person.exactRole, widget.language),
                          ),
                          onChanged: (value) => setState(() {
                            if (_kind == YorksV1ChatKind.direct) {
                              _selected.clear();
                            }
                            if (value == true) {
                              _selected.add(person.authUserId);
                            } else {
                              _selected.remove(person.authUserId);
                            }
                          }),
                        ),
                  ],
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: AppColors.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            YorksV1TeamChatStrings.accessInheritance.active(
                              widget.language,
                            ),
                            style: AppTypography.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _creating ? null : () => Navigator.pop(context),
                    child: Text(
                      YorksV1TeamChatStrings.cancel.active(widget.language),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _canCreate ? _create : null,
                    icon: _creating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_comment_outlined, size: 18),
                    label: Text(
                      YorksV1TeamChatStrings.create.active(widget.language),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canCreate {
    if (_creating || _kind == null) return false;
    if (_kind == YorksV1ChatKind.direct) return _selected.length == 1;
    if (_kind == YorksV1ChatKind.project ||
        _kind == YorksV1ChatKind.materialRequest) {
      return _selectedTarget != null;
    }
    if (_kind == YorksV1ChatKind.group) {
      return _selected.isNotEmpty && _titleController.text.trim().length >= 2;
    }
    if (_kind == YorksV1ChatKind.announcement) {
      return _titleController.text.trim().length >= 2;
    }
    return false;
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    final conversation = await ref
        .read(yorksV1TeamChatProvider.notifier)
        .createConversation(
          YorksV1ChatCreateInput(
            kind: _kind!,
            idempotencyKey: const Uuid().v4(),
            title: _titleController.text,
            description: _descriptionController.text,
            participantAuthUserIds: _selected.toList(),
            projectId: _kind == YorksV1ChatKind.project
                ? _selectedTarget?.id
                : null,
            materialRequestId: _kind == YorksV1ChatKind.materialRequest
                ? _selectedTarget?.id
                : null,
          ),
        );
    if (!mounted) return;
    setState(() => _creating = false);
    if (conversation != null) Navigator.pop(context, conversation);
  }
}

class _ManageGroupSheet extends ConsumerStatefulWidget {
  const _ManageGroupSheet({required this.thread, required this.language});

  final YorksV1ChatThread thread;
  final AppLanguage language;

  @override
  ConsumerState<_ManageGroupSheet> createState() => _ManageGroupSheetState();
}

class _ManageGroupSheetState extends ConsumerState<_ManageGroupSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final Set<String> _selected;
  late final Set<String> _owners;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.thread.conversation.title,
    );
    _descriptionController = TextEditingController(
      text: widget.thread.conversation.description,
    );
    _selected = widget.thread.participants
        .map((participant) => participant.authUserId)
        .toSet();
    _owners = widget.thread.participants
        .where((participant) => participant.isOwner)
        .map((participant) => participant.authUserId)
        .toSet();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(yorksV1TeamChatProvider);
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
          maxWidth: 560,
        ),
        margin: EdgeInsets.only(
          left: 10,
          right: 10,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 10,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      YorksV1TeamChatStrings.manageGroup.active(
                        widget.language,
                      ),
                      style: AppTypography.titleMedium,
                    ),
                  ),
                  _ChatIconButton(
                    tooltip: YorksV1TeamChatStrings.close.active(
                      widget.language,
                    ),
                    icon: Icons.close_rounded,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _titleController,
                    maxLength: 120,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: YorksV1TeamChatStrings.groupName.active(
                        widget.language,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    maxLength: 500,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: YorksV1TeamChatStrings.descriptionOptional
                          .active(widget.language),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    YorksV1TeamChatStrings.chooseParticipants.active(
                      widget.language,
                    ),
                    style: AppTypography.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  for (final person in state.directory)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.trailing,
                      value: _selected.contains(person.authUserId),
                      secondary: _PersonAvatar(
                        name: person.displayName,
                        size: 36,
                      ),
                      title: Text(person.displayName),
                      subtitle: Text(
                        _roleLabel(person.exactRole, widget.language),
                      ),
                      onChanged: _owners.contains(person.authUserId)
                          ? null
                          : (selected) => setState(() {
                              if (selected == true) {
                                _selected.add(person.authUserId);
                              } else {
                                _selected.remove(person.authUserId);
                              }
                            }),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: Text(
                      YorksV1TeamChatStrings.cancel.active(widget.language),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed:
                        _saving ||
                            _selected.length < 2 ||
                            _titleController.text.trim().length < 2
                        ? null
                        : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(
                      YorksV1TeamChatStrings.saveChanges.active(
                        widget.language,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final saved = await ref
        .read(yorksV1TeamChatProvider.notifier)
        .updateGroup(
          YorksV1ChatGroupUpdateInput(
            conversationId: widget.thread.conversation.id,
            idempotencyKey: const Uuid().v4(),
            title: _titleController.text,
            description: _descriptionController.text,
            participantAuthUserIds: _selected.toList(growable: false),
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved) Navigator.pop(context);
  }
}

class _ConversationEmptyState extends StatelessWidget {
  const _ConversationEmptyState({
    required this.language,
    required this.onCreate,
  });
  final AppLanguage language;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.blueContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.forum_outlined,
                size: 30,
                color: AppColors.blue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              YorksV1TeamChatStrings.selectConversation.active(language),
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              YorksV1TeamChatStrings.selectConversationBody.active(language),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                YorksV1TeamChatStrings.newConversation.active(language),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChatLoadFailure extends StatelessWidget {
  const _ChatLoadFailure({required this.language, required this.onRetry});
  final AppLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: _SmallEmptyState(
      icon: Icons.cloud_off_outlined,
      title: YorksV1TeamChatStrings.couldNotLoad.active(language),
      body: YorksV1TeamChatStrings.retry.active(language),
      action: FilledButton(
        onPressed: onRetry,
        child: Text(YorksV1TeamChatStrings.retry.active(language)),
      ),
    ),
  );
}

class _SmallEmptyState extends StatelessWidget {
  const _SmallEmptyState({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.mutedLight, size: 38),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            body,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall,
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({required this.conversation, required this.size});
  final YorksV1ChatConversation conversation;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _kindColor(conversation.kind).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(
        conversation.kind == YorksV1ChatKind.direct ? size : 12,
      ),
    ),
    alignment: Alignment.center,
    child: conversation.kind == YorksV1ChatKind.direct
        ? Text(
            _initials(conversation.title),
            style: AppTypography.labelLarge.copyWith(
              color: _kindColor(conversation.kind),
            ),
          )
        : Icon(
            _kindIcon(conversation.kind),
            size: size * .46,
            color: _kindColor(conversation.kind),
          ),
  );
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: AppColors.blueContainer,
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      _initials(name),
      style: AppTypography.labelLarge.copyWith(color: AppColors.navy),
    ),
  );
}

class _AttachmentTile extends ConsumerWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.dark,
    required this.language,
  });
  final YorksV1ChatAttachment attachment;
  final bool dark;
  final AppLanguage language;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = attachment.isImage && attachment.byteSize <= 2 * 1024 * 1024
        ? ref.watch(yorksV1ChatAttachmentBytesProvider(attachment.id))
        : null;
    final previewFile = preview?.valueOrNull;
    return Material(
      color: dark
          ? Colors.white.withValues(alpha: .11)
          : AppColors.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _open(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (previewFile != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.memory(
                      previewFile.bytes,
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Icon(
                    attachment.isImage
                        ? Icons.image_outlined
                        : Icons.insert_drive_file_outlined,
                    size: 18,
                    color: dark ? Colors.white : AppColors.blue,
                  ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    attachment.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: dark ? Colors.white : AppColors.inkSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _fileSize(attachment.byteSize),
                  style: AppTypography.labelSmall.copyWith(
                    color: dark ? Colors.white70 : AppColors.muted,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.download_rounded,
                  size: 17,
                  color: dark ? Colors.white70 : AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    if (!attachment.isImage) {
      await _download(context, ref);
      return;
    }
    try {
      final file = await ref
          .read(yorksV1TeamChatProvider.notifier)
          .downloadAttachment(attachment.id);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
          backgroundColor: AppColors.navy,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: .5,
                    maxScale: 5,
                    child: Center(child: Image.memory(file.bytes)),
                  ),
                ),
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  end: 8,
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        tooltip: YorksV1TeamChatStrings.close.active(language),
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const Spacer(),
                      IconButton.filledTonal(
                        tooltip: YorksV1TeamChatStrings.attachFiles.active(
                          language,
                        ),
                        onPressed: () async {
                          await ref
                              .read(yorksV1ChatFileServiceProvider)
                              .saveFile(
                                bytes: file.bytes,
                                fileName: file.fileName,
                                mimeType: file.mimeType,
                              );
                        },
                        icon: const Icon(Icons.download_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (_) {
      if (context.mounted) _showAttachmentError(context);
    }
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    try {
      final file = await ref
          .read(yorksV1TeamChatProvider.notifier)
          .downloadAttachment(attachment.id);
      final saved = await ref
          .read(yorksV1ChatFileServiceProvider)
          .saveFile(
            bytes: file.bytes,
            fileName: file.fileName,
            mimeType: file.mimeType,
          );
      if (!context.mounted || !saved) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(YorksV1TeamChatStrings.fileSaved.active(language)),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (context.mounted) _showAttachmentError(context);
    }
  }

  void _showAttachmentError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(YorksV1TeamChatStrings.attachmentFailed.active(language)),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _LinkedRecordChip extends StatelessWidget {
  const _LinkedRecordChip({
    required this.message,
    required this.dark,
    required this.language,
  });
  final YorksV1ChatMessage message;
  final bool dark;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(
      Icons.link_rounded,
      size: 16,
      color: dark ? Colors.white : AppColors.blue,
    ),
    backgroundColor: dark
        ? Colors.white.withValues(alpha: .12)
        : AppColors.blueContainer,
    side: BorderSide.none,
    label: Text(
      YorksV1TeamChatStrings.linkedRecord.active(language),
      style: AppTypography.labelSmall.copyWith(
        color: dark ? Colors.white : AppColors.navy,
      ),
    ),
    onPressed: () {
      final id = message.linkedEntityId;
      if (id == null) return;
      if (message.linkedEntityType == 'material_request') {
        context.go(RoutePaths.yorksV1MaterialRequestPath(id));
      } else if (message.linkedEntityType == 'project') {
        context.go(RoutePaths.yorksV1ProjectPath(id));
      }
    },
  );
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({
    required this.preview,
    required this.dark,
    required this.language,
  });
  final YorksV1ChatReplyPreview preview;
  final bool dark;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      color: dark
          ? Colors.white.withValues(alpha: .1)
          : AppColors.blueContainer,
      borderRadius: BorderRadius.circular(7),
      border: Border(
        left: BorderSide(
          color: dark ? Colors.white70 : AppColors.blue,
          width: 3,
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          preview.senderDisplayName,
          style: AppTypography.labelSmall.copyWith(
            color: dark ? Colors.white : AppColors.blue,
          ),
        ),
        if (preview.isDeleted)
          Text(
            YorksV1TeamChatStrings.messageDeleted.active(language),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: dark ? Colors.white70 : AppColors.muted,
              fontStyle: FontStyle.italic,
            ),
          )
        else if (preview.body != null)
          Text(
            preview.body!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: dark ? Colors.white70 : AppColors.inkSecondary,
            ),
          ),
      ],
    ),
  );
}

class _ChatMentionSuggestions extends StatelessWidget {
  const _ChatMentionSuggestions({
    required this.people,
    required this.language,
    required this.onSelected,
  });

  final List<YorksV1ChatParticipant> people;
  final AppLanguage language;
  final ValueChanged<YorksV1ChatParticipant> onSelected;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxHeight: 184),
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: AppColors.surfaceContainerLowest,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(
          color: AppColors.shadow,
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: people.length,
      itemBuilder: (context, index) {
        final person = people[index];
        return ListTile(
          minTileHeight: AppSpacing.minTapTarget,
          leading: _PersonAvatar(name: person.displayName, size: 32),
          title: Text(person.displayName),
          subtitle: Text(_roleLabel(person.exactRole, language)),
          onTap: () => onSelected(person),
        );
      },
    ),
  );
}

class _ComposerContextStrip extends StatelessWidget {
  const _ComposerContextStrip({
    required this.icon,
    required this.title,
    required this.body,
    required this.onClose,
    this.showClose = true,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onClose;
  final bool showClose;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.fromLTRB(9, 5, 4, 5),
    decoration: BoxDecoration(
      color: AppColors.blueContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Icon(icon, size: 17, color: AppColors.blue),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            body.isEmpty ? title : '$title · $body',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(color: AppColors.navy),
          ),
        ),
        if (showClose)
          IconButton(
            constraints: const BoxConstraints(
              minWidth: AppSpacing.minTapTarget,
              minHeight: AppSpacing.minTapTarget,
            ),
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 17),
          ),
      ],
    ),
  );
}

class _ChatIconButton extends StatelessWidget {
  const _ChatIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    constraints: const BoxConstraints(
      minWidth: AppSpacing.minTapTarget,
      minHeight: AppSpacing.minTapTarget,
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.blue,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppTypography.labelSmall.copyWith(color: Colors.white),
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date, required this.language});
  final DateTime date;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            _chatDateLabel(date, language),
            style: AppTypography.labelSmall,
          ),
        ),
        const Expanded(child: Divider()),
      ],
    ),
  );
}

class _InfoHeading extends StatelessWidget {
  const _InfoHeading({
    required this.icon,
    required this.title,
    required this.count,
  });
  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: AppColors.blue),
      const SizedBox(width: 7),
      Expanded(child: Text(title, style: AppTypography.labelLarge)),
      _CountBadge(count: count),
    ],
  );
}

class _InfoAction extends StatelessWidget {
  const _InfoAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: AppSpacing.minTapTarget,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 20, color: AppColors.inkSecondary),
    title: Text(label, style: AppTypography.bodyMedium),
    onTap: onTap,
  );
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 9), Text(label)],
  );
}

void _openConversationRecord(
  BuildContext context,
  YorksV1ChatConversation conversation,
) {
  final requestId = conversation.materialRequestId;
  if (requestId != null) {
    context.go(RoutePaths.yorksV1MaterialRequestPath(requestId));
    return;
  }
  final projectId = conversation.projectId;
  if (projectId != null) {
    context.go(RoutePaths.yorksV1ProjectPath(projectId));
  }
}

Future<void> _showManageGroup(
  BuildContext context,
  WidgetRef ref,
  YorksV1ChatThread thread,
  AppLanguage language,
) async {
  await ref.read(yorksV1TeamChatProvider.notifier).loadDirectory();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _ManageGroupSheet(thread: thread, language: language),
  );
}

String _filterLabel(
  YorksV1ChatFilter filter,
  AppLanguage language,
) => switch (filter) {
  YorksV1ChatFilter.all => YorksV1TeamChatStrings.all.active(language),
  YorksV1ChatFilter.unread => YorksV1TeamChatStrings.unread.active(language),
  YorksV1ChatFilter.projects => YorksV1TeamChatStrings.projects.active(
    language,
  ),
  YorksV1ChatFilter.requests => YorksV1TeamChatStrings.requests.active(
    language,
  ),
  YorksV1ChatFilter.direct => YorksV1TeamChatStrings.direct.active(language),
  YorksV1ChatFilter.groups => YorksV1TeamChatStrings.groups.active(language),
  YorksV1ChatFilter.announcements =>
    YorksV1TeamChatStrings.announcements.active(language),
  YorksV1ChatFilter.archived => YorksV1TeamChatStrings.archived.active(
    language,
  ),
};

String _kindLabel(YorksV1ChatKind kind, AppLanguage language) => switch (kind) {
  YorksV1ChatKind.project => YorksV1TeamChatStrings.projectChannel.active(
    language,
  ),
  YorksV1ChatKind.materialRequest =>
    YorksV1TeamChatStrings.requestThread.active(language),
  YorksV1ChatKind.direct => YorksV1TeamChatStrings.directMessage.active(
    language,
  ),
  YorksV1ChatKind.group => YorksV1TeamChatStrings.workingGroup.active(language),
  YorksV1ChatKind.announcement =>
    YorksV1TeamChatStrings.operationalAnnouncement.active(language),
};

IconData _kindIcon(YorksV1ChatKind kind) => switch (kind) {
  YorksV1ChatKind.project => Icons.account_tree_outlined,
  YorksV1ChatKind.materialRequest => Icons.assignment_outlined,
  YorksV1ChatKind.direct => Icons.person_outline_rounded,
  YorksV1ChatKind.group => Icons.groups_outlined,
  YorksV1ChatKind.announcement => Icons.campaign_outlined,
};

Color _kindColor(YorksV1ChatKind kind) => switch (kind) {
  YorksV1ChatKind.project => AppColors.blue,
  YorksV1ChatKind.materialRequest => AppColors.warning,
  YorksV1ChatKind.direct => AppColors.success,
  YorksV1ChatKind.group => AppColors.purple,
  YorksV1ChatKind.announcement => AppColors.error,
};

String _conversationSubtitle(
  YorksV1ChatConversation conversation,
  int participants,
  AppLanguage language,
) => '${_kindLabel(conversation.kind, language)} · $participants';

String _roleLabel(YorksV1Role role, AppLanguage language) => switch (role) {
  YorksV1Role.projectEngineer => AppStrings.projectEngineerRole.active(
    language,
  ),
  YorksV1Role.siteEngineer => AppStrings.siteEngineerRole.active(language),
  YorksV1Role.seniorMechanicalEngineer =>
    AppStrings.seniorMechanicalEngineerRole.active(language),
  YorksV1Role.projectManager => AppStrings.projectManagerRole.active(language),
  YorksV1Role.workshopInCharge => AppStrings.workshopInChargeRole.active(
    language,
  ),
  YorksV1Role.documentController => AppStrings.documentControllerRole.active(
    language,
  ),
  YorksV1Role.accountant => AppStrings.accountantRole.active(language),
  YorksV1Role.pr => AppStrings.prRole.active(language),
  YorksV1Role.procurement => AppStrings.procurementRole.active(language),
  YorksV1Role.admin => AppStrings.adminRole.active(language),
};

String _compactTime(DateTime date) {
  final now = DateTime.now();
  return _sameDay(now, date)
      ? DateFormat.jm().format(date)
      : DateFormat.MMMd().format(date);
}

String _chatDateLabel(DateTime date, AppLanguage language) {
  final now = DateTime.now();
  if (_sameDay(now, date)) {
    return YorksV1TeamChatStrings.today.active(language);
  }
  final yesterday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 1));
  if (_sameDay(yesterday, date)) {
    return YorksV1TeamChatStrings.yesterday.active(language);
  }
  return DateFormat.yMMMd().format(date);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  final initials = words.take(2).map((word) => word.characters.first).join();
  return initials.isEmpty ? 'Y' : initials.toUpperCase();
}

String _fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _messagePreview(YorksV1ChatMessage message, AppLanguage language) {
  if (message.isSystem) {
    return YorksV1TeamChatStrings.systemEvent(
      message.systemEventCode,
    ).active(language);
  }
  if (message.isDeleted) {
    return YorksV1TeamChatStrings.messageDeleted.active(language);
  }
  if (message.body != null) return message.body!;
  if (message.attachments.isNotEmpty) return message.attachments.first.fileName;
  return YorksV1TeamChatStrings.linkedRecord.active(language);
}
