import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/overlay/gift_overlay.dart';
import 'package:okeyix/screens/spectator_screen.dart';
import 'package:okeyix/services/celebration_service.dart';
import 'package:okeyix/services/device_identity_service.dart';
import 'package:okeyix/services/profile_service.dart';
import 'package:okeyix/services/push_notification_service.dart';
import 'package:okeyix/services/user_state.dart';

import 'package:okeyix/ui/lobby/LobbyTableWheel.dart';
import 'package:okeyix/widgets/aaa_button.dart';
import 'package:okeyix/widgets/create_button.dart';
import 'package:okeyix/widgets/dock_icon.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:okeyix/services/auth_service.dart';

import 'okey_game_screen.dart';
import 'login_screen.dart';
import 'store_screen.dart';
import 'leaderboard_screen.dart';
import '../ui/lobby/lobby_avatar.dart';
import '../ui/lobby/lobby_league_list.dart';
import '../ui/lobby/lobby_bottom_dock.dart';
import '../ui/lobby/lobby_side_menu.dart';
import '../ui/lobby/lobby_right_panel.dart';
import '../ui/lobby/_ui_helpers.dart';
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
    with TickerProviderStateMixin {
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
  late final AnimationController _bgController;
  final TextEditingController _chatController = TextEditingController();
  final _recorder = AudioRecorder();
  final ScrollController _chatScrollController = ScrollController();
  String? selectedLeague = "standart";
  int createMaxPlayer = 2;
  int createTurnSeconds = 15;
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

  final Set<String> _notifiedIncomingRequestIds = <String>{};
  final Set<String> _handledTableInviteIds = <String>{};
  List<Map<String, dynamic>> _activeChatMessages = [];
  String? _activeChatUserId;
  String? _activeChatUserTableId;
  RealtimeChannel? _tableInviteChannel;

  late AnimationController _storePulse;
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
  bool _deviceReady = false;
  bool _initCalled = false;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _showGuestBanner = false;
  List<Map<String, dynamic>> _systemMessages = [];
  final Set<String> _seenSystemMessageIds = <String>{};
  String? _lastSystemToastMessageId;
  DateTime? _globalSpectatorPassUntil;
  bool _campaignChecked = false;
  bool _autoResumeAttempted = false;

  int selectedIndex = 0;
  bool isLeagueLocked = false;
  dynamic lockedLeague;

  @override
  void initState() {
    super.initState();
    _checkGuestWelcome();
    _audioPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() => _playingMessageId = null);
      }
    });
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();

    _storePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _init();
    _leagueActivityTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      _loadLeagueActivity();
    });
    _socialRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadSocialData();
    });
    _tablesRefreshTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _loadTables(),
    );
    _systemMessageTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkUnreadSystemMessages(showToast: true),
    );
    _spectatorPassTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshGlobalSpectatorPassStatus(),
    );

    _initDevice();
  }

  Future<void> _initDevice() async {
    if (_initCalled) return;
    _initCalled = true;

    try {
      /// 🔥 UI HEMEN A�ILSIN
      setState(() {
        _deviceReady = true;
      });

      /// 🔥 REGISTER ARKADA �ALIŞSIN
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

  Future<String> getDeviceId() async {
    return DeviceIdentityService.getStableInstallId();
  }

  Future<void> registerDevice() async {
    try {
      final deviceId = await getDeviceId();
      final pushToken = await PushNotificationService.instance.getToken();

      final packageInfo = await PackageInfo.fromPlatform();

      String platform = "web";
      String deviceModel = "";
      String osVersion = "";

      if (kIsWeb) {
        platform = "web";
        deviceModel = "browser";
        osVersion = "web";
      } else {
        final deviceInfo = DeviceInfoPlugin();

        if (Platform.isAndroid) {
          final android = await deviceInfo.androidInfo;
          platform = "android";
          deviceModel = android.model;
          osVersion = android.version.release;
        } else if (Platform.isIOS) {
          final ios = await deviceInfo.iosInfo;
          platform = "ios";
          deviceModel = ios.utsname.machine;
          osVersion = ios.systemVersion;
        }
      }

      final session = supabase.auth.currentSession;

      if (session == null) {
        throw Exception("Session yok");
      }
      final user = supabase.auth.currentUser;
      try {
        await supabase.functions.invoke(
          'register_device',
          body: {
            "user_id": user?.id,
            "device_id": deviceId,
            "platform": platform,
            "device_model": deviceModel,
            "os_version": osVersion,
            "app_version": packageInfo.version,
            "push_token": pushToken,
          },
        );
      } catch (_) {
        await supabase.functions.invoke(
          'register_device',
          body: {
            "user_id": user?.id,
            "device_id": deviceId,
            "platform": platform,
            "device_model": deviceModel,
            "os_version": osVersion,
            "app_version": packageInfo.version,
          },
        );
      }

      /// 🔥 HATA KONTROL� BURADA
    } catch (e) {
      print(e);

      /// 🔥 SADECE SIGNOUT + FORWARD

      rethrow; // 🔥 EN DOĞRU
    }
  }

  Future<void> _checkGuestWelcome() async {
    if (!AuthService.isGuest()) return;

    setState(() {
      _showGuestBanner = true;
    });
  }

  Widget _guestBanner() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: Colors.amber.withOpacity(0.4)),

        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.7), blurRadius: 12),
        ],
      ),
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
    _leagueActivityTimer?.cancel();
    _socialRefreshTimer?.cancel();
    _tablesRefreshTimer?.cancel();
    _systemMessageTimer?.cancel();
    _spectatorPassTimer?.cancel();
    _chatController.dispose();
    _bgController.dispose();
    _storePulse.dispose();
    _audioPlayer.dispose();
    _tableInviteChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _init() async {
    await FeedbackSettingsService.load();
    _soundEnabled = FeedbackSettingsService.soundEnabled;
    _vibrationEnabled = FeedbackSettingsService.vibrationEnabled;

    await _loadUser();
    await _refreshGlobalSpectatorPassStatus();
    await _checkOnboarding();
    await _loadSocialData();
    await _loadSystemMessages();
    await _restoreSeenSystemMessages();
    await _checkUnreadSystemMessages(showToast: false);
    await _loadLeagues();
    await _loadLeagueActivity();
    await _loadTables();
    await _tryResumeActiveGame();
    await _checkCampaignPopup();
    final user = supabase.auth.currentUser;

    if (user != null) {
      _bindTableInviteListener(user.id);
      await _loadPendingTableInvites(user.id);
      await loadMissedGifts(user.id);
    }
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
    try {
      final rows = await supabase
          .from('table_invites')
          .select('id,table_id,from_user,to_user,status,created_at')
          .eq('to_user', myUserId)
          .eq('status', 'pending')
          .order('created_at', ascending: true)
          .limit(20);
      for (final raw in (rows as List)) {
        await _handleIncomingTableInvite(Map<String, dynamic>.from(raw));
      }
    } catch (e) {
      debugPrint('PENDING INVITE LOAD ERROR: $e');
    }
  }

  Future<void> _handleIncomingTableInvite(Map<String, dynamic> invite) async {
    if (!mounted) return;
    final id = invite['id']?.toString();
    if (id == null || id.isEmpty) return;
    if (_handledTableInviteIds.contains(id)) return;
    if ((invite['status']?.toString() ?? 'pending') != 'pending') return;
    _handledTableInviteIds.add(id);
    await _showTableInviteDialog(invite);
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
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF20352E), Color(0xFF132621)],
              ),
              border: Border.all(color: const Color(0xB3E3BB62), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x99230F00).withOpacity(.55),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: const [
                    Icon(Icons.celebration_rounded, color: Color(0xFFE3BB62)),
                    SizedBox(width: 8),
                    Text(
                      'Masa Daveti',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x4D000000),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x446EC6A0)),
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
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.3,
                            ),
                            children: [
                              TextSpan(
                                text: inviterName,
                                style: const TextStyle(
                                  color: Color(0xFFE3BB62),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const TextSpan(text: ' seni masaya davet etti.'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0x66FFFFFF)),
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Reddet',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE3BB62),
                          foregroundColor: const Color(0xFF1A241F),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Masaya Kat�l',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted) return;

    try {
      if (accepted == true) {
        await supabase
            .from('table_invites')
            .update({'status': 'accepted'})
            .eq('id', inviteId)
            .eq('status', 'pending');

        final table = await supabase
            .from('tables')
            .select('id,status,entry_coin,league_id,max_players')
            .eq('id', tableId)
            .maybeSingle();
        if (table == null) {
          _msg('Masa art�k bulunam�yor.');
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
      _msg('Davet i�lenemedi.');
      debugPrint('TABLE INVITE HANDLE ERROR: $e');
    }
  }

  Future<void> _loadUser() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await ProfileService.ensureUserRow();
    try {
      final row = await ProfileService.findUserRow(
        user,
        columns: 'id,username,avatar_url,wins,losses',
      );

      // ? profiles'den coins ve rating al
      final profileRows = await supabase
          .from('profiles')
          .select('coins,rating')
          .eq('id', user.id)
          .limit(1);
      final profile = (profileRows as List).isNotEmpty
          ? Map<String, dynamic>.from(profileRows.first)
          : null;

      final profileCoin = (profile?['coins'] as int?) ?? 0;
      final profileRating = (profile?['rating'] as int?) ?? 1200;

      if (!mounted) return;
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
        });
      }
    } catch (e) {
      debugPrint('USER LOAD ERROR: $e');
    }
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
      final isIncomplete = username.isEmpty || avatar.isEmpty;
      if (isIncomplete && _isLikelyFirstLogin(user)) {
        if (!mounted) return;
        await ProfileService.openProfileSetupDialog(
          forceComplete: true,
          onSuccess: () async {
            await _loadUser();
            await _loadSocialData();
            await _loadTables();
          },
        );
      }
    } catch (e) {
      debugPrint('ONBOARDING ERROR: $e');
    }
  }

  bool _isLikelyFirstLogin(User user) {
    DateTime? parseDate(dynamic raw) {
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      return DateTime.tryParse(raw.toString());
    }

    final createdAt = parseDate(user.createdAt);
    final lastSignInAt = parseDate(user.lastSignInAt);
    if (createdAt == null || lastSignInAt == null) return false;
    final diff = lastSignInAt.difference(createdAt).abs();
    return diff <= const Duration(minutes: 15);
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
    final minPlayersByName = {
      'Standart': 180,
      'Bronz': 120,
      'G�m��': 80,
      'Alt�n': 40,
    };

    if (leagues.isEmpty) return;

    try {
      final activeTables = await supabase
          .from('tables')
          .select('id, league_id, status')
          .inFilter('status', ['waiting', 'playing']);

      final tableRows = (activeTables as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final usersByLeague = <String, Set<String>>{};
      final tableCountByLeague = <String, int>{};

      if (tableRows.isNotEmpty) {
        final tableIds = tableRows.map((e) => e['id'] as String).toList();

        /// ? ger�ek masa say�s�
        for (final row in tableRows) {
          final leagueId = row['league_id']?.toString();
          if (leagueId == null) continue;

          tableCountByLeague[leagueId] =
              (tableCountByLeague[leagueId] ?? 0) + 1;
        }

        final players = await supabase
            .from('table_players')
            .select('table_id,user_id')
            .inFilter('table_id', tableIds);

        final leagueByTable = <String, String>{};

        for (final row in tableRows) {
          final tableId = row['id']?.toString();
          final leagueId = row['league_id']?.toString();
          if (tableId == null || leagueId == null) continue;

          leagueByTable[tableId] = leagueId;
        }

        for (final row in (players as List)) {
          final map = Map<String, dynamic>.from(row);

          final tableId = map['table_id']?.toString();
          final userId = map['user_id']?.toString();

          if (tableId == null || userId == null) continue;

          final leagueId = leagueByTable[tableId];
          if (leagueId == null) continue;

          usersByLeague.putIfAbsent(leagueId, () => <String>{}).add(userId);
        }
      }

      final rnd = Random();

      final playersResult = <String, int>{};
      final tablesResult = <String, int>{};

      for (final league in leagues) {
        final id = league['id']?.toString();
        final name = league['name']?.toString();

        if (id == null) continue;

        final realPlayers = usersByLeague[id]?.length ?? 0;
        final basePlayers = minPlayersByName[name] ?? 50;

        /// ?? ak�ll� fake
        final fluctuation = rnd.nextInt(20); // k���k oynama

        final boostedPlayers =
            (realPlayers > basePlayers ? realPlayers : basePlayers) +
            fluctuation;

        playersResult[id] = boostedPlayers;
        final realTables = tableCountByLeague[id] ?? 0;

        if (realTables == 0) {
          tablesResult[id] = 1 + rnd.nextInt(2); // 1-2 masa
        } else {
          tablesResult[id] = realTables;
        }
      }

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
  }

  Future<void> _cleanupOrphanTables(List<String> orphanTableIds) async {
    if (orphanTableIds.isEmpty) return;

    try {
      await supabase
          .from('match_moves')
          .delete()
          .inFilter('table_id', orphanTableIds);

      /// ?? BURASI S�L�ND� (view oldu�u i�in)

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
          .inFilter('status', ['waiting', 'playing'])
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

      final inactiveTableIds = tableRows
          .map((t) => t['id']?.toString())
          .whereType<String>()
          .where((id) {
            final seats = playersByTable[id] ?? const <Map<String, dynamic>>[];
            if (seats.isEmpty) return true;
            final hasHuman = seats.any((p) {
              final uid = p['user_id']?.toString();
              if (uid == null || uid.isEmpty) return false;
              return isBotById[uid] != true;
            });
            return !hasHuman;
          })
          .toList();
      if (inactiveTableIds.isNotEmpty) {
        await _cleanupOrphanTables(inactiveTableIds);
        tableRows.removeWhere(
          (t) => inactiveTableIds.contains(t['id']?.toString()),
        );
      }

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

      const minVisibleTableCount = 5;
      if (merged.length < minVisibleTableCount) {
        final botRows = await supabase
            .from('users')
            .select('id,username,avatar_url')
            .eq('is_bot', true)
            .limit(40);
        final bots = (botRows as List)
            .map((e) => Map<String, dynamic>.from(e))
            .where((b) => (b['id']?.toString() ?? '').isNotEmpty)
            .toList();
        final botIds = bots
            .map((b) => b['id']?.toString())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toList();
        final botRatings = <String, int>{};
        if (botIds.isNotEmpty) {
          final botProfiles = await supabase
              .from('profiles')
              .select('id,rating')
              .inFilter('id', botIds);
          for (final raw in (botProfiles as List)) {
            final row = Map<String, dynamic>.from(raw);
            final id = row['id']?.toString();
            if (id == null || id.isEmpty) continue;
            botRatings[id] = (row['rating'] as int?) ?? 1200;
          }
        }
        if (bots.length >= 2) {
          final rnd = Random();
          final needFake = minVisibleTableCount - merged.length;
          for (int i = 0; i < needFake; i++) {
            final shuffled = List<Map<String, dynamic>>.from(bots)
              ..shuffle(rnd);
            final b1 = shuffled[0];
            final b2 = shuffled[1];
            merged.add({
              'id': 'fake_${league['id']}_$i',
              'league_id': league['id'],
              'status': 'playing',
              'entry_coin': (league['entry_coin'] as int?) ?? 100,
              'max_players': 2,
              'is_fake': true,
              '_players': [
                {
                  'seat_index': 0,
                  'user_id': b1['id']?.toString(),
                  'username':
                      (b1['username']?.toString().trim().isNotEmpty ?? false)
                      ? b1['username']
                      : 'Bot Oyuncu',
                  'avatar_url': b1['avatar_url']?.toString(),
                  'rating': botRatings[b1['id']?.toString()] ?? 1200,
                  'blocked': false,
                },
                {
                  'seat_index': 1,
                  'user_id': b2['id']?.toString(),
                  'username':
                      (b2['username']?.toString().trim().isNotEmpty ?? false)
                      ? b2['username']
                      : 'Bot Oyuncu',
                  'avatar_url': b2['avatar_url']?.toString(),
                  'rating': botRatings[b2['id']?.toString()] ?? 1200,
                  'blocked': false,
                },
              ],
            });
          }
        }
      }

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

  Future<void> _createTable() async {
    final user = supabase.auth.currentUser;
    if (user == null || leagues.isEmpty) return;

    final league = leagues.firstWhere(
      (l) => l['id'] == selectedLeague,
      orElse: () => leagues.first,
    );

    final effectiveTurnSeconds = draftTurnSeconds;
    final entry = coinOptions[selectedIndex];
    if (UserState.userCoin < entry) return _msg('Yetersiz coin.');
    if (UserState.userRating < ((league['min_rating'] as int?) ?? 0)) {
      return _msg('Bu lig i�in rating yetersiz.');
    }

    final table = await supabase
        .from('tables')
        .insert({
          'league_id': league['id'],
          'max_players': createMaxPlayer,
          'entry_coin': entry,
          'min_rounds': league['min_rounds'] ?? 2,
          'status': 'waiting',
          'created_by': user.id,
          'turn_seconds': effectiveTurnSeconds,
        })
        .select()
        .single();

    final tableId = table['id'] as String;
    await supabase.from('table_players').insert({
      'table_id': tableId,
      'user_id': user.id,
      'seat_index': 0,
    });

    if (!mounted) return;
    Navigator.pop(context);
    await _openGame(tableId, true);
  }

  Future<void> _joinTable(Map<String, dynamic> table) async {
    if (table['is_fake'] == true) {
      _msg('Bu masa vitrin masas�d�r. Kat�l�m kapal�.');
      return;
    }
    final user = supabase.auth.currentUser;
    final tableId = table['id'] as String?;
    if (user == null || tableId == null) return;
    final status = table['status']?.toString() ?? 'waiting';
    if (status == 'playing') {
      return _handleSpectateTap(table);
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
        return _msg('Bu lig i�in rating yetersiz.');
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
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(18),
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 220),
            tween: Tween(begin: 0.92, end: 1),
            curve: Curves.easeOut,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },

            child: Container(
              width: 560,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),

                /// ?? GLASS + DEPTH
                color: const Color(0xFF0F1B17).withOpacity(0.92),

                border: Border.all(
                  color: const Color(0xFFE7C06A).withOpacity(0.7),
                  width: 1.3,
                ),

                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.75),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: const Color(0xFFE7C06A).withOpacity(0.15),
                    blurRadius: 20,
                  ),
                ],
              ),

              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// ?? HEADER
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE7C06A), Color(0xFFB9932F)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE7C06A).withOpacity(0.6),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.visibility_rounded,
                          color: Colors.black,
                          size: 18,
                        ),
                      ),

                      const SizedBox(width: 10),

                      const Expanded(
                        child: Text(
                          'Genel Seyirci Ge�i�i',
                          style: TextStyle(
                            color: Color(0xFFE7C06A),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .4,
                          ),
                        ),
                      ),

                      InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.pop(context, false),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  /// ?? INFO BOX
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.white.withOpacity(0.03),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: const Text(
                      'Sadece arkada�lar�n�n masas�n� �cretsiz izleyebilirsin.\n\n'
                      '24 saat boyunca t�m masalar� izlemek i�in bu ge�i�i a�abilirsin.',
                      style: TextStyle(
                        color: Colors.white70,
                        height: 1.4,
                        fontSize: 13.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  /// ?? PRICE CARD (�OK �NEML�)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1F4D3A), Color(0xFF153B2D)],
                      ),
                      border: Border.all(
                        color: const Color(0xFFE7C06A).withOpacity(0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.access_time_filled,
                          color: Color(0xFFE7C06A),
                          size: 16,
                        ),
                        SizedBox(width: 6),
                        Text(
                          '24 Saat',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Spacer(),
                        Icon(
                          Icons.monetization_on,
                          color: Colors.amber,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '10.000',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  /// ?? BUTTONS
                  Row(
                    children: [
                      /// CANCEL
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(context, false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.white.withOpacity(0.03),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                "Vazge�",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      /// ?? BUY BUTTON
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE7C06A), Color(0xFFB9932F)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE7C06A).withOpacity(0.6),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.pop(context, true),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: Text(
                                    "Sat�n Al",
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
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
    if (!showToast || unreadIds.isEmpty || !mounted) return;
    final newestId = unreadIds.first;
    if (_lastSystemToastMessageId == newestId) return;
    _lastSystemToastMessageId = newestId;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Yeni sistem duyurusu var.'),
        action: SnackBarAction(
          label: 'A\u00E7',
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
                if (!mounted) return;
                Navigator.pop(context);
                _msg('Talebiniz al�nm��t�r.');
              } catch (_) {
                setLocalState(() {
                  sending = false;
                  errorText =
                      'Talep g\u00F6nderilemedi. support_requests tablosunu kontrol et.';
                });
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(18),
              child: Container(
                width: 560,
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF132A22), Color(0xFF0D1C17)],
                  ),
                  border: Border.all(
                    color: const Color(0xCCB07A1A),
                    width: 1.8,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.support_agent_rounded,
                          color: Color(0xFFFFE0A8),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Destek �ikayet G�nder',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: sending
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: category,
                      dropdownColor: const Color(0xFF1A2E27),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'talep', child: Text('Talep')),
                        DropdownMenuItem(
                          value: 'sikayet',
                          child: Text('\u015Eikayet'),
                        ),
                        DropdownMenuItem(value: 'hata', child: Text('Hata')),
                      ],
                      onChanged: sending
                          ? null
                          : (v) => setLocalState(
                              () => category = (v ?? 'talep').trim(),
                            ),
                      decoration: InputDecoration(
                        labelText: 'Kategori',
                        labelStyle: const TextStyle(color: Color(0xFFD9EBDD)),
                        filled: true,
                        fillColor: const Color(0x33273830),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: messageController,
                      minLines: 5,
                      maxLines: 7,
                      enabled: !sending,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Mesaj',
                        labelStyle: const TextStyle(color: Color(0xFFD9EBDD)),
                        hintText:
                            'Talep / \u015Fikayet detay\u0131n\u0131 yaz\u0131n.',
                        hintStyle: const TextStyle(color: Color(0x99D9EBDD)),
                        filled: true,
                        fillColor: const Color(0x33273830),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(
                          color: Color(0xFFFF8A8A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: sending
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Vazge�'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: sending ? null : submit,
                          icon: sending
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          label: Text(sending ? 'Gonderiliyor' : 'Gonder'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2B7B55),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
                colors: [Color(0xFF132A22), Color(0xFF0D1C17)],
              ),
              border: Border.all(color: const Color(0xCCB07A1A), width: 1.8),
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
                              const SizedBox(height: 10),
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
                                color: const Color(0x33273830),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0x334F8F75),
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
          profileOnlineById[id] = (row['is_online'] as bool?) ?? false;
          final lastSeenRaw = row['last_seen_at']?.toString();
          profileLastSeenById[id] = lastSeenRaw == null
              ? null
              : DateTime.tryParse(lastSeenRaw)?.toLocal();
        }
      }

      /// FRIEND TABLE MAP
      final friendTables = <String, String>{};

      if (friendIds.isNotEmpty) {
        final tableRows = await supabase
            .from('table_players')
            .select('user_id,table_id')
            .inFilter('user_id', friendIds.toList());

        for (final raw in (tableRows as List)) {
          final row = Map<String, dynamic>.from(raw);
          final userId = row['user_id']?.toString();
          final tableId = row['table_id']?.toString();
          if (userId != null && tableId != null) {
            friendTables[userId] = tableId;
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

      if (!mounted) return;

      setState(() {
        UserState.userId = uid;
        _friends = friendList;
        UserState.friendIds = friendIds;
        UserState.blockedUserIds = blockedIds;
        UserState.incomingRequestIds = incomingRequestIds;
        UserState.outgoingRequestIds = outgoingRequestIds;
        _unreadByUser = unread;
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
    setState(() {
      _rightPanelType = type;
      _rightPanelLoading = false;
    });

    await _loadSocialData();

    if (type == _RightPanelType.messages) {
      final fallbackId = _friends.isNotEmpty
          ? _friends.first['id'] as String
          : null;
      final fallbacktableId = _friends.isNotEmpty
          ? _friends.first['friendid'] as String
          : "";
      final targetUserId = initialChatUserId ?? _activeChatUserId ?? fallbackId;
      final activeChatUserId = _activeChatUserId ?? fallbacktableId;
      if (targetUserId != null) {
        await _loadMessagesWith(targetUserId, activeChatUserId, markRead: true);
      }
    }
  }

  void _closeRightPanel() {
    if (!mounted) return;
    setState(() => _rightPanelType = _RightPanelType.none);
  }

  Future<void> _loadMessagesWith(
    String otherUserId,
    String friendtableid, {
    bool markRead = true,
  }) async {
    final uid = UserState.userId ?? supabase.auth.currentUser?.id;
    if (uid == null) return;
    if (_rightPanelType != _RightPanelType.messages) return;

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

      if (markRead) {
        await supabase
            .from('messages')
            .update({'read_at': DateTime.now().toIso8601String()})
            .eq('sender_id', otherUserId)
            .eq('receiver_id', uid)
            .isFilter('read_at', null);
      }

      if (!mounted) return;
      setState(() {
        _activeChatMessages = (rows as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _rightPanelLoading = false;
        _unreadByUser = Map<String, int>.from(_unreadByUser)
          ..remove(otherUserId);
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom(animated: false);
      });
    } catch (e) {
      debugPrint('MESSAGE LOAD ERROR: $e');
      if (!mounted) return;
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
      return _msg('Sadece arkada�lara mesaj g�nderebilirsin.');
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
      _msg('Mesaj g�nderilemedi.');
      debugPrint('SEND MESSAGE ERROR: $e');
    }
  }

  Future<void> _showCreateModal() async {
    final league = leagues.firstWhere(
      (l) => l['id'] == selectedLeague,
      orElse: () => leagues.first,
    );

    final entry = (league['entry_coin'] as int?) ?? 100;

    final playerCoin = UserState.userCoin;
    final playerRating = UserState.userRating;

    final minCoin = league['min_coin'];
    final minRating = league['min_rating'];

    final eligible = playerCoin >= minCoin && playerRating >= minRating;

    final maxCoin = league['max_coin'];
    bool isDragging = false;

    /// ?? PRESET COIN L�STES�

    int current = minCoin;
    coinOptions = [];
    selectedIndex = 0;
    draftTurnSeconds = 20;
    while (current < maxCoin) {
      coinOptions.add(current);

      if (current < 100000) {
        current *= 2;
      } else if (current < 1000000) {
        current = (current * 2.5).toInt();
      } else {
        current = (current * 2).toInt();
      }

      if (coinOptions.length > 8) break;
    }

    if (!coinOptions.contains(maxCoin)) {
      coinOptions.add(maxCoin);
    }

    // normal default
    /// ?? K�L�TL�YSE � D�REKT SATIN ALMA
    if (!eligible) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoreScreen(initialCoin: UserState.userCoin),
        ),
      );

      /// ?? widget hala aktif mi?
      if (!mounted) return;

      if (result == true) {
        await _loadUser();
      }

      return;
    }

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canCreate = UserState.userCoin >= entry;

            return Material(
              color: Colors.transparent,
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth * 0.65;
                    final height = constraints.maxHeight * 0.85;

                    return Container(
                      width: width,
                      height: height,
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: const Color(0xCFE7C66A),
                          width: 1.0,
                        ),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xF01A3529), Color(0xF00C1813)],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0xB3000000),
                            blurRadius: 30,
                            offset: Offset(0, 14),
                          ),
                          BoxShadow(
                            color: Color(0x3FE7C66A),
                            blurRadius: 18,
                            spreadRadius: -2,
                          ),
                        ],
                      ),

                      child: Column(
                        children: [
                          /// HEADER
                          Row(
                            children: [
                              const Text(
                                "MASA OLUŞTUR",
                                style: TextStyle(
                                  color: Color(0xFFF2D38D),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: 0.5,
                                ),
                              ),

                              const SizedBox(width: 8),

                              Text(
                                league['name'],
                                style: const TextStyle(
                                  color: Color(0xFFEAF3EE),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),

                              const Spacer(),

                              InkWell(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(
                                  Icons.close,
                                  color: Color(0xFFDCE8E2),
                                ),
                              ),
                            ],
                          ),

                          /// LEAGUE INFO

                          /// PICKERS YAN YANA
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                /// ?? SE��LEN COIN (HERO)

                                /// ?? SLIDER (AAA)
                                SizedBox(
                                  height: 90,
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final width = constraints.maxWidth;

                                      const handleWidth = 120.0;
                                      const sidePadding = 58.0;

                                      final usableWidth =
                                          width - (sidePadding * 2);
                                      final percent =
                                          selectedIndex /
                                          (coinOptions.length - 1);
                                      final left =
                                          sidePadding +
                                          (usableWidth - handleWidth) * percent;

                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          /// ?? TRACK
                                          Positioned.fill(
                                            child: Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 18,
                                                  ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                                color: const Color(0x26111915),
                                                border: Border.all(
                                                  color: const Color(0x446E8F7F),
                                                  width: 1.2,
                                                ),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x6A000000),
                                                    blurRadius: 12,
                                                    offset: Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),

                                          /// ?? - BUTTON
                                          Positioned(
                                            left: 6,
                                            top: 0,
                                            bottom: 0,
                                            child: Center(
                                              child: GestureDetector(
                                                onTap: () {
                                                  setDialogState(() {
                                                    selectedIndex =
                                                        (selectedIndex - 1)
                                                            .clamp(
                                                              0,
                                                              coinOptions
                                                                      .length -
                                                                  1,
                                                            );
                                                  });
                                                },
                                                child: _circleButton(
                                                  Icons.remove,
                                                ),
                                              ),
                                            ),
                                          ),

                                          Positioned(
                                            right: 6,
                                            top: 0,
                                            bottom: 0,
                                            child: Center(
                                              child: GestureDetector(
                                                onTap: () {
                                                  setDialogState(() {
                                                    selectedIndex =
                                                        (selectedIndex + 1)
                                                            .clamp(
                                                              0,
                                                              coinOptions
                                                                      .length -
                                                                  1,
                                                            );
                                                  });
                                                },
                                                child: _circleButton(Icons.add),
                                              ),
                                            ),
                                          ),

                                          /// ?? HANDLE + DRAG
                                          Positioned(
                                            left: left,
                                            top: 22,
                                            child: GestureDetector(
                                              onHorizontalDragStart: (_) {
                                                setDialogState(
                                                  () => isDragging = true,
                                                );
                                              },
                                              onHorizontalDragUpdate: (details) {
                                                final dx = details
                                                    .localPosition
                                                    .dx
                                                    .clamp(0, usableWidth);
                                                final newIndex =
                                                    ((dx / usableWidth) *
                                                            (coinOptions
                                                                    .length -
                                                                1))
                                                        .round();

                                                setDialogState(() {
                                                  selectedIndex = newIndex
                                                      .clamp(
                                                        0,
                                                        coinOptions.length - 1,
                                                      );
                                                });
                                              },
                                              onHorizontalDragEnd: (_) {
                                                setDialogState(
                                                  () => isDragging = false,
                                                );
                                              },

                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  /// ?? BALON (SADECE DRAG SIRASINDA)
                                                  if (isDragging)
                                                    Positioned(
                                                      top: -46,
                                                      left: 0,
                                                      right: 0,
                                                      child: Center(
                                                        child: Column(
                                                          children: [
                                                            /// ?? BALON
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        14,
                                                                    vertical: 7,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      12,
                                                                    ),

                                                                /// ?? MODERN DARK GLASS
                                                                gradient: LinearGradient(
                                                                  colors: [
                                                                    Colors.black
                                                                        .withOpacity(
                                                                          0.85,
                                                                        ),
                                                                    Colors.black
                                                                        .withOpacity(
                                                                          0.65,
                                                                        ),
                                                                  ],
                                                                ),

                                                                border: Border.all(
                                                                  color: Colors
                                                                      .white
                                                                      .withOpacity(
                                                                        0.15,
                                                                      ),
                                                                ),

                                                                boxShadow: [
                                                                  /// glow
                                                                  BoxShadow(
                                                                    color: Colors
                                                                        .amber
                                                                        .withOpacity(
                                                                          0.4,
                                                                        ),
                                                                    blurRadius:
                                                                        12,
                                                                  ),

                                                                  /// depth
                                                                  BoxShadow(
                                                                    color: Colors
                                                                        .black
                                                                        .withOpacity(
                                                                          0.6,
                                                                        ),
                                                                    blurRadius:
                                                                        8,
                                                                    offset:
                                                                        const Offset(
                                                                          0,
                                                                          4,
                                                                        ),
                                                                  ),
                                                                ],
                                                              ),
                                                              child: Text(
                                                                Format.coin(
                                                                  coinOptions[selectedIndex],
                                                                ),
                                                                style: const TextStyle(
                                                                  color: Color(
                                                                    0xFFF2C14E,
                                                                  ),
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w900,
                                                                  fontSize: 13,
                                                                  letterSpacing:
                                                                      0.5,
                                                                ),
                                                              ),
                                                            ),

                                                            /// ?? POINTER
                                                            Container(
                                                              width: 10,
                                                              height: 6,
                                                              decoration: BoxDecoration(
                                                                color: Colors
                                                                    .black
                                                                    .withOpacity(
                                                                      0.8,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      2,
                                                                    ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),

                                                  /// ?? HANDLE
                                                  AnimatedContainer(
                                                    duration: const Duration(
                                                      milliseconds: 120,
                                                    ),
                                                    width: handleWidth,
                                                    height: 44,
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            20,
                                                          ),

                                                      gradient:
                                                          const LinearGradient(
                                                            colors: [
                                                              Color(0xFFFFE082),
                                                              Color(0xFFF2C14E),
                                                              Color(0xFFD4A24C),
                                                            ],
                                                            begin: Alignment
                                                                .topCenter,
                                                            end: Alignment
                                                                .bottomCenter,
                                                          ),

                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black
                                                              .withOpacity(0.6),
                                                          blurRadius: 10,
                                                          offset: const Offset(
                                                            0,
                                                            4,
                                                          ),
                                                        ),
                                                        BoxShadow(
                                                          color: const Color(
                                                            0xFFF2C14E,
                                                          ).withOpacity(0.5),
                                                          blurRadius: 12,
                                                        ),
                                                      ],
                                                    ),

                                                    child: Text(
                                                      Format.coin(
                                                        coinOptions[selectedIndex],
                                                      ),
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF1A1A1A,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 14),

                                /// ? OYUN HIZI (AAA SEGMENTED)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: const Color(0x1F101A16),
                                    border: Border.all(
                                      color: const Color(0x44779B8A),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      /// ? HIZLI
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setDialogState(() {
                                              draftTurnSeconds = 15;
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              color: draftTurnSeconds == 15
                                                  ? const Color(0x2EF2C14E)
                                                  : Colors.transparent,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.flash_on,
                                                  size: 16,
                                                  color: draftTurnSeconds == 15
                                                      ? const Color(0xFFF2D38D)
                                                      : Colors.white54,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "Hızlı",
                                                  style: TextStyle(
                                                    color:
                                                        draftTurnSeconds == 15
                                                        ? const Color(0xFFF2D38D)
                                                        : Colors.white70,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                      /// ?? NORMAL
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setDialogState(() {
                                              draftTurnSeconds = 20;
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              color: draftTurnSeconds == 20
                                                  ? const Color(0x2E5FA8FF)
                                                  : Colors.transparent,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.schedule,
                                                  size: 16,
                                                  color: draftTurnSeconds == 20
                                                      ? Colors.blue
                                                      : Colors.white54,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  "Normal",
                                                  style: TextStyle(
                                                    color:
                                                        draftTurnSeconds == 20
                                                        ? Colors.blue
                                                        : Colors.white70,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 10),

                                /// ALT A�IKLAMA
                                Text(
                                  draftTurnSeconds == 15
                                      ? "Daha hızlı oyun • kısa hamle süresi"
                                      : "Standart tempo",
                                  style: const TextStyle(
                                    color: Color(0xB7C9D6CE),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          /// CREATE BUTTON
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: Material(
                              color: Colors.transparent,
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                ),

                                child: buildCreateButton(
                                  canCreate: canCreate,
                                  onTap: () {
                                    createMaxPlayer = 2;
                                    createTurnSeconds = draftTurnSeconds;

                                    Navigator.pop(context);
                                    _createTable();
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
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
              border: Border.all(
                color: const Color(0xFFF9E2A8),
                width: 1.1,
              ),
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
                        fontSize: 16,
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
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFF2C14E), Color(0xFFD4A24C)],
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 8),
        ],
      ),
      child: Icon(icon, color: Colors.black),
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
    final size = MediaQuery.of(context).size;
    final compact = size.width < 1320;
    final leagueWidth = compact ? 260.0 : 270.0;
    if (!_deviceReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xFF0b1d17),
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

          SafeArea(
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        Expanded(
                          child: _connectedLeagueAndTables(
                            leagueWidth: leagueWidth,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                _bottomDock(),
              ],
            ),
          ),

          LobbySideMenu(
            open: _isSideMenuOpen,
            onClose: _closeSideMenu,

            onLeaderboard: () {
              _closeSideMenu();
              _openLeaderboard();
            },

            onFriends: () {
              _closeSideMenu();
              _openRightPanel(_RightPanelType.friends);
            },

            onMessages: () {
              _closeSideMenu();
              _openRightPanel(_RightPanelType.messages);
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
    return LobbyRightPanel(
      open: _rightPanelType != _RightPanelType.none,
      onClose: _closeRightPanel,
      panelContent: _rightPanelContent(),
    );
  }

  Widget _friendsPanel() {
    final body = _friends.isEmpty
        ? const Center(
            child: Text(
              'Hen�z arkada��n yok.',
              style: TextStyle(color: Colors.white70),
            ),
          )
        : ListView.separated(
            itemCount: _friends.length,
            separatorBuilder: (_, index) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
        final friend = _friends[i];
        final blocked = UserState.blockedUserIds.contains(friend['id']);
        final tableId = friend['table_id'];

        return InkWell(
          onTap: () async {
            await ProfileService.showUserCard(
              friend,
              onRefresh: () async {
                await _loadSocialData();
                await _loadTables();
              },
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: const Color(0x6624362E),
              border: Border.all(color: const Color(0x444F8F75)),
            ),
            child: Row(
              children: [
                _statusAvatar(
                  username: friend['username']?.toString() ?? 'Oyuncu',
                  avatarUrl: friend['avatar_url']?.toString(),
                  isOnline: (friend['is_online'] as bool?) ?? false,
                  size: 15,
                  blocked: blocked,
                ),
                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        friend['username']?.toString() ?? 'Oyuncu',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ((friend['is_online'] as bool?) ?? false)
                            ? '�evrimi�i'
                            : _formatLastSeen(friend['last_seen_at']),
                        style: TextStyle(
                          color: ((friend['is_online'] as bool?) ?? false)
                              ? const Color(0xFF7DDA8F)
                              : Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                /// MASADAYSA KATIL BUTONU
                if (tableId != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => SpectatorScreen(tableId: tableId),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E6F5C),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          "Kat�l",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),

                if (blocked)
                  const Icon(
                    Icons.block_rounded,
                    size: 18,
                    color: Color(0xFFFFB3B3),
                  ),
              ],
            ),
          ),
        );
            },
          );

    return Column(
      children: [
        Row(
          children: [
            const Text(
              'Arkadaşlar',
              style: TextStyle(
                color: Color(0xFFEFD18A),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: _closeRightPanel,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close, size: 20, color: Colors.white70),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: body),
      ],
    );
  }

  Widget _messagesPanel() {
    final body = _friends.isEmpty
        ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.group_off, color: Colors.white30, size: 42),
            SizedBox(height: 10),
            Text(
              'Mesajla�mak i�in arkada� eklemelisin',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      )
        : Row(
      children: [
        /// SOL ARKADAŞ L�STES�
        Container(
          width: 230,
          decoration: BoxDecoration(
            color: const Color(0x4424362E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0x334F8F75)),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: _friends.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final friend = _friends[i];
              final friendId = friend['id']?.toString();
              final selected = friendId == _activeChatUserId;
              final unread = _unreadByUser[friendId] ?? 0;
              final friendtableid = friend['friendid']?.toString() ?? "";
              return InkWell(
                onTap: friendId == null
                    ? null
                    : () => _loadMessagesWith(
                        friendId,
                        friendtableid,
                        markRead: true,
                      ),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: selected
                        ? const Color(0xAA2E7752)
                        : const Color(0x6624362E),
                    border: Border.all(
                      color: selected
                          ? const Color(0x88E7C06A)
                          : const Color(0x334F8F75),
                    ),
                  ),
                  child: Row(
                    children: [
                      /// AVATAR + ONLINE
                      _statusAvatar(
                        username: friend['username']?.toString() ?? 'Oyuncu',
                        avatarUrl: friend['avatar_url']?.toString(),
                        isOnline: (friend['is_online'] as bool?) ?? false,
                        size: 16,
                      ),

                      const SizedBox(width: 8),

                      /// �S�M + SON G�R�LME
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              friend['username']?.toString() ?? 'Oyuncu',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (!((friend['is_online'] as bool?) ?? false))
                              Text(
                                _formatLastSeen(friend['last_seen_at']),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),

                      if (unread > 0) _badge(unread.toString()),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(width: 12),

        /// MESAJ PANEL�
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0x5524362E),
              border: Border.all(color: const Color(0x334F8F75)),
            ),
            child: Column(
              children: [
                /// MESAJ L�STES�
                Expanded(
                  child: Stack(
                    children: [
                      /// 💬 MESAJ L�STES�
                      _rightPanelLoading
                          ? Center(child: _premiumLoader(size: 32))
                          : ListView.builder(
                              controller: _chatScrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: _activeChatMessages.length,
                              itemBuilder: (_, i) {
                                final msg = _activeChatMessages[i];
                                final senderId = msg['sender_id']?.toString();
                                final mine =
                                    msg['sender_id'] == UserState.userId;

                                final isVoice = msg['type'] == 'voice';
                                final friendData = senderId == null
                                    ? null
                                    : _friends
                                          .cast<Map<String, dynamic>?>()
                                          .firstWhere(
                                            (f) =>
                                                f?['id']?.toString() ==
                                                senderId,
                                            orElse: () => null,
                                          );
                                final senderName = mine
                                    ? (UserState.userName.isEmpty
                                          ? 'Sen'
                                          : UserState.userName)
                                    : (friendData?['username']?.toString() ??
                                          'Oyuncu');
                                final senderAvatar = mine
                                    ? UserState.userAvatarUrl
                                    : friendData?['avatar_url']?.toString();
                                final senderOnline = mine
                                    ? true
                                    : ((friendData?['is_online'] as bool?) ??
                                          false);

                                final bubble = AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  constraints: const BoxConstraints(
                                    maxWidth: 260,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                    gradient: mine
                                        ? const LinearGradient(
                                            colors: [
                                              Color(0xFF2E7752),
                                              Color(0xFF1F5A40),
                                            ],
                                          )
                                        : const LinearGradient(
                                            colors: [
                                              Color(0xFF3A4A43),
                                              Color(0xFF2C3934),
                                            ],
                                          ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: mine
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        senderName,
                                        style: const TextStyle(
                                          color: Color(0xFFD4AF37),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      isVoice
                                          ? _voiceBubble(msg, mine)
                                          : Text(
                                              msg['content']?.toString() ?? '',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                height: 1.35,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                    ],
                                  ),
                                );

                                return Align(
                                  alignment: mine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: mine
                                        ? [
                                            bubble,
                                            const SizedBox(width: 8),
                                            _statusAvatar(
                                              username: senderName,
                                              avatarUrl: senderAvatar,
                                              isOnline: senderOnline,
                                              size: 12,
                                            ),
                                          ]
                                        : [
                                            _statusAvatar(
                                              username: senderName,
                                              avatarUrl: senderAvatar,
                                              isOnline: senderOnline,
                                              size: 12,
                                            ),
                                            const SizedBox(width: 8),
                                            bubble,
                                          ],
                                  ),
                                );
                              },
                            ),

                      /// 🔥 FLOATING MENU (Ş�MD� �ALIŞIR)
                      Positioned(top: 8, right: 8, child: _floatingMenu()),
                    ],
                  ),
                ),
                if (_showPreview && _previewPath != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151A18),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        /// ▶️ PLAY
                        GestureDetector(
                          onTap: () async {
                            if (_previewPlaying) {
                              await _audioPlayer.stop();
                              setState(() => _previewPlaying = false);
                            } else {
                              if (!FeedbackSettingsService.soundEnabled) {
                                await FeedbackSettingsService.triggerHaptic();
                                return;
                              }
                              await _audioPlayer.setFilePath(_previewPath!);
                              await _audioPlayer.play();
                              await FeedbackSettingsService.triggerHaptic();
                              setState(() => _previewPlaying = true);

                              _audioPlayer.playerStateStream.listen((state) {
                                if (state.processingState ==
                                    ProcessingState.completed) {
                                  setState(() => _previewPlaying = false);
                                }
                              });
                            }
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _previewPlaying
                                  ? const Color(0xFFE7C06A)
                                  : Colors.white24,
                            ),
                            child: Icon(
                              _previewPlaying ? Icons.pause : Icons.play_arrow,
                              color: _previewPlaying
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        /// 🔊 WAVE
                        Expanded(child: _waveform(_previewPlaying)),

                        const SizedBox(width: 8),

                        /// ❌ DELETE
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.redAccent,
                          ),
                          onPressed: () async {
                            final path = _previewPath;

                            if (path == null) return;

                            await File(path).delete();

                            if (mounted) {
                              setState(() {
                                _previewPath = null;
                                _showPreview = false;
                              });
                            }
                          },
                        ),

                        /// ✅ SEND
                        IconButton(
                          icon: const Icon(
                            Icons.send,
                            color: Colors.greenAccent,
                          ),
                          onPressed: () async {
                            final path = _previewPath;

                            if (path == null) return;

                            await _sendVoiceMessage(path);

                            if (mounted) {
                              setState(() {
                                _previewPath = null;
                                _showPreview = false;
                              });
                            }

                            await File(path).delete();
                          },
                        ),
                      ],
                    ),
                  ),
                if (_isRecording)
                  Container(
                    margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151A18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.redAccent.withOpacity(.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        /// 🎤 ICON
                        const Icon(
                          Icons.mic,
                          color: Colors.redAccent,
                          size: 18,
                        ),

                        const SizedBox(width: 10),

                        /// TEXT
                        const Text(
                          "Recording...",
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),

                        const Spacer(),

                        /// 🔴 BLINK DOT
                        _recordDot(),

                        const SizedBox(width: 6),

                        /// ⏱️ TIMER
                        Text(
                          _recordDuration,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                /// MESAJ G�NDERME ALANI
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0x334F8F75))),
                  ),
                  child: Row(
                    children: [
                      Listener(
                        onPointerDown: (_) async {
                          print("DOWN");

                          _pressStartTime = DateTime.now();

                          await Future.delayed(
                            const Duration(milliseconds: 250),
                          );

                          // hala bas�l�ysa ba�lat
                          if (_isPressing) {
                            print("START RECORD");
                            await _startRecording();
                          }
                        },

                        onPointerUp: (_) async {
                          print("UP");

                          _isPressing = false;

                          await _stopRecording(send: true);
                        },

                        onPointerCancel: (_) async {
                          print("CANCEL");

                          _isPressing = false;

                          await _stopRecording(send: false);
                        },

                        child: GestureDetector(
                          onTapDown: (_) {
                            _isPressing = true;
                          },
                          onTapUp: (_) {
                            _isPressing = false;
                          },
                          child: _recordButton(),
                        ),
                      ),

                      /// 🎤 VOICE BUTTON
                      const SizedBox(width: 8),

                      /// TEXTFIELD
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          style: const TextStyle(
                            color: Color(0xFFF3FFF9),
                            fontWeight: FontWeight.w600,
                          ),
                          cursorColor: const Color(0xFFE7C06A),
                          decoration: InputDecoration(
                            hintText: 'Mesaj yaz...',
                            hintStyle: const TextStyle(
                              color: Color(0x8FB8CEC3),
                            ),
                            filled: true,
                            fillColor: const Color(0x5524362E),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0x3359A588),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0x3359A588),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Color(0x88E7C06A),
                                width: 1.3,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),

                      const SizedBox(width: 8),

                      /// G�NDER BUTONU
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE7C06A), Color(0xFF9C7A2B)],
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _sendMessage,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Center(
                                child: Icon(
                                  Icons.send,
                                  color: Colors.black,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return Column(
      children: [
        Row(
          children: [
            const Text(
              'Mesajlar',
              style: TextStyle(
                color: Color(0xFFEFD18A),
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: _closeRightPanel,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close, size: 20, color: Colors.white70),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: body),
      ],
    );
  }

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
          border: Border.all(color: const Color(0x334F8F75)),
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
                border: Border.all(color: const Color(0x334F8F75)),
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
                  /// 🧠 TITLE
                  const Text(
                    "Sohbeti sil",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  /// ⚠️ DESCRIPTION
                  const Text(
                    "Bu kullan�c�yla t�m mesajlar ve ses kay�tlar� silinecek.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),

                  const SizedBox(height: 18),

                  /// 🔘 BUTTONS
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
                                color: const Color(0x334F8F75),
                              ),
                            ),
                            child: const Text(
                              "�ptal",
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
      /// 3. mesajlar� sil
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
      _msg("Silme hatas�");
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

      /// 🆔 message id
      final messageId = const Uuid().v4();

      final storagePath = 'friend/$ftableid/$messageId.m4a';

      /// 📦 1. STORAGE UPLOAD
      await supabase.storage.from('voice').upload(storagePath, file);

      /// 🧾 2. DB INSERT (senin yap�ya uyumlu)
      await supabase.from('messages').insert({
        'sender_id': uid,
        'receiver_id': otherId,
        'content': null, // ❗ text yok
        'type': 'voice',
        'voice_url': storagePath,
        'duration': 5, // �imdilik sabit
      });

      /// 🧹 3. LOCAL TEM�ZLE
      await file.delete();

      /// 🔄 4. CHAT REFRESH (senin sistem)
      await _loadMessagesWith(otherId, ftableid, markRead: false);
    } catch (e) {
      _msg('Sesli mesaj g�nderilemedi.');
      debugPrint('VOICE MESSAGE ERROR: $e');
    }
  }

  Future<String> getVoiceUrl(String path) async {
    return await supabase.storage.from('voice').createSignedUrl(path, 60);
  }

  Widget _voiceBubble(Map<String, dynamic> msg, bool mine) {
    final isPlaying = _playingMessageId == msg['id'];

    return Row(
      mainAxisSize: MainAxisSize.min, // ❗ �nemli
      children: [
        /// ▶️ PLAY
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

        /// 🔊 WAVE
        SizedBox(
          width: 80, // ❗ sabit width
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

        /// ⏱️ s�re
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

      /// ayn� mesaj → stop
      if (_playingMessageId == msg['id']) {
        await _audioPlayer.stop();
        setState(() => _playingMessageId = null);
        return;
      }

      /// yeni mesaj ba�lat
      final url = await supabase.storage
          .from('voice')
          .createSignedUrl(path, 60);

      await _audioPlayer.stop(); // 💥 �nemli (�nceki sesi kes)

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

    /// 💥 EN KR�T�K (recorder warmup)
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

    /// ❗ ARTIK G�NDERMEY�Z
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

        /// 🎨 BACKGROUND
        color: _isRecording ? Colors.redAccent : const Color(0xFF1E2A25),

        /// 💎 BORDER
        border: Border.all(
          color: _isRecording ? Colors.redAccent : const Color(0x3359A588),
          width: _isRecording ? 1.6 : 1,
        ),

        /// ✨ GLOW
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
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF18231F),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x3359A588)),
          ),
          child: Column(
            children: [
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF163328),
                activeTrackColor: const Color(0xFFE7C06A),
                inactiveThumbColor: const Color(0xFF8EA79A),
                inactiveTrackColor: const Color(0x334E6A5D),
                title: const Text(
                  'Ses',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Oyun ve mesaj sesleri',
                  style: TextStyle(color: Colors.white70),
                ),
                value: _soundEnabled,
                onChanged: (value) async {
                  await FeedbackSettingsService.setSoundEnabled(value);
                  if (!mounted) return;
                  setState(() => _soundEnabled = value);
                },
              ),
              const Divider(color: Color(0x3359A588), height: 1),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF163328),
                activeTrackColor: const Color(0xFFE7C06A),
                inactiveThumbColor: const Color(0xFF8EA79A),
                inactiveTrackColor: const Color(0x334E6A5D),
                title: const Text(
                  'Titre�im',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Sesle birlikte haptic geri bildirim',
                  style: TextStyle(color: Colors.white70),
                ),
                value: _vibrationEnabled,
                onChanged: (value) async {
                  await FeedbackSettingsService.setVibrationEnabled(value);
                  if (!mounted) return;
                  setState(() => _vibrationEnabled = value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        lobbySideMenuButton(
          icon: Icons.support_agent_rounded,
          label: 'Destek / \u015Eikayet G\u00F6nder',
          onTap: () async {
            _closeRightPanel();
            await _openSupportRequestDialog();
          },
        ),
        const SizedBox(height: 6),
        lobbySideMenuButton(
          icon: Icons.notifications_active_rounded,
          label: 'Sistem Duyurular\u0131',
          onTap: () async {
            _closeRightPanel();
            await _showSystemMessagesDialog();
          },
        ),
        const SizedBox(height: 6),
        lobbySideMenuButton(
          icon: Icons.person_rounded,
          label: 'Profil Kart�m',
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
            },
          ),
        ),

        const SizedBox(height: 10),

        // 🔥 YEN� EKLED�Ğ�M�Z
        lobbySideMenuButton(
          icon: Icons.delete_forever_rounded,
          label: 'Hesab� Sil',
          danger: true,
          onTap: () async {
            _closeRightPanel();
            await _confirmDeleteAccount();
          },
        ),
      ],
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Hesab� Sil"),
          content: Text(
            "Bu i�lem geri al�namaz. Hesab�n�z ve t�m verileriniz silinecek. Emin misiniz?",
          ),
          actions: [
            TextButton(
              child: Text("�ptal"),
              onPressed: () => Navigator.pop(context, false),
            ),
            TextButton(
              child: Text("Sil"),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
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
      ).showSnackBar(SnackBar(content: Text("Hesap silinirken hata olu�tu")));
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

  Widget _connectedLeagueAndTables({required double leagueWidth}) {
    return Row(
      children: [
        /// 🔥 SOL PANEL (GLASS EFFECT)
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Container(
              /// 🔥 biraz daha geni�
              width: leagueWidth + 80,

              margin: const EdgeInsets.fromLTRB(4, 2, 6, 8),
              padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),

              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),

                /// ?? ANA BORDER (daha koyu + classy)
                border: Border.all(
                  color: const Color(0x33FFEBC6), // ?? opacity d���r�ld�
                  width: 1.0,
                ),

                /// ?? SOFT SHADOW SYSTEM
                boxShadow: [
                  /// �ok hafif d�� glow
                  BoxShadow(
                    color: const Color(0xFFFFD76A).withOpacity(0.10),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),

                  /// ambient shadow
                  BoxShadow(
                    color: Colors.black.withOpacity(0.35),
                    blurRadius: 12,
                  ),

                  /// i� derinlik
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      const Text(
                        "Adil Dağıtım • Gerçek Rekabet",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD4A24C),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  /// 🔥 GOLD DIVIDER
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Color(0x66F2C14E),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  /// 🔥 L�G L�STES�
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
          ),
        ),

        /// 🔥 MASALAR
        Expanded(
          child: LobbyTableWheel(
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
              await _loadTables(); // ?? coin de�i�ti � listeler de�i�ebilir
            },

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
          ),
        ),
      ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2328), Color(0xFF11181C)],
        ),
        border: Border.all(color: const Color(0x33E7C06A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFE7C06A)),
          const SizedBox(width: 4),
          Text(
            coin ? Format.coin(value) : Format.rating(value),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dockLeft() {
    return Row(
      children: [
        lobbyDockIcon(
          asset: "assets/images/lobby/menu_bar.png",
          onTap: _toggleSideMenu,
        ),
        const SizedBox(width: 10),

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
          child: LobbyAvatar(
            username: UserState.userName,
            avatarUrl: UserState.userAvatarUrl,
          ),
        ),

        const SizedBox(width: 10),

        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              UserState.userName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 5), // 🔥 BURASI

            Row(
              children: [
                statChip(Icons.star, UserState.userRating, false),

                const SizedBox(width: 10),

                statChip(Icons.monetization_on, UserState.userCoin, true),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _dockCenter() {
    return Transform.translate(
      offset: const Offset(0, -20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [CreateButton(onTap: _showCreateModal)],
      ),
    );
  }

  Widget _dockRight() {
    return Row(
      children: [
        AaaDockIcon(
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoreScreen(initialCoin: UserState.userCoin),
              ),
            );

            if (result == true) {
              await _loadUser(); // coin yeniden y�klenir
            }
          },
          child: const PremiumCoinButton(),
        ),
        const SizedBox(width: 10),
        AaaDockIcon(
          icon: Icons.emoji_events,
          onTap: () {
            _openLeaderboard();
          },
        ),
        const SizedBox(width: 10),
        AaaDockIcon(
          icon: Icons.people,
          onTap: () => _openRightPanel(_RightPanelType.friends),
        ),
        const SizedBox(width: 10),
        AaaDockIcon(
          icon: Icons.mail,
          onTap: () => _openRightPanel(_RightPanelType.messages),
        ),
      ],
    );
  }

  IconData _leagueIcon(String id) {
    switch (id) {
      case 'standard':
        return Icons.star;
      case 'bronze':
        return Icons.extension; // puzzle hissi
      case 'silver':
        return Icons.build; // kalfa
      case 'gold':
        return Icons.workspace_premium; // usta
      case 'elite':
        return Icons.emoji_events; // �ampiyon
      default:
        return Icons.circle;
    }
  }

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

    // ?? 1. G�NDERENE G�RE GRUPLA
    final Map<String, List<dynamic>> grouped = {};

    for (final g in res) {
      final sender = g['sender_id'];
      grouped.putIfAbsent(sender, () => []).add(g);
    }

    // ?? 2. HER GRUP ���N G�STER
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

      // ?? gift info (ilk gift �zerinden)
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
          senderId: senderId,
        );
      } else {
        // ?? �OKLU GIFT
        GiftOverlay.show(
          senderName: senderName,
          emoji: "??",
          giftName: "${gifts.length} hediye g�nderdi!",
          senderId: senderId,
        );
      }

      // ?? CONFETTI (her sender i�in 1 kere)
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
