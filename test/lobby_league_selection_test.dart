import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/core/lobby_league_selection.dart';

void main() {
  // Fixtures use arbitrary thresholds, never production league constants.
  final leagues = [
    {'id': 'a', 'min_coin': 10, 'min_rating': 0},
    {'id': 'b', 'min_coin': 20, 'min_rating': 100},
    {'id': 'c', 'min_coin': 30, 'min_rating': 200},
    {'id': 'd', 'min_coin': 40, 'min_rating': 300},
    {'id': 'e', 'min_coin': 50, 'min_rating': 400},
  ];

  test('initial selection requires both balance and rating, inclusively', () {
    for (var i = 0; i < leagues.length; i++) {
      final selection = LobbyLeagueSelection()..useSession('login');
      expect(
        selection.resolve(leagues, coins: 10 * (i + 1), rating: 1000),
        leagues[i]['id'],
      );
      final ratingLimited = LobbyLeagueSelection()..useSession('login');
      expect(
        ratingLimited.resolve(leagues, coins: 1000, rating: 100 * i),
        leagues[i]['id'],
      );
    }
  });

  test('manual lower league survives refresh, growth and route recreation', () {
    final selection = LobbyLeagueSelection()..useSession('login');
    expect(selection.resolve(leagues, coins: 50, rating: 400), 'e');
    selection.selectedId = 'b';
    selection.useSession('login');
    expect(selection.resolve(leagues, coins: 1000, rating: 1000), 'b');
  });

  test('lost balance or rating falls back to highest eligible league', () {
    final selection = LobbyLeagueSelection()..useSession('login');
    selection.resolve(leagues, coins: 50, rating: 400);
    expect(selection.resolve(leagues, coins: 30, rating: 400), 'c');
    expect(selection.resolve(leagues, coins: 100, rating: 100), 'b');
  });

  test('removed selected league falls back using current server order', () {
    final selection = LobbyLeagueSelection()..useSession('login');
    selection.resolve(leagues, coins: 50, rating: 400);
    expect(
      selection.resolve(leagues.take(4).toList(), coins: 50, rating: 400),
      'd',
    );
  });

  test('new login resets selection including another login by same user', () {
    final selection = LobbyLeagueSelection()..useSession('user:login1');
    selection.resolve(leagues, coins: 20, rating: 100);
    selection.useSession('user:login2');
    expect(selection.resolve(leagues, coins: 50, rating: 400), 'e');
    selection.useSession('other:login3');
    expect(selection.resolve(leagues, coins: 30, rating: 200), 'c');
  });

  test(
    'no eligible league retains a locked selection without granting access',
    () {
      final selection = LobbyLeagueSelection()..useSession('login');
      expect(selection.resolve(leagues, coins: 0, rating: 1000), 'a');
      expect(
        canAccessLobbyLeague(leagues.first, coins: 0, rating: 1000),
        isFalse,
      );
      selection.selectedId = 'c';
      expect(selection.resolve(leagues, coins: 0, rating: 0), 'c');
      expect(canAccessLobbyLeague(leagues[2], coins: 0, rating: 0), isFalse);
    },
  );

  test('empty league data does not initialize a selection', () {
    final selection = LobbyLeagueSelection()..useSession('login');
    expect(selection.resolve([], coins: 50, rating: 400), isNull);
    expect(selection.selectedId, isNull);
    expect(selection.resolve(leagues, coins: 50, rating: 400), 'e');
  });
}
