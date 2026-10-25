import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/core/table_invite_policy.dart';

void main() {
  test('Masters and Champions exclude bots while lower leagues keep invitations', () {
    expect(leagueAllowsBotPlayers('elite'), isFalse);
    expect(leagueAllowsBotPlayers('gold'), isFalse);
    expect(leagueAllowsBotPlayers(null), isFalse);
    for (final league in ['standard', 'bronze', 'silver']) {
      expect(leagueAllowsBotPlayers(league), isTrue);
    }
  });
  final now = DateTime.utc(2026, 10, 22, 12);
  Map<String, dynamic> invite(Duration age, {String status = 'pending'}) => {
    'created_at': now.subtract(age).toIso8601String(), 'status': status,
  };
  test('only current pending game invites are presented', () {
    expect(isFreshTableInvite(invite(const Duration(seconds: 30)), now), isTrue);
    expect(isFreshTableInvite(invite(const Duration(seconds: 119)), now), isTrue);
    expect(isFreshTableInvite(invite(const Duration(minutes: 2)), now), isFalse);
    expect(isFreshTableInvite(invite(const Duration(days: 2)), now), isFalse);
    expect(isFreshTableInvite(invite(Duration.zero, status: 'rejected'), now), isFalse);
    expect(isFreshTableInvite({'status': 'pending'}, now), isFalse);
    expect(isFreshTableInvite(invite(const Duration(minutes: -5)), now), isFalse);
  });
}
