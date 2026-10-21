part of '../okey_game.dart';

// Transport adapter only: the engine receives no game instance or client.
extension _StrategicBotTurn on OkeyGame {
  BotStone? _botPublicIndicator() {
    if (closedPile.isEmpty) return null;
    final t = closedPile.first;
    return BotStone(t.id, tileColorToString(t.color), t.value);
  }

  Future<List<BotPublicMove>> _loadBotPublicHistory(BotStone? indicator) async {
    try {
      final rows = await _botClient
          .from('table_discards')
          .select('id,seat_index,tile,drawn_at,drawn_by_user_id,created_at')
          .eq('table_id', tableId)
          .order('created_at')
          .order('id')
          .limit(500)
          .timeout(const Duration(seconds: 2));
      return botPublicHistory(
        (rows as List).map((r) => Map<String, dynamic>.from(r as Map)).toList(),
        {
          for (final e in _playerSeatMap.entries)
            e.value['user_id'].toString(): e.key,
        },
        indicator: indicator,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> _playStrategicBotTurn() async {
    final seat = currentTurn;
    final botUserId = _playerSeatMap[seat]?['user_id']?.toString();
    if (botUserId == null) return;
    final epoch = _handStateEpoch;
    final round = _round;
    final turnStart = _turnStartedAt;
    final token =
        '${seat}_${(turnStart ?? DateTime.now()).millisecondsSinceEpoch}';
    bool current() =>
        _lifecycleActive &&
        epoch == _handStateEpoch &&
        round == _round &&
        seat == currentTurn &&
        _botSeats.contains(seat) &&
        turnStart == _turnStartedAt;
    _actionInFlight = true;
    try {
      Future<Map<String, dynamic>?> readHand() async {
        final rows = await _botClient
            .from('table_players')
            .select('hand,is_double_mode')
            .eq('table_id', tableId)
            .eq('user_id', botUserId)
            .limit(1)
            .timeout(const Duration(seconds: 8));
        return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
      }

      Future<bool> stillOwnsTurn() async {
        if (!current()) return false;
        final tables = await _botClient
            .from('tables')
            .select('status,current_turn,turn_started_at,round_count')
            .eq('id', tableId)
            .limit(1)
            .timeout(const Duration(seconds: 6));
        if (!current() || tables.isEmpty) return false;
        final t = tables.first;
        return t['status'] == 'playing' &&
            t['current_turn'] == seat &&
            _normalizedRoundFromTable(t) == round &&
            turnStart != null &&
            _parseServerTime(
                  t['turn_started_at'],
                )?.isAtSameMomentAs(turnStart) ==
                true;
      }

      final indicator = _botPublicIndicator();
      List<BotStone> parseHand(Object? raw) => raw is List
          ? raw
                .whereType<Map>()
                .map(
                  (t) => BotStone.fromJson(
                    Map<String, dynamic>.from(t),
                    indicator: indicator,
                  ),
                )
                .toList()
          : <BotStone>[];
      var row = await readHand();
      if (!current() || row == null) return;
      var hand = parseHand(row['hand']);
      if (hand.length != 14 && hand.length != 15) {
        _botNoHandRetryAfter = DateTime.now().add(const Duration(seconds: 2));
        await _loadInitialState(forceHandSync: false);
        return;
      }
      final history = await _loadBotPublicHistory(indicator);
      if (!current()) return;
      BotObservation observe(
        List<BotStone> stones, {
        BotStone? top,
        bool? pairs,
        bool allowPairs = true,
      }) => BotObservation(
        handKey: '$tableId:$round:$epoch',
        hand: stones,
        history: history,
        ownSeat: seat,
        deckRemaining: (closedPile.length - 1).clamp(0, 106),
        indicator: indicator,
        topDiscard: top,
        pairsDeclared: pairs ?? row?['is_double_mode'] == true,
        canDeclarePairs: allowPairs && !_botPairsEndpointUnavailable,
      );
      if (hand.length == 14) {
        final fromSeat = (seat - 1 + _maxPlayers) % _maxPlayers;
        final rawTop = await _fetchDiscardTopForSeat(fromSeat);
        if (!current()) return;
        final top = rawTop == null
            ? null
            : BotStone.fromJson(rawTop, indicator: indicator);
        final drawObservation = observe(hand, top: top);
        final choice = await runBotDecision(
          drawObservation,
          worker: _botDecisionWorker,
        );
        if (!current() || !await stillOwnsTurn()) return;
        var source = choice.takeDiscard && top != null ? 'discard' : 'closed';
        try {
          final result = await _botClient
              .rpc(
                'game_draw',
                params: {
                  'p_table_id': tableId,
                  'p_user_id': botUserId,
                  'p_source': source,
                  'p_from_seat': source == 'discard' ? fromSeat : null,
                },
              )
              .timeout(const Duration(seconds: 8));
          if (result is Map && result['ok'] == false) {
            throw StateError('BOT_DRAW_REJECTED');
          }
        } catch (_) {
          if (!current()) return;
          // Re-read before recovery: a timed-out request may have committed.
          row = await readHand();
          if (!current() || row == null) return;
          hand = parseHand(row['hand']);
          if (hand.length == 14 && source == 'discard') {
            if (!await stillOwnsTurn()) return;
            source = 'closed';
            final fallbackResult = await _botClient
                .rpc(
                  'game_draw',
                  params: {
                    'p_table_id': tableId,
                    'p_user_id': botUserId,
                    'p_source': source,
                    'p_from_seat': null,
                  },
                )
                .timeout(const Duration(seconds: 8));
            if (fallbackResult is Map && fallbackResult['ok'] == false) {
              throw StateError('BOT_CLOSED_DRAW_REJECTED');
            }
          } else if (hand.length != 15) {
            rethrow;
          }
        }
        row = await readHand();
        if (!current() || row == null) return;
        hand = parseHand(row['hand']);
        await Future<void>.delayed(
          Duration(milliseconds: 780 + DateTime.now().millisecond % 420),
        );
      }
      if (!current() || hand.length != 15) return;
      _botNoHandRetryAfter = null;
      var observation = observe(hand);
      var decision = await runBotDecision(observation);
      if (!current()) return;

      Future<bool> validHand(String id) async {
        if (!await stillOwnsTurn()) return false;
        final latest = await readHand();
        return current() &&
            latest != null &&
            botCanCommit(
              expectedTurn: token,
              currentTurn:
                  '${currentTurn}_${(_turnStartedAt ?? DateTime.now()).millisecondsSinceEpoch}',
              expectedHand: hand,
              currentHand: parseHand(latest['hand']),
              discardId: id,
            );
      }

      Future<void> discardFresh([bool recompute = true]) async {
        if (recompute && !await validHand(decision.discardId)) return;
        final safe = recompute
            ? await runBotDecision(observation, discardOnly: true)
            : decision;
        if (!current() || !await validHand(safe.discardId)) return;
        final tile = hand.firstWhere((s) => s.id == safe.discardId);
        await _botClient
            .rpc(
              'game_discard_fast',
              params: {
                'p_table_id': tableId,
                'p_user_id': botUserId,
                'p_tile': tile.toPayload(),
              },
            )
            .timeout(const Duration(seconds: 8));
      }

      if (!await validHand(decision.discardId)) return;
      var finish = decision.finish;
      if (finish != null && finish.pairs && !observation.pairsDeclared) {
        var declared = false;
        try {
          final response = await _botClient
              .rpc(
                'okeyix_bot_confirm_pairs',
                params: {
                  'p_table_id': tableId,
                  'p_user_id': botUserId,
                  'p_last_tile_id': finish.discard.id,
                  'p_expected_round': round,
                },
              )
              .timeout(const Duration(seconds: 6));
          declared = botFinishSucceeded(response);
        } on PostgrestException catch (e) {
          if (e.code == 'PGRST202' || e.code == '42883') {
            _botPairsEndpointUnavailable = true;
          }
        } catch (_) {}
        final refreshed = await readHand();
        if (!current() || refreshed == null) return;
        declared = declared || refreshed['is_double_mode'] == true;
        observation = observe(hand, pairs: declared, allowPairs: declared);
        decision = await runBotDecision(observation);
        finish = decision.finish;
      }
      if (!current()) return;
      if (finish != null) {
        final plan = finish;
        await botFinishOrRecover(
          finish: () async {
            if (!await validHand(plan.discard.id)) return null;
            return _botClient
                .rpc(
                  'game_finish',
                  params: {
                    'p_table_id': tableId,
                    'p_user_id': botUserId,
                    'p_slots': plan.slots,
                    'p_last_tile': plan.discard.toPayload(),
                  },
                )
                .timeout(const Duration(seconds: 8));
          },
          revalidateAndDiscard: discardFresh,
        );
      } else {
        await discardFresh(false);
      }
    } catch (_) {
      if (current()) {
        await _recoverBotStall(botUserId: botUserId, expectedTurnToken: token);
      }
    } finally {
      if (current()) _lastBotTurnToken = null;
      _actionInFlight = false;
    }
  }
}
