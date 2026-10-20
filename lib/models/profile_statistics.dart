/// Recorded finishes plus career counters read in the same server snapshot.
class ProfileStatistics {
  const ProfileStatistics({
    required this.wins,
    required this.losses,
    required this.normalWins,
    required this.okeyWins,
    required this.doubleWins,
    required this.okeyDoubleWins,
    this.careerWins,
    this.careerLosses,
    this.previousWins,
    this.hasCareerSnapshot = false,
  });

  factory ProfileStatistics.fromJson(Map<String, dynamic> json) {
    int count(String key) {
      final value = json[key];
      if (value is! int || value < 0) {
        throw const FormatException('Invalid profile statistics');
      }
      return value;
    }

    int? nullableCount(String key) {
      if (!json.containsKey(key)) {
        throw const FormatException('Missing career snapshot');
      }
      return json[key] == null ? null : count(key);
    }

    final result = ProfileStatistics(
      wins: count('wins'),
      losses: count('losses'),
      normalWins: count('normal_wins'),
      okeyWins: count('okey_wins'),
      doubleWins: count('double_wins'),
      okeyDoubleWins: count('okey_double_wins'),
      careerWins: nullableCount('career_wins'),
      careerLosses: nullableCount('career_losses'),
      previousWins: nullableCount('previous_wins'),
      hasCareerSnapshot: true,
    );
    if ((result.previousWins != null &&
            (result.careerWins == null ||
                result.previousWins != result.careerWins! - result.wins)) ||
        result.okeyDoubleWins > result.okeyWins ||
        result.okeyDoubleWins > result.doubleWins ||
        result.normalWins +
                result.okeyWins +
                result.doubleWins -
                result.okeyDoubleWins !=
            result.wins) {
      throw const FormatException('Inconsistent profile statistics');
    }
    return result;
  }

  final int wins;
  final int losses;
  final int normalWins;
  final int okeyWins;
  final int doubleWins;
  final int okeyDoubleWins;
  final int? careerWins;
  final int? careerLosses;
  final int? previousWins;
  final bool hasCareerSnapshot;
  int get total => wins + losses;
  double get winRate => total == 0 ? 0 : wins * 100 / total;
}
