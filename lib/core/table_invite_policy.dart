const tableInviteLifetime = Duration(minutes: 2);

bool leagueAllowsBotPlayers(String? leagueId) =>
    leagueId != null && leagueId != 'gold' && leagueId != 'elite';

bool isFreshTableInvite(Map<String, dynamic> invite, DateTime now) {
  final created = DateTime.tryParse(invite['created_at']?.toString() ?? '');
  if (created == null || invite['status'] != 'pending') return false;
  final age = now.toUtc().difference(created.toUtc());
  return age >= const Duration(seconds: -30) && age < tableInviteLifetime;
}
