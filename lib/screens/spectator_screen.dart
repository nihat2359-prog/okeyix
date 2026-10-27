import 'package:okeyix/ui/table_chat_panel.dart';
import 'package:okeyix/ui/spectator_finish_notice.dart';
import 'package:okeyix/services/table_chat_sync.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:okeyix/services/game_view_data_source.dart';
import 'package:okeyix/ui/spectator_table_scores.dart';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/core/spectator_presentation.dart';
import 'package:okeyix/services/profile_service.dart';
import 'package:okeyix/services/feedback_settings_service.dart';
import '../game/spectator_game.dart';
import 'package:okeyix/ui/table_gift_layer.dart';

class SpectatorScreen extends StatefulWidget {
  final String tableId;

  const SpectatorScreen({super.key, required this.tableId});

  @override
  State<SpectatorScreen> createState() => _SpectatorScreenState();
}

class _SpectatorScreenState extends State<SpectatorScreen> {
  final supabase = Supabase.instance.client;
  final topAvatarKey = GlobalKey();
  final bottomAvatarKey = GlobalKey();
  final topGiftBoundsKey = GlobalKey();
  final bottomGiftBoundsKey = GlobalKey();
  late SpectatorGame game;
  RealtimeChannel? spectatorChannel;
  final _scoresRefresh = CoalescedViewRefresh();
  final _scoreMembersRefresh = CoalescedViewRefresh();
  final _liveDetailsRefresh = CoalescedViewRefresh();
  final Map<String, int> _playerCoins = {};
  final DateTime _watchStartedAt = DateTime.now();
  Timer? _finishOverlayTimer;
  List<Map<String,dynamic>> _playerScores = [];
  String? _scoresViewer;
  String? _scoresTable;
  bool _scoresUnavailable = false;
  Map<String, dynamic>? table;
  List players = [];
  int spectators = 0;
  final ScrollController _chatScrollController = ScrollController();
  Map<String, dynamic>? _lastIncomingMessage;
  bool _showMessageBanner = false;
  Timer? _messageBannerTimer;
  bool chatOpen = false;
  final TextEditingController chatController = TextEditingController();
  List messages = [];
  late final TableChatSync _chatSync;
  bool _chatReady = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Map<String, String> _avatarChatByUserId = {};
  final Map<String, Timer> _avatarChatTimers = {};
  final Map<String, Map<String, dynamic>> _chatSenders = {};
  int _spectatorNoticeSequence = 0;
  DateTime? _lastFinishAt;
  bool _showFinishOverlay = false;
  String _finishWinnerName = 'Oyuncu';
  String? _finishTypeLabel;
  bool _tableChatEnabled = true;
  int _currentTurnSeat = 0;
  DateTime? _turnStartedAt;
  int _turnSeconds = 20;
  Timer? _turnTicker;
  bool _sendingMessage = false;
  bool _turnRefreshInFlight = false;

  bool _isPressing = false;
  bool _isRecording = false;
  bool _showPreview = false;
  bool _showEmojiPicker = false;
  bool _previewPlaying = false;

  int _recordSeconds = 0;
  Timer? _recordTimer;
  Timer? _safetyTimer;
  DateTime? _recordStartTime;
  bool _longPressActive = false;
  String? _recordPath;
  bool _canStop = false;
  DateTime? _pressStartTime;
  String? _playingMessageId;
  String? _previewPath;
  String _recordDuration = "0:00";
  final _recorder = AudioRecorder();

  static const List<String> _chatEmojis = <String>[
    '\u{1F600}',
    '\u{1F602}',
    '\u{1F60D}',
    '\u{1F60E}',
    '\u{1F44F}',
    '\u{1F525}',
    '\u{1F44D}',
    '\u{1F64F}',
    '\u{1F389}',
    '\u{2764}\u{FE0F}',
    '\u{1F621}',
    '\u{1F605}',
  ];

  void _insertEmojiToChat(String emoji) {
    final value = chatController.value;
    final start = value.selection.start >= 0
        ? value.selection.start
        : value.text.length;
    final end = value.selection.end >= 0 ? value.selection.end : start;
    final newText = value.text.replaceRange(start, end, emoji);
    chatController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  DateTime _messageCreatedAt(Map msg) {
    final raw = msg['created_at']?.toString();
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List _sortMessages(List input) {
    final sorted = List<Map<String, dynamic>>.from(
      input.map((e) => Map<String, dynamic>.from(e as Map)),
    );
    sorted.sort((a, b) => _messageCreatedAt(a).compareTo(_messageCreatedAt(b)));
    return sorted;
  }

  String _leagueDisplayName(dynamic rawLeagueId) {
    final id = (rawLeagueId ?? '').toString().trim().toLowerCase();
    switch (id) {
      case 'standard':
        return 'Acemiler';
      case 'bronze':
        return 'Çıraklar';
      case 'silver':
        return 'Kalfalar';
      case 'gold':
        return 'Ustalar';
      case 'elite':
        return 'Şampiyonlar';
      default:
        return id.isEmpty ? '-' : id;
    }
  }

  void _appendIncomingMessage(Map<String, dynamic> msg) {
    final incomingId = msg['id']?.toString();
    final next = List<Map<String, dynamic>>.from(
      messages.map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final alreadyExists =
        incomingId != null &&
        next.any((m) => m['id']?.toString() == incomingId);
    if (!alreadyExists) {
      next.add(msg);
    }
    messages = _sortMessages(next);
  }

  @override
  void initState() {
    super.initState();
    _chatSync = TableChatSync(
      loadRecent: () async {
        final since = _chatSync.latestMessageAt
            ?.subtract(const Duration(seconds: 2)) ?? _watchStartedAt;
        final rows = await supabase.from('table_messages').select()
            .eq('table_id', widget.tableId)
            .gte('created_at', since.toUtc().toIso8601String())
            .order('created_at', ascending: false).limit(200)
            .timeout(const Duration(seconds: 5));
        return rows.map((row) => Map<String, dynamic>.from(row)).toList();
      },
      onMessage: _receiveChatMessage,
    );

    game = SpectatorGame(
      tableId: widget.tableId,
      onTableClosed: () {
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
    );
    unawaited(_initializeSpectator());
    _turnTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && table != null) setState(() {});
    });
    _safetyTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_refreshTurnState());
      unawaited(_refreshLiveDetails());
      unawaited(_recoverChatMessages());
    });
  }

  Future<void> _initializeSpectator() async {
    await _joinSpectator();
    if (!mounted) return;
    try {
      await _load();
      await _refreshLiveDetails();
    } catch (_) {
      if (mounted) _msg('Masa bilgileri yüklenemedi. Lütfen yeniden deneyin.');
    }
  }

  Future<void> _refreshLiveDetails() => _liveDetailsRefresh.run(() async {
    await Future.wait([
      _refreshPlayerScores(),
      _refreshCoins(),
      _refreshLastFinish(),
    ]);
  });

  Future<void> _refreshCoins() async {
    final ids = players.map((p) => p['user_id']?.toString())
        .whereType<String>().toSet().toList();
    if (ids.isEmpty) return;
    try {
      final rows = await supabase.from('profiles').select('id,coins')
          .inFilter('id', ids);
      if (!mounted) return;
      final coins = <String, int>{
        for (final row in rows)
          if (row['coins'] is num) row['id'].toString(): (row['coins'] as num).toInt(),
      };
      if (jsonEncode(coins) != jsonEncode(_playerCoins)) {
        setState(() { _playerCoins.clear(); _playerCoins.addAll(coins); });
      }
    } catch (_) {
      // Do not invent balances when profile access is unavailable.
    }
  }

  Future<void> _refreshLastFinish() async {
    try {
      final raw = await supabase.rpc('okeyix_spectator_last_finish',
        params: {'p_table_id': widget.tableId});
      if (!mounted || raw is! Map) return;
      final result = Map<String, dynamic>.from(raw);
      final finishedAt = _parseServerTime(result['finished_at']);
      if (finishedAt == null || finishedAt.isBefore(_watchStartedAt)) return;
      final label = spectatorFinishLabel(result);
      if (_lastFinishAt != null && !finishedAt.isAfter(_lastFinishAt!)) {
        // The table Realtime event can arrive before the durable finish details.
        // Enrich that same notice without replaying it or resetting its timer.
        if (finishedAt.isAtSameMomentAs(_lastFinishAt!) && label != _finishTypeLabel) {
          setState(() => _finishTypeLabel = label);
        }
        return;
      }
      _lastFinishAt = finishedAt;
      _openFinishOverlay(result['username']?.toString() ?? 'Oyuncu', finishLabel: label);
    } catch (e) {
      // Keep the winner-only fallback, but expose missing RPC/access failures.
      debugPrint('SPECTATOR FINISH DETAILS ERROR: $e');
    }
  }
  Future<void> _refreshTurnState() async {
    if (!mounted || _turnRefreshInFlight) return;
    _turnRefreshInFlight = true;
    final previousStart = _turnStartedAt;
    final previousSeat = _currentTurnSeat;
    try {
      final row = await supabase.from('tables')
          .select('status,current_turn,turn_started_at,turn_seconds,chat_enabled,pot_amount,last_finish_at,last_winner_user_id')
          .eq('id', widget.tableId).maybeSingle();
      if (!mounted || row == null) return;
      _observeTableFinish(row);
      if (previousStart != _turnStartedAt || previousSeat != _currentTurnSeat) return;
      setState(() {
        table = {...?table, ...row};
        _turnStartedAt = _parseServerTime(row['turn_started_at']);
        _turnSeconds = (row['turn_seconds'] as num?)?.toInt() ?? 20;
        _currentTurnSeat = (row['current_turn'] as num?)?.toInt() ?? 0;
        _tableChatEnabled = row['chat_enabled'] != false;
      });
    } catch (_) {
      // Keep Realtime active and retry on the next safety tick.
    } finally {
      _turnRefreshInFlight = false;
    }
  }

  void _observeTableFinish(Map<String, dynamic> row) {
    final at = _parseServerTime(row['last_finish_at']);
    final winnerId = row['last_winner_user_id']?.toString();
    if (!mounted || at == null || winnerId == null ||
        at.isBefore(_watchStartedAt) ||
        (_lastFinishAt != null && !at.isAfter(_lastFinishAt!))) return;
    final seated = players.where((p) => p['user_id']?.toString() == winnerId);
    if (seated.isEmpty) return;
    final user = seated.first['users'];
    final name = user is Map ? user['username']?.toString() : null;
    _lastFinishAt = at;
    _openFinishOverlay(name ?? 'Oyuncu');
  }

  Future<void> _refreshPlayerScores() => _scoresRefresh.run(() async {
    final viewer = supabase.auth.currentUser?.id;
    final tableId = widget.tableId;
    if (viewer == null) {
      return;
    }
    try {
      final data = Map<String, dynamic>.from(
        await supabase.rpc(
              'okeyix_spectator_table_scores',
              params: {'p_table_id': tableId},
            )
            as Map,
      );
      if (!mounted ||
          widget.tableId != tableId ||
          supabase.auth.currentUser?.id != viewer ||
          data['table_id'] != tableId) {
        return;
      }
      final rows = (data['players'] as List)
          .map((p) => Map<String, dynamic>.from(p as Map))
          .toList();
      if (_scoresViewer == viewer &&
          _scoresTable == tableId &&
          !_scoresUnavailable &&
          jsonEncode(rows) == jsonEncode(_playerScores)) {
        return;
      }
      setState(() {
        _scoresUnavailable = false;
        _playerScores = rows;
        _scoresViewer = viewer;
        _scoresTable = tableId;
      });
    } catch (_) {
      if (mounted && supabase.auth.currentUser?.id == viewer && !_scoresUnavailable) {
        setState(() => _scoresUnavailable = true);
      }
    }
  });

  Future<void> _refreshScoreMembers() => _scoreMembersRefresh.run(() async {
    final tableId = widget.tableId;
    final viewer = supabase.auth.currentUser?.id;
    try {
      final rows = await supabase
          .from('table_players')
          .select('id,user_id,seat_index,users(username,avatar_url,is_bot)')
          .eq('table_id', tableId);
      if (!mounted ||
          widget.tableId != tableId ||
          supabase.auth.currentUser?.id != viewer) {
        return;
      }
      setState(() => players = rows);
      await _refreshPlayerScores();
    } catch (_) {}
  });

  List<Map<String, dynamic>> get _visibleScores {
    if (_scoresViewer == supabase.auth.currentUser?.id &&
        _scoresTable == widget.tableId && !_scoresUnavailable) {
      return _playerScores;
    }
    final rows =
        players
            .where((p) => p['seat_index'] == 0 || p['seat_index'] == 1)
            .map(
              (p) => <String, dynamic>{
                'seat_index': p['seat_index'],
                'username': p['users']?['username'] ?? 'Oyuncu',
                'wins': null,
                'losses': null,
              },
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['seat_index'] as int).compareTo(b['seat_index'] as int),
          );
    return rows;
  }

  Future<void> _load() async {
    await FeedbackSettingsService.load();
    final t = await supabase
        .from('tables')
        .select()
        .eq('id', widget.tableId)
        .single();
    final tableChatEnabled = (t['chat_enabled'] as bool?) ?? true;
    final turnStartedAt = _parseServerTime(t['turn_started_at']);
    final turnSeconds = (t['turn_seconds'] as int?) ?? 20;
    final currentTurnSeat = (t['current_turn'] as int?) ?? 0;

    final p = await supabase
        .from('table_players')
        .select('id,user_id,seat_index,users(username,avatar_url,is_bot)')
        .eq('table_id', widget.tableId);

    final s = await supabase
        .from('table_spectators')
        .select()
        .eq('table_id', widget.tableId);



    List<dynamic> m;
    try {
      m = await supabase.from('table_messages').select('*,users(username)')
          .eq('table_id', widget.tableId).order('created_at');
    } catch (_) {
      // A missing users relationship must not prevent table/turn subscription.
      try {
        m = await supabase.from('table_messages').select()
            .eq('table_id', widget.tableId).order('created_at');
      } catch (_) {
        m = [];
        if (mounted) _msg('Masa sohbeti yüklenemedi.');
      }
    }

    if (!mounted) return;

    _chatSync.seed(m.map((row) => Map<String, dynamic>.from(row as Map)));
    final previousChannel = spectatorChannel;
    if (previousChannel != null) await supabase.removeChannel(previousChannel);
    if (!mounted) return;
    final channel = supabase.channel('spectators:${widget.tableId}');
    spectatorChannel = channel;

    channel
        /// ğŸ‘€ BÄ°RÄ° GÄ°RÄ°NCE
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'table_spectators',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: widget.tableId,
          ),
          callback: (payload) {
            if (!mounted) return;

            setState(() {
              spectators++;

            });
          },
        )
        /// ğŸ‘€ BÄ°RÄ° Ã‡IKINCA
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'table_spectators',
          callback: (payload) {
            final old = payload.oldRecord;

            if (old['table_id'] == widget.tableId) {
              if (!mounted) return;

              setState(() {
                spectators = (spectators - 1).clamp(0, 9999);
  
              });
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'table_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'table_id',
            value: widget.tableId,
          ),
          callback: (payload) {
            if (!mounted) return;
            _chatSync.receive(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'tables',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.tableId,
          ),
          callback: (payload) async {
            final row = payload.newRecord;
            unawaited(_refreshPlayerScores());
            unawaited(_refreshLiveDetails());
            final turnStartedAt = _parseServerTime(row['turn_started_at']);
            final turnSeconds = (row['turn_seconds'] as int?) ?? _turnSeconds;
            final currentTurnSeat =
                (row['current_turn'] as int?) ?? _currentTurnSeat;
            if (mounted) {
              setState(() {
                table = {...?table, ...row};
                _turnStartedAt = turnStartedAt;
                _turnSeconds = turnSeconds;
                _currentTurnSeat = currentTurnSeat;
              });
            }
            _observeTableFinish(row);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,schema: 'public',table: 'table_players',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,column: 'table_id',value: widget.tableId),
          callback: (_) => unawaited(_refreshScoreMembers()),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,schema: 'public',table: 'table_players',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,column: 'table_id',value: widget.tableId),
          callback: (_) => unawaited(_refreshScoreMembers()),
        )
        .subscribe((status, err) {
          if (mounted && status==RealtimeSubscribeStatus.subscribed) {
            unawaited(_refreshScoreMembers());
            unawaited(_recoverChatMessages());
          }
          if (err != null) {
            print("SPECTATOR ERROR: $err");
          }
        });

    setState(() {
      table = t;
      players = p;
      spectators = s.length;
      for (final message in m) {
        _appendIncomingMessage(Map<String, dynamic>.from(message as Map));
      }
      _chatReady = true;
      _tableChatEnabled = tableChatEnabled;
      _turnStartedAt = turnStartedAt;
      _turnSeconds = turnSeconds;
      _currentTurnSeat = currentTurnSeat;
      if (!_tableChatEnabled) chatOpen = false;
    });
    unawaited(_refreshPlayerScores());
    unawaited(_recoverChatMessages());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToBottom();
    });
  }

  Map? player(int seat) {
    try {
      return players.firstWhere((e) => e['seat_index'] == seat);
    } catch (_) {
      return null;
    }
  }

  Widget avatar(String? path, {Key? key}) {
    if (path == null || path.isEmpty) {
      return CircleAvatar(key: key, radius: 26, backgroundColor: Colors.black);
    }

    if (path.startsWith("http")) {
      return CircleAvatar(
        key: key,
        radius: 26,
        backgroundImage: NetworkImage(path),
      );
    }

    return CircleAvatar(
      key: key,
      radius: 26,
      backgroundColor: Colors.black,
      child: ClipOval(
        child: Image.asset(path, fit: BoxFit.cover, width: 52, height: 52),
      ),
    );
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> sendMessage() async {
    if (!_tableChatEnabled || _sendingMessage) return;
    final content = chatController.text.trim();
    final user = supabase.auth.currentUser;
    if (content.isEmpty || user == null) return;
    _sendingMessage = true;
    final message = <String, dynamic>{
      'id': const Uuid().v4(), 'table_id': widget.tableId,
      'sender_id': user.id, 'content': content,
      'role': 'spectator', 'type': 'text',
    };
    try {
      await supabase.from('table_messages').insert(message);
      if (!mounted) return;
      setState(() => _appendIncomingMessage({
        ...message, 'created_at': DateTime.now().toUtc().toIso8601String(),
        'users': {'username': 'Sen'},
      }));
      if (chatController.text.trim() == content) chatController.clear();
      FocusManager.instance.primaryFocus?.unfocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    } on PostgrestException catch (e) {
      if (mounted) _msg(e.code == '42501'
          ? 'Bu masada mesaj gönderme izni yok.'
          : 'Mesaj gönderilemedi. Tekrar deneyin.');
    } catch (_) {
      if (mounted) _msg('Mesaj gönderilemedi. Bağlantınızı kontrol edin.');
    } finally {
      _sendingMessage = false;
    }
  }
  @override
  Widget build(BuildContext context) {
    final top = player(1);
    final bottom = player(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (topAvatarKey.currentContext == null ||
          bottomAvatarKey.currentContext == null) {
        return;
      }

      final topPos = _getAvatarWorldPosition(topAvatarKey);
      final bottomPos = _getAvatarWorldPosition(bottomAvatarKey);

      game.setAvatarPositions(topPos, bottomPos);
    });
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Positioned.fill(child: SpectatorBackdrop()),
          /// MASA (FLAME)
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: GameWidget(game: game),
            ),
          ),

          /// HEADER
          if (table != null)
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + 10,
              left: MediaQuery.viewPaddingOf(context).left + 14,
              right: MediaQuery.viewPaddingOf(context).right + 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xB52A3039), Color(0xC410151D)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0x668F9BA6),
                    width: 0.8,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 18,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _headerChip(
                        icon: Icons.shield_rounded,
                        text: 'Lig ${_leagueDisplayName(table!['league_id'])}',
                      ),
                      const SizedBox(width: 9),
                      _headerChip(
                        icon: Icons.monetization_on_rounded,
                        text: Format.coin((table!['entry_coin'] as int?) ?? 0),
                        highlight: true,
                      ),
                      const SizedBox(width: 9),
                      _headerChip(
                        icon: Icons.rice_bowl_rounded,
                        text: Format.coin((table!['pot_amount'] as num?)?.toInt() ?? 0),
                      ),
                      const SizedBox(width: 9),
                      _headerChip(
                        icon: Icons.timer_rounded,
                        text: '${(table!['turn_seconds'] as int?) ?? 20} sn',
                      ),
                      const SizedBox(width: 9),
                      _headerChip(
                        icon: Icons.people_alt_rounded,
                        text:
                            '${players.length}/${(table!['max_players'] as int?) ?? 2}',
                      ),
                      const SizedBox(width: 9),
                      _headerChip(
                        icon: Icons.remove_red_eye_rounded,
                        text: '$spectators',
                      ),
                      const SizedBox(width: 9),
                      _headerChip(
                        icon: _tableChatEnabled
                            ? Icons.chat_bubble_rounded
                            : Icons.chat_bubble_outline_rounded,
                        text: _tableChatEnabled
                            ? 'Sohbet Açık'
                            : 'Sohbet Kapalı',
                      ),
                      const SizedBox(width: 9),
                    ],
                  ),
                ),
              ),
            ),

          if (table != null)
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + 68,
              left: MediaQuery.viewPaddingOf(context).left + 22,
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SpectatorTableScores(players: _visibleScores),
                if (_lastFinishAt != null) Container(
                  constraints: const BoxConstraints(maxWidth: 210),
                  margin: const EdgeInsets.only(top: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xDD101A20),
                    borderRadius: BorderRadius.circular(10)),
                  child: Text('Son eli kazanan: $_finishWinnerName',
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFE4C88D), fontSize: 11)),
                ),
              ],
            )),

          /// OYUNCULAR: iki koltukta da ayni dikey avatar/isim yerlesimi.
          if (top != null)
            Positioned(
              top: 60,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTurnAvatar(
                    seatIndex: 1,
                    userId: top['user_id']?.toString(),
                    avatarPath: top['users']['avatar_url']?.toString(),
                    avatarKey: topAvatarKey,
                    giftBoundsKey: topGiftBoundsKey,
                  ),
                  if ((_avatarChatByUserId[top['user_id']?.toString()] ?? '')
                      .isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _buildAvatarBubble(
                      _avatarChatByUserId[top['user_id']?.toString()]!,
                    ),
                  ],
                ],
              ),
            ),

          if (bottom != null)
            Positioned(
              bottom: 58,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((_avatarChatByUserId[bottom['user_id']?.toString()] ?? '')
                      .isNotEmpty) ...[
                    _buildAvatarBubble(
                      _avatarChatByUserId[bottom['user_id']?.toString()]!,
                    ),
                    const SizedBox(height: 4),
                  ],
                  _buildTurnAvatar(
                    seatIndex: 0,
                    userId: bottom['user_id']?.toString(),
                    avatarPath: bottom['users']['avatar_url']?.toString(),
                    avatarKey: bottomAvatarKey,
                    giftBoundsKey: bottomGiftBoundsKey,
                  ),
                ],
              ),
            ),

          /// CHAT BUTTON
          Positioned.fill(child: TableGiftLayer(
            key: ValueKey('spectator-gifts:${widget.tableId}:${supabase.auth.currentUser?.id}:${players.map((p) => p['id'] ?? p['user_id']).join(':')}'),
            tableId: widget.tableId,
            spectator: true,
            anchors: [
              if (top != null) TableGiftAnchor(top['user_id'].toString(), top['users']['username']?.toString() ?? '', topGiftBoundsKey),
              if (bottom != null) TableGiftAnchor(bottom['user_id'].toString(), bottom['users']['username']?.toString() ?? '', bottomGiftBoundsKey),
            ],
          )),
          if (_tableChatEnabled)
            Positioned(
              right: 20,
              bottom: 20,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    chatOpen = !chatOpen;
                  });
                  if (chatOpen) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || !chatOpen || !_chatScrollController.hasClients) return;
                      _chatScrollController.jumpTo(
                        _chatScrollController.position.maxScrollExtent,
                      );
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          /// CLOSE BUTTON
          Positioned(
            left: 20,
            bottom: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),

          /// CHAT PANEL
          if (_tableChatEnabled && chatOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() {
                    chatOpen = false;
                  });
                },
                child: Container(
                  color: Colors.black.withOpacity(.35),
                  padding: EdgeInsets.fromLTRB(
                    MediaQuery.viewPaddingOf(context).left,
                    MediaQuery.viewPaddingOf(context).top,
                    MediaQuery.viewPaddingOf(context).right,
                    MediaQuery.viewInsetsOf(context).bottom > 0
                        ? MediaQuery.viewInsetsOf(context).bottom
                        : MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () {},

                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,

                        width: 560,
                        margin: const EdgeInsets.fromLTRB(0, 8, 12, 8),
                        padding: EdgeInsets.all(MediaQuery.viewInsetsOf(context).bottom > 0 ? 6 : 12),

                        decoration: BoxDecoration(
                          color: const Color(0xEE0F141A),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0x33FFFFFF)),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black87,
                              blurRadius: 30,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),

                        child: Column(
                          children: [
                            /// HEADER
                            if (MediaQuery.viewInsetsOf(context).bottom == 0)
                            Row(
                              children: [
                                const Icon(
                                  Icons.forum_rounded,
                                  color: Color(0xFFD4AF37),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  "Masa Sohbeti",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () {
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    setState(() => chatOpen = false);
                                  },
                                ),
                              ],
                            ),

                            SizedBox(height: MediaQuery.viewInsetsOf(context).bottom > 0 ? 2 : 10),

                            /// ğŸ”¥ MESSAGE LIST
                            Expanded(
                              child: ListView.builder(
                                controller: _chatScrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                itemCount: messages.length,
                                itemBuilder: (_, i) {
                                  final m = messages[i];

                                  final mine =
                                      m['sender_id'] ==
                                      supabase.auth.currentUser?.id;

                                  final isVoice = m['type'] == 'voice';

                                  final username =
                                      m['users']?['username'] ?? "Oyuncu";

                                  return Align(
                                    alignment: mine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      padding: const EdgeInsets.all(10),
                                      constraints: const BoxConstraints(
                                        maxWidth: 240,
                                      ),
                                      decoration: BoxDecoration(
                                        color: mine
                                            ? const Color(0xFF2A3D1B)
                                            : const Color(0xFF1A222A),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: mine
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            username,
                                            style: const TextStyle(
                                              color: Color(0xFFD4AF37),
                                              fontSize: 11,
                                            ),
                                          ),
                                          const SizedBox(height: 4),

                                          isVoice
                                              ? _voiceBubble(m, mine)
                                              : Text(
                                                  m['content'] ?? '',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  ),
                                                ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),

                            /// ğŸ”¥ PREVIEW
                            if (_showPreview && _previewPath != null && MediaQuery.viewInsetsOf(context).bottom == 0)
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A222A),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.play_arrow,
                                        color: Colors.white,
                                      ),
                                      onPressed: () async {
                                        if (!FeedbackSettingsService
                                            .soundEnabled) {
                                          await FeedbackSettingsService.triggerHaptic();
                                          return;
                                        }
                                        await _audioPlayer.setFilePath(
                                          _previewPath!,
                                        );
                                        await _audioPlayer.play();
                                        await FeedbackSettingsService.triggerHaptic();
                                      },
                                    ),
                                    Expanded(child: _waveform(false)),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                      ),
                                      onPressed: () async {
                                        await File(_previewPath!).delete();
                                        setState(() {
                                          _previewPath = null;
                                          _showPreview = false;
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.send,
                                        color: Colors.green,
                                      ),
                                      onPressed: () async {
                                        await sendVoiceMessage(_previewPath!);
                                        setState(() {
                                          _previewPath = null;
                                          _showPreview = false;
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),

                            /// ğŸ”¥ QUICK CHAT
                            if (MediaQuery.viewInsetsOf(context).bottom == 0)
                            TableChatQuickMessages(onSelected: (message) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              setState(() {
                                chatOpen = false;
                                _showEmojiPicker = false;
                              });
                              chatController.text = message;
                              unawaited(sendMessage());
                            }),
                            SizedBox(height: MediaQuery.viewInsetsOf(context).bottom > 0 ? 2 : 8),

                            /// ğŸ”¥ INPUT + VOICE
                            if (_showEmojiPicker && MediaQuery.viewInsetsOf(context).bottom == 0) ...[
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xAA1E2B24),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0x3359A588),
                                  ),
                                ),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _chatEmojis.map((emoji) {
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _insertEmojiToChat(emoji),
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Text(
                                          emoji,
                                          style: const TextStyle(fontSize: 22),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                            Row(
                              children: [
                                /// ğŸ¤ RECORD
                                Listener(
                                  onPointerDown: (_) async {
                                    _isPressing = true;

                                    await Future.delayed(
                                      const Duration(milliseconds: 250),
                                    );

                                    if (_isPressing) {
                                      await _startRecording();
                                    }
                                  },
                                  onPointerUp: (_) async {
                                    _isPressing = false;
                                    await _stopRecording(send: false);
                                  },
                                  child: _recordButton(),
                                ),

                                const SizedBox(width: 6),

                                IconButton(
                                  tooltip: 'Emoji',
                                  onPressed: () {
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    setState(() {
                                      _showEmojiPicker = !_showEmojiPicker;
                                    });
                                  },
                                  icon: Icon(
                                    _showEmojiPicker
                                        ? Icons.emoji_emotions
                                        : Icons.emoji_emotions_outlined,
                                    color: const Color(0xFFD4AF37),
                                  ),
                                ),

                                /// TEXT
                                Expanded(
                                  child: TextField(
                                    controller: chatController,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => sendMessage(),
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: "Mesaj yaz...",
                                      hintStyle: const TextStyle(
                                        color: Colors.white54,
                                      ),
                                      filled: true,
                                      fillColor: const Color(0x221A222A),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),

                                  ),
                                ),

                                const SizedBox(width: 6),

                                /// SEND
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD4AF37),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: IconButton(
                                    onPressed: sendMessage,
                                    icon: const Icon(
                                      Icons.send,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (_showMessageBanner && _lastIncomingMessage != null)
            Positioned(
              top: 72,
              right: 12,
              width: 360,
              child: _buildMessageBanner(),
            ),
          if (_showFinishOverlay) Positioned.fill(child: _buildFinishOverlay()),
        ],
      ),
    );
  }

  Future<void> _playVoice(Map<String, dynamic> msg) async {
    try {
      final path = msg['voice_url'];
      if (path == null) return;
      if (!FeedbackSettingsService.soundEnabled) {
        await FeedbackSettingsService.triggerHaptic();
        return;
      }

      /// aynÄ± mesaj â†’ stop
      if (_playingMessageId == msg['id']) {
        await _audioPlayer.stop();
        setState(() => _playingMessageId = null);
        return;
      }

      /// yeni mesaj baÅŸlat
      final url = await supabase.storage
          .from('voice')
          .createSignedUrl(path, 60);

      await _audioPlayer.stop(); // ğŸ’¥ Ã¶nemli (Ã¶nceki sesi kes)

      await _audioPlayer.setUrl(url);

      setState(() => _playingMessageId = msg['id']);

      await _audioPlayer.play();
      await FeedbackSettingsService.triggerHaptic();
    } catch (e) {
      debugPrint("VOICE PLAY ERROR: $e");
    }
  }

  Widget _buildAvatarBubble(String text) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF2D596), Color(0xFFE7BE6A)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xCC7A5A1F), width: 1),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1D2A25),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerChip({
    required IconData icon,
    required String text,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x802A3039), Color(0x9910151D)],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: highlight ? const Color(0xB8D9B46A) : const Color(0x448F9BA6),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: highlight ? const Color(0xFFE7C06A) : Colors.white70,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: highlight ? const Color(0xFFE7C06A) : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBanner() {
    final msg = _lastIncomingMessage!;
    final name = (msg['users']?['username'] ?? 'İzleyici').toString();
    final type = (msg['type'] ?? 'text').toString();
    final text = type == 'voice'
        ? 'Sesli mesaj gönderdi'
        : (msg['content'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xF02A3039), Color(0xF010151D)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x668F8062), width: .8),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 12,
            offset: Offset(0, 4)),
        ],
      ),
      child: Text(
        '$name: $text',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFF0E9DA),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildFinishOverlay() => SpectatorFinishNotice(winnerName: _finishWinnerName, finishLabel: _finishTypeLabel);

  bool _isPlayerSender(String? senderId) {
    if (senderId == null) return false;
    return players.any((p) => p['user_id']?.toString() == senderId);
  }

  Future<void> _recoverChatMessages() async {
    if (!mounted || !_chatReady) return;
    try {
      await _chatSync.refresh();
    } catch (error) {
      debugPrint('SPECTATOR CHAT RECOVERY ERROR: $error');
    }
  }

  void _receiveChatMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final senderId = msg['sender_id']?.toString();
    for (final player in players) {
      if (player['user_id']?.toString() == senderId) {
        msg['users'] = player['users'];
        break;
      }
    }
    msg['users'] ??= _chatSenders[senderId];
    setState(() => _appendIncomingMessage(msg));
    unawaited(_deliverChatEffects(msg));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToBottom();
    });
    if (senderId != null && msg['users'] == null && msg['role'] != 'spectator') {
      unawaited(_enrichMessageSender(msg));
    }
  }

  Future<void> _deliverChatEffects(Map<String, dynamic> msg) async {
    if (msg['role'] == 'spectator' &&
        msg['sender_id']?.toString() != supabase.auth.currentUser?.id) {
      final sequence = ++_spectatorNoticeSequence;
      final existingName = msg['users']?['username']?.toString().trim() ?? '';
      if (existingName.isEmpty) await _enrichMessageSender(msg);
      if (!mounted || sequence != _spectatorNoticeSequence) return;
      // Open the notice with its final identity, never a temporary role label.
      if ((msg['users']?['username']?.toString().trim() ?? '').isEmpty) return;
    }
    _handleIncomingMessageEffects(msg);
  }

  Future<void> _enrichMessageSender(Map<String, dynamic> msg) async {
    try {
      final user = await supabase.from('users').select('username')
          .eq('id', msg['sender_id']).maybeSingle()
          .timeout(const Duration(seconds: 5));
      if (!mounted || user == null) return;
      setState(() {
        _chatSenders[msg['sender_id'].toString()] = Map<String, dynamic>.from(user);
        msg['users'] = user;
        for (final existing in messages) {
          if (existing['id'] == msg['id']) existing['users'] = user;
        }
        if (_lastIncomingMessage?['id'] == msg['id']) {
          _lastIncomingMessage!['users'] = user;
        }
      });
    } catch (_) {
      // Keep the message in the list if sender metadata is unavailable.
    }
  }

  void _handleIncomingMessageEffects(Map<String, dynamic> msg) {
    final senderId = msg['sender_id']?.toString();
    if (senderId == null) return;
    final type = (msg['type'] ?? 'text').toString();
    final text = type == 'voice'
        ? 'Sesli mesaj gönderdi'
        : (msg['content'] ?? '').toString().trim();
    final role = (msg['role'] ?? '').toString();
    final mine = senderId == supabase.auth.currentUser?.id;

    if (_isPlayerSender(senderId) && text.isNotEmpty) {
      _avatarChatTimers[senderId]?.cancel();
      setState(() {
        _avatarChatByUserId[senderId] = text;
      });
      _avatarChatTimers[senderId] = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _avatarChatByUserId.remove(senderId);
        });
        _avatarChatTimers.remove(senderId);
      });
      return;
    }

    if (!mine &&
        role == 'spectator') {
      setState(() {
        _lastIncomingMessage = msg;
        _showMessageBanner = true;
      });
      _messageBannerTimer?.cancel();
      _messageBannerTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _showMessageBanner = false);
      });
    }
  }

  void _openFinishOverlay(String winnerName, {String? finishLabel}) {
    if (!mounted) return;
    setState(() {
      _finishWinnerName = winnerName;
      _finishTypeLabel = finishLabel;
      _showFinishOverlay = true;
    });
    _finishOverlayTimer?.cancel();
    _finishOverlayTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _showFinishOverlay = false);
    });
  }

  Widget _voiceBubble(Map<String, dynamic> msg, bool mine) {
    final isPlaying = _playingMessageId == msg['id'];

    return Row(
      mainAxisSize: MainAxisSize.min, // â— Ã¶nemli
      children: [
        /// â–¶ï¸ PLAY
        GestureDetector(
          onTap: () => _playVoice(msg),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isPlaying
                  ? const Color(0xFFE7C06A)
                  : (mine ? Colors.white : Colors.black26),
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              size: 18,
              color: isPlaying
                  ? Colors.black
                  : (mine ? Colors.black : Colors.white),
            ),
          ),
        ),

        const SizedBox(width: 8),

        /// ğŸ”Š WAVE
        SizedBox(
          width: 80, // â— sabit width
          child: Row(
            children: List.generate(12, (i) {
              final height = (i % 5 + 3).toDouble();

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                width: 3,
                height: height * 2,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(.85),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        ),

        const SizedBox(width: 6),

        /// â±ï¸ sÃ¼re
        Text(
          "${msg['duration'] ?? 0}s",
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  Widget _waveform(bool playing) {
    return Row(
      children: List.generate(20, (i) {
        final baseHeight = (i % 5 + 3).toDouble();

        return AnimatedContainer(
          duration: Duration(milliseconds: 200 + (i * 20)),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: 3,
          height: playing ? baseHeight * 5 : baseHeight * 2,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.85),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Future<void> sendVoiceMessage(String filePath) async {
    if (!_tableChatEnabled) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final file = File(filePath);

      if (!await file.exists()) return;

      /// ğŸ†” unique id
      final messageId = const Uuid().v4();

      /// ğŸ”— storage path (table bazlÄ±)
      final storagePath = 'table/${widget.tableId}/$messageId.m4a';

      /// ğŸ“¦ STORAGE UPLOAD
      await supabase.storage.from('voice').upload(storagePath, file);

      /// ğŸ§¾ DB INSERT
      await supabase.from('table_messages').insert({
        "table_id": widget.tableId,
        "sender_id": user.id,
        "role": "spectator", // veya player
        "content": "", // boÅŸ
        "type": "voice",
        "voice_url": storagePath,
        "duration": 5, // ÅŸimdilik sabit
      });

      /// ğŸ§¹ local temizle
      await file.delete();

      /// ğŸ”„ refresh
      await _load();
      _scrollToBottom();
    } catch (e) {
      debugPrint("VOICE SEND ERROR: $e");
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    if (!await _recorder.hasPermission()) return;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${const Uuid().v4()}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: path,
    );

    _recordPath = path;

    setState(() => _isRecording = true);

    _startTimer();

    /// ğŸ’¥ EN KRÄ°TÄ°K (recorder warmup)
    _canStop = false;

    Future.delayed(const Duration(milliseconds: 300), () {
      _canStop = true;
    });
  }

  void _startTimer() {
    _recordSeconds = 0;

    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        _recordSeconds++;
      });
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_isRecording) return;

    if (!_canStop) return;

    final path = await _recorder.stop();

    _stopTimer();
    setState(() => _isRecording = false);

    if (path == null) return;

    final file = File(path);
    final size = await file.length();

    if (size < 8000) {
      await file.delete();
      return;
    }

    /// â— ARTIK GÃ–NDERMEYÄ°Z
    setState(() {
      _previewPath = path;
      _showPreview = true;
    });
  }

  void _stopTimer() {
    _recordTimer?.cancel();
  }

  Widget _recordButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,

      height: _isRecording ? 54 : 44,
      width: _isRecording ? 54 : 44,

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),

        /// ğŸ¨ BACKGROUND
        color: _isRecording ? Colors.redAccent : const Color(0xFF1E2A25),

        /// ğŸ’ BORDER
        border: Border.all(
          color: _isRecording ? Colors.redAccent : const Color(0x3359A588),
          width: _isRecording ? 1.6 : 1,
        ),

        /// âœ¨ GLOW
        boxShadow: _isRecording
            ? [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(.7),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : [BoxShadow(color: Colors.black.withOpacity(.25), blurRadius: 6)],
      ),

      child: Center(
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: _isRecording ? 1.2 : 1,

          child: Icon(
            _isRecording ? Icons.mic : Icons.mic_none,
            size: _isRecording ? 26 : 22,
            color: _isRecording ? Colors.white : const Color(0xFFE7C06A),
          ),
        ),
      ),
    );
  }

  Vector2 _getAvatarWorldPosition(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Vector2.zero();

    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;

    final centerX = pos.dx + size.width / 2;
    final centerY = pos.dy + size.height / 2;

    // ğŸ”¥ Flutter â†’ Flame dÃ¶nÃ¼ÅŸÃ¼m
    final screenSize = MediaQuery.of(context).size;

    final scaleX = 1600 / screenSize.width;
    final scaleY = 900 / screenSize.height;

    return Vector2(centerX * scaleX, centerY * scaleY);
  }

  Widget _buildTurnAvatar({
    required int seatIndex,
    required String? userId,
    required String? avatarPath,
    required Key avatarKey,
    required GlobalKey giftBoundsKey,
  }) {
    final seated = player(seatIndex);
    final name = seated?['users']?['username']?.toString() ?? 'Oyuncu';
    return SpectatorPlayerCard(
      isBot: seated?['users']?['is_bot'] == true,
      key: giftBoundsKey,
      username: name,
      coins: _playerCoins[userId],
      avatar: avatar(avatarPath, key: avatarKey),
      active: _currentTurnSeat == seatIndex,
      progress: _turnProgress(),

      onTap: userId == null || userId.isEmpty ? null
          : () => ProfileService.showUserCard({'id': userId}),
    );
  }
  DateTime? _parseServerTime(dynamic raw) {
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw.toString());
    return parsed?.toLocal();
  }

  double _turnProgress() {
    return spectatorTurnProgress(_turnStartedAt, _turnSeconds, DateTime.now());
  }

  @override
  void dispose() {
    _chatSync.dispose();
    _liveDetailsRefresh.dispose();
    _finishOverlayTimer?.cancel();
    _scoresRefresh.dispose();
    _scoreMembersRefresh.dispose();
    _messageBannerTimer?.cancel();
    for (final t in _avatarChatTimers.values) {
      t.cancel();
    }
    _avatarChatTimers.clear();
    _turnTicker?.cancel();
    _safetyTimer?.cancel();
    _chatScrollController.dispose();
    spectatorChannel?.unsubscribe();
    _leaveSpectator();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_chatScrollController.hasClients) return;

    _chatScrollController.animateTo(
      _chatScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _joinSpectator() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from('table_spectators').upsert({
        'table_id': widget.tableId,
        'user_id': user.id,
      }, onConflict: 'table_id,user_id', ignoreDuplicates: true);
      if (!mounted) return;
      unawaited(_refreshPlayerScores());
  
    } catch (e) {
      print("JOIN ERROR: $e");
    }
  }

  Future<void> _leaveSpectator() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase
          .from('table_spectators')
          .delete()
          .eq('table_id', widget.tableId)
          .eq('user_id', user.id);
    } catch (e) {
      print("LEAVE ERROR: $e");
    }
  }
}
