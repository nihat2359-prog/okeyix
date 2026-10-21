import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/core/message_contacts.dart';

void main() {
  final friends = <Map<String, dynamic>>[
    {'id': 'a', 'username': 'Ali'},
    {'id': 'z', 'username': 'Zeynep'},
  ];
  test('unread sender comes first without changing friends order', () {
    final contacts = messageContacts(friends, {'z': 1});
    expect(contacts.first['id'], 'z');
    expect(friends.first['id'], 'a');
    expect(initialMessageContact(contacts, {'z': 1}, active: 'a'), 'z');
    expect(initialMessageContact(contacts, {'z': 1}, requested: 'a'), 'a');
  });
  test('incoming sender outside friends is visible with real identity', () {
    final contacts = messageContacts(
      friends,
      {'other': 2},
      senders: [
        {'id': 'other', 'username': 'Deniz', 'avatar_url': 'avatar'},
      ],
    );
    expect(contacts.first['username'], 'Deniz');
    expect(contacts.first['avatar_url'], 'avatar');
    expect(initialMessageContact(contacts, {'other': 2}), 'other');
  });
  test(
    'unavailable identity still exposes conversation; zero unread is ignored',
    () {
      final contacts = messageContacts(friends, {'unknown': 1, 'read': 0});
      expect(contacts.first['id'], 'unknown');
      expect(contacts.any((c) => c['id'] == 'read'), false);
      expect(
        initialMessageContact(messageContacts(friends, {}), {}, active: 'z'),
        'z',
      );
      expect(initialMessageContact([], {}), isNull);
    },
  );
}
