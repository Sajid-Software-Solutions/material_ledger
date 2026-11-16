import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/app/push_bridge.dart';
import 'package:material_ledger/core/theme/app_theme.dart';
import 'package:material_ledger/features/chat/presentation/screens/yorks_v1_team_chat_screen.dart';
import 'package:material_ledger/shared/models/yorks_v1_role.dart';
import 'package:material_ledger/shared/models/yorks_v1_team_chat.dart';
import 'package:material_ledger/shared/providers/language_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_identity_provider.dart';
import 'package:material_ledger/shared/providers/yorks_v1_team_chat_provider.dart';
import 'package:material_ledger/shared/repositories/yorks_v1_team_chat_repository.dart';
import 'package:material_ledger/shared/services/push_service.dart';
import 'package:material_ledger/shared/services/yorks_v1_chat_file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  test('chat projection decodes protected thread data and nested messages', () {
    final thread = YorksV1ChatThread.fromRpcJson(_threadRpcFixture());

    expect(thread.conversation.kind, YorksV1ChatKind.group);
    expect(thread.conversation.unreadCount, 2);
    expect(thread.conversation.needsDeliveryAcknowledgement, isFalse);
    expect(thread.participants, hasLength(3));
    expect(thread.participants.first.isOwner, isTrue);
    expect(thread.messages, hasLength(4));
    expect(thread.messages.first.isSystem, isTrue);
    expect(thread.messages.last.attachments.single.fileName, 'schedule.pdf');
    expect(thread.messages.last.replyPreview?.body, 'Site handover at 3 PM.');
    expect(thread.messages[2].receiptStatus, YorksV1ChatReceiptStatus.read);
    expect(thread.messages[2].canEdit, isTrue);
  });

  test('an older backend conservatively retains delivery acknowledgements', () {
    final json = _threadRpcFixture()..remove('needs_delivery_ack');
    expect(
      YorksV1ChatConversation.fromRpcJson(json).needsDeliveryAcknowledgement,
      isTrue,
    );
  });

  test('malformed delivery metadata is not silently treated as delivered', () {
    final json = _threadRpcFixture()..['needs_delivery_ack'] = 'false';
    expect(
      () => YorksV1ChatConversation.fromRpcJson(json),
      throwsFormatException,
    );
  });

  test('chat command payloads trim text and retain server identifiers', () {
    const create = YorksV1ChatCreateInput(
      kind: YorksV1ChatKind.group,
      idempotencyKey: 'create-chat-1',
      title: '  Project Coordination  ',
      description: '  Daily site coordination  ',
      participantAuthUserIds: ['user-procurement', 'user-engineer'],
    );
    const send = YorksV1ChatSendInput(
      conversationId: 'conversation-1',
      idempotencyKey: 'send-chat-1',
      body: '  Please confirm receipt.  ',
      replyToMessageId: 'message-1',
      attachmentIds: ['attachment-1'],
      mentionedAuthUserIds: ['user-engineer'],
    );

    expect(create.toRpcPayload()['title'], 'Project Coordination');
    expect(create.toRpcPayload()['description'], 'Daily site coordination');
    expect(send.toRpcPayload()['body'], 'Please confirm receipt.');
    expect(send.toRpcPayload()['reply_to_message_id'], 'message-1');
    expect(send.toRpcPayload()['attachment_ids'], ['attachment-1']);

    const edit = YorksV1ChatEditInput(
      messageId: 'message-1',
      body: '  Updated dispatch time.  ',
      expectedVersion: 4,
      idempotencyKey: 'edit-chat-1',
    );
    const delete = YorksV1ChatDeleteInput(
      messageId: 'message-1',
      expectedVersion: 5,
      idempotencyKey: 'delete-chat-1',
    );
    expect(edit.toRpcPayload()['body'], 'Updated dispatch time.');
    expect(edit.toRpcPayload()['expected_version'], 4);
    expect(delete.toRpcPayload()['expected_version'], 5);
  });

  test(
    'attachment selection accepts the allowlist and rejects unsafe files',
    () {
      final file = YorksV1SelectedChatFile.checked(
        fileName: r'C:\handover\schedule.XLSX',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(file.fileName, 'schedule.XLSX');
      expect(
        file.mimeType,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      expect(
        () => YorksV1SelectedChatFile.checked(
          fileName: 'script.exe',
          bytes: Uint8List.fromList([1]),
        ),
        throwsA(isA<Exception>()),
      );
      expect(
        () => YorksV1SelectedChatFile.checked(
          fileName: 'empty.pdf',
          bytes: Uint8List(0),
        ),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('global unread badge excludes muted conversations', () {
    final conversations = _conversationFixtures();
    final state = YorksV1TeamChatState(
      conversations: [
        ...conversations,
        _conversation(
          id: 'muted-chat',
          kind: YorksV1ChatKind.direct,
          title: 'Muted conversation',
          description: 'Muted test fixture',
          unreadCount: 9,
          isMuted: true,
        ),
      ],
      loadingList: false,
    );

    expect(state.unreadCount, 5);
  });

  test(
    'chat refresh acknowledges only server-projected pending deliveries',
    () async {
      final repository = _RecordingTeamChatRepository([
        _conversation(
          id: 'already-delivered',
          kind: YorksV1ChatKind.direct,
          title: 'Delivered',
          description: 'No acknowledgement needed',
          unreadCount: 0,
          needsDeliveryAcknowledgement: false,
        ),
      ]);
      final controller = YorksV1TeamChatController(
        repository: repository,
        client: null,
        authUserId: 'user-admin',
        enabled: true,
      );
      addTearDown(controller.dispose);

      await controller.refreshConversations();
      expect(repository.deliveryAcknowledgements, isEmpty);

      repository.conversations = [
        _conversation(
          id: 'pending-delivery',
          kind: YorksV1ChatKind.direct,
          title: 'Pending',
          description: 'Acknowledgement required',
          unreadCount: 1,
          needsDeliveryAcknowledgement: true,
        ),
      ];
      await controller.refreshConversations();

      expect(repository.deliveryAcknowledgements, [
        ['pending-delivery'],
      ]);
    },
  );

  testWidgets('desktop renders the full three-pane Team Chat workspace', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 768));
    await _pumpChat(tester, preferences, selected: true);

    expect(find.text('Team Chat'), findsOneWidget);
    expect(find.text('Procurement Coordination'), findsWidgets);
    expect(find.text('Conversation info'), findsOneWidget);
    expect(find.text('Participants'), findsOneWidget);
    expect(find.text('PINNED'), findsOneWidget);
    expect(find.text('RECENT'), findsOneWidget);
    expect(
      find.textContaining('visible to authorized members only'),
      findsOneWidget,
    );
    expect(find.byTooltip('Attach files'), findsOneWidget);
    expect(find.byTooltip('Search this conversation'), findsOneWidget);
    expect(find.byIcon(Icons.videocam_outlined), findsNothing);
    expect(find.byIcon(Icons.phone_outlined), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('chat-pinned-message-message-3')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop details panel toggles and remembers the preference', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 768));
    await _pumpChat(tester, preferences, selected: true);

    expect(find.text('Participants'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide conversation details'));
    await tester.pumpAndSettle();

    expect(find.text('Participants'), findsNothing);
    expect(find.byTooltip('Show conversation details'), findsOneWidget);
    expect(
      preferences.getBool('yorks_v1_team_chat_details_panel_visible'),
      isFalse,
    );

    await _pumpChat(tester, preferences, selected: true);
    expect(find.text('Participants'), findsNothing);
    expect(find.byTooltip('Show conversation details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion: the details panel hides and shows without a layout error',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      // The panel docks only on a wide screen; a phone opens it as a sheet.
      await _setViewport(tester, const Size(1366, 768));
      await _pumpChat(tester, preferences, selected: true);

      await tester.tap(find.byTooltip('Hide conversation details'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 20));
      expect(
        tester
            .renderObjectList<RenderAnimatedSize>(find.byType(AnimatedSize))
            .where((size) => size.isAnimating),
        isEmpty,
        reason: 'reduced motion runs the size change in one frame',
      );
      await tester.pumpAndSettle();
      expect(find.text('Participants'), findsNothing);

      await tester.tap(find.byTooltip('Show conversation details'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.text('Participants'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('conversation search finds and reveals a recent message', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 768));
    await _pumpChat(tester, preferences, selected: true);

    await tester.tap(find.byTooltip('Search this conversation'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('chat-message-search-field')),
      'signed schedule',
    );
    await tester.pumpAndSettle();

    final result = find.byKey(
      const ValueKey('chat-message-search-result-message-3'),
    );
    expect(result, findsOneWidget);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-message-search-field')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('own message edit and soft-delete actions update the thread', (
    tester,
  ) async {
    await _setViewport(tester, const Size(1366, 768));
    await _pumpChat(tester, preferences, selected: true);

    await tester.tap(find.byKey(const ValueKey('chat-message-menu-message-2')));
    await tester.pumpAndSettle();
    expect(find.text('Edit message'), findsOneWidget);
    expect(find.text('Delete message'), findsOneWidget);

    await tester.tap(find.text('Edit message'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, 'Edit message'), findsOneWidget);
    expect(
      find.widgetWithText(
        TextField,
        '@MasaudKhan please confirm the unloading team.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Unloading team confirmed for 3 PM.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Unloading team confirmed for 3 PM.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-message-menu-message-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete message'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Delete this message for everyone? A secure audit record will be retained.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete message'));
    await tester.pumpAndSettle();
    expect(find.text('This message was deleted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer drafts stay isolated per conversation', (tester) async {
    await _setViewport(tester, const Size(1366, 768));
    await _pumpChat(tester, preferences, selected: true);

    final composer = find.widgetWithText(TextField, 'Write a message…');
    await tester.enterText(composer, 'Keep this with procurement');
    await tester.tap(find.text('YRA-313 · Project Team'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Write a message…'))
          .controller!
          .text,
      isEmpty,
    );

    await tester.tap(find.text('Procurement Coordination').first);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Write a message…'))
          .controller!
          .text,
      'Keep this with procurement',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile list remains focused and opens a full-width thread', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800));
    await _pumpChat(tester, preferences, selected: false);

    expect(find.text('Team Chat'), findsOneWidget);
    expect(find.text('Procurement Coordination'), findsOneWidget);
    expect(find.text('Conversation info'), findsNothing);
    expect(tester.takeException(), isNull);

    await _pumpChat(tester, preferences, selected: true);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(
      find.textContaining('visible to authorized members only'),
      findsOneWidget,
    );
    expect(find.byTooltip('Attach files'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile Chat exposes device-alert recovery without overflow', (
    tester,
  ) async {
    await _setViewport(tester, const Size(360, 800));
    await _pumpChat(
      tester,
      preferences,
      selected: false,
      pushStatus: const PushDeliveryStatus(
        authorization: PushAuthorizationState.denied,
      ),
    );

    expect(find.byTooltip('Enable device alerts'), findsOneWidget);
    await tester.tap(find.byTooltip('Enable device alerts'));
    await tester.pumpAndSettle();

    expect(find.text('Device alerts are blocked'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in <({String name, Size size, bool selected})>[
    (name: 'desktop 1366x768', size: const Size(1366, 768), selected: true),
    (name: 'mobile 360x800', size: const Size(360, 800), selected: false),
  ]) {
    testWidgets(
      'header unread badge is a 20px pill on ${viewport.name}, not row height',
      (tester) async {
        await _setViewport(tester, viewport.size);
        await _pumpChat(tester, preferences, selected: viewport.selected);

        final badge = find.byKey(const ValueKey('chat-total-unread-badge'));
        expect(
          find.descendant(of: badge, matching: find.text('5')),
          findsOneWidget,
        );
        final size = tester.getSize(badge);
        expect(size.height, 20);
        expect(size.width, greaterThanOrEqualTo(size.height));
        expect(
          tester.getCenter(badge).dy,
          closeTo(tester.getCenter(find.text('Team Chat')).dy, 0.5),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final evidence in <({String name, Size size, bool selected})>[
    (name: 'desktop_1366x768', size: const Size(1366, 768), selected: true),
    (name: 'tablet_900x1024', size: const Size(900, 1024), selected: true),
    (name: 'mobile_list_390x844', size: const Size(390, 844), selected: false),
    (name: 'mobile_thread_360x800', size: const Size(360, 800), selected: true),
  ]) {
    testWidgets('R38.5 Team Chat visual evidence — ${evidence.name}', (
      tester,
    ) async {
      await _setViewport(tester, evidence.size);
      await _pumpChat(tester, preferences, selected: evidence.selected);

      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(YorksV1TeamChatScreen),
        matchesGoldenFile('goldens/r38_5/team_chat_${evidence.name}.png'),
      );
    });
  }
}

Future<void> _setViewport(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpChat(
  WidgetTester tester,
  SharedPreferences preferences, {
  required bool selected,
  PushDeliveryStatus? pushStatus,
}) async {
  final state = _chatState(selected: selected);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        yorksV1AuthUserIdProvider.overrideWithValue('user-admin'),
        yorksV1CurrentRoleProvider.overrideWithValue(YorksV1Role.admin),
        yorksV1TeamChatProvider.overrideWith(
          (ref) => _FixtureTeamChatController(state),
        ),
        if (pushStatus != null)
          pushDeliveryStatusProvider.overrideWith(
            (ref) => Stream<PushDeliveryStatus>.value(pushStatus),
          ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const Scaffold(body: YorksV1TeamChatScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FixtureTeamChatController extends YorksV1TeamChatController {
  _FixtureTeamChatController(YorksV1TeamChatState fixture)
    : super(repository: null, client: null, authUserId: null, enabled: false) {
    state = fixture;
  }

  @override
  Future<void> openConversation(String conversationId) async {
    final conversation = _conversationFixtures().firstWhere(
      (item) => item.id == conversationId,
    );
    state = YorksV1TeamChatState(
      conversations: _conversationFixtures(),
      selectedConversationId: conversation.id,
      thread: YorksV1ChatThread(
        conversation: conversation,
        participants: _participants(),
        messages: conversation.id == 'conversation-group'
            ? _messages()
            : const [],
      ),
      loadingList: false,
      loadingThread: false,
      hasOlderMessages: false,
    );
  }

  @override
  Future<bool> editMessage(YorksV1ChatEditInput input) async {
    final current = state.thread!.messages.firstWhere(
      (message) => message.id == input.messageId,
    );
    _replaceFixtureMessage(
      YorksV1ChatMessage.fromRpcJson({
        ..._messageToRpc(current),
        'body': input.body.trim(),
        'version': current.version + 1,
        'edited_at': '2026-08-28T12:00:00Z',
      }),
    );
    return true;
  }

  @override
  Future<bool> deleteMessage(YorksV1ChatDeleteInput input) async {
    final current = state.thread!.messages.firstWhere(
      (message) => message.id == input.messageId,
    );
    _replaceFixtureMessage(
      YorksV1ChatMessage.fromRpcJson({
        ..._messageToRpc(current),
        'body': null,
        'version': current.version + 1,
        'edited_at': null,
        'deleted_at': '2026-08-28T12:01:00Z',
        'can_edit': false,
        'can_delete': false,
      }),
    );
    return true;
  }

  void _replaceFixtureMessage(YorksV1ChatMessage replacement) {
    final thread = state.thread!;
    state = state.copyWith(
      thread: YorksV1ChatThread(
        conversation: thread.conversation,
        participants: thread.participants,
        messages: [
          for (final message in thread.messages)
            if (message.id == replacement.id) replacement else message,
        ],
      ),
    );
  }
}

class _RecordingTeamChatRepository implements YorksV1TeamChatRepository {
  _RecordingTeamChatRepository(this.conversations);

  List<YorksV1ChatConversation> conversations;
  final List<List<String>> deliveryAcknowledgements = [];

  @override
  Future<List<YorksV1ChatConversation>> listConversations() async =>
      conversations;

  @override
  Future<void> markDelivered(Iterable<String> conversationIds) async {
    deliveryAcknowledgements.add(conversationIds.toList(growable: false));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

YorksV1TeamChatState _chatState({required bool selected}) {
  final conversations = _conversationFixtures();
  final conversation = conversations.first;
  return YorksV1TeamChatState(
    conversations: conversations,
    selectedConversationId: selected ? conversation.id : null,
    thread: selected
        ? YorksV1ChatThread(
            conversation: conversation,
            participants: _participants(),
            messages: _messages(),
          )
        : null,
    loadingList: false,
    loadingThread: false,
    hasOlderMessages: false,
  );
}

List<YorksV1ChatConversation> _conversationFixtures() => [
  _conversation(
    id: 'conversation-group',
    kind: YorksV1ChatKind.group,
    title: 'Procurement Coordination',
    description: 'Daily coordination between Engineering and Procurement',
    unreadCount: 2,
    isPinned: true,
    lastMessage: _messages().last,
  ),
  _conversation(
    id: 'conversation-project',
    kind: YorksV1ChatKind.project,
    title: 'YRA-313 · Project Team',
    description: 'Yorks Regional Administration Building',
    unreadCount: 1,
    projectId: 'project-313',
    lastMessage: _message(
      id: 'project-message',
      conversationId: 'conversation-project',
      sender: 'Sher Zaman',
      body: 'The site measurements are now attached.',
    ),
  ),
  _conversation(
    id: 'conversation-request',
    kind: YorksV1ChatKind.materialRequest,
    title: 'YRA313-MR012 · Common',
    description: 'Material Request coordination',
    unreadCount: 2,
    materialRequestId: 'request-12',
    lastMessage: _message(
      id: 'request-message',
      conversationId: 'conversation-request',
      sender: 'Masaud Khan',
      body: 'Arrangement returned with one clarification.',
    ),
  ),
  _conversation(
    id: 'conversation-direct',
    kind: YorksV1ChatKind.direct,
    title: 'Silvin Pailo',
    description: 'Procurement',
    unreadCount: 0,
    lastMessage: _message(
      id: 'direct-message',
      conversationId: 'conversation-direct',
      sender: 'Silvin Pailo',
      body: 'Delivery is planned for tomorrow morning.',
    ),
  ),
  _conversation(
    id: 'conversation-announcement',
    kind: YorksV1ChatKind.announcement,
    title: 'Company Announcements',
    description: 'Official Yorks updates',
    unreadCount: 0,
    lastMessage: _message(
      id: 'announcement-message',
      conversationId: 'conversation-announcement',
      sender: 'Owner',
      body: 'Updated holiday working hours are now available.',
    ),
  ),
];

YorksV1ChatConversation _conversation({
  required String id,
  required YorksV1ChatKind kind,
  required String title,
  required String description,
  required int unreadCount,
  YorksV1ChatMessage? lastMessage,
  String? projectId,
  String? materialRequestId,
  bool isPinned = false,
  bool isMuted = false,
  bool needsDeliveryAcknowledgement = true,
}) => YorksV1ChatConversation(
  id: id,
  kind: kind,
  title: title,
  description: description,
  projectId: projectId,
  materialRequestId: materialRequestId,
  createdAt: DateTime(2026, 8, 14, 9),
  updatedAt: DateTime(2026, 8, 14, 11, 42),
  lastMessageAt: DateTime(2026, 8, 14, 11, 42),
  isPinned: isPinned,
  isMuted: isMuted,
  isArchived: false,
  unreadCount: unreadCount,
  participantCount: kind == YorksV1ChatKind.direct ? 2 : 3,
  needsDeliveryAcknowledgement: needsDeliveryAcknowledgement,
  lastMessage: lastMessage,
);

List<YorksV1ChatParticipant> _participants() => const [
  YorksV1ChatParticipant(
    authUserId: 'user-admin',
    displayName: 'Owner',
    exactRole: YorksV1Role.admin,
    isOwner: true,
  ),
  YorksV1ChatParticipant(
    authUserId: 'user-procurement',
    displayName: 'Silvin Pailo',
    exactRole: YorksV1Role.procurement,
  ),
  YorksV1ChatParticipant(
    authUserId: 'user-engineer',
    displayName: 'Masaud Khan',
    exactRole: YorksV1Role.projectEngineer,
  ),
];

List<YorksV1ChatMessage> _messages() => [
  YorksV1ChatMessage(
    id: 'system-message',
    conversationId: 'conversation-group',
    kind: 'system',
    systemEventCode: 'conversation_created',
    body: 'Owner created this group.',
    createdAt: DateTime(2026, 8, 14, 9),
    isMine: false,
    isPinned: false,
    acknowledgementCount: 0,
    acknowledgedByMe: false,
    attachments: const [],
    mentionedAuthUserIds: const [],
  ),
  _message(
    id: 'message-1',
    conversationId: 'conversation-group',
    sender: 'Silvin Pailo',
    body: 'Site handover at 3 PM.',
  ),
  _message(
    id: 'message-2',
    conversationId: 'conversation-group',
    sender: 'Owner',
    body: '@MasaudKhan please confirm the unloading team.',
    isMine: true,
  ),
  YorksV1ChatMessage(
    id: 'message-3',
    conversationId: 'conversation-group',
    kind: 'message',
    senderAuthUserId: 'user-engineer',
    senderDisplayName: 'Masaud Khan',
    senderExactRole: YorksV1Role.projectEngineer,
    body: 'Confirmed. The signed schedule is attached.',
    replyToMessageId: 'message-1',
    replyPreview: const YorksV1ChatReplyPreview(
      id: 'message-1',
      senderDisplayName: 'Silvin Pailo',
      body: 'Site handover at 3 PM.',
    ),
    createdAt: DateTime(2026, 8, 14, 11, 42),
    isMine: false,
    isPinned: true,
    acknowledgementCount: 2,
    acknowledgedByMe: true,
    attachments: const [
      YorksV1ChatAttachment(
        id: 'attachment-1',
        fileName: 'schedule.pdf',
        mimeType: 'application/pdf',
        byteSize: 185240,
      ),
    ],
    mentionedAuthUserIds: const [],
  ),
];

YorksV1ChatMessage _message({
  required String id,
  required String conversationId,
  required String sender,
  required String body,
  bool isMine = false,
}) => YorksV1ChatMessage(
  id: id,
  conversationId: conversationId,
  kind: 'message',
  senderAuthUserId: isMine ? 'user-admin' : 'user-procurement',
  senderDisplayName: sender,
  senderExactRole: isMine ? YorksV1Role.admin : YorksV1Role.procurement,
  body: body,
  createdAt: DateTime(2026, 8, 14, 10, 30),
  isMine: isMine,
  canEdit: isMine,
  canDelete: isMine,
  isPinned: false,
  acknowledgementCount: 0,
  acknowledgedByMe: false,
  attachments: const [],
  mentionedAuthUserIds: const [],
  recipientCount: isMine ? 2 : 0,
  deliveredCount: isMine ? 2 : 0,
  readCount: isMine ? 2 : 0,
);

Map<String, dynamic> _threadRpcFixture() => {
  'id': 'conversation-group',
  'kind': 'group',
  'title': 'Procurement Coordination',
  'description': 'Daily coordination',
  'project_id': null,
  'material_request_id': null,
  'created_at': '2026-08-14T04:00:00Z',
  'updated_at': '2026-08-14T06:42:00Z',
  'last_message_at': '2026-08-14T06:42:00Z',
  'is_pinned': true,
  'is_muted': false,
  'is_archived': false,
  'unread_count': 2,
  'needs_delivery_ack': false,
  'participant_count': 3,
  'last_message': null,
  'participants': [
    {
      'auth_user_id': 'user-admin',
      'display_name': 'Owner',
      'exact_role': 'admin',
      'member_role': 'owner',
    },
    {
      'auth_user_id': 'user-procurement',
      'display_name': 'Silvin Pailo',
      'exact_role': 'procurement',
      'member_role': 'member',
    },
    {
      'auth_user_id': 'user-engineer',
      'display_name': 'Masaud Khan',
      'exact_role': 'project_engineer',
      'member_role': 'member',
    },
  ],
  'messages': [
    {
      'id': 'system-message',
      'conversation_id': 'conversation-group',
      'kind': 'system',
      'system_event_code': 'conversation_created',
      'sender_auth_user_id': null,
      'sender_display_name': null,
      'sender_exact_role': null,
      'body': 'Owner created this group.',
      'reply_to_message_id': null,
      'reply_preview': null,
      'linked_entity_type': null,
      'linked_entity_id': null,
      'created_at': '2026-08-14T04:00:00Z',
      'is_mine': false,
      'is_pinned': false,
      'acknowledgement_count': 0,
      'acknowledged_by_me': false,
      'attachments': [],
      'mentions': [],
    },
    ..._messages().skip(1).map(_messageToRpc),
  ],
};

Map<String, dynamic> _messageToRpc(YorksV1ChatMessage message) => {
  'id': message.id,
  'conversation_id': message.conversationId,
  'kind': message.kind,
  'system_event_code': message.systemEventCode,
  'sender_auth_user_id': message.senderAuthUserId,
  'sender_display_name': message.senderDisplayName,
  'sender_exact_role': message.senderExactRole?.claimValue,
  'body': message.body,
  'reply_to_message_id': message.replyToMessageId,
  'reply_preview': message.replyPreview == null
      ? null
      : {
          'id': message.replyPreview!.id,
          'sender_display_name': message.replyPreview!.senderDisplayName,
          'body': message.replyPreview!.body,
          'is_deleted': message.replyPreview!.isDeleted,
        },
  'linked_entity_type': message.linkedEntityType,
  'linked_entity_id': message.linkedEntityId,
  'created_at': message.createdAt.toUtc().toIso8601String(),
  'version': message.version,
  'edited_at': message.editedAt?.toUtc().toIso8601String(),
  'deleted_at': message.deletedAt?.toUtc().toIso8601String(),
  'is_mine': message.isMine,
  'can_edit': message.canEdit,
  'can_delete': message.canDelete,
  'is_pinned': message.isPinned,
  'acknowledgement_count': message.acknowledgementCount,
  'acknowledged_by_me': message.acknowledgedByMe,
  'recipient_count': message.recipientCount,
  'delivered_count': message.deliveredCount,
  'read_count': message.readCount,
  'attachments': message.attachments
      .map(
        (attachment) => {
          'id': attachment.id,
          'file_name': attachment.fileName,
          'mime_type': attachment.mimeType,
          'byte_size': attachment.byteSize,
        },
      )
      .toList(),
  'mentions': message.mentionedAuthUserIds,
};
