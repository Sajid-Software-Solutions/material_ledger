import 'package:flutter_test/flutter_test.dart';
import 'package:material_ledger/shared/providers/yorks_v1_team_chat_provider.dart';

YorksV1ChatMemberChange _classify(
  Map<String, dynamic> record, {
  String? selected,
  bool deleted = false,
}) => YorksV1TeamChatController.classifyMemberChange(
  newRecord: deleted ? const {} : record,
  oldRecord: deleted ? record : const {},
  authUserId: 'me',
  selectedConversationId: selected,
);

void main() {
  test('my own membership change reloads the list', () {
    expect(
      _classify({'auth_user_id': 'me', 'conversation_id': 'c1'}),
      YorksV1ChatMemberChange.refreshAll,
    );
    expect(
      _classify({'auth_user_id': 'me', 'conversation_id': 'c1'}, deleted: true),
      YorksV1ChatMemberChange.refreshAll,
    );
  });

  test("another member's cursor only refreshes the open thread", () {
    final other = {'auth_user_id': 'them', 'conversation_id': 'c1'};
    expect(
      _classify(other, selected: 'c1'),
      YorksV1ChatMemberChange.refreshOpenThread,
    );
    // A delivery/read cursor in a conversation not on screen needs nothing;
    // reloading every member's list here made one message cost N² loads.
    expect(_classify(other, selected: 'c2'), YorksV1ChatMemberChange.ignore);
    expect(_classify(other), YorksV1ChatMemberChange.ignore);
  });

  test('an unattributable change falls back to a full reload', () {
    expect(_classify({'id': 'x'}), YorksV1ChatMemberChange.refreshAll);
  });
}
