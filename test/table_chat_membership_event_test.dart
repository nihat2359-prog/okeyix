import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/ui/table_chat_membership_event.dart';

void main() {
  test('ordinary and malformed messages are not membership events', () {
    expect(TableChatMembershipEvent.matches({'type': 'text'}), isFalse);
    expect(TableChatMembershipEvent.matches({'membership_event': 'join'}), isFalse);
    expect(TableChatMembershipEvent.matches({'membership_event': {'action': 'other'}}), isFalse);
  });
  for (final role in ['player', 'spectator']) {
    for (final action in ['join', 'leave']) {
      testWidgets('$role $action keeps identity and uses the requested color', (tester) async {
        await tester.binding.setSurfaceSize(const Size(568, 320));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final event = {'role': role, 'action': action, 'username': 'Serkan'};
        expect(TableChatMembershipEvent.matches({'membership_event': event}), isTrue);
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 240,
          child: TableChatMembershipEvent(event: event)))));
        final expected = role == 'player'
            ? (action == 'join' ? 'masaya katıldı' : 'masadan ayrıldı')
            : (action == 'join' ? 'izlemeye başladı' : 'izlemekten ayrıldı');
        final text = tester.widget<Text>(find.text('Serkan $expected'));
        expect(text.style!.color, action == 'join'
            ? const Color(0xFF83C99A) : const Color(0xFFE08C88));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
