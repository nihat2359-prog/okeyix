import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/core/table_creation_options.dart';
import 'package:okeyix/core/message_contacts.dart';
import 'package:okeyix/core/league_player_counts.dart';
import 'package:okeyix/overlay/gift_overlay.dart';
import 'package:okeyix/screens/spectator_screen.dart';
import 'package:okeyix/services/celebration_service.dart';
import 'package:okeyix/services/device_registration_service.dart';
import 'package:okeyix/services/presence_service.dart';
import 'package:okeyix/services/profile_service.dart';
import 'package:okeyix/services/user_state.dart';
import 'package:okeyix/services/ready_table_service.dart';
import 'package:okeyix/ui/reward_dialogs.dart';
import 'package:okeyix/ui/lobby/lobby_utility_scenes.dart';
import 'package:okeyix/services/reward_audio.dart';
import 'package:okeyix/ui/coin_transfer_overlay.dart';
import 'package:okeyix/ui/lobby/lobby_columns.dart';
import 'package:okeyix/ui/lobby/create_table_scene.dart';
import 'package:okeyix/ui/lobby/quick_play_panel.dart';
import 'package:okeyix/services/quick_play_service.dart';
import 'package:okeyix/core/table_invite_policy.dart';

import 'package:okeyix/ui/lobby/LobbyTableWheel.dart';
import 'package:okeyix/widgets/aaa_button.dart';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:okeyix/services/auth_service.dart';

import 'okey_game_screen.dart';
import 'login_screen.dart';
import 'store_screen.dart';
import 'friend_invite_screen.dart';
import 'package:okeyix/ui/lobby/lobby_metal_surface.dart';
import 'package:okeyix/ui/profile_action_scenes.dart';
import 'package:okeyix/ui/invite_strings.dart';
import 'leaderboard_screen.dart';
import 'banned_screen.dart';
import '../ui/lobby/lobby_avatar.dart';
import '../ui/lobby/lobby_level_badge.dart';
import '../ui/lobby/lobby_league_list.dart';
import '../ui/lobby/lobby_bottom_dock.dart';
import '../ui/lobby/lobby_side_menu.dart';
import '../ui/lobby/lobby_right_panel.dart';
import '../ui/lobby/lobby_social_scenes.dart';
import '../ui/lobby/_ui_helpers.dart';
import '../ui/lobby/lobby_table_listing_card.dart';
import '../ui/ambient/sky_planes_overlay.dart';
import 'package:flutter/cupertino.dart';
import 'package:record/record.dart';
import 'package:okeyix/services/feedback_settings_service.dart';

enum _RightPanelType { none, friends, messages, settings }

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const Color _goldBorderColor = Color(0xCCB07A1A);
  static const Color _goldBorderDark = Color(0xFF8F6215);
  static const double _goldBorderWidth = 0.3;
  static const int _renameCoinCost = 1000;
  static const int _globalSpectatorPassCost = 10000;

  final _audioPlayer = AudioPlayer();
  String? _playingMessageId;
  final supabase = Supabase.instance.client;
  Timer? _leagueActivityTimer;
  Timer? _socialRefreshTimer;
  Timer? _tablesRefreshTimer;
  Timer? _systemMessageTimer;
  Timer? _spectatorPassTimer;
  Timer? _tableInvitePollTimer;
  bool _lobbyLoopsRunning = false;
  bool _banScreenOpened = false;
  bool _rewardFlowRunning = false;
  static const int _welcomeCoinAmount = 10000;
  static const int _dailyBonusCoinAmount = 2500;
  late final AnimationController _bgController;
  late final AnimationController _coinFxController;
  late final AnimationController _coinCountController;
  late final AnimationController _ratingCountController;
  Animation<int>? _coinCountAnimation;
  Animation<int>? _ratingCountAnimation;
  final _coinTargetKey = GlobalKey();
  final _lobbySceneKey = GlobalKey();
  RewardAudio? _rewardAudio;
  late final AnimationController _rewardFlight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  Offset _flightSource = Offset.zero, _flightDestination = Offset.zero;
  Timer? _coinFxTimer;
  bool _coinFxActive = false;
  int _coinDisplayValue = 0;
  int _ratingDisplayValue = 0;
  final TextEditingController _chatController = TextEditingController();
  final _recorder = AudioRecorder();
  final ScrollController _chatScrollController = ScrollController();
  String? selectedLeague = "standart";
  int createMaxPlayer = 2;
  int createTurnSeconds = 15;
  bool createSpectatorEnabled = true;
  bool createChatEnabled = true;
  int draftTurnSeconds = 15;
  List<Map<String, dynamic>> leagues = [];
  List<Map<String, dynamic>> tables = [];
  Map<String, int> leagueActivePlayers = {};
  Map<String, int> leagueActiveTables = {};
  List<int> coinOptions = [];
  bool loadingLeagues = true;
  bool loadingTables = true;
  bool _tablesInitialized = false;
  bool _isSideMenuOpen = false;
  bool _rightPanelLoading = false;

  _RightPanelType _rightPanelType = _RightPanelType.none;
  List<Map<String, dynamic>> _friends = [];
  Map<String, int> _unreadByUser = {};
  Map<String, Map<String, dynamic>> _messageSenders = {};
  String? _messageSendersUserId;
  final Set<String> _loadingMessageSenders = {};
  List<Map<String, dynamic>> get _messageContacts => messageContacts(
    _friends, _unreadByUser,
    senders: _messageSendersUserId == supabase.auth.currentUser?.id
        ? _messageSenders.values : const [],
  );

  final Set<String> _notifiedIncomingRequestIds = <String>{};
  final Set<String> _handledTableInviteIds = <String>{};
  List<Map<String, dynamic>> _activeChatMessages = [];
  int _messageLoadGeneration = 0;
  String? _activeChatUserId;
  String? _activeChatUserTableId;
  RealtimeChannel? _tableInviteChannel;
  bool _loadingPendingTableInvites = false;
  bool _handlingTableInvite = false;
  String? _tableInviteBoundUserId;
  RealtimeChannel? _messagesChannel;
  String? _messagesBoundUserId;

  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  Timer? _safetyTimer;
  DateTime? _recordStartTime;
  bool _longPressActive = false;
  String? _recordPath;
  bool _canStop = false;
  bool _isPressing = false;
  DateTime? _pressStartTime;
  String? _previewPath;
  bool _previewPlaying = false;
  bool _showPreview = false;
  bool _showEmojiPicker = false;
  bool _deviceReady = false;
  bool _initCalled = false;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _colorBlindMode = false;
  bool _allowGameInvites = true;
  bool _showGuestBanner = false;
  List<Map<String, dynamic>> _systemMessages = [];
  final Set<String> _seenSystemMessageIds = <String>{};
  String? _lastSystemToastMessageId;
  DateTime? _globalSpectatorPassUntil;
  bool _campaignChecked = false;
  bool _autoResumeAttempted = false;
  static const List<String> _chatEmojis = <String>[
    '??',
    '??',
    '??',
    '??',
    '??',
    '??',
    '??',
    '??',
    '??',
    '??',
    '??',
    '??',
  ];

  int selectedIndex = 0;
  bool isLeagueLocked = false;
  dynamic lockedLeague;

  void _insertEmojiToChat(String emoji) {
    final value = _chatController.value;
    final start = value.selection.start >= 0
        ? value.selection.start
        : value.text.length;
    final end = value.selection.end >= 0 ? value.selection.end : start;
    final newText = value.text.replaceRange(start, end, emoji);
    _chatController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkGuestWelcome();
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() => _playingMessageId = null);
      }
    });
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
    _coinFxController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _coinCountController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..addListener(() {
          final anim = _coinCountAnimation;
          if (anim == null || !mounted) return;
          setState(() => _coinDisplayValue = anim.value);
        });
    _ratingCountController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1100),
        )..addListener(() {
          final anim = _ratingCountAnimation;
          if (anim == null || !mounted) return;
          setState(() => _ratingDisplayValue = anim.value);
        });

    _init();
    _startLobbyLoops();

    _initDevice();
  }

  Future<void> _initDevice() async {
    if (_initCalled) return;
    _initCalled = true;

    try {
      /// ?? UI HEMEN A?ILSIN
      setState(() {
        _deviceReady = true;
      });

      /// ?? REGISTER ARKADA ?ALIŞSIN
      unawaited(_safeRegister());
    } catch (e) {
      print(e);
    }
  }

  Future<void> _safeRegister() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300)); // optional
      await registerDevice();
    } catch (e) {
      print("Device error: $e");
    }
  }

  Future<void> registerDevice() async {
    try {
      await DeviceRegistrationService.registerCurrentDevice();

      /// ?? HATA KONTROL? BURADA
    } catch (e) {
      print(e);

      /// ?? SADECE SIGNOUT + FORWARD

      rethrow; // ?? EN DOĞRU
    }
  }

  Future<void> _checkGuestWelcome() async {
    if (!AuthService.isGuest()) return;

    setState(() {
      _showGuestBanner = true;
    });
  }

  Widget _guestBanner() {
    return LobbyMetalSurface(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, color: Colors.amber, size: 16),
          SizedBox(width: 6),
          Text(
            "Misafir modu",
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          SizedBox(width: 10),

          GestureDetector(
            onTap: _signOutAndGoLogin,
            child: Text(
              "Bağla",
              style: TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stopLobbyLoops();
    _coinFxTimer?.cancel();
    _chatController.dispose();
    _bgController.dispose();
    _coinFxController.dispose();
    _rewardFlight.dispose();
    _rewardAudio?.dispose();
    _coinCountController.dispose();
    _ratingCountController.dispose();
    _audioPlayer.dispose();
    _tableInviteChannel?.unsubscribe();
    _messagesChannel?.unsubscribe();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startLobbyLoops();
      unawaited(_loadTables());
      unawaited(_loadSocialData());
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopLobbyLoops();
    }
  }

  void _startLobbyLoops() {
    if (_lobbyLoopsRunning) return;
    _lobbyLoopsRunning = true;
    _leagueActivityTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadLeagueActivity();
    });
    _socialRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadSocialData();
    });
    _tablesRefreshTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _loadTables(),
    );
    _systemMessageTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _checkUnreadSystemMessages(showToast: true),
    );
    _spectatorPassTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _refreshGlobalSpectatorPassStatus(),
    );
    _tableInvitePollTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _ensureTableInviteListener();
      _ensureMessagesListener();
    });
  }

  void _stopLobbyLoops() {
    _lobbyLoopsRunning = false;
    _rewardFlight.reset();
    _rewardAudio?.stop();
    _leagueActivityTimer?.cancel();
    _leagueActivityTimer = null;
    _socialRefreshTimer?.cancel();
    _socialRefreshTimer = null;
    _tablesRefreshTimer?.cancel();
    _tablesRefreshTimer = null;
    _systemMessageTimer?.cancel();
    _systemMessageTimer = null;
    _spectatorPassTimer?.cancel();
    _spectatorPassTimer = null;
    _tableInvitePollTimer?.cancel();
    _tableInvitePollTimer = null;
    if (_bgController.isAnimating) {
      _bgController.stop();
    }
  }

  Future<void> _init() async {
    await FeedbackSettingsService.load();
    _soundEnabled = FeedbackSettingsService.soundEnabled;
    _vibrationEnabled = FeedbackSettingsService.vibrationEnabled;
    final prefs = await SharedPreferences.getInstance();
    _colorBlindMode = prefs.getBool('color_blind_mode') ?? false;
    UserState.colorBlindMode = _colorBlindMode;

    final canContinue = await _loadUser();
    if (!canContinue) return;
    await _ensureTableInviteListener();
    await _ensureMessagesListener();
    await _refreshGlobalSpectatorPassStatus();
    await _checkOnboarding();
    await _loadSocialData();
    await _loadSystemMessages();
    await _restoreSeenSystemMessages();
    await _checkUnreadSystemMessages(showToast: false);
    await _loadLeagues();
    await _loadLeagueActivity();
    await _loadTables();
    await _runRewardFlowIfNeeded();
    await _tryResumeActiveGame();
    await _checkCampaignPopup();
    final userId = UserState.userId ?? supabase.auth.currentUser?.id;
    if (userId != null) {
      await loadMissedGifts(userId);
    }
  }

  Future<void> _ensureTableInviteListener() async {
    final myUserId = UserState.userId ?? supabase.auth.currentUser?.id;
    if (myUserId == null || myUserId.isEmpty) return;
    if (_tableInviteBoundUserId != myUserId || _tableInviteChannel == null) {
      _bindTableInviteListener(myUserId);
    }
    // Realtime gecikse bile pending davetler mutlaka yakalansın.
    await _loadPendingTableInvites(myUserId);
  }

  Future<void> _runRewardFlowIfNeeded() async {
    if (_rewardFlowRunning) return;
    final user = supabase.auth.currentUser;
    if (user == null || !mounted) return;
    _rewardFlowRunning = true;
    try {
      final dailyAvailable = await _isDailyBonusAvailable(user.id);
      if (!dailyAvailable || !mounted) return;

      var credited = false;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DailyBonusDialog(
          amount: _dailyBonusCoinAmount,
          onClaim: () async {
            final now = DateTime.now();
            final dayKey =
                'daily_bonus:${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
            final claimed = await supabase.rpc(
              'claim_daily_bonus',
              params: {
                'p_user_id': user.id,
                'p_amount': _dailyBonusCoinAmount,
                'p_day_key': dayKey,
              },
            );
            if (claimed != true) {
              return false;
            }
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('daily_bonus_claimed_${user.id}', dayKey);
            credited = true;
            return true;
          },
        ),
      );
      await _loadUser(
        rewardPresentation: credited ? _dailyBonusCoinAmount : null,
      );
    } catch (e) {
      debugPrint('REWARD FLOW ERROR: $e');
    } finally {
      _rewardFlowRunning = false;
    }
  }

  Future<void> _showWelcomeAfterOnboardingIfNeeded(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'onboarding_welcome_shown_$userId';
    if (prefs.getBool(key) == true) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const WelcomeRewardDialog(amount: _welcomeCoinAmount),
    );
    await prefs.setBool(key, true);
    await _loadUser(rewardPresentation: _welcomeCoinAmount);
  }

  Future<bool> _isDailyBonusAvailable(String userId) async {
    final now = DateTime.now();
    final dayKey =
        'daily_bonus:${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final prefs = await SharedPreferences.getInstance();
    final localKey = 'daily_bonus_claimed_$userId';
    if (prefs.getString(localKey) == dayKey) return false;

    final rows = await supabase
        .from('wallet_transactions')
        .select('id')
        .eq('user_id', userId)
        .eq('reason', 'daily_bonus')
        .eq('note', dayKey)
        .limit(1);
    return (rows as List).isEmpty;
  }

  Future<void> _grantCoins({
    required String userId,
    required int amount,
    required String reason,
    String? note,
  }) async {
    final profileRows = await supabase
        .from('profiles')
        .select('coins')
        .eq('id', userId)
        .limit(1);
    final current = (profileRows as List).isNotEmpty
        ? (profileRows.first['coins'] as int?) ?? 0
        : 0;
    final next = current + amount;

    try {
      final payload = <String, dynamic>{
        'user_id': userId,
        'amount': amount,
        'reason': reason,
        'type': 'credit',
        'store': 'system',
      };
      if (note != null && note.trim().isNotEmpty) {
        payload['note'] = note;
      }
      await supabase.from('wallet_transactions').insert(payload);
    } catch (e) {
      // note kolonu olmayan eski şemalarda fallback
      final payload = <String, dynamic>{
        'user_id': userId,
        'amount': amount,
        'reason': reason,
        'type': 'credit',
        'store': 'system',
      };
      await supabase.from('wallet_transactions').insert(payload);
    }

    if ((profileRows).isNotEmpty) {
      await supabase.from('profiles').update({'coins': next}).eq('id', userId);
    }
  }

  Future<void> _ensureMessagesListener() async {
    final myUserId = UserState.userId ?? supabase.auth.currentUser?.id;
    if (myUserId == null || myUserId.isEmpty) return;
    if (_messagesBoundUserId == myUserId && _messagesChannel != null) return;
    _bindMessagesListener(myUserId);
  }

  void _bindMessagesListener(String myUserId) {
    _messagesChannel?.unsubscribe();
    _messagesBoundUserId = myUserId;
    _messagesChannel = supabase.channel('messages-unread-$myUserId');

    _messagesChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: myUserId,
          ),
          callback: (payload) {
            if (!mounted) return;
            final row = Map<String, dynamic>.from(payload.newRecord);
            final senderId = row['sender_id']?.toString();
            final receiverId = row['receiver_id']?.toString();
            final readAt = row['read_at'];
            if (senderId == null ||
                senderId.isEmpty ||
                receiverId != myUserId ||
                readAt != null) {
              return;
            }
            if (_rightPanelType == _RightPanelType.messages &&
                _activeChatUserId == senderId) {
              return;
            }
            setState(() {
              _unreadByUser = Map<String, int>.from(_unreadByUser)
                ..update(senderId, (v) => v + 1, ifAbsent: () => 1);
            });
            if (_rightPanelType == _RightPanelType.messages) {
              unawaited(_ensureMessageSender(senderId, myUserId));
            }
          },
        )
        .subscribe();
  }

  Future<void> _tryResumeActiveGame() async {
    if (_autoResumeAttempted) return;
    _autoResumeAttempted = true;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final playerRows = await supabase
          .from('table_players')
          .select('table_id')
          .eq('user_id', uid);

      final tableIds = (playerRows as List)
          .map((e) => (e as Map<String, dynamic>)['table_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (tableIds.isEmpty) return;

      final activeTables = await supabase
          .from('tables')
          .select('id,status,created_by')
          .inFilter('id', tableIds)
          .inFilter('status', ['waiting', 'start', 'playing'])
          .limit(1);

      final rows = (activeTables as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (rows.isEmpty) return;

      final table = rows.first;
      final tableId = table['id']?.toString();
      if (tableId == null || tableId.isEmpty) return;
      if (!mounted) return;

      final isCreator = table['created_by']?.toString() == uid;
      await _openGame(tableId, isCreator);
    } catch (e) {
      debugPrint('AUTO RESUME ERROR: ');
    }
  }

  void _bindTableInviteListener(String myUserId) {
    _tableInviteChannel?.unsubscribe();
    _tableInviteChannel = supabase.channel('table-invites-$myUserId');
    _tableInviteBoundUserId = myUserId;
    _tableInviteChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'table_invites',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'to_user',
            value: myUserId,
          ),
          callback: (payload) async {
            final invite = Map<String, dynamic>.from(payload.newRecord);
            await _handleIncomingTableInvite(invite);
          },
        )
        .subscribe();
  }

  Future<void> _loadPendingTableInvites(String myUserId) async {
    if (_loadingPendingTableInvites || _handlingTableInvite ||
        ModalRoute.of(context)?.isCurrent != true) return;
    _loadingPendingTableInvites = true;
    try {
      final cutoff = DateTime.now().toUtc().subtract(tableInviteLifetime).toIso8601String();
      try {
        await supabase.from('table_invites').update({'status': 'rejected'})
            .eq('to_user', myUserId).eq('status', 'pending').lt('created_at', cutoff);
      } catch (_) {
        // The read filter still prevents old dialogs if cleanup is denied.
      }
      final rows = await supabase
          .from('table_invites')
          .select('id,table_id,from_user,to_user,status,created_at')
          .eq('to_user', myUserId)
          .eq('status', 'pending')
          .gte('created_at', cutoff)
          .order('created_at', ascending: false)
          .limit(1);
      for (final raw in (rows as List)) {
        if (!mounted || supabase.auth.currentUser?.id != myUserId) return;
        // Only the latest invitation is actionable on return to the lobby.
        try {
          await supabase.from('table_invites').update({'status': 'rejected'})
              .eq('to_user', myUserId).eq('status', 'pending')
              .lte('created_at', raw['created_at']).neq('id', raw['id']);
        } catch (_) {}
        await _handleIncomingTableInvite(Map<String, dynamic>.from(raw));
      }
    } catch (e) {
      debugPrint('PENDING INVITE LOAD ERROR: $e');
    } finally {
      _loadingPendingTableInvites = false;
    }
  }

  Future<void> _handleIncomingTableInvite(Map<String, dynamic> invite) async {
    if (!mounted) return;
    if (_handlingTableInvite || ModalRoute.of(context)?.isCurrent != true ||
        invite['to_user']?.toString() != supabase.auth.currentUser?.id) return;
    final id = invite['id']?.toString();
    if (id == null || id.isEmpty) return;
    if (!_allowGameInvites) {
      try {
        await supabase
            .from('table_invites')
            .update({'status': 'rejected'})
            .eq('id', id)
            .eq('status', 'pending');
      } catch (_) {}
      return;
    }
    if (_handledTableInviteIds.contains(id)) return;
    if ((invite['status']?.toString() ?? 'pending') != 'pending') return;
    _handlingTableInvite = true;
    try {
      final tableId = invite['table_id']?.toString();
      var valid = isFreshTableInvite(invite, DateTime.now()) && tableId != null;
      if (valid) {
        final table = await supabase.from('tables').select('status,max_players')
            .eq('id', tableId!).maybeSingle();
        final seated = await supabase.from('table_players').select('user_id')
            .eq('table_id', tableId);
        valid = table != null && table['status'] == 'waiting' &&
            seated.length < ((table['max_players'] as num?)?.toInt() ?? 2) &&
            seated.any((p) => p['user_id']?.toString() == invite['from_user']?.toString());
      }
      if (!mounted) return;
      if (!valid) {
        _handledTableInviteIds.add(id);
        await supabase.from('table_invites').update({'status': 'rejected'})
            .eq('id', id).eq('to_user', supabase.auth.currentUser!.id).eq('status', 'pending');
        return;
      }
      if (ModalRoute.of(context)?.isCurrent != true) return;
      _handledTableInviteIds.add(id);
      await _showTableInviteDialog(invite);
    } catch (e) {
      debugPrint('TABLE INVITE VALIDATION ERROR: $e');
    } finally {
      _handlingTableInvite = false;
    }
  }

  Future<void> _showTableInviteDialog(Map<String, dynamic> invite) async {
    final inviteId = invite['id']?.toString();
    final fromUserId = invite['from_user']?.toString();
    final tableId = invite['table_id']?.toString();
    if (inviteId == null || fromUserId == null || tableId == null) return;

    String inviterName = 'Oyuncu';
    String? inviterAvatar;
    try {
      final userRow = await supabase
          .from('users')
          .select('username,avatar_url')
          .eq('id', fromUserId)
          .maybeSingle();
      final name = userRow?['username']?.toString().trim() ?? '';
      if (name.isNotEmpty) inviterName = name;
      inviterAvatar = userRow?['avatar_url']?.toString();
    } catch (_) {}

    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xDD171B23), Color(0xCC0D1016)],
                ),
                border: Border.all(color: const Color(0x5CE7C06A), width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: const [
                      Icon(
                        Icons.local_activity_rounded,
                        color: Color(0xFFD9B97A),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Masa Daveti',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0x38202834), Color(0x26131922)],
                      ),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: const Color(0x4DE7C06A),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        LobbyAvatar(
                          username: inviterName,
                          avatarUrl: inviterAvatar,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                color: Color(0xFFD6E1DB),
                                fontSize: 13.5,
                                height: 1.3,
                              ),
                              children: [
                                TextSpan(
                                  text: inviterName,
                                  style: const TextStyle(
                                    color: Color(0xFFE6C788),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const TextSpan(text: ' seni masaya davet etti'),
                                const TextSpan(
                                  text: '. Hemen katılmak ister misin?',
                                  style: TextStyle(color: Color(0xFFBFCBC5)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0x55D7DEE5),
                              width: 1,
                            ),
                            foregroundColor: const Color(0xFFE0E6EB),
                            backgroundColor: const Color(0x2411161E),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: const Text(
                            'Reddet',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD9B97A),
                            foregroundColor: const Color(0xFF2A1A04),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login_rounded, size: 15),
                              SizedBox(width: 6),
                              Text(
                                'Masaya Katıl',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!mounted) return;

    try {
      if (accepted == true && !isFreshTableInvite(invite, DateTime.now())) {
        await supabase.from('table_invites').update({'status': 'rejected'})
            .eq('id', inviteId).eq('status', 'pending');
        if (mounted) _msg('Bu oyun davetinin süresi doldu.');
        return;
      }
      if (accepted == true) {
        await supabase
            .from('table_invites')
            .update({'status': 'accepted'})
            .eq('id', inviteId)
            .eq('status', 'pending');

        final table = await supabase
            .from('tables')
            .select(
              'id,status,entry_coin,league_id,max_players,pot_amount,round_count,turn_seconds',
            )
            .eq('id', tableId)
            .maybeSingle();
        if (table == null) {
          _msg('Masa artık bulunamıyor.');
          return;
        }
        await _joinTable(Map<String, dynamic>.from(table));
      } else {
        await supabase
            .from('table_invites')
            .update({'status': 'rejected'})
            .eq('id', inviteId)
            .eq('status', 'pending');
      }
    } catch (e) {
      _msg('Davet işlenemedi.');
      debugPrint('TABLE INVITE HANDLE ERROR: $e');
    }
  }

  Future<bool> _loadUser({int? rewardPresentation}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return false;
    await ProfileService.ensureUserRow();
    try {
      final row = await ProfileService.findUserRow(
        user,
        columns:
            'id,username,avatar_url,wins,losses,is_banned,ban_reason,ban_until',
      );

      if (row != null) {
        final isBanned = (row['is_banned'] as bool?) ?? false;
        final banReason = (row['ban_reason'] as String?) ?? '';
        final banUntilRaw = row['ban_until'];
        final banUntil = banUntilRaw == null
            ? null
            : DateTime.tryParse(banUntilRaw.toString());

        if (isBanned) {
          final now = DateTime.now();
          final expired = banUntil != null && !banUntil.isAfter(now);
          if (expired) {
            await supabase
                .from('users')
                .update({
                  'is_banned': false,
                  'ban_reason': null,
                  'ban_until': null,
                })
                .eq('id', user.id);
          } else {
            if (!_banScreenOpened && mounted) {
              _banScreenOpened = true;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) =>
                      BannedScreen(reason: banReason, banUntil: banUntil),
                ),
                (_) => false,
              );
            }
            return false;
          }
        }
      }

      // ? profiles'den coins ve rating al
      final profileRows = await supabase
          .from('profiles')
          .select('coins,rating,allow_game_invites')
          .eq('id', user.id)
          .limit(1);
      final profile = (profileRows as List).isNotEmpty
          ? Map<String, dynamic>.from(profileRows.first)
          : null;

      final profileCoin = (profile?['coins'] as int?) ?? 0;
      final profileRating = (profile?['rating'] as int?) ?? 1200;
      final allowGameInvites =
          (profile?['allow_game_invites'] as bool?) ?? true;
      final previousCoin = UserState.userCoin;
      final previousRating = _ratingDisplayValue;

      if (!mounted) return false;
      if (row != null) {
        setState(() {
          UserState.userId = user.id;
          UserState.wins = (row['wins'] as int?) ?? 0; // ? users'dan
          UserState.losses = (row['losses'] as int?) ?? 0; // ? users'dan
          UserState.userRowId = row['id']?.toString();
          UserState.userName =
              ((row['username'] as String?) ?? '').trim().isEmpty
              ? (user.email?.split('@').first ?? 'Oyuncu')
              : row['username'] as String;
          UserState.userRating = profileRating; // ? profiles'den
          UserState.userAvatarUrl = (row['avatar_url'] as String?)?.trim();
          UserState.userCoin = profileCoin; // ? profiles'den
          if (_coinDisplayValue == 0 || previousCoin == 0) {
            _coinDisplayValue = profileCoin;
          }
          _allowGameInvites = allowGameInvites;
        });
      } else {
        setState(() {
          UserState.userId = user.id;
          UserState.wins = 0;
          UserState.losses = 0;
          UserState.userRowId = null;
          UserState.userName = user.email?.split('@').first ?? 'Oyuncu';
          UserState.userRating = profileRating;
          UserState.userAvatarUrl = null;
          UserState.userCoin = profileCoin;
          if (_coinDisplayValue == 0 || previousCoin == 0) {
            _coinDisplayValue = profileCoin;
          }
          _allowGameInvites = allowGameInvites;
        });
      }
      final presentReward =
          rewardPresentation != null &&
          rewardPresentation > 0 &&
          profile != null &&
          profileCoin >= rewardPresentation;
      if (presentReward) {
        _animateCoinCount(
          profileCoin - rewardPresentation,
          profileCoin,
          reward: true,
        );
        _startRewardTransfer();
        _triggerCoinFx();
      } else if (profileCoin != previousCoin) {
        _animateCoinCount(previousCoin, profileCoin);
      }
      if (profileRating != previousRating) {
        _animateRatingCount(previousRating, profileRating);
      }
      if (profileCoin > previousCoin && !presentReward) {
        _triggerCoinFx();
      }
      return true;
    } catch (e) {
      debugPrint('USER LOAD ERROR: $e');
      return false;
    }
  }

  void _triggerCoinFx() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _coinFxTimer?.cancel();
    setState(() => _coinFxActive = true);
    _coinFxController
      ..stop()
      ..reset()
      ..repeat();
    _coinFxTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _coinFxController.stop();
      setState(() => _coinFxActive = false);
    });
  }

  void _startRewardTransfer() {
    if (!mounted || !_lobbyLoopsRunning) return;
    unawaited((_rewardAudio ??= RewardAudio()).play(RewardSound.deposit));
    if (MediaQuery.disableAnimationsOf(context)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_lobbyLoopsRunning) return;
      final scene = _lobbySceneKey.currentContext?.findRenderObject();
      final target = _coinTargetKey.currentContext?.findRenderObject();
      if (scene is! RenderBox ||
          target is! RenderBox ||
          !scene.hasSize ||
          !target.hasSize) {
        return;
      }
      setState(() {
        _flightSource = Offset(scene.size.width * .5, scene.size.height * .42);
        _flightDestination = scene.globalToLocal(
          target.localToGlobal(
            Offset(target.size.width * .18, target.size.height / 2),
          ),
        );
      });
      _rewardFlight.forward(from: 0);
    });
  }

  void _animateCoinCount(int from, int to, {bool reward = false}) {
    if (!mounted) return;
    _coinCountController.stop();
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _coinDisplayValue = to);
      return;
    }
    _coinCountController.duration = Duration(milliseconds: reward ? 1100 : 900);
    _coinCountAnimation = IntTween(begin: from, end: to).animate(
      CurvedAnimation(
        parent: _coinCountController,
        curve: reward
            ? const Interval(.65, 1, curve: Curves.easeOutCubic)
            : Curves.easeOutCubic,
      ),
    );
    _coinDisplayValue = from;
    _coinCountController
      ..reset()
      ..forward();
  }

  void _animateRatingCount(int from, int to) {
    if (!mounted) return;
    _ratingCountController.stop();
    _ratingCountAnimation = IntTween(begin: from, end: to).animate(
      CurvedAnimation(
        parent: _ratingCountController,
        curve: Curves.easeOutCubic,
      ),
    );
    _ratingDisplayValue = from;
    _ratingCountController
      ..reset()
      ..forward();
  }

  Future<void> _checkOnboarding() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await ProfileService.ensureUserRow();
    try {
      final row = await ProfileService.findUserRow(
        user,
        columns: 'id,username,avatar_url',
      );
      if (row == null) return;
      final username = ((row['username'] as String?) ?? '').trim();
      final avatar = ((row['avatar_url'] as String?) ?? '').trim();
      final isGuestLike =
          username.isNotEmpty && username.toLowerCase().startsWith('guest_');
      final isIncomplete = username.isEmpty || avatar.isEmpty || isGuestLike;
      if (isIncomplete) {
        if (!mounted) return;
        await ProfileService.openProfileSetupDialog(
          forceComplete: true,
          onSuccess: () async {
            await _loadUser();
            await _loadSocialData();
            await _loadTables();
          },
        );
        await _showWelcomeAfterOnboardingIfNeeded(user.id);
      }
    } catch (e) {
      debugPrint('ONBOARDING ERROR: $e');
    }
  }

  Future<void> _loadLeagues() async {
    if (!mounted) return;
    setState(() => loadingLeagues = true);
    try {
      final response = await supabase
          .from('leagues')
          .select()
          .order('display_order', ascending: true);

      if (!mounted) return;
      setState(() {
        leagues = (response as List).map((e) {
          final row = Map<String, dynamic>.from(e);
          row['name'] = _normalizeTrText(row['name']?.toString() ?? '');
          return row;
        }).toList();

        if (!leagues.any((l) => l['id'] == selectedLeague)) {
          selectedLeague = leagues.first['id'];
        }
      });
    } catch (e) {
      debugPrint('LEAGUE LOAD ERROR: $e');
      if (!mounted) return;
      setState(() => leagues = []);
    } finally {
      if (mounted) setState(() => loadingLeagues = false);
    }
  }

  Future<void> _loadLeagueActivity() async {
    if (leagues.isEmpty) return;

    try {
      final activeTables = await supabase
          .from('tables')
          .select('id, league_id, status')
          .inFilter('status', lobbyTableStatuses);

      final tableRows = (activeTables as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final seatedPlayers = <Map<String, dynamic>>[];


      if (tableRows.isNotEmpty) {
        final tableIds = tableRows.map((e) => e['id'] as String).toList();

        final players = await supabase
            .from('table_players')
            .select('table_id,user_id')
            .inFilter('table_id', tableIds);

        seatedPlayers.addAll((players as List).map((p) => Map<String, dynamic>.from(p)));
      }

      // Online users by league (based on rating ranges).

      final tableCountByLeague = listedLeagueTableCounts(tableRows, seatedPlayers);
      final tablesResult = <String, int>{};

      for (final league in leagues) {
        final id = league['id']?.toString();
        if (id == null) continue;

        tablesResult[id] = tableCountByLeague[id] ?? 0;
      }

      final onlineProfiles = await supabase
          .from('profiles')
          .select('id,rating')
          .eq('is_online', true);

      final onlineRows = (onlineProfiles as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);

      final accountIds = <String>{
        for (final row in onlineRows) if (row['id'] != null) row['id'].toString(),
        for (final row in seatedPlayers) if (row['user_id'] != null) row['user_id'].toString(),
      }.toList();
      final botIds = <String>{};
      // Bound IN clauses; this uses the existing activity refresh, not a new loop.
      for (var i = 0; i < accountIds.length; i += 200) {
        final chunk = accountIds.sublist(i, min(i + 200, accountIds.length));
        final bots = await supabase.from('users').select('id')
            .eq('is_bot', true).inFilter('id', chunk);
        botIds.addAll((bots as List).map((b) => b['id'].toString()));
      }
      final playersResult = leaguePlayerCounts(
        leagues: leagues, onlineProfiles: onlineRows,
        tables: tableRows, seats: seatedPlayers, botIds: botIds,
      );
      if (!mounted) return;

      setState(() {
        leagueActivePlayers = playersResult;
        leagueActiveTables = tablesResult;
      });
    } catch (e) {
      debugPrint('LEAGUE ACTIVITY ERROR: $e');
    }
  }

  void _mergeTables(List<Map<String, dynamic>> newTables) {
    final existingById = {for (var t in tables) t['id'].toString(): t};

    final newIds = <String>{};

    for (final t in newTables) {
      final id = t['id'].toString();
      newIds.add(id);

      if (existingById.containsKey(id)) {
        existingById[id]!.addAll(t); // UPDATE
      } else {
        tables.add(t); // NEW TABLE
      }
    }

    tables.removeWhere((t) => !newIds.contains(t['id'].toString()));
    bool hasHuman(Map<String, dynamic> table) =>
        ((table['_players'] as List?) ?? const []).any((p) => p['is_bot'] != true);
    tables.sort((a, b) {
      final humanOrder = (hasHuman(a) ? 0 : 1).compareTo(hasHuman(b) ? 0 : 1);
      if (humanOrder != 0) return humanOrder;
      return (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? '');
    });
  }

  Future<void> _cleanupOrphanTables(List<String> orphanTableIds) async {
    if (orphanTableIds.isEmpty) return;

    try {
      await supabase
          .from('match_moves')
          .delete()
          .inFilter('table_id', orphanTableIds);

      /// ?? BURASI S?L?ND? (view oldu?u i?in)

      await supabase
          .from('table_discards')
          .delete()
          .inFilter('table_id', orphanTableIds);

      await supabase
          .from('table_players')
          .delete()
          .inFilter('table_id', orphanTableIds);

      await supabase.from('tables').delete().inFilter('id', orphanTableIds);

      debugPrint(
        'ORPHAN TABLE CLEANUP: ${orphanTableIds.length} masa temizlendi.',
      );
    } catch (e) {
      debugPrint('ORPHAN TABLE CLEANUP ERROR: $e');
    }
  }

  Future<void> _loadTables() async {
    if (!mounted) return;

    if (!_tablesInitialized) {
      setState(() {
        loadingTables = true;
      });
    }
    if (leagues.isEmpty) {
      setState(() {
        tables = [];
        loadingTables = false;
      });
      return;
    }

    try {
      final league = leagues.firstWhere(
        (l) => l['id'] == selectedLeague,
        orElse: () => leagues.first,
      );

      /// ---------------- REAL TABLES ----------------

      final response = await supabase
          .from('tables')
          .select()
          .eq('league_id', league['id'])
          .inFilter('status', lobbyTableStatuses)
          .order('created_at', ascending: false);

      final fetchedRows = (response as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final seenTableIds = <String>{};
      final tableRows = <Map<String, dynamic>>[];
      for (final row in fetchedRows) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty || seenTableIds.contains(id)) continue;
        seenTableIds.add(id);
        tableRows.add(row);
      }

      final tableIds = tableRows.map((e) => e['id'] as String).toList();

      final playersByTable = <String, List<Map<String, dynamic>>>{};
      final allUserIds = <String>{};

      if (tableIds.isNotEmpty) {
        final playerRows = await supabase
            .from('table_players')
            .select('table_id,user_id,seat_index')
            .inFilter('table_id', tableIds);

        for (final raw in (playerRows as List)) {
          final row = Map<String, dynamic>.from(raw);
          final tableId = row['table_id']?.toString();
          final userId = row['user_id']?.toString();

          if (tableId == null) continue;

          if (userId != null) allUserIds.add(userId);

          playersByTable.putIfAbsent(tableId, () => []).add(row);
        }
      }

      final orphanTableIds = tableRows
          .map((t) => t['id']?.toString())
          .whereType<String>()
          .where((id) => (playersByTable[id] ?? const []).isEmpty)
          .toList();
      if (orphanTableIds.isNotEmpty) {
        await _cleanupOrphanTables(orphanTableIds);
        tableRows.removeWhere(
          (t) => orphanTableIds.contains(t['id']?.toString()),
        );
      }

      final usernameById = <String, String>{};
      final avatarById = <String, String?>{};
      final ratingById = <String, int>{};
      final isBotById = <String, bool>{};

      if (allUserIds.isNotEmpty) {
        final users = await supabase
            .from('users')
            .select('id,username,avatar_url,is_bot')
            .inFilter('id', allUserIds.toList());
        final profiles = await supabase
            .from('profiles')
            .select('id,rating')
            .inFilter('id', allUserIds.toList());
        for (final raw in (profiles as List)) {
          final row = Map<String, dynamic>.from(raw);
          final id = row['id']?.toString();
          if (id == null || id.isEmpty) continue;
          ratingById[id] = (row['rating'] as int?) ?? 1200;
        }

        for (final raw in (users as List)) {
          final row = Map<String, dynamic>.from(raw);
          final id = row['id']?.toString();
          if (id == null) continue;

          final name = ((row['username'] as String?) ?? '').trim();

          usernameById[id] = name.isEmpty ? 'Oyuncu' : name;
          avatarById[id] = row['avatar_url']?.toString();
          isBotById[id] = row['is_bot'] == true;
        }
      }

      // Keep bot-only waiting tables visible in lobby.
      // Only truly orphan tables (no players) are cleaned above.

      final merged = tableRows.map((table) {
        final tableId = table['id']?.toString();
        final players = <Map<String, dynamic>>[];

        if (tableId != null) {
          for (final p in (playersByTable[tableId] ?? [])) {
            final uid = p['user_id']?.toString();

            players.add({
              'seat_index': p['seat_index'],
              'user_id': uid,
              'username': uid == null
                  ? 'Oyuncu'
                  : (usernameById[uid] ?? 'Oyuncu'),
              'avatar_url': uid == null ? null : avatarById[uid],
              'is_bot': uid != null && isBotById[uid] == true,
              'rating': uid == null ? 1200 : (ratingById[uid] ?? 1200),
              'blocked': uid != null && UserState.blockedUserIds.contains(uid),
            });
          }
        }

        /// COIN FIX
        final coinOptions = [100, 200, 300, 500, 1000];

        table['entry_coin'] =
            (table['entry_coin'] as int?) ??
            coinOptions[Random().nextInt(coinOptions.length)];

        table['_players'] = players;

        return table;
      }).toList();

      if (!mounted) return;

      setState(() {
        _mergeTables(merged);
        loadingTables = false;
        _tablesInitialized = true;
      });

      await _loadLeagueActivity();
    } catch (e) {
      debugPrint('TABLE LOAD ERROR: $e');

      if (!mounted) return;

      setState(() {
        tables = [];
        loadingTables = false;
      });
    }
  }

  Future<void> _createTable({
    required Map<String, dynamic> league,
    required int entry,
    required int turnSeconds,
    required bool spectatorsEnabled,
    required bool chatEnabled,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _msg('Oturum bulunamadı.');
      return;
    }
    if (leagues.isEmpty) {
      _msg('Lig bilgisi yüklenemedi.');
      return;
    }

    if (UserState.userCoin < entry) return _msg('Yetersiz coin.');
    if (UserState.userRating < ((league['min_rating'] as int?) ?? 0)) {
      return _msg('Bu lig için seviye yetersiz.');
    }

    try {
      final payload = tableCreationPayload(
        league: league,
        userId: user.id,
        entry: entry,
        turnSeconds: turnSeconds,
        spectatorsEnabled: spectatorsEnabled,
        chatEnabled: chatEnabled,
      );
      final table = await supabase
          .from('tables')
          .insert(payload)
          .select()
          .single();

      final tableId = table['id'] as String;
      await supabase.from('table_players').insert({
        'table_id': tableId,
        'user_id': user.id,
        'seat_index': 0,
      });

      if (!mounted) return;
      await _openGame(tableId, true);
    } catch (e) {
      debugPrint('CREATE TABLE ERROR: $e');
      if (!mounted) return;
      _msg('Masa açılırken bir hata oluştu.');
    }
  }

  Future<void> _joinTable(Map<String, dynamic> table) async {
    if (table['is_fake'] == true) {
      _msg('Bu masa vitrin masasıdır. Katılım kapalı.');
      return;
    }
    final user = supabase.auth.currentUser;
    final tableId = table['id'] as String?;
    if (user == null || tableId == null) return;
    // Use fresh server status to avoid stale lobby card state
    // (can look empty but still carry old local "playing" flag).
    var status = table['status']?.toString() ?? 'waiting';
    String? createdBy = table['created_by']?.toString();
    try {
      final latest = await supabase
          .from('tables')
          .select('status,created_by')
          .eq('id', tableId)
          .maybeSingle();
      if (latest != null) {
        status = (latest['status']?.toString() ?? status).trim();
        createdBy = latest['created_by']?.toString() ?? createdBy;
      }
    } catch (_) {
      // If fetch fails, keep current fallback status.
    }

    var serverManaged = false;
    if (status == 'waiting' && createdBy != null && createdBy != user.id) {
      try {
        serverManaged = await ReadyTableService(supabase).isManaged(tableId);
      } catch (_) {
        _msg('Masa bilgisi doğrulanamadı. Lütfen tekrar dene.');
        return;
      }
    }
    // Fast stale-owner guard:
    // If table owner is stale/offline, close waiting table immediately
    // so users do not get stuck trying to join a dead table.
    if (status == 'waiting' &&
        !serverManaged &&
        createdBy != null &&
        createdBy!.isNotEmpty &&
        createdBy != user.id) {
      try {
        final owner = await supabase
            .from('profiles')
            .select('is_online,last_seen_at')
            .eq('id', createdBy!)
            .maybeSingle();
        final ownerOnline = owner?['is_online'] == true;
        final lastSeenRaw = owner?['last_seen_at']?.toString();
        final lastSeen = lastSeenRaw == null
            ? null
            : DateTime.tryParse(lastSeenRaw)?.toUtc();
        final stale =
            !ownerOnline ||
            (lastSeen != null &&
                DateTime.now().toUtc().difference(lastSeen) >
                    const Duration(seconds: 75));
        if (stale) {
          await _cleanupOrphanTables([tableId]);
          await _loadTables();
          _msg('Masa sahibi bağlantıda değil. Masa otomatik kapatıldı.');
          return;
        }
      } catch (_) {
        // If guard check fails, continue normal join flow.
      }
    }

    if (status == 'playing') {
      _msg('Bu masa şu anda oyunda. İzlemek için İZLE butonunu kullan.');
      await _loadTables();
      return;
    }
    if (status != 'waiting') {
      _msg('Bu masa oyuna hazırlanıyor.');
      return;
    }
    final entry = (table['entry_coin'] as int?) ?? 100;
    if (UserState.userCoin < entry) return _msg('Yetersiz coin.');
    final tableRating = await supabase
        .from('leagues')
        .select('min_rating')
        .eq('id', table['league_id'])
        .limit(1);
    if ((tableRating as List).isNotEmpty) {
      final minRating = (tableRating.first['min_rating'] as int?) ?? 0;
      if (UserState.userRating < minRating) {
        return _msg('Bu lig için seviye yetersiz.');
      }
    }

    final rows = await supabase
        .from('table_players')
        .select('user_id,seat_index')
        .eq('table_id', tableId);
    final players = (rows as List)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final alreadyJoined = players.any((p) => p['user_id'] == user.id);
    if (!alreadyJoined) {
      final maxPlayers = (table['max_players'] as int?) ?? 4;
      final occupied = players
          .map((e) => e['seat_index'] as int?)
          .whereType<int>()
          .toSet();
      int? seat;
      for (var i = 0; i < maxPlayers; i++) {
        if (!occupied.contains(i)) {
          seat = i;
          break;
        }
      }
      if (seat == null) return _msg('Masa dolu.');
      await supabase.from('table_players').insert({
        'table_id': tableId,
        'user_id': user.id,
        'seat_index': seat,
      });
    }
    if (!mounted) return;
    await _openGame(tableId, false);
  }

  Future<void> _openGame(String tableId, bool isCreator) async {
    await precacheImage(
      const AssetImage('assets/images/lobby/lobby.png'),
      context,
    );
    await precacheImage(const AssetImage('assets/images/table.png'), context);
    if (!mounted) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) =>
            OkeyGameScreen(tableId: tableId, isCreator: isCreator),
        transitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _msg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  bool get _hasGlobalSpectatorPass {
    final until = _globalSpectatorPassUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  String _globalSpectatorPassRemainingText() {
    final until = _globalSpectatorPassUntil;
    if (until == null) return 'Pasif';
    final diff = until.difference(DateTime.now());
    if (diff.isNegative) return 'Pasif';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return '${h}s ${m}dk';
  }

  Future<void> _refreshGlobalSpectatorPassStatus() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await supabase
          .from('wallet_transactions')
          .select('created_at,note')
          .eq('user_id', uid)
          .eq('reason', 'spectator_pass_purchase')
          .order('created_at', ascending: false)
          .limit(20);
      DateTime? bestUntil;
      for (final row in (rows as List)) {
        final note = row['note']?.toString() ?? '';
        DateTime? until;
        if (note.startsWith('spectator_pass_until:')) {
          final raw = note.split(':').skip(1).join(':').trim();
          until = DateTime.tryParse(raw)?.toLocal();
        }
        until ??= DateTime.tryParse(
          row['created_at']?.toString() ?? '',
        )?.toLocal().add(const Duration(hours: 24));
        if (until == null) continue;
        if (bestUntil == null || until.isAfter(bestUntil)) {
          bestUntil = until;
        }
      }
      if (!mounted) return;
      setState(() {
        _globalSpectatorPassUntil = bestUntil;
      });
    } catch (_) {}
  }

  Future<bool> _purchaseGlobalSpectatorPass() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    if (UserState.userCoin < _globalSpectatorPassCost) {
      _msg('Yetersiz coin. Gereken: $_globalSpectatorPassCost');
      return false;
    }
    final base =
        (_globalSpectatorPassUntil != null &&
            _globalSpectatorPassUntil!.isAfter(DateTime.now()))
        ? _globalSpectatorPassUntil!
        : DateTime.now();
    final until = base.add(const Duration(hours: 24));
    try {
      await ProfileService.spendProfileCoins(
        userId: uid,
        amount: _globalSpectatorPassCost,
        reason: 'spectator_pass_purchase',
        note: 'spectator_pass_until:${until.toUtc().toIso8601String()}',
      );
      await _loadUser();
      await _refreshGlobalSpectatorPassStatus();
      _msg(
        'Genel seyirci gecisi aktif. Kalan: ${_globalSpectatorPassRemainingText()}',
      );
      return true;
    } catch (_) {
      _msg('Satin alma basarisiz.');
      return false;
    }
  }

  bool _tableHasFriendPlayer(Map<String, dynamic> table) {
    final players = ((table['_players'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    for (final p in players) {
      final uid = p['user_id']?.toString();
      if (uid != null && UserState.friendIds.contains(uid)) return true;
    }
    return false;
  }

  Future<void> _handleSpectateTap(Map<String, dynamic> table) async {
    final tableId = table['id']?.toString();
    if (tableId == null || tableId.isEmpty) return;
    final status = table['status']?.toString() ?? 'waiting';
    if (status != 'playing') {
      return _joinTable(table);
    }
    final hasFriendAtTable = _tableHasFriendPlayer(table);
    if (hasFriendAtTable || _hasGlobalSpectatorPass) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SpectatorScreen(tableId: tableId)),
      );
      return;
    }
    await _showSpectatorPassOfferDialog(tableId);
  }

  Future<void> _showSpectatorPassOfferDialog(String tableId) async {
    final shouldBuy = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.75),
      builder: (context) => ProfileActionScene(
        title: 'Genel Seyirci Geçişi',
        subtitle: '24 saat boyunca tüm masaları keşfet',
        icon: Icons.visibility_rounded,
        action: 'SATIN AL · ${Format.coin(_globalSpectatorPassCost)} COIN',
        onClose: () => Navigator.pop(context, false),
        onSubmit: () => Navigator.pop(context, true),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x66232B34),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x447D8993)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.access_time_rounded,
                      color: Color(0xFFE5C585), size: 22),
                  SizedBox(width: 10),
                  Expanded(child: Text('24 SAAT · TÜM MASALAR',
                    style: TextStyle(color: Color(0xFFF3E7D0),
                      fontSize: 16, fontWeight: FontWeight.w700))),
                ]),
                SizedBox(height: 14),
                Text(
                  'Arkadaşlarının masalarını ücretsiz izleyebilirsin. '
                  'Genel Seyirci Geçişi ile 24 saat boyunca tüm masaları izleyebilirsin.',
                  style: TextStyle(color: Color(0xFFBAC2CC),
                    fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (shouldBuy != true) return;
    final ok = await _purchaseGlobalSpectatorPass();
    if (!ok || !_hasGlobalSpectatorPass || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SpectatorScreen(tableId: tableId)),
    );
  }

  Future<void> _loadSystemMessages() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await supabase
          .from('system_messages')
          .select('id,title,body,type,created_at,target_user_id,is_active')
          .or('target_user_id.is.null,target_user_id.eq.$uid')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(50);
      if (!mounted) return;
      setState(() {
        _systemMessages = (rows as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {
      // Table may not exist yet in some environments.
      if (!mounted) return;
      setState(() => _systemMessages = []);
    }
  }

  Future<void> _restoreSeenSystemMessages() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList('system_seen_$uid') ?? const <String>[];
    _seenSystemMessageIds
      ..clear()
      ..addAll(values);
  }

  Future<void> _persistSeenSystemMessages() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'system_seen_$uid',
      _seenSystemMessageIds.toList()..sort(),
    );
  }

  Future<void> _markVisibleSystemMessagesAsSeen() async {
    var changed = false;
    for (final row in _systemMessages) {
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty && !_seenSystemMessageIds.contains(id)) {
        _seenSystemMessageIds.add(id);
        changed = true;
      }
    }
    if (changed) {
      await _persistSeenSystemMessages();
      _lastSystemToastMessageId = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> _checkUnreadSystemMessages({required bool showToast}) async {
    await _loadSystemMessages();
    final unreadIds = <String>[];
    for (final row in _systemMessages) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      if (!_seenSystemMessageIds.contains(id)) {
        unreadIds.add(id);
      }
    }
    if (unreadIds.isEmpty) {
      _lastSystemToastMessageId = null;
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      return;
    }
    if (!showToast || !mounted) return;
    final newestId = unreadIds.first;
    if (_lastSystemToastMessageId == newestId) return;
    _lastSystemToastMessageId = newestId;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Yeni sistem duyurusu var.'),
        backgroundColor: const Color(0xD915191F),
        action: SnackBarAction(
          label: 'A\u00E7',
          textColor: const Color(0xFFE7C06A),
          onPressed: () async {
            await _showSystemMessagesDialog();
          },
        ),
      ),
    );
  }

  Future<void> _openSupportRequestDialog() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final messageController = TextEditingController();
    String category = 'talep';
    String? errorText;
    bool sending = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !sending,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> submit() async {
              if (sending) return;
              final message = messageController.text.trim();
              if (message.length < 8) {
                setLocalState(() {
                  errorText =
                      'L\u00FCtfen en az 8 karakter a\u00E7\u0131klama yaz.';
                });
                return;
              }
              setLocalState(() {
                sending = true;
                errorText = null;
              });
              try {
                await supabase.from('support_requests').insert({
                  'user_id': uid,
                  'category': category,
                  'message': message,
                  'status': 'open',
                  'reported_user_id': '',
                });
                if (!mounted || !context.mounted) return;
                Navigator.pop(context);
                _msg('Talebiniz alınmıştır.');
              } catch (_) {
                if (!context.mounted) return;
                setLocalState(() {
                  sending = false;
                  errorText = 'Mesajın gönderilemedi. Lütfen tekrar dene.';
                });
              }
            }

            return GameSupportScene(
              message: messageController,
              category: category,
              sending: sending,
              error: errorText,
              onCategory: (value) => setLocalState(() => category = value),
              onSend: submit,
              onClose: () => Navigator.pop(context),
            );
          },
        );
      },
    );
    messageController.dispose();
  }

  Future<void> _showSystemMessagesDialog() async {
    await _loadSystemMessages();
    await _markVisibleSystemMessagesAsSeen();
    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: Container(
            width: 600,
            constraints: const BoxConstraints(maxHeight: 620),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xEE171B23), Color(0xDD0D1016)],
              ),
              border: Border.all(color: const Color(0x66E7C06A), width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFFFFE0A8),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Sistem Duyurular\u0131',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: _systemMessages.isEmpty
                      ? const Center(
                          child: Text(
                            'G\u00F6sterilecek duyuru yok.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _systemMessages.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 7),
                          itemBuilder: (_, i) {
                            final row = _systemMessages[i];
                            final title = _normalizeTrText(
                              row['title']?.toString().trim() ?? '',
                            );
                            final body = _normalizeTrText(
                              row['body']?.toString().trim() ?? '',
                            );
                            final type = row['type']?.toString().trim();
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0x33303844),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0x335B6778),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title.isNotEmpty ? title : 'Duyuru',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                      if (type != null && type.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0x33E7C06A),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            type.toUpperCase(),
                                            style: const TextStyle(
                                              color: Color(0xFFFFE0A8),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    body?.isNotEmpty == true ? body! : '-',
                                    style: const TextStyle(
                                      color: Color(0xFFD9EBDD),
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
    // Dialog kapandıktan sonra tekrar kontrol et, rozet/snackbar state'i temiz kalsın.
    await _checkUnreadSystemMessages(showToast: false);
  }

  Future<void> _checkCampaignPopup() async {
    if (_campaignChecked) return;
    _campaignChecked = true;
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || !mounted) return;
    try {
      final nowIso = DateTime.now().toIso8601String();
      final rows = await supabase
          .from('campaigns')
          .select('id,image_url,title,is_active,start_at,end_at,priority')
          .eq('is_active', true)
          .lte('start_at', nowIso)
          .gte('end_at', nowIso)
          .order('priority', ascending: false)
          .limit(1);
      if ((rows as List).isEmpty) return;
      final campaign = Map<String, dynamic>.from(rows.first);
      final campaignId = campaign['id']?.toString();
      if (campaignId == null || campaignId.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final localKey = 'campaign_seen_${uid}_$campaignId';
      if (prefs.getBool(localKey) == true) return;

      bool seenInDb = false;
      try {
        final seenRows = await supabase
            .from('campaign_views')
            .select('id')
            .eq('campaign_id', campaignId)
            .eq('user_id', uid)
            .limit(1);
        seenInDb = (seenRows as List).isNotEmpty;
      } catch (_) {
        seenInDb = false;
      }
      if (seenInDb) {
        await prefs.setBool(localKey, true);
        return;
      }

      if (!mounted) return;
      await _showCampaignDialog(campaign);

      await prefs.setBool(localKey, true);
      try {
        await supabase.from('campaign_views').insert({
          'campaign_id': campaignId,
          'user_id': uid,
          'seen_at': DateTime.now().toIso8601String(),
        });
      } catch (_) {}
    } catch (_) {
      // Table may not exist yet in some environments.
    }
  }

  Future<void> _showCampaignDialog(Map<String, dynamic> campaign) async {
    final imageUrl = campaign['image_url']?.toString().trim() ?? '';
    final title = campaign['title']?.toString().trim();
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF111A16),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xCCB07A1A),
                    width: 1.8,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null && title.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: imageUrl.startsWith('http')
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0x3324362E),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'Kampanya g\u00F6rseli y\u00FCklenemedi.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              )
                            : Container(
                                color: const Color(0x3324362E),
                                alignment: Alignment.center,
                                child: const Text(
                                  'Kampanya g\u00F6rseli yok.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _toggleSideMenu() {
    setState(() => _isSideMenuOpen = !_isSideMenuOpen);
  }

  void _closeSideMenu() {
    if (_isSideMenuOpen) {
      setState(() => _isSideMenuOpen = false);
    }
  }

  int get _friendCount => _friends.length;
  int get _unreadTotal =>
      _unreadByUser.values.fold(0, (sum, value) => sum + value);

  Future<void> _ensureMessageSender(String senderId, String uid) async {
    if (_friends.any((f) => f['id']?.toString() == senderId) ||
        (_messageSendersUserId == uid && _messageSenders.containsKey(senderId))) return;
    final key = '$uid:$senderId';
    if (!_loadingMessageSenders.add(key)) return;
    try {
      final rows = await supabase.from('users').select('id,username,avatar_url')
          .eq('id', senderId).limit(1);
      if (!mounted || supabase.auth.currentUser?.id != uid || rows.isEmpty) return;
      setState(() {
        if (_messageSendersUserId != uid) _messageSenders = {};
        _messageSendersUserId = uid;
        _messageSenders[senderId] = Map<String, dynamic>.from(rows.first);
      });
    } catch (_) {
      // Keep the incoming conversation accessible even if identity lookup fails.
    } finally {
      _loadingMessageSenders.remove(key);
    }
  }

  Future<void> _loadSocialData() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final previousIncoming = Set<String>.from(UserState.incomingRequestIds);

      final friendshipRows = await supabase
          .from('friends')
          .select('id,user_id,friend_id,status,created_at')
          .or('user_id.eq.$uid,friend_id.eq.$uid');

      final rows = (friendshipRows as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final counterpartIds = <String>{};
      final friendIds = <String>{};
      final blockedIds = <String>{};
      final incomingRequestIds = <String>{};
      final outgoingRequestIds = <String>{};
      final friendTableID = <String, String>{};
      for (final row in rows) {
        final tableid = row['id'].toString();
        final userId = row['user_id']?.toString();
        final friendId = row['friend_id']?.toString();
        final status = row['status']?.toString() ?? 'pending';
        if (userId == null || friendId == null) continue;

        final isOutgoing = userId == uid;
        final otherId = isOutgoing ? friendId : userId;
        counterpartIds.add(otherId);

        if (status == 'accepted') {
          friendIds.add(otherId);
          friendTableID[otherId] = tableid;
        } else if (status == 'blocked' && isOutgoing) {
          blockedIds.add(otherId);
        } else if (status == 'pending' && isOutgoing) {
          outgoingRequestIds.add(otherId);
        } else if (status == 'pending' && !isOutgoing) {
          incomingRequestIds.add(otherId);
        }
      }

      /// USERS
      final usersById = <String, Map<String, dynamic>>{};
      final profileRatingById = <String, int>{};
      final profileOnlineById = <String, bool>{};
      final profileLastSeenById = <String, DateTime?>{};
      if (counterpartIds.isNotEmpty) {
        final userRows = await supabase
            .from('users')
            .select('id,username,avatar_url')
            .inFilter('id', counterpartIds.toList());
        final profileRows = await supabase
            .from('profiles')
            .select('id,rating,is_online,last_seen_at')
            .inFilter('id', counterpartIds.toList());

        for (final raw in (userRows as List)) {
          final row = Map<String, dynamic>.from(raw);
          final id = row['id']?.toString();
          if (id != null) usersById[id] = row;
        }
        for (final raw in (profileRows as List)) {
          final row = Map<String, dynamic>.from(raw);
          final id = row['id']?.toString();
          if (id == null || id.isEmpty) continue;
          profileRatingById[id] = (row['rating'] as int?) ?? 1200;
          final lastSeenRaw = row['last_seen_at']?.toString();
          final serverOnline = (row['is_online'] as bool?) ?? false;
          profileOnlineById[id] = PresenceService.effectiveOnline(
            isOnlineFlag: serverOnline,
            lastSeenRaw: lastSeenRaw,
          );
          profileLastSeenById[id] = lastSeenRaw == null
              ? null
              : DateTime.tryParse(lastSeenRaw)?.toLocal();
        }
      }

      /// Prefer a live player seat; otherwise follow the friend's watched table.
      final friendTables = <String, String>{};
      final friendTableRoles = <String, String>{};
      final spectatorsEnabledByTableId = <String, bool>{};
      if (friendIds.isNotEmpty) {
        final seated = await supabase.from('table_players')
            .select('user_id,table_id').inFilter('user_id', friendIds.toList());
        List<dynamic> watching = [];
        try {
          watching = await supabase.from('table_spectators')
              .select('user_id,table_id').inFilter('user_id', friendIds.toList());
        } catch (_) {
          // Preserve seated friends if spectator presence is not readable.
        }
        final ids = [...seated, ...watching].map((r) => r['table_id']?.toString())
            .whereType<String>().toSet().toList();
        final active = <String>{};
        if (ids.isNotEmpty) {
          final rows = await supabase.from('tables').select('id,status,spectators_enabled')
              .inFilter('id', ids);
          for (final row in rows) {
            final id = row['id'].toString();
            if (!{'waiting', 'start', 'starting', 'playing'}.contains(row['status'])) continue;
            active.add(id);
            spectatorsEnabledByTableId[id] = row['spectators_enabled'] == true;
          }
        }
        for (final role in ['player', 'spectator']) {
          for (final row in role == 'player' ? seated : watching) {
            final user = row['user_id']?.toString();
            final id = row['table_id']?.toString();
            if (user == null || id == null || !active.contains(id) || friendTables.containsKey(user)) continue;
            friendTables[user] = id;
            friendTableRoles[user] = role;
          }
        }
      }
      /// FRIEND LIST
      final friendList = <Map<String, dynamic>>[];

      for (final friendId in friendIds) {
        final user = usersById[friendId];

        friendList.add({
          'id': friendId,
          'friendid': friendTableID[friendId],
          'username': ((user?['username'] as String?) ?? '').trim().isEmpty
              ? 'Oyuncu'
              : user!['username'],
          'avatar_url': user?['avatar_url'],
          'rating': profileRatingById[friendId] ?? 1200,
          'is_online': profileOnlineById[friendId] ?? false,
          'last_seen_at': profileLastSeenById[friendId],
          'blocked': blockedIds.contains(friendId),

          /// EKLENEN
          'table_id': friendTables[friendId],
          'table_role': friendTableRoles[friendId],
          'table_spectators_enabled': (() {
            final tableId = friendTables[friendId];
            if (tableId == null || tableId.isEmpty) return true;
            return spectatorsEnabledByTableId[tableId] ?? true;
          })(),
        });
      }

      friendList.sort(
        (a, b) => (a['username'] as String).toLowerCase().compareTo(
          (b['username'] as String).toLowerCase(),
        ),
      );

      /// UNREAD MESSAGES
      final unreadRows = await supabase
          .from('messages')
          .select('sender_id')
          .eq('receiver_id', uid)
          .isFilter('read_at', null);

      final unread = <String, int>{};

      for (final raw in (unreadRows as List)) {
        final senderId = (raw as Map<String, dynamic>)['sender_id']?.toString();
        if (senderId == null) continue;
        unread.update(senderId, (v) => v + 1, ifAbsent: () => 1);
      }

      final senders = _messageSendersUserId == uid
          ? Map<String, Map<String, dynamic>>.from(_messageSenders)
          : <String, Map<String, dynamic>>{};
      final missingSenders = unread.keys.where((id) =>
          !friendIds.contains(id) && !senders.containsKey(id)).toList();
      if (missingSenders.isNotEmpty) {
        try {
          final rows = await supabase.from('users').select('id,username,avatar_url')
              .inFilter('id', missingSenders);
          for (final row in rows) {
            final sender = Map<String, dynamic>.from(row);
            senders[sender['id'].toString()] = sender;
          }
        } catch (_) {
          // Identity failure must not hide incoming unread conversations.
        }
      }
      if (!mounted || supabase.auth.currentUser?.id != uid) return;

      setState(() {
        UserState.userId = uid;
        _friends = friendList;
        UserState.friendIds = friendIds;
        UserState.blockedUserIds = blockedIds;
        UserState.incomingRequestIds = incomingRequestIds;
        UserState.outgoingRequestIds = outgoingRequestIds;
        _unreadByUser = unread;
        _messageSenders = {
          if (_messageSendersUserId == uid) ..._messageSenders,
          ...senders,
        };
        _messageSendersUserId = uid;
      });

      _notifiedIncomingRequestIds.removeWhere(
        (id) => !incomingRequestIds.contains(id),
      );

      final newIncoming = incomingRequestIds
          .where(
            (id) =>
                !previousIncoming.contains(id) &&
                !_notifiedIncomingRequestIds.contains(id),
          )
          .toList();

      if (newIncoming.isNotEmpty) {
        final requesterId = newIncoming.first;
        _notifiedIncomingRequestIds.add(requesterId);
        unawaited(
          ProfileService.showIncomingFriendRequestDialog(
            context,
            requesterId,
            usersById[requesterId],
          ),
        );
      }
    } catch (e) {
      debugPrint('SOCIAL LOAD ERROR: $e');
    }
  }

  Future<void> _openRightPanel(
    _RightPanelType type, {
    String? initialChatUserId,
  }) async {
    if (!mounted) return;
    _messageLoadGeneration++;
    setState(() {
      _rightPanelType = type;
      _rightPanelLoading = false;
    });

    await _loadSocialData();

    if (type == _RightPanelType.messages) {
      final contacts = _messageContacts;
      final targetUserId = initialMessageContact(contacts, _unreadByUser,
          requested: initialChatUserId, active: _activeChatUserId);
      final targetFriend = contacts.where((friend) => friend['id']?.toString() == targetUserId).firstOrNull;
      if (targetUserId != null) {
        await _loadMessagesWith(targetUserId, targetFriend?['friendid']?.toString() ?? '', markRead: true);
      }
    }
  }

  void _closeRightPanel() {
    _messageLoadGeneration++;
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _isPressing = false;
    if (_isRecording) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 300), () async {
        if (mounted && _rightPanelType != _RightPanelType.messages) await _stopRecording(send: false);
      }));
    }
    setState(() {
      _rightPanelType = _RightPanelType.none;
      _showEmojiPicker = false;
    });
  }

  Future<void> _loadMessagesWith(
    String otherUserId,
    String friendtableid, {
    bool markRead = true,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    if (_rightPanelType != _RightPanelType.messages) return;
    final generation = ++_messageLoadGeneration;
    bool currentRequest() => mounted && generation == _messageLoadGeneration &&
        _rightPanelType == _RightPanelType.messages && _activeChatUserId == otherUserId &&
        supabase.auth.currentUser?.id == uid;

    setState(() {
      _rightPanelLoading = true;
      _activeChatUserId = otherUserId;
      _activeChatUserTableId = friendtableid;
    });

    try {
      final rows = await supabase
          .from('messages')
          .select(
            'id,sender_id,receiver_id,content,created_at,read_at,type,voice_url,duration',
          )
          .or(
            'and(sender_id.eq.$uid,receiver_id.eq.$otherUserId),and(sender_id.eq.$otherUserId,receiver_id.eq.$uid)',
          )
          .order('created_at', ascending: true);

      if (!currentRequest()) return;
      if (markRead) {
        await supabase
            .from('messages')
            .update({'read_at': DateTime.now().toIso8601String()})
            .eq('sender_id', otherUserId)
            .eq('receiver_id', uid)
            .isFilter('read_at', null);
      }

      if (!currentRequest()) return;
      setState(() {
        _activeChatMessages = (rows as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _rightPanelLoading = false;
        if (markRead) {
          _unreadByUser = Map<String, int>.from(_unreadByUser)
            ..remove(otherUserId);
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(animated: false);
      });
    } catch (e) {
      debugPrint('MESSAGE LOAD ERROR: $e');
      if (!currentRequest()) return;
      setState(() => _rightPanelLoading = false);
    }
  }

  Future<void> _sendMessage() async {
    final uid = UserState.userId ?? supabase.auth.currentUser?.id;
    final otherId = _activeChatUserId;
    final ftableid = _activeChatUserTableId ?? "";
    final text = _chatController.text.trim();
    if (uid == null || otherId == null || text.isEmpty) return;
    if (!UserState.friendIds.contains(otherId)) {
      return _msg('Sadece arkadaşlara mesaj gönderebilirsin.');
    }
    try {
      await supabase.from('messages').insert({
        'sender_id': uid,
        'receiver_id': otherId,
        'content': text,
      });
      _chatController.clear();
      await _loadMessagesWith(otherId, ftableid, markRead: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      _msg('Mesaj gönderilemedi.');
      debugPrint('SEND MESSAGE ERROR: $e');
    }
  }

  Future<void> _showCreateModal() async {
    if (leagues.isEmpty) {
      _msg('Lig bilgisi yüklenemedi.');
      return;
    }
    final league = leagues.firstWhere(
      (l) => l['id'] == selectedLeague,
      orElse: () => leagues.first,
    );
    final minCoin = (league['min_coin'] as num?)?.toInt() ?? 100;
    final maxCoin = (league['max_coin'] as num?)?.toInt() ?? minCoin;
    final minRating = (league['min_rating'] as num?)?.toInt() ?? 0;
    if (UserState.userCoin < minCoin || UserState.userRating < minRating) {
      final result = await openStoreScreen(
        context,
        initialCoin: UserState.userCoin,
      );
      if (!mounted) return;
      if (result == true) await _loadUser();
      return;
    }

    try {
      coinOptions = buildTableStakes(minCoin, maxCoin);
    } on ArgumentError {
      _msg('Ligin giriş bedeli aralığı geçersiz.');
      return;
    }
    selectedIndex = 0;
    draftTurnSeconds = 20;
    var spectator = createSpectatorEnabled;
    var chat = createChatEnabled;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x33020507),
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => CreateTableScene(
          leagueName: '${league['name']}',
          stakes: coinOptions,
          selectedIndex: selectedIndex,
          turnSeconds: draftTurnSeconds,
          spectator: spectator,
          chat: chat,
          canCreate: UserState.userCoin >= coinOptions[selectedIndex],
          formatStake: _formatCreateStake,
          onStake: (index) => refresh(() => selectedIndex = index),
          onSpeed: (seconds) => refresh(() => draftTurnSeconds = seconds),
          onSpectator: () => refresh(() => spectator = !spectator),
          onChat: () => refresh(() => chat = !chat),
          onClose: () => Navigator.of(dialogContext).pop(),
          onCreate: () {
            createMaxPlayer = 2;
            createTurnSeconds = draftTurnSeconds;
            createSpectatorEnabled = spectator;
            createChatEnabled = chat;
            Navigator.of(dialogContext).pop();
            unawaited(
              _createTable(
                league: Map<String, dynamic>.from(league),
                entry: coinOptions[selectedIndex],
                turnSeconds: draftTurnSeconds,
                spectatorsEnabled: spectator,
                chatEnabled: chat,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget buildCreateButton({
    required bool canCreate,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: canCreate ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: canCreate ? onTap : null,
          splashColor: const Color(0x40FFE7B0),
          highlightColor: const Color(0x14FFFFFF),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFFE3A0),
                  Color(0xFFE4B54E),
                  Color(0xFFBB8321),
                ],
              ),
              border: Border.all(color: const Color(0xFFF9E2A8), width: 1.1),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x99B1771C),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: const Color(0xCC000000),
                  offset: const Offset(0, 8),
                  blurRadius: 14,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 11,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withOpacity(0.32),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: const Text(
                      "MASAYI AÇ",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF221A08),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        shadows: [
                          Shadow(
                            color: Color(0x66FFFFFF),
                            offset: Offset(0, 1),
                            blurRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton(IconData icon) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFF2C14E), Color(0xFFD4A24C)],
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8),
        ],
      ),
      child: Icon(icon, color: Colors.black, size: 18),
    );
  }

  Widget gamePicker({
    required List<Widget> children,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      height: 110,
      child: CupertinoPicker(
        itemExtent: 40,
        diameterRatio: 1.35,
        magnification: 1.2,
        useMagnifier: true,
        scrollController: controller,
        onSelectedItemChanged: onChanged,

        /// AAA CENTER BAR
        selectionOverlay: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),

            border: Border.all(color: const Color(0x55E7B95A), width: 1),

            color: const Color(0x22E7B95A),
          ),
        ),

        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_deviceReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        key: _lobbySceneKey,
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFF050608),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: 2048,
                  height: 1152,
                  child: Image.asset(
                    'assets/images/lobby/lobby.png',
                    fit: BoxFit.fill,
                  ),
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x88081016),
                    Color(0x22081016),
                    Color(0xAA050D10),
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: SkyPlanesOverlay(skyHeightFactor: 0.34, planeCount: 2),
          ),

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 7),
                Expanded(
                  child: Padding(
                    // SafeArea above already reserves the device cutouts.
                    // Keep only a small, symmetric gutter inside that area.
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _connectedLeagueAndTables(),
                  ),
                ),

                _bottomDock(),
              ],
            ),
          ),

          LobbySideMenu(
            open: _isSideMenuOpen,
            onClose: _closeSideMenu,

            onSupport: () async {
              _closeSideMenu();
              await _openSupportRequestDialog();
            },

            onAnnouncements: () async {
              _closeSideMenu();
              await _showSystemMessagesDialog();
            },

            onProfileCard: () {
              _closeSideMenu();
              ProfileService.showUserCard(
                {
                  'id': UserState.userId,
                  'username': UserState.userName,
                  'avatar_url': UserState.userAvatarUrl,
                  'rating': UserState.userRating,
                  'wins': UserState.wins,
                  'losses': UserState.losses,
                },
                onRefresh: () async {
                  await _loadSocialData();
                  await _loadTables();
                },
              );
            },

            onSettings: () {
              _closeSideMenu();
              _openRightPanel(_RightPanelType.settings);
            },

            onLogout: () async {
              _closeSideMenu();
              await _signOutAndGoLogin();
            },

            menuButtonBuilder: lobbySideMenuButton,

            goldBorderColor: _goldBorderColor,
            goldBorderWidth: _goldBorderWidth,
          ),

          Positioned.fill(
            child: CoinTransferOverlay(
              progress: _rewardFlight,
              source: _flightSource,
              destination: _flightDestination,
            ),
          ),
          _rightPanelOverlay(),
          if (_showGuestBanner)
            Positioned(top: 12, right: 12, child: _guestBanner()),
        ],
      ),
    );
  }

  Widget _rightPanelContent() {
    switch (_rightPanelType) {
      case _RightPanelType.friends:
        return _friendsPanel();

      case _RightPanelType.messages:
        return _messagesPanel();

      case _RightPanelType.settings:
        return _settingsPanel();

      default:
        return const SizedBox();
    }
  }

  Widget _rightPanelOverlay() {
    if (_rightPanelType == _RightPanelType.settings) {
      return Positioned.fill(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeRightPanel,
                child: const ColoredBox(color: Color(0x88000000)),
              ),
            ),
            _settingsPanel(),
          ],
        ),
      );
    }
    final isMessagesPanel = _rightPanelType == _RightPanelType.messages;
    return LobbyRightPanel(
      open: _rightPanelType != _RightPanelType.none,
      onClose: _closeRightPanel,
      panelContent: _rightPanelContent(),
      widthFactor: isMessagesPanel ? 0.62 : 0.44,
      minWidth: isMessagesPanel ? 350 : 280,
      maxWidth: isMessagesPanel ? 500 : 350,
    );
  }

  Widget _socialAvatar(Map<String, dynamic> friend) => _statusAvatar(
    username: friend['username']?.toString() ?? 'Oyuncu',
    avatarUrl: friend['avatar_url']?.toString(),
    isOnline: friend['is_online'] == true,
    size: 14,
    blocked: UserState.blockedUserIds.contains(friend['id']),
  );

  Widget _friendsPanel() => LobbyFriendsScene(
    friends: _friends,
    avatarBuilder: _socialAvatar,
    statusText: (friend) => friend['table_id'] != null
      ? (friend['table_role'] == 'spectator' ? 'Masayı izliyor' : 'Masada oynuyor')
      : friend['is_online'] == true
      ? 'Çevrimiçi' : _formatLastSeen(friend['last_seen_at']),
    onClose: _closeRightPanel,
    onProfile: (friend) async {
      await ProfileService.showUserCard(friend, onRefresh: () async {
        await _loadSocialData();
        await _loadTables();
      });
    },
    onMessage: (friend) => _openRightPanel(_RightPanelType.messages,
      initialChatUserId: friend['id']?.toString()),
    onSpectate: (friend) async {
      await _loadSocialData();
      if (!mounted) return;
      final current = _friends.where((f) => f['id'] == friend['id']);
      if (current.isEmpty) return;
      final tableId = current.first['table_id']?.toString();
      if (tableId == null || current.first['table_spectators_enabled'] == false) {
        _msg('Arkadaşının izlenebilir bir masası bulunamadı.');
        return;
      }
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => SpectatorScreen(tableId: tableId)));
      if (mounted) await _loadSocialData();
    },
  );

  Widget _messagesPanel() => LobbyMessagesScene(
    friends: _messageContacts,
    activeId: _activeChatUserId,
    unread: _unreadByUser,
    avatarBuilder: _socialAvatar,
    onSelect: (friend) {
      final id = friend['id']?.toString();
      if (id != null) _loadMessagesWith(id, friend['friendid']?.toString() ?? '', markRead: true);
    },
    onClose: _closeRightPanel,
    controller: _chatController,
    scrollController: _chatScrollController,
    onSend: _sendMessage,
    onEmoji: () {
      setState(() => _showEmojiPicker = !_showEmojiPicker);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    },
    loading: _rightPanelLoading,
    menu: _floatingMenu(),
    microphone: Listener(
      onPointerDown: (_) async {
        _isPressing = true;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_isPressing && mounted && _rightPanelType == _RightPanelType.messages) {
          await _startRecording();
        }
      },
      onPointerUp: (_) async {
        _isPressing = false;
        await _stopRecording(send: false);
      },
      onPointerCancel: (_) async {
        _isPressing = false;
        await _stopRecording(send: false);
      },
      child: _recordButton(),
    ),
    accessory: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_isRecording) Padding(padding: const EdgeInsets.all(4),
        child: Text('Kayıt · $_recordDuration', style: const TextStyle(color: Color(0xFFE8B8A5), fontSize: 11))),
      if (_showPreview && _previewPath != null) Row(children: [
        IconButton(tooltip: 'Kaydı dinle',
          icon: Icon(_previewPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: const Color(0xFFE4C98D)),
          onPressed: () async {
            if (_previewPlaying) {
              await _audioPlayer.stop();
              if (mounted) setState(() => _previewPlaying = false);
              return;
            }
            if (!FeedbackSettingsService.soundEnabled) {
              await FeedbackSettingsService.triggerHaptic();
              return;
            }
            await _audioPlayer.setFilePath(_previewPath!);
            if (!mounted) return;
            setState(() => _previewPlaying = true);
            await _audioPlayer.play();
            if (mounted) setState(() => _previewPlaying = false);
          },
        ),
        Expanded(child: ClipRect(child: _waveform(_previewPlaying))),
        IconButton(tooltip: 'Kaydı sil',
          icon: const Icon(Icons.close_rounded, color: Colors.white60),
          onPressed: () async {
            final path = _previewPath;
            if (path == null) return;
            await File(path).delete();
            if (mounted) setState(() { _previewPath = null; _showPreview = false; });
          },
        ),
        IconButton(tooltip: 'Sesli mesaj gönder',
          icon: const Icon(Icons.send_rounded, color: Color(0xFFE4C98D)),
          onPressed: () async {
            final path = _previewPath;
            if (path == null) return;
            await _sendVoiceMessage(path);
            if (mounted) setState(() { _previewPath = null; _showPreview = false; });
          },
        ),
      ]),
      if (_showEmojiPicker) SizedBox(height: 38, child: ListView(
        scrollDirection: Axis.horizontal,
        children: _chatEmojis.map((emoji) => InkWell(
          onTap: () => _insertEmojiToChat(emoji),
          child: Padding(padding: const EdgeInsets.all(5),
            child: Text(emoji, style: const TextStyle(fontSize: 22))),
        )).toList(),
      )),
    ]),
    messageCount: _activeChatMessages.length,
    messageBuilder: (context, index) {
      final msg = _activeChatMessages[index];
      final mine = msg['sender_id'] == UserState.userId;
      final senderId = msg['sender_id']?.toString();
      final friend = _messageContacts.where((f) => f['id']?.toString() == senderId).firstOrNull;
      final name = mine ? (UserState.userName.isEmpty ? 'Sen' : UserState.userName)
        : friend?['username']?.toString() ?? 'Oyuncu';
      return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.fromLTRB(3, 4, 3, 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: mine ? const Color(0x20DABF82) : const Color(0x301F2C39),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFE4C98D), fontSize: 10, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              if (msg['type'] == 'voice') _voiceBubble(msg, mine)
              else Text(msg['content']?.toString() ?? '',
                style: const TextStyle(color: Color(0xFFE5EAE7), fontSize: 12, height: 1.35)),
            ]),
        ),
      );
    },
  );
  Widget _recordDot() {
    return TweenAnimationBuilder(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 700),
      builder: (_, double value, __) {
        return Opacity(
          opacity: value,
          child: const Icon(Icons.circle, color: Colors.red, size: 8),
        );
      },
      onEnd: () {},
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

  void _scrollToBottom({bool animated = true}) {
    if (!_chatScrollController.hasClients) return;

    final position = _chatScrollController.position.maxScrollExtent;

    if (animated) {
      _chatScrollController.animateTo(
        position,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _chatScrollController.jumpTo(position);
    }
  }

  Widget _floatingMenu() {
    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF1A1D1B),

      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0x6624362E),
          border: Border.all(color: const Color(0x335B6778)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(.4), blurRadius: 10),
          ],
        ),
        child: const Icon(Icons.more_vert, color: Colors.white70, size: 18),
      ),

      onSelected: (value) {
        if (value == 'delete_chat') {
          _confirmDeleteChat();
        }
      },

      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'delete_chat',
          child: Row(
            children: const [
              Icon(Icons.delete, color: Colors.redAccent, size: 18),
              SizedBox(width: 10),
              Text("Sohbeti sil", style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteChat() async {
    final confirm = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "",
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 200),

      pageBuilder: (context, _, __) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(16),

              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xFF1A1D1B),
                border: Border.all(color: const Color(0x335B6778)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.6),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),

              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  /// ?? TITLE
                  const Text(
                    "Sohbeti sil",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 7),

                  /// ?? DESCRIPTION
                  const Text(
                    "Bu kullanıcıyla tüm mesajlar ve ses kayıtları silinecek.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),

                  const SizedBox(height: 18),

                  /// ?? BUTTONS
                  Row(
                    children: [
                      /// CANCEL
                      Expanded(
                        child: InkWell(
                          onTap: () => Navigator.pop(context, false),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: const Color(0x3324362E),
                              border: Border.all(
                                color: const Color(0x335B6778),
                              ),
                            ),
                            child: const Text(
                              "İptal",
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      /// DELETE
                      Expanded(
                        child: InkWell(
                          onTap: () => Navigator.pop(context, true),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 42,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFE14B4B), Color(0xFF9F2A2A)],
                              ),
                            ),
                            child: const Text(
                              "Sil",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirm == true) {
      await _deleteChat();
    }
  }

  Future<void> _deleteChat() async {
    final uid = UserState.userId;
    final other = _activeChatUserId;

    if (uid == null || other == null) return;

    try {
      /// 3. mesajlar? sil
      await supabase
          .from('messages')
          .delete()
          .or(
            'and(sender_id.eq.$uid,receiver_id.eq.$other),and(sender_id.eq.$other,receiver_id.eq.$uid)',
          );

      /// 4. UI temizle
      setState(() {
        _activeChatMessages.clear();
      });

      _msg("Sohbet silindi");
    } catch (e) {
      debugPrint("DELETE CHAT ERROR: $e");
      _msg("Silme hatası");
    }
  }

  Future<void> _sendVoiceMessage(String filePath) async {
    final uid = UserState.userId ?? supabase.auth.currentUser?.id;
    final otherId = _activeChatUserId;
    final ftableid = _activeChatUserTableId ?? "";
    if (uid == null || otherId == null) return;

    try {
      final file = File(filePath);

      if (!await file.exists()) return;

      /// ?? message id
      final messageId = const Uuid().v4();

      final storagePath = 'friend/$ftableid/$messageId.m4a';

      /// ?? 1. STORAGE UPLOAD
      await supabase.storage.from('voice').upload(storagePath, file);

      /// ?? 2. DB INSERT (senin yap?ya uyumlu)
      await supabase.from('messages').insert({
        'sender_id': uid,
        'receiver_id': otherId,
        'content': null, // ? text yok
        'type': 'voice',
        'voice_url': storagePath,
        'duration': 5, // ?imdilik sabit
      });

      /// ?? 3. LOCAL TEM?ZLE
      await file.delete();

      /// ?? 4. CHAT REFRESH (senin sistem)
      await _loadMessagesWith(otherId, ftableid, markRead: false);
    } catch (e) {
      _msg('Sesli mesaj gönderilemedi.');
      debugPrint('VOICE MESSAGE ERROR: $e');
    }
  }

  Future<String> getVoiceUrl(String path) async {
    return await supabase.storage.from('voice').createSignedUrl(path, 60);
  }

  Widget _voiceBubble(Map<String, dynamic> msg, bool mine) {
    final isPlaying = _playingMessageId == msg['id'];

    return Row(
      mainAxisSize: MainAxisSize.min, // ? ?nemli
      children: [
        /// ?? PLAY
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

        /// ?? WAVE
        SizedBox(
          width: 80, // ? sabit width
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

        /// ?? s?re
        Text(
          "${msg['duration'] ?? 0}s",
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
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

      /// ayn? mesaj › stop
      if (_playingMessageId == msg['id']) {
        await _audioPlayer.stop();
        setState(() => _playingMessageId = null);
        return;
      }

      /// yeni mesaj ba?lat
      final url = await supabase.storage
          .from('voice')
          .createSignedUrl(path, 60);

      await _audioPlayer.stop(); // ?? ?nemli (?nceki sesi kes)

      await _audioPlayer.setUrl(url);

      setState(() => _playingMessageId = msg['id']);

      await _audioPlayer.play();
      await FeedbackSettingsService.triggerHaptic();
    } catch (e) {
      debugPrint("VOICE PLAY ERROR: $e");
    }
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

  void _stopTimer() {
    _recordTimer?.cancel();
  }

  String get _recordDuration {
    final m = (_recordSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recordSeconds % 60).toString().padLeft(2, '0');
    return "$m:$s";
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    if (!await _recorder.hasPermission()) return;
    if (!mounted || !_isPressing || _rightPanelType != _RightPanelType.messages) return;

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

    if (!mounted || !_isPressing || _rightPanelType != _RightPanelType.messages) {
      await _recorder.stop();
      final abandoned = File(path);
      if (await abandoned.exists()) await abandoned.delete();
      return;
    }

    setState(() => _isRecording = true);

    _startTimer();

    /// ?? EN KR?T?K (recorder warmup)
    _canStop = false;

    Future.delayed(const Duration(milliseconds: 300), () {
      _canStop = true;
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

    /// ? ARTIK G?NDERMEY?Z
    setState(() {
      _previewPath = path;
      _showPreview = true;
    });
  }

  Widget _recordButton() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,

      height: _isRecording ? 54 : 44,
      width: _isRecording ? 54 : 44,

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),

        /// ?? BACKGROUND
        color: _isRecording ? Colors.redAccent : const Color(0xFF1E2A25),

        /// ?? BORDER
        border: Border.all(
          color: _isRecording ? Colors.redAccent : const Color(0x335C6878),
          width: _isRecording ? 1.6 : 1,
        ),

        /// ? GLOW
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

  Widget _settingsPanel() {
    return GameSettingsScene(
      sound: _soundEnabled,
      vibration: _vibrationEnabled,
      colorBlind: _colorBlindMode,
      invites: _allowGameInvites,
      onClose: _closeRightPanel,
      onSound: (value) async {
        await FeedbackSettingsService.setSoundEnabled(value);
        if (!mounted) return;
        setState(() => _soundEnabled = value);
      },
      onVibration: (value) async {
        await FeedbackSettingsService.setVibrationEnabled(value);
        if (!mounted) return;
        setState(() => _vibrationEnabled = value);
      },
      onColorBlind: (value) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('color_blind_mode', value);
        UserState.colorBlindMode = value;
        if (!mounted) return;
        setState(() => _colorBlindMode = value);
      },
      onInvites: (value) async {
        final prev = _allowGameInvites;
        setState(() => _allowGameInvites = value);
        try {
          final uid = supabase.auth.currentUser?.id;
          if (uid == null) throw Exception('AUTH_REQUIRED');
          await supabase
              .from('profiles')
              .update({'allow_game_invites': value})
              .eq('id', uid);
        } catch (e) {
          if (!mounted) return;
          setState(() => _allowGameInvites = prev);
          _msg('Davet ayarı kaydedilemedi.');
        }
      },
      onDelete: () async {
        _closeRightPanel();
        await _confirmDeleteAccount();
      },
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        final width = MediaQuery.of(context).size.width;
        final dialogWidth = width > 700
            ? 430.0
            : (width * 0.86).clamp(300.0, 430.0);
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Center(
            child: SizedBox(
              width: dialogWidth,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: BoxDecoration(
                  color: const Color(0xCC121826),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0x66E7C06A),
                    width: 1.2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFFFB4B4),
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Hesabı Sil',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Bu işlem geri alınamaz.\nHesabınız ve tüm verileriniz kalıcı olarak silinecek.',
                      style: TextStyle(
                        color: Color(0xFFD8DEE8),
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0x557B8593)),
                              foregroundColor: const Color(0xFFE7EDF5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                            ),
                            child: const Text(
                              'İptal',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE34A4A),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                            ),
                            child: const Text(
                              'Sil',
                              style: TextStyle(fontWeight: FontWeight.w800),
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
        );
      },
    );

    if (confirm == true) {
      await _deleteAccountFlow();
    }
  }

  Future<void> _deleteAccountFlow() async {
    try {
      // loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(child: CircularProgressIndicator()),
      );

      await deleteAccount(); // API call

      Navigator.of(context).pop(); // loading kapat

      await _signOutAndGoLogin();
    } catch (e) {
      Navigator.of(context).pop();
      print("DELETE ERROR: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Hesap silinirken hata oluştu")));
    }
  }

  Future<void> deleteAccount() async {
    final session = supabase.auth.currentSession;

    if (session == null) {
      print("No session");
      throw Exception("No session");
    }

    final userId = supabase.auth.currentUser!.id;

    final res = await supabase.functions.invoke(
      'delete_user',
      body: {'user_id': userId},
    );

    print(res.data);
  }

  Future<void> _signOutAndGoLogin() async {
    try {
      await supabase.auth.signOut();
    } catch (e) {
      debugPrint('SIGN OUT ERROR: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Widget _badge(String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE34A4A),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _statusAvatar({
    required String username,
    required String? avatarUrl,
    required bool isOnline,
    required double size,
    bool blocked = false,
  }) {
    final dotColor = isOnline
        ? const Color(0xFF3BD16F)
        : const Color(0xFFE34A4A);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        LobbyAvatar(
          username: username,
          avatarUrl: avatarUrl,
          size: size,
          blocked: blocked,
        ),
        Positioned(
          right: -1,
          top: -1,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black87, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  String _formatLastSeen(dynamic rawValue) {
    DateTime? dt;
    if (rawValue is DateTime) {
      dt = rawValue;
    } else if (rawValue is String) {
      dt = DateTime.tryParse(rawValue)?.toLocal();
    }
    if (dt == null) return 'Son görülme bilinmiyor';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Az önce görüldü';
    if (diff.inHours < 1) return '${diff.inMinutes} dk önce görüldü';
    if (diff.inDays < 1) return '${diff.inHours} sa önce görüldü';
    return '${diff.inDays} gün önce görüldü';
  }

  Widget _premiumLoader({double size = 30}) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: const CircularProgressIndicator(
              strokeWidth: 2.6,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF2C14E)),
              backgroundColor: Color(0x33547A69),
            ),
          ),
          Icon(
            Icons.auto_awesome_rounded,
            size: size * 0.38,
            color: const Color(0xFFEEC36C),
          ),
        ],
      ),
    );
  }

  String _normalizeTrText(String input) {
    return input;
  }

  Widget _connectedLeagueAndTables() {
    return LobbyColumns(
      leagues:
          Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                child: Column(
                  children: [
                    const SizedBox(height: 2),
                    const LobbyMotto(),
                    const SizedBox(height: 6),
                    /// ?? L?G L?STES?
                    Expanded(
                      child: Stack(
                        children: [
                          LobbyLeagueList(
                            leagues: leagues,
                            selectedLeagueId: selectedLeague,
                            leagueActivePlayers: leagueActivePlayers,
                            leagueActiveTables: leagueActiveTables,
                            userCoin: UserState.userCoin,
                            userRating: UserState.userRating,
                            loading: loadingLeagues,
                            onSelect: (league) {
                              final playerCoin = UserState.userCoin;
                              final playerRating = UserState.userRating;

                              final minCoin = league['min_coin'];
                              final minRating = league['min_rating'];

                              final eligible =
                                  playerCoin >= minCoin &&
                                  playerRating >= minRating;

                              setState(() {
                                selectedLeague = league['id'];

                                if (!eligible) {
                                  isLeagueLocked = true;
                                  lockedLeague = league;

                                  tables = [];
                                  loadingTables = false;
                                  _tablesInitialized = true;
                                  return;
                                }

                                /// ?? NORMAL
                                isLeagueLocked = false;
                                lockedLeague = null;

                                tables = [];
                                loadingTables = true;
                                _tablesInitialized = false;
                              });

                              if (eligible) {
                                _loadTables();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
          ),

      /// ?? MASALAR
      tables: _buildTablesPanel(),
    );
  }

  String get _selectedLeagueName => leagues
      .where((league) => league['id'] == selectedLeague)
      .map((league) => league['name']?.toString() ?? '')
      .firstOrNull ?? '';

  bool _quickPlayBusy = false;

  Future<void> _quickPlay() async {
    if (_quickPlayBusy || leagues.isEmpty) return;
    setState(() => _quickPlayBusy = true);
    QuickPlayController? flow;
    try {
      await _loadUser();
      if (!mounted) return;
      flow = QuickPlayController(SupabaseQuickPlayBackend(supabase));
      final result = await showDialog<Map<String, dynamic>>(
        context: context, barrierDismissible: false, barrierColor: const Color(0x99050C12),
        builder: (_) => QuickPlayWaitDialog(controller: flow!, leagueName: 'Tüm ligler'),
      );
      if (!mounted) return;
      if (result != null && result['table_id'] is String) {
        if (result['bot'] == true) _msg('Bot rakiple masaya geçiliyor.');
        await _openGame(result['table_id'] as String, result['is_creator'] == true);
      }
      await _loadTables();
    } catch (_) {
      if (mounted) _msg('Hızlı Oyna başlatılamadı. Lütfen yeniden dene.');
    } finally {
      flow?.dispose();
      if (mounted) setState(() => _quickPlayBusy = false);
    }
  }

  Widget _buildTablesPanel() {
    if (loadingTables) return _buildTablesPanelContents();
    if (tables.isEmpty && !isLeagueLocked) return QuickPlayPanel(
      leagueName: _selectedLeagueName, onPlay: _quickPlayBusy ? null : _quickPlay);
    return Column(children: [
      SizedBox(height: 55, child: QuickPlayPanel(compact: true,
        leagueName: _selectedLeagueName, onPlay: _quickPlayBusy ? null : _quickPlay)),
      const SizedBox(height: 4),
      Expanded(child: _buildTablesPanelContents()),
    ]);
  }

  Widget _buildTablesPanelContents() {
    final useWebGrid = kIsWeb && MediaQuery.of(context).size.width >= 1200;

    if (!useWebGrid || isLeagueLocked) {
      return LobbyTableWheel(
        leagueName: _selectedLeagueName,
        tables: tables,
        loading: loadingTables,
        blockedUserIds: UserState.blockedUserIds,
        isLocked: isLeagueLocked,
        lockedLeague: lockedLeague,
        playerCoin: UserState.userCoin,
        playerRating: UserState.userRating,
        onJoin: (table) => _joinTable(table),
        onSpectate: (table) => _handleSpectateTap(table),
        canSpectateAll: true,
        onNeedRefreshUser: () async {
          await _loadUser();
          await _loadTables();
        },
        onCreateTable: _showCreateModal,
        onUserTap: (user) async {
          await ProfileService.showUserCard(
            user,
            onRefresh: () async {
              await _loadSocialData();
              await _loadTables();
            },
          );
        },
        onRefresh: () => _loadTables(),
      );
    }

    if (loadingTables) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE7C66A)),
      );
    }

    if (tables.isEmpty) {
      return _buildEmptyEligibleTablesCta();
    }
    return RefreshIndicator(
      onRefresh: _loadTables,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = width >= 1500 ? 3 : 2;
          final sidePadding = width >= 1500 ? 18.0 : 12.0;
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(sidePadding, 8, sidePadding, 16),
            physics: const AlwaysScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              mainAxisExtent: 140,
            ),
            itemCount: tables.length,
            itemBuilder: (context, i) {
              final table = tables[i];
              return LobbyTableListingCard(
                number: i + 1,
                table: table,
                blockedUserIds: UserState.blockedUserIds,
                onJoin: _joinTable,
                onSpectate: _handleSpectateTap,
                canSpectateAll: true,
                onUserTap: (user) async {
                  await ProfileService.showUserCard(
                    user,
                    onRefresh: () async {
                      await _loadSocialData();
                      await _loadTables();
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyEligibleTablesCta() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xEE173328), Color(0xEE0D1915)],
            ),
            border: Border.all(color: const Color(0x88E7C66A), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.table_restaurant_rounded,
                color: Color(0xFFE7C66A),
                size: 34,
              ),
              const SizedBox(height: 10),
              Text(
                '$_selectedLeagueName liginde açık masa yok',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFF2F6F3),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'İlk masayı sen aç, oyuncular katıldıkça oyun hemen başlasın.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xC7E0ECE5), fontSize: 13.5),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 220,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _showCreateModal();
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: const Text(
                    'Masa A?',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE7C66A),
                    foregroundColor: const Color(0xFF1A241F),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomDock() {
    return LobbyBottomDock(
      left: _dockLeft(),
      center: _dockCenter(),
      right: _dockRight(),
    );
  }

  Widget statChip(IconData icon, int value, bool coin) {
    final t = _coinFxActive ? _coinFxController.value : 0.0;
    final spin = t * 6.28318;
    if (!coin) return LobbyLevelBadge(rating: _ratingDisplayValue);
    final chipPadding = coin
        ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 3);
    final iconSize = coin ? 15.0 : 14.0;
    final textSize = 14.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          key: coin ? _coinTargetKey : null,
          duration: const Duration(milliseconds: 260),
          constraints: const BoxConstraints(minHeight: 26),
          padding: coin
              ? chipPadding
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: coin && _coinFxActive
                ? const [
                    BoxShadow(
                      color: Color(0x66E7C06A),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (coin) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _coinFxController,
                      builder: (_, child) {
                        final tv = _coinFxActive
                            ? _coinFxController.value
                            : 0.0;
                        return Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: _coinFxActive
                                ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFE7C06A,
                                      ).withOpacity(0.52 + (0.28 * tv)),
                                      blurRadius: 12 + (10 * tv),
                                      spreadRadius: 0.9 + (1.4 * tv),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (_coinFxActive)
                                Container(
                                  width: 14 + (10 * tv),
                                  height: 14 + (10 * tv),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(
                                        0xAAFFE9AF,
                                      ).withOpacity((0.9 - tv).clamp(0.0, 0.9)),
                                      width: 1.0,
                                    ),
                                  ),
                                ),
                              Transform.rotate(
                                angle: tv * 6.28318,
                                child: child,
                              ),
                            ],
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.monetization_on,
                        size: 18,
                        color: Color(0xFFC9A86C),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      Format.coin(_coinDisplayValue),
                      style: TextStyle(
                        color: const Color(0xFFE5D3AA),
                        fontSize: textSize,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (coin && _coinFxActive) ...[
          Positioned(
            top: -6 + (2.0 * sin(spin)),
            left: 8 + (4.0 * cos(spin)),
            child: Opacity(
              opacity: (0.65 + (0.25 * sin(spin))).clamp(0.2, 0.95),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 9,
                color: Color(0xFFFFE8AB),
              ),
            ),
          ),
          Positioned(
            top: -5 + (2.3 * cos(spin + 2.2)),
            right: 8 + (4.2 * sin(spin + 2.2)),
            child: Opacity(
              opacity: (0.62 + (0.24 * cos(spin + 1.8))).clamp(0.2, 0.94),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 8,
                color: Color(0xFFFFD66B),
              ),
            ),
          ),
          Positioned(
            bottom: -5 + (2.0 * sin(spin + 4.0)),
            right: 3 + (3.7 * cos(spin + 4.0)),
            child: Opacity(
              opacity: (0.5 + (0.22 * sin(spin + 0.8))).clamp(0.15, 0.86),
              child: const Icon(
                Icons.circle,
                size: 4,
                color: Color(0xFFFFE8AB),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _dockLeft() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LobbyDockAction(
          label: 'Menü',
          onTap: _toggleSideMenu,
          child: LobbyDockEmblem(
            kind: LobbyDockEmblemKind.menu,
            active: _isSideMenuOpen,
          ),
        ),
        const SizedBox(width: 9),
        InkWell(
          onTap: () => ProfileService.showUserCard(
            {
              'id': UserState.userId,
              'username': UserState.userName,
              'avatar_url': UserState.userAvatarUrl,
              'rating': UserState.userRating,
              'wins': UserState.wins,
              'losses': UserState.losses,
            },
            onRefresh: () async {
              await _loadSocialData();
              await _loadTables();
              await _loadUser();
            },
          ),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF293440),
                  Color(0xFF111A26),
                  Color(0xFF0C131D),
                ],
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 5),
              ],
            ),
            child: LobbyAvatar(
              premium: true,
              username: UserState.userName,
              avatarUrl: UserState.userAvatarUrl,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                UserState.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFFFF2D7),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 0.2,
                  shadows: [Shadow(color: Color(0x99000000), blurRadius: 5)],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                statChip(Icons.star, UserState.userRating, false),
                const SizedBox(width: 7),
                statChip(Icons.monetization_on, UserState.userCoin, true),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _dockCenter() => LobbyDockCreate(onTap: _showCreateModal);

  Widget _dockRight() {
    final unreadTotal = _unreadTotal;
    return Row(
      children: [
        _coinBuyDockButton(),
        const SizedBox(width: 2),
        LobbyDockAction(
          label: InviteStrings.of(context).t('Davet', 'Invite'),
          emblem: LobbyDockEmblemKind.invite,
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const FriendInviteScreen(),
            ));
            if (mounted) await _loadUser();
          },
        ),
        const SizedBox(width: 2),
        LobbyDockAction(
          label: 'Sıralama',
          emblem: LobbyDockEmblemKind.ranking,
          onTap: () {
            _openLeaderboard();
          },
        ),
        const SizedBox(width: 2),
        LobbyDockAction(
          label: 'Arkadaşlarım',
          emblem: LobbyDockEmblemKind.social,
          onTap: () => _openRightPanel(_RightPanelType.friends),
        ),
        const SizedBox(width: 2),
        LobbyDockAction(
          label: 'Mesajlar',
          onTap: () => _openRightPanel(_RightPanelType.messages),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const LobbyDockEmblem(kind: LobbyDockEmblemKind.messages),
              if (unreadTotal > 0)
                Positioned(
                  right: -10,
                  top: -10,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE74C3C),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      unreadTotal > 99 ? '99+' : '$unreadTotal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _coinBuyDockButton() => LobbyDockAction(
    label: 'Mağaza',
    emblem: LobbyDockEmblemKind.store,
    onTap: () async {
      final result = await openStoreScreen(
        context,
        initialCoin: UserState.userCoin,
      );
      if (result == true) {
        await _loadUser();
      }
    },
  );
  void _openLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
    );
  }

  Future<void> loadMissedGifts(String userId) async {
    final res = await supabase
        .from('gifts')
        .select()
        .eq('receiver_id', userId)
        .eq('seen', false)
        .order('created_at', ascending: true);

    if (res.isEmpty) return;

    // ?? 1. G?NDERENE G?RE GRUPLA
    final Map<String, List<dynamic>> grouped = {};

    for (final g in res) {
      final sender = g['sender_id'];
      grouped.putIfAbsent(sender, () => []).add(g);
    }

    // ?? 2. HER GRUP ???N G?STER
    for (final entry in grouped.entries) {
      final senderId = entry.key;
      final gifts = entry.value;

      final firstGift = gifts.first;
      final giftType = firstGift['gift_type'];

      // ?? sender name
      String senderName = "Bir oyuncu";

      try {
        final profile = await supabase
            .from('profiles')
            .select('username')
            .eq('id', senderId)
            .maybeSingle();

        if (profile != null) {
          senderName = profile['username'] ?? senderName;
        }
      } catch (_) {}

      // ?? gift info (ilk gift ?zerinden)
      String emoji = "??";
      String giftName = "Hediye";

      try {
        final giftRes = await supabase
            .from('gift_types')
            .select('emoji, name')
            .eq('type', giftType)
            .maybeSingle();

        if (giftRes != null) {
          emoji = giftRes['emoji'] ?? emoji;
          giftName = giftRes['name'] ?? giftName;
        }
      } catch (_) {}

      // ?? MULTI LOGIC
      if (gifts.length == 1) {
        // ? TEK GIFT
        GiftOverlay.show(
          senderName: senderName,
          emoji: emoji,
          giftName: giftName,
          giftType: giftType?.toString() ?? '',
          senderId: senderId,
        );
      } else {
        // ?? ?OKLU GIFT
        GiftOverlay.show(
          senderName: senderName,
          emoji: "??",
          giftName: "${gifts.length} hediye gönderdi!",
          giftType: '',
          senderId: senderId,
        );
      }

      // ?? CONFETTI (her sender i?in 1 kere)
      CelebrationService.showConfetti();
    }

    // ?? TOPLU SEEN
    await supabase
        .from('gifts')
        .update({'seen': true, 'seen_at': DateTime.now().toIso8601String()})
        .eq('receiver_id', userId)
        .eq('seen', false);
  }
}

class AnimatedStoreButton extends StatefulWidget {
  final VoidCallback onTap;

  const AnimatedStoreButton({super.key, required this.onTap});

  @override
  State<AnimatedStoreButton> createState() => _AnimatedStoreButtonState();
}

class _AnimatedStoreButtonState extends State<AnimatedStoreButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scale = Tween<double>(
      begin: 1.0,
      end: 1.12,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withOpacity(0.6),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          ],
        ),
        child: lobbyStoreIcon(onTap: widget.onTap),
      ),
    );
  }
}

class LobbyLayout extends StatelessWidget {
  final Widget mobile;
  final Widget tablet;
  final Widget desktop;

  const LobbyLayout({
    super.key,
    required this.mobile,
    required this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width < 600) {
          return mobile;
        }

        if (width < 1000) {
          return tablet;
        }

        return desktop;
      },
    );
  }
}

// Masa kurma sahnesi: hafif perspektifli keçe, köşe ışıkları ve altın masa izi.
class _OkeyCreateTablePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF183D30), Color(0xFF061912), Color(0xFF102B22)],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
    final table = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * .10,
        size.height * .13,
        size.width * .80,
        size.height * .76,
      ),
      const Radius.elliptical(140, 90),
    );
    canvas.drawRRect(table, Paint()..color = const Color(0x33000000));
    canvas.drawRRect(
      table,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x557DAD7E),
    );
    canvas.drawRRect(
      table,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x667E6230),
    );
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [const Color(0x2CF7C66D), const Color(0x00F7C66D)],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width / 2, size.height * .45),
              radius: size.width * .35,
            ),
          );
    canvas.drawRect(rect, glow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _formatCreateStake(int amount) => formatTableStake(amount);
