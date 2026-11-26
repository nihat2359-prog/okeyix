import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/services/user_state.dart';

void main() {
  tearDown(() {
    UserState.userId = null;
    UserState.userName = 'Oyuncu';
    UserState.userAvatarUrl = null;
  });
  test('new table takes one consistent name/avatar snapshot for its owner', () {
    UserState.userId = 'owner';
    UserState.userName = 'Deniz';
    UserState.userAvatarUrl = 'kadin_komik_01';
    final identity = UserState.tableIdentityFor('owner')!;
    UserState.userName = 'Changed later';
    UserState.userAvatarUrl = 'erkek_01';
    expect(identity['id'], 'owner');
    expect(identity['username'], 'Deniz');
    expect(identity['avatar_url'], 'kadin_komik_01');
  });
  test('previous account and signed-out sessions cannot seed an owner', () {
    UserState.userId = 'previous-account';
    UserState.userName = 'Previous name';
    UserState.userAvatarUrl = 'previous-avatar';
    expect(UserState.tableIdentityFor('new-account'), isNull);
    expect(UserState.tableIdentityFor(null), isNull);
  });
  test('an owner without an avatar uses initials instead of another portrait', () {
    UserState.userId = 'owner';
    UserState.userName = 'Deniz';
    UserState.userAvatarUrl = null;
    expect(UserState.tableIdentityFor('owner')!['avatar_url'], '');
  });
}
