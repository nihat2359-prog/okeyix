/// Presentation only; never advances a turn or writes a server deadline.
class GameTurnClock {
  int seat = 0;
  int? round;
  String status = 'waiting';
  DateTime? startedAt;
  DateTime? _serverStartedAt;

  bool apply({
    required int nextSeat,
    required String nextStatus,
    required DateTime? serverStartedAt,
    int? nextRound,
    required DateTime fallbackNow,
  }) {
    if (nextRound != null && round != null && nextRound < round!) return false;
    final sameRound = nextRound == null || round == null || nextRound == round;
    if (sameRound &&
        serverStartedAt != null &&
        _serverStartedAt != null &&
        serverStartedAt.isBefore(_serverStartedAt!)) {
      return false;
    }

    final newTurn = nextSeat != seat || !sameRound;
    seat = nextSeat;
    status = nextStatus;
    if (nextRound != null) round = nextRound;
    if (serverStartedAt != null) {
      _serverStartedAt = serverStartedAt;
      startedAt = serverStartedAt;
    } else if (newTurn || startedAt == null) {
      startedAt = fallbackNow;
    }
    return true;
  }
}
