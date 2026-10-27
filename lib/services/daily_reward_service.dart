import 'package:supabase_flutter/supabase_flutter.dart';

class DailyRewardStatus {
  final int day, amount;
  final List<int> rewards;
  final bool available;
  final String dayKey;
  const DailyRewardStatus({
    required this.day,
    required this.amount,
    required this.rewards,
    required this.available,
    required this.dayKey,
  });
  factory DailyRewardStatus.fromJson(Map<String, dynamic> json) {
    final rewards = (json['rewards'] as List)
        .map((v) => (v as num).toInt())
        .toList();
    final day = (json['day'] as num).toInt();
    final amount = (json['amount'] as num).toInt();
    if (rewards.length != 7 ||
        day < 1 ||
        day > 7 ||
        rewards.any((v) => v <= 0) ||
        amount != rewards[day - 1]) {
      throw const FormatException('Invalid daily reward status');
    }
    return DailyRewardStatus(
      day: day,
      amount: json['available'] != true && json['credited_amount'] is num &&
          (json['credited_amount'] as num) > 0
          ? (json['credited_amount'] as num).toInt() : amount,
      rewards: rewards,
      available: json['available'] == true,
      dayKey: json['day_key'] as String,
    );
  }
}

class DailyRewardService {
  final SupabaseClient client;
  DailyRewardService(this.client);
  Future<DailyRewardStatus?> status() async {
    try {
      final result = await client
          .rpc('okeyix_daily_reward_status')
          .timeout(const Duration(seconds: 5));
      return DailyRewardStatus.fromJson(
        Map<String, dynamic>.from(result as Map),
      );
    } on PostgrestException catch (e) {
      // Only an undeployed endpoint falls back to the released daily reward.
      if (e.code == 'PGRST202' || e.code == '42883') return null;
      rethrow;
    }
  }

  Future<int> claim(DailyRewardStatus shown) async {
    final result = Map<String, dynamic>.from(
      await client.rpc('okeyix_claim_daily_reward') as Map,
    );
    if (result['credited'] != true) return 0;
    final amount = (result['amount'] as num).toInt();
    // Never show a guessed win or silently credit a client-supplied amount.
    if (amount <= 0) throw const FormatException('Invalid credited amount');
    return amount;
  }
}
