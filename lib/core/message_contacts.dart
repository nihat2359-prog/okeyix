/// A separate conversation list: incoming senders need not still be friends.
List<Map<String, dynamic>> messageContacts(
  List<Map<String, dynamic>> friends,
  Map<String, int> unread, {
  Iterable<Map<String, dynamic>> senders = const [],
}) {
  final contacts = <String, Map<String, dynamic>>{};
  for (final contact in [...senders, ...friends]) {
    final id = contact['id']?.toString();
    if (id != null && id.isNotEmpty) contacts[id] = contact;
  }
  for (final id in unread.keys) {
    if ((unread[id] ?? 0) > 0) {
      contacts.putIfAbsent(id, () => {'id': id, 'username': 'Oyuncu'});
    }
  }
  final result = contacts.values.toList();
  result.sort((a, b) {
    final aId = a['id'].toString(), bId = b['id'].toString();
    final count = (unread[bId] ?? 0).compareTo(unread[aId] ?? 0);
    if (count != 0) return count;
    final name = (a['username']?.toString() ?? '').toLowerCase().compareTo(
      (b['username']?.toString() ?? '').toLowerCase(),
    );
    return name != 0 ? name : aId.compareTo(bId);
  });
  return result;
}

String? initialMessageContact(
  List<Map<String, dynamic>> contacts,
  Map<String, int> unread, {
  String? requested,
  String? active,
}) {
  bool contains(String? id) =>
      id != null && contacts.any((c) => c['id']?.toString() == id);
  if (contains(requested)) return requested;
  for (final contact in contacts) {
    final id = contact['id'].toString();
    if ((unread[id] ?? 0) > 0) return id;
  }
  if (contains(active)) return active;
  return contacts.firstOrNull?['id']?.toString();
}
