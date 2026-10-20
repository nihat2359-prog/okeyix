import 'package:okeyix/models/profile_statistics.dart';

class ComparedPlayer {
  const ComparedPlayer({
    required this.id,
    required this.name,
    this.avatar,
    this.league,
    required this.stats,
  });
  factory ComparedPlayer.fromJson(Map<String, dynamic> json) => ComparedPlayer(
    id: json['id'] as String,
    name: json['username'] as String,
    avatar: json['avatar_url'] as String?,
    league: json['league'] as String?,
    // This endpoint deliberately has no users.wins/losses career fields.
    stats: ProfileStatistics.fromJson({
      ...json,
      'career_wins': null,
      'career_losses': null,
      'previous_wins': null,
    }),
  );
  final String id;
  final String name;
  final String? avatar;
  final String? league;
  final ProfileStatistics stats;
}

class PlayerComparison {
  const PlayerComparison({
    required this.left,
    required this.right,
    required this.leftWins,
    required this.rightWins,
    required this.asOf,
  });
  factory PlayerComparison.fromJson(
    Map<String, dynamic> json, {
    required String viewerId,
    required String opponentId,
  }) {
    if (json['scope'] != 'head_to_head') {
      throw const FormatException('Mutual comparison endpoint required');
    }
    final left = ComparedPlayer.fromJson(
      Map<String, dynamic>.from(json['left_player'] as Map),
    );
    final right = ComparedPlayer.fromJson(
      Map<String, dynamic>.from(json['right_player'] as Map),
    );
    final a = json['left_wins'];
    final b = json['right_wins'];
    if (left.id != viewerId ||
        right.id != opponentId ||
        left.id == right.id ||
        a is! int ||
        b is! int ||
        a < 0 ||
        b < 0 ||
        a != left.stats.wins ||
        b != right.stats.wins ||
        a != right.stats.losses ||
        b != left.stats.losses) {
      throw const FormatException('Invalid comparison identity or score');
    }
    return PlayerComparison(
      left: left,
      right: right,
      leftWins: a,
      rightWins: b,
      asOf: DateTime.parse(json['as_of'] as String),
    );
  }
  final ComparedPlayer left;
  final ComparedPlayer right;
  final int leftWins;
  final int rightWins;
  final DateTime asOf;
  int get meetings => leftWins + rightWins;
  double get leftShare => meetings == 0 ? .5 : leftWins / meetings;
  String get resultLabel => meetings == 0
      ? 'Henüz birbirinize karşı tamamlanmış el yok'
      : leftWins == rightWins
      ? 'Rekabette eşitlik var'
      : '${leftWins > rightWins ? left.name : right.name} önde';
}
