import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:okeyix/screens/spectator_screen.dart';
import 'package:okeyix/ui/lobby/LobbyTableWheel.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'okey_game_screen.dart';
import 'login_screen.dart';
import 'store_screen.dart';
import 'leaderboard_screen.dart';
import '../ui/avatar_preset.dart';
import '../ui/lobby/lobby_avatar.dart';
import '../ui/lobby/lobby_league_list.dart';
import '../ui/lobby/lobby_bottom_dock.dart';
import '../ui/lobby/lobby_side_menu.dart';
import '../ui/lobby/lobby_right_panel.dart';
import '../ui/lobby/_ui_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
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
  static const String _freeRenameUsedPrefix = 'profile.free_rename_used.';
  static const String _ownedPremiumAvatarPrefix = 'profile.premium_avatars.';
  final _audioPlayer = AudioPlayer();
  static const _secureStorage = FlutterSecureStorage();
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

  List<Map<String, dynamic>> leagues = [];
  List<Map<String, dynamic>> tables = [];
  Map<String, int> leagueActivePlayers = {};

  bool loadingLeagues = true;
  bool loadingTables = true;
  bool _tablesInitialized = false;
  bool _isSideMenuOpen = false;
  bool _rightPanelLoading = false;

  String userName = 'Oyuncu';
  int userRating = 1200;
  int userCoin = 0;
  String? _userId;
  String? _userRowId;
  String? _userAvatarUrl;

  _RightPanelType _rightPanelType = _RightPanelType.none;
  List<Map<String, dynamic>> _friends = [];
  Map<String, int> _unreadByUser = {};
  Set<String> _friendIds = {};
  Set<String> _blockedUserIds = {};
  Set<String> _incomingRequestIds = {};
  Set<String> _outgoingRequestIds = {};
  final Set<String> _notifiedIncomingRequestIds = <String>{};
  List<Map<String, dynamic>> _activeChatMessages = [];
  String? _activeChatUserId;
  String? _activeChatUserTableId;
  bool _friendRequestPromptOpen = false;
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
  List<Map<String, dynamic>> _systemMessages = [];
  final Set<String> _seenSystemMessageIds = <String>{};
  String? _lastSystemToastMessageId;
  DateTime? _globalSpectatorPassUntil;
  bool _campaignChecked = false;
  @override
  void initState() {
    super.initState();
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
      /// ğŸ”¥ UI HEMEN AÇILSIN
      setState(() {
        _deviceReady = true;
      });

      /// ğŸ”¥ REGISTER ARKADA ÇALIÅSIN
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
    final deviceInfo = DeviceInfoPlugin();
    String? id;

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      id = prefs.getString("device_id");
      id ??= 'web_${const Uuid().v4()}';
      await prefs.setString("device_id", id);
    } else if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      id = 'android_${android.id}';
    } else if (Platform.isIOS) {
      id = await _secureStorage.read(key: 'stable_device_id');
      if (id == null || id.isEmpty) {
        final ios = await deviceInfo.iosInfo;
        final vendor = ios.identifierForVendor;
        id = (vendor != null && vendor.isNotEmpty)
            ? 'ios_$vendor'
            : 'ios_${const Uuid().v4()}';
        await _secureStorage.write(key: 'stable_device_id', value: id);
      }
    } else {
      id = await _secureStorage.read(key: 'stable_device_id');
      id ??= 'device_${const Uuid().v4()}';
      await _secureStorage.write(key: 'stable_device_id', value: id);
    }
    return id;
  }

  Future<void> registerDevice() async {
    try {
      final deviceId = await getDeviceId();

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
      final res = await supabase.functions.invoke(
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

      /// ğŸ”¥ HATA KONTROLÜ BURADA
    } catch (e) {
      print(e);

      /// ğŸ”¥ SADECE SIGNOUT + FORWARD

      rethrow; // ğŸ”¥ EN DOÄRU
    }
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
    await _checkCampaignPopup();
  }

  Future<void> _ensureUserRow() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final existing = await _findUserRow(
        user,
        columns: 'id,email,username,avatar_url',
      );
      if (existing != null) return;
      await supabase.from('users').insert({'id': user.id, 'email': user.email});
    } catch (e) {
      debugPrint('ENSURE USER ROW ERROR: $e');
    }
  }

  Future<Map<String, dynamic>?> _findUserRow(
    User user, {
    required String columns,
  }) async {
    final byId = await supabase
        .from('users')
        .select(columns)
        .eq('id', user.id)
        .limit(1);
    if ((byId as List).isNotEmpty) {
      return Map<String, dynamic>.from(byId.first);
    }

    final email = user.email?.trim();
    if (email == null || email.isEmpty) return null;

    final byEmail = await supabase
        .from('users')
        .select(columns)
        .eq('email', email)
        .limit(1);
    if ((byEmail as List).isNotEmpty) {
      return Map<String, dynamic>.from(byEmail.first);
    }
    return null;
  }

  Future<void> _loadUser() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await _ensureUserRow();
    try {
      final row = await _findUserRow(
        user,
        columns: 'id,username,avatar_url',
      );
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
      final effectiveCoin = profileCoin;
      final effectiveRating = profileRating;

      if (!mounted) return;
      if (row != null) {
        setState(() {
          _userId = user.id;
          _userRowId = row['id']?.toString();
          userName = ((row['username'] as String?) ?? '').trim().isEmpty
              ? (user.email?.split('@').first ?? 'Oyuncu')
              : row['username'] as String;
          userRating = effectiveRating;
          _userAvatarUrl = (row['avatar_url'] as String?)?.trim();
          userCoin = effectiveCoin;
        });
      } else {
        setState(() {
          _userId = user.id;
          _userRowId = null;
          userName = user.email?.split('@').first ?? 'Oyuncu';
          userRating = effectiveRating;
          _userAvatarUrl = null;
          userCoin = effectiveCoin;
        });
      }
    } catch (e) {
      debugPrint('USER LOAD ERROR: $e');
    }
  }

  Future<void> _checkOnboarding() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await _ensureUserRow();
    try {
      final row = await _findUserRow(user, columns: 'id,username,avatar_url');
      if (row == null) return;
      final username = ((row['username'] as String?) ?? '').trim();
      final avatar = ((row['avatar_url'] as String?) ?? '').trim();
      final isIncomplete = username.isEmpty || avatar.isEmpty;
      if (isIncomplete && _isLikelyFirstLogin(user)) {
        if (!mounted) return;
        await _openProfileSetupDialog(forceComplete: true);
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

  Future<void> _openProfileSetupDialog({required bool forceComplete}) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await _ensureUserRow();

    var initialUsername = userName == 'Oyuncu' ? '' : userName;
    var initialAvatar = _userAvatarUrl;

    try {
      final row = await _findUserRow(user, columns: 'id,username,avatar_url');
      if (row != null) {
        initialUsername = ((row['username'] as String?) ?? '').trim();
        initialAvatar = (row['avatar_url'] as String?)?.trim();
        _userRowId = row['id']?.toString();
      }
    } catch (_) {}

    final freeRenameUsed = await _isFreeRenameUsed(user.id);
    final ownedPremiumAvatars = await _getOwnedPremiumAvatars(user.id);

    if (!mounted) return;
    final result = await showDialog<_ProfileSetupResult>(
      context: context,
      barrierDismissible: !forceComplete,
      builder: (_) => _ProfileSetupDialog(
        forceComplete: forceComplete,
        initialUsername: initialUsername,
        initialAvatarRef: initialAvatar,
        currentUserId: user.id,
        currentCoins: userCoin,
        renameCoinCost: _renameCoinCost,
        freeRenameUsed: freeRenameUsed,
        ownedPremiumAvatarRefs: ownedPremiumAvatars,
      ),
    );

    if (result == null) return;

    try {
      final payload = {
        'username': result.username,
        'avatar_url': normalizeAvatarForStorage(result.avatarRef),
      };
      final targetId = _userRowId ?? user.id;
      final updated = await supabase
          .from('users')
          .update(payload)
          .eq('id', targetId)
          .select('id')
          .limit(1);

      if ((updated as List).isEmpty) {
        final email = user.email?.trim();
        if (email != null && email.isNotEmpty) {
          final updatedByEmail = await supabase
              .from('users')
              .update(payload)
              .eq('email', email)
              .select('id')
              .limit(1);
          if ((updatedByEmail as List).isNotEmpty) {
            _userRowId = updatedByEmail.first['id']?.toString();
          } else {
            await supabase.from('users').insert({
              'id': user.id,
              'email': user.email,
              ...payload,
            });
            _userRowId = user.id;
          }
        }
      } else {
        _userRowId = updated.first['id']?.toString();
      }

      if (result.renameCoinSpent > 0) {
        await _spendProfileCoins(
          userId: user.id,
          amount: result.renameCoinSpent,
          reason: 'profile_name_change',
          note: 'profile_name_change_coin_spend',
        );
      }
      if (result.avatarCoinSpent > 0) {
        final unlockedAvatarRef = result.unlockedAvatarRef;
        await _spendProfileCoins(
          userId: user.id,
          amount: result.avatarCoinSpent,
          reason: 'avatar_purchase',
          note: unlockedAvatarRef == null
              ? 'profile_avatar_purchase'
              : 'profile_avatar_purchase:$unlockedAvatarRef',
        );
      }
      if (result.consumeFreeRename) {
        await _setFreeRenameUsed(user.id);
      }
      if (result.newUnlockedPremiumAvatarRefs.isNotEmpty) {
        final merged = {
          ...ownedPremiumAvatars,
          ...result.newUnlockedPremiumAvatarRefs,
        };
        await _setOwnedPremiumAvatars(user.id, merged);
      }

      await _loadUser();
      await _loadTables();
      if (!mounted) return;
      if (result.spentCoins > 0) {
        _msg('Profil guncellendi. ${result.spentCoins} coin harcandi.');
      } else {
        _msg('Profil guncellendi.');
      }
      return;
    } catch (e) {
      if (e is PostgrestException && e.code == '23505') {
        _msg('Bu kullanıcı adı zaten kullanımda.');
      } else {
        _msg('Profil guncellenemedi.');
      }
      return;
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
    final minPlayersByName = {
      'Standart': 180,
      'Bronz': 120,
      'Gümüş': 80,
      'Altın': 40,
    };

    if (leagues.isEmpty) return;

    try {
      final activeTables = await supabase
          .from('tables')
          .select('id,league_id,status')
          .inFilter('status', ['waiting', 'playing']);

      final tableRows = (activeTables as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final usersByLeague = <String, Set<String>>{};

      if (tableRows.isNotEmpty) {
        final tableIds = tableRows.map((e) => e['id'] as String).toList();

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
      final result = <String, int>{};

      for (final league in leagues) {
        final id = league['id']?.toString();
        final name = league['name']?.toString();

        if (id == null) continue;

        final realPlayers = usersByLeague[id]?.length ?? 0;
        final basePlayers = minPlayersByName[name] ?? 50;

        final fluctuation = rnd.nextInt(25); // 0-24

        result[id] =
            (realPlayers > basePlayers ? realPlayers : basePlayers) +
            fluctuation;
      }

      if (!mounted) return;

      setState(() {
        leagueActivePlayers = result;
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
      try {
        await supabase
            .from('match_moves')
            .delete()
            .inFilter('table_id', orphanTableIds);
      } catch (_) {}
      try {
        await supabase
            .from('table_discard_tops')
            .delete()
            .inFilter('table_id', orphanTableIds);
      } catch (_) {}
      try {
        await supabase
            .from('table_discards')
            .delete()
            .inFilter('table_id', orphanTableIds);
      } catch (_) {}
      try {
        await supabase
            .from('table_players')
            .delete()
            .inFilter('table_id', orphanTableIds);
      } catch (_) {}
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
              'blocked': uid != null && _blockedUserIds.contains(uid),
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
    final entry = (league['entry_coin'] as int?) ?? 100;
    final effectiveTurnSeconds = createTurnSeconds;
    if (userCoin < entry) return _msg('Yetersiz coin.');
    if (userRating < ((league['min_rating'] as int?) ?? 0)) {
      return _msg('Bu lig için rating yetersiz.');
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
      _msg('Bu masa vitrin masasıdır. Katılım kapalı.');
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
    if (userCoin < entry) return _msg('Yetersiz coin.');
    final tableRating = await supabase
        .from('leagues')
        .select('min_rating')
        .eq('id', table['league_id'])
        .limit(1);
    if ((tableRating as List).isNotEmpty) {
      final minRating = (tableRating.first['min_rating'] as int?) ?? 0;
      if (userRating < minRating) {
        return _msg('Bu lig için rating yetersiz.');
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
    await precacheImage(const AssetImage('assets/images/lobby/lobby.png'), context);
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
    if (userCoin < _globalSpectatorPassCost) {
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
      await _spendProfileCoins(
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
      if (uid != null && _friendIds.contains(uid)) return true;
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
      builder: (context) {
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
              border: Border.all(color: const Color(0xCCB07A1A), width: 1.8),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 22,
                  offset: Offset(0, 10),
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
                      Icons.workspace_premium_rounded,
                      color: Color(0xFFFFE0A8),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Genel Seyirci Geçişi',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x33273830),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x334F8F75)),
                  ),
                  child: const Text(
                    'Sadece arkadaşı olduğun kullanıcının masasını ücretsiz izleyebilirsin.\n\n'
                    '24 saat boyunca tüm oynanan masaları izlemek için '
                    '10.000 coin ile Genel Seyirci Geçişi açabilirsin.',
                    style: TextStyle(
                      color: Color(0xFFD9EBDD),
                      height: 1.35,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF24563F), Color(0xFF1B4232)],
                    ),
                    border: Border.all(color: const Color(0x66E7C06A)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.access_time_filled_rounded,
                        size: 16,
                        color: Color(0xFFFFE0A8),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Süre: 24 saat  •  Ücret: 10.000 coin',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Vazgeç'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.visibility_rounded),
                      label: const Text('10.000 coin ile Aç'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2B7B55),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(
                            color: Color(0xFF8F6215),
                            width: 1.2,
                          ),
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
                });
                if (!mounted) return;
                Navigator.pop(context);
                _msg('Talebiniz al\u0131nm\u0131\u015Ft\u0131r.');
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
                          'Destek / \u015Eikayet G\u00F6nder',
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
                          child: const Text('Vazgeç'),
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

  Future<bool> _isFreeRenameUsed(String userId) async {
    try {
      final rows = await supabase
          .from('wallet_transactions')
          .select('id')
          .eq('user_id', userId)
          .eq('reason', 'profile_name_change')
          .limit(1);
      if ((rows as List).isNotEmpty) {
        return true;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_freeRenameUsedPrefix$userId') ?? false;
  }

  Future<void> _setFreeRenameUsed(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_freeRenameUsedPrefix$userId', true);
  }

  Future<Set<String>> _getOwnedPremiumAvatars(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('$_ownedPremiumAvatarPrefix$userId');
    final owned = stored == null ? <String>{} : stored.toSet();
    try {
      final purchaseRows = await supabase
          .from('wallet_transactions')
          .select('reason,note')
          .eq('user_id', userId)
          .eq('reason', 'avatar_purchase');
      for (final row in (purchaseRows as List)) {
        final note = row['note']?.toString() ?? '';
        if (note.startsWith('profile_avatar_purchase:')) {
          final ref = note.split(':').last.trim();
          if (ref.isNotEmpty) owned.add(ref);
        }
      }
    } catch (_) {}
    return owned;
  }

  Future<void> _setOwnedPremiumAvatars(String userId, Set<String> owned) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      '$_ownedPremiumAvatarPrefix$userId',
      owned.toList()..sort(),
    );
  }

  Future<void> _spendProfileCoins({
    required String userId,
    required int amount,
    required String reason,
    required String note,
  }) async {
    if (amount <= 0) return;
    final profileRows = await supabase
        .from('profiles')
        .select('coins')
        .eq('id', userId)
        .limit(1);
    final currentCoins = (profileRows as List).isNotEmpty
        ? (profileRows.first['coins'] as int?) ?? userCoin
        : userCoin;
    if (currentCoins < amount) {
      throw Exception('Insufficient profile balance');
    }
    final nextCoins = max(0, currentCoins - amount);

    await supabase.from('wallet_transactions').insert({
      'user_id': userId,
      'amount': -amount,
      'reason': reason,
      'type': 'debit',
      'store': 'system',
      'note': note,
    });

    if ((profileRows).isNotEmpty) {
      await supabase
          .from('profiles')
          .update({'coins': nextCoins})
          .eq('id', userId);
    }
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
      final previousIncoming = Set<String>.from(_incomingRequestIds);

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
      if (counterpartIds.isNotEmpty) {
        final userRows = await supabase
            .from('users')
            .select('id,username,avatar_url')
            .inFilter('id', counterpartIds.toList());
        final profileRows = await supabase
            .from('profiles')
            .select('id,rating')
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
        _userId = uid;
        _friends = friendList;
        _friendIds = friendIds;
        _blockedUserIds = blockedIds;
        _incomingRequestIds = incomingRequestIds;
        _outgoingRequestIds = outgoingRequestIds;
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
          _showIncomingFriendRequestDialog(requesterId, usersById[requesterId]),
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
    final uid = _userId ?? supabase.auth.currentUser?.id;
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
    final uid = _userId ?? supabase.auth.currentUser?.id;
    final otherId = _activeChatUserId;
    final ftableid = _activeChatUserTableId ?? "";
    final text = _chatController.text.trim();
    if (uid == null || otherId == null || text.isEmpty) return;
    if (!_friendIds.contains(otherId)) {
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

  Future<void> _sendFriendRequest(String otherUserId) async {
    if (_userId == null || otherUserId == _userId) return;
    if (_blockedUserIds.contains(otherUserId)) {
      return _msg('Engellediğin kullanıcıya istek gönderemezsin.');
    }
    try {
      await supabase.from('friends').upsert({
        'user_id': _userId,
        'friend_id': otherUserId,
        'status': 'pending',
      }, onConflict: 'user_id,friend_id');
      await _loadSocialData();
      _msg('Arkadaşlık isteği gönderildi.');
    } catch (e) {
      debugPrint('FRIEND REQUEST ERROR: $e');
      _msg('İstek gönderilemedi.');
    }
  }

  Future<void> _acceptFriendRequest(String otherUserId) async {
    if (_userId == null) return;
    try {
      await supabase
          .from('friends')
          .update({'status': 'accepted'})
          .eq('user_id', otherUserId)
          .eq('friend_id', _userId!);
      await _loadSocialData();
      _msg('Arkadaşlık isteği kabul edildi.');
    } catch (e) {
      _msg('İstek kabul edilemedi.');
      debugPrint('ACCEPT FRIEND ERROR: $e');
    }
  }

  Future<void> _rejectFriendRequest(String otherUserId) async {
    if (_userId == null) return;
    try {
      await supabase
          .from('friends')
          .delete()
          .eq('user_id', otherUserId)
          .eq('friend_id', _userId!);
      await _loadSocialData();
      _msg('İstek reddedildi.');
    } catch (e) {
      _msg('İstek reddedilemedi.');
      debugPrint('REJECT FRIEND ERROR: $e');
    }
  }

  Future<void> _removeFriend(String otherUserId) async {
    if (_userId == null) return;
    try {
      await supabase
          .from('friends')
          .delete()
          .eq('user_id', _userId!)
          .eq('friend_id', otherUserId);
      await supabase
          .from('friends')
          .delete()
          .eq('user_id', otherUserId)
          .eq('friend_id', _userId!);
      await _loadSocialData();
      _msg('Arkadaşlıktan çıkarıldı.');
    } catch (e) {
      _msg('İşlem başarısız.');
      debugPrint('REMOVE FRIEND ERROR: $e');
    }
  }

  Future<void> _blockUser(String otherUserId) async {
    if (_userId == null || otherUserId == _userId) return;
    try {
      await supabase.from('friends').upsert({
        'user_id': _userId,
        'friend_id': otherUserId,
        'status': 'blocked',
      }, onConflict: 'user_id,friend_id');
      await _loadSocialData();
      await _loadTables();
      _msg('Kullanıcı engellendi.');
    } catch (e) {
      _msg('Kullanıcı engellenemedi.');
      debugPrint('BLOCK USER ERROR: $e');
    }
  }

  Future<void> _unblockUser(String otherUserId) async {
    if (_userId == null) return;
    try {
      await supabase
          .from('friends')
          .delete()
          .eq('user_id', _userId!)
          .eq('friend_id', otherUserId)
          .eq('status', 'blocked');
      await _loadSocialData();
      await _loadTables();
      _msg('Engel kaldırıldı.');
    } catch (e) {
      _msg('Engel kaldırılamadı.');
      debugPrint('UNBLOCK ERROR: $e');
    }
  }

  Future<void> _showUserCard(Map<String, dynamic> user) async {
    final otherId = user['id']?.toString() ?? user['user_id']?.toString();
    if (otherId == null) return;

    final isSelf = otherId == _userId;
    final isFriend = _friendIds.contains(otherId);
    final isBlocked = _blockedUserIds.contains(otherId);
    final incoming = _incomingRequestIds.contains(otherId);
    final outgoing = _outgoingRequestIds.contains(otherId);
    final profile = await supabase
        .from('profiles')
        .select('coins, rating')
        .eq('id', otherId)
        .single();

    final coins = profile['coins'] ?? 0;
    final rating = (profile['rating'] as int?) ?? 1200;

    final username = (user['username']?.toString().trim().isNotEmpty ?? false)
        ? user['username'].toString().trim()
        : 'Oyuncu';

    final statusText = isSelf
        ? 'Bu senin profilin'
        : isBlocked
        ? 'Bu kullanıcı engellendi'
        : isFriend
        ? 'Arkadaşın'
        : incoming
        ? 'Sana arkadaşlık isteği gönderdi'
        : outgoing
        ? 'Arkadaşlık isteği gönderildi'
        : 'Henüz arkadaş değilsiniz';

    final statusColor = isBlocked
        ? const Color(0xFFE57373)
        : (isFriend || isSelf)
        ? const Color(0xFF7ED9A5)
        : const Color(0xFFF2C14E);

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(.78),
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF17382E), Color(0xFF0D221B)],
                ),
                border: Border.all(color: _goldBorderColor, width: _goldBorderWidth),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xCC000000),
                    blurRadius: 34,
                    offset: Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: const Color(0x2CECCB79),
                          border: Border.all(color: const Color(0x66E9C46A)),
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Color(0xFFFFE0A8),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Oyuncu Profili',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0x221A2520),
                          border: Border.all(color: const Color(0x55FFFFFF)),
                        ),
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE9C46A), width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE9C46A).withOpacity(.28),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: LobbyAvatar(
                          username: username,
                          avatarUrl: user['avatar_url'],
                          size: 56,
                          blocked: isBlocked,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(.18),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: statusColor.withOpacity(.55)),
                              ),
                              child: Text(
                                statusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _statPanel(
                          label: 'Rating',
                          icon: Icons.star_rounded,
                          value: rating,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _statPanel(
                          label: 'Coin',
                          icon: Icons.monetization_on_rounded,
                          value: coins,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (isSelf)
                        _modalActionButton(
                          label: 'Düzenle',
                          primary: true,
                          onPressed: () async {
                            Navigator.pop(context);
                            await _openProfileSetupDialog(forceComplete: false);
                          },
                        ),
                      if (!isSelf && !isBlocked && !isFriend && !incoming && !outgoing)
                        _modalActionButton(
                          label: 'Arkadaş Ekle',
                          onPressed: () async {
                            Navigator.pop(context);
                            await _sendFriendRequest(otherId);
                          },
                        ),
                      if (!isSelf && incoming)
                        _modalActionButton(
                          label: 'Kabul',
                          primary: true,
                          onPressed: () async {
                            Navigator.pop(context);
                            await _acceptFriendRequest(otherId);
                          },
                        ),
                      if (!isSelf && incoming)
                        _modalActionButton(
                          label: 'Reddet',
                          danger: true,
                          onPressed: () async {
                            Navigator.pop(context);
                            await _rejectFriendRequest(otherId);
                          },
                        ),
                      if (!isSelf && isFriend)
                        _modalActionButton(
                          label: 'Arkadaşı Çıkar',
                          onPressed: () async {
                            Navigator.pop(context);
                            await _removeFriend(otherId);
                          },
                        ),
                      if (!isSelf && !isBlocked)
                        _modalActionButton(
                          label: 'Engelle',
                          danger: true,
                          onPressed: () async {
                            Navigator.pop(context);
                            await _blockUser(otherId);
                          },
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
  }

  Widget _statPanel({
    required String label,
    required IconData icon,
    required int value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x2CF6E7C1), Color(0x15F6E7C1)],
        ),
        border: Border.all(color: const Color(0x55E9C46A)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFE9C46A)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFD4E8DB),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(IconData icon, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.amber),
          const SizedBox(width: 4),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showIncomingFriendRequestDialog(
    String otherUserId,
    Map<String, dynamic>? user,
  ) async {
    if (!mounted || _friendRequestPromptOpen) return;
    _friendRequestPromptOpen = true;

    final username = ((user?['username'] as String?) ?? '').trim().isEmpty
        ? 'Oyuncu'
        : user!['username'].toString();
    final avatarUrl = user?['avatar_url']?.toString();

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13231C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: _goldBorderColor, width: _goldBorderWidth),
        ),
        title: const Text(
          'Yeni arkadaşlık isteği',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Row(
          children: [
            LobbyAvatar(username: username, avatarUrl: avatarUrl, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$username sana arkadaşlık isteği gönderdi.',
                style: const TextStyle(color: Color(0xFFD5E9DF)),
              ),
            ),
          ],
        ),
        actions: [
          _modalActionButton(
            label: 'Reddet',
            danger: true,
            onPressed: () async {
              Navigator.pop(context);
              await _rejectFriendRequest(otherUserId);
            },
          ),
          _modalActionButton(
            label: 'Engelle',
            danger: true,
            onPressed: () async {
              Navigator.pop(context);
              await _blockUser(otherUserId);
            },
          ),
          _modalActionButton(
            label: 'Kabul Et',
            primary: true,
            onPressed: () async {
              Navigator.pop(context);
              await _acceptFriendRequest(otherUserId);
            },
          ),
        ],
      ),
    );

    if (mounted) {
      _friendRequestPromptOpen = false;
    }
  }

  String _leagueBadge(String name) {
    final n = name.toLowerCase();

    if (n.contains("standart")) return "assets/images/lobby/standart.png";
    if (n.contains("bronz")) return "assets/images/lobby/bronz.png";
    if (n.contains("gumus")) return "assets/images/lobby/gumus.png";
    if (n.contains("altin")) return "assets/images/lobby/altin.png";
    if (n.contains("elit")) return "assets/images/lobby/elit.png";

    return "assets/images/lobby/standart.png";
  }

  void _showCreateModal() {
    final league = leagues.firstWhere(
      (l) => l['id'] == selectedLeague,
      orElse: () => leagues.first,
    );

    final entry = (league['entry_coin'] as int?) ?? 100;

    int draftPlayers = 2;
    int draftTurnSeconds = createTurnSeconds;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canCreate = userCoin >= entry;

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
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),

                        image: const DecorationImage(
                          image: AssetImage("assets/images/lobby/lobby.png"),
                          fit: BoxFit.cover,
                          opacity: 0.38,
                        ),

                        color: const Color(0xCC102620),
                      ),

                      child: Column(
                        children: [
                          /// HEADER
                          Row(
                            children: [
                              const Text(
                                "MASA OLUŞTUR",
                                style: TextStyle(
                                  color: Color(0xFFE7B95A),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),

                              const Spacer(),

                              InkWell(
                                onTap: () => Navigator.pop(context),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          /// LEAGUE INFO
                          Row(
                            children: [
                              Image.asset(
                                _leagueBadge(league['name']),
                                width: 28,
                              ),

                              const SizedBox(width: 8),

                              Text(
                                league['name'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),

                              const Spacer(),

                              Image.asset(
                                "assets/images/lobby/store.png",
                                width: 18,
                              ),

                              const SizedBox(width: 4),

                              Text(
                                "$entry",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          /// PICKERS YAN YANA
                          Expanded(
                            child: Row(
                              children: [
                                /// PLAYERS
                                Expanded(
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(
                                            Icons.group,
                                            color: Colors.white70,
                                            size: 18,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            "Oyuncu",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 4),

                                      gamePicker(
                                        controller: FixedExtentScrollController(
                                          initialItem: 0,
                                        ),
                                        onChanged: (i) {
                                          if (i == 1) {
                                            return; // 4 oyuncu kilitli
                                          }

                                          setDialogState(() {
                                            draftPlayers = 2;
                                          });
                                        },
                                        children: const [
                                          Center(
                                            child: Text(
                                              "2 Oyuncu",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),

                                          Center(
                                            child: Text(
                                              "4 Oyuncu • Yakında",
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Color(0x66FFFFFF),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 10),

                                /// TURN TIME
                                Expanded(
                                  child: Column(
                                    children: [
                                      /// TITLE
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: const [
                                          Icon(
                                            Icons.timer,
                                            color: Colors.white70,
                                            size: 18,
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            "Hamle Süresi",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 4),

                                      /// PICKER
                                      gamePicker(
                                        controller: FixedExtentScrollController(
                                          initialItem: [
                                            20,
                                            15,
                                            10,
                                          ].indexOf(draftTurnSeconds),
                                        ),
                                        onChanged: (i) {
                                          setDialogState(() {
                                            draftTurnSeconds = [20, 15, 10][i];
                                          });
                                        },
                                        children: const [
                                          Center(
                                            child: Text(
                                              "20 sn  Yavaş",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),

                                          Center(
                                            child: Text(
                                              "15 sn  Normal",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),

                                          Center(
                                            child: Text(
                                              "10 sn  Hızlı",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE7B95A),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: canCreate
                                  ? () {
                                      createMaxPlayer = 2;
                                      createTurnSeconds = draftTurnSeconds;

                                      Navigator.pop(context);
                                      _createTable();
                                    }
                                  : null,
                              child: const Text(
                                "MASAYI AÇ",
                                style: TextStyle(fontWeight: FontWeight.w900),
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
                const SizedBox(height: 0),
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
    if (_friends.isEmpty) {
      return const Center(
        child: Text(
          'Henüz arkadaşın yok.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.separated(
      itemCount: _friends.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final friend = _friends[i];
        final blocked = _blockedUserIds.contains(friend['id']);
        final tableId = friend['table_id'];

        return InkWell(
          onTap: () => _showUserCard(friend),
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
                LobbyAvatar(
                  username: friend['username']?.toString() ?? 'Oyuncu',
                  avatarUrl: friend['avatar_url']?.toString(),
                  blocked: blocked,
                ),
                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    friend['username']?.toString() ?? 'Oyuncu',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
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
                          "Katıl",
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
  }

  Widget _messagesPanel() {
    if (_friends.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.group_off, color: Colors.white30, size: 42),
            SizedBox(height: 10),
            Text(
              'Mesajlaşmak için arkadaş eklemelisin',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        /// SOL ARKADAÅ LİSTESİ
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
                      /// AVATAR
                      LobbyAvatar(
                        username: friend['username']?.toString() ?? 'Oyuncu',
                        avatarUrl: friend['avatar_url']?.toString(),
                        size: 16,
                      ),

                      const SizedBox(width: 8),

                      /// İSİM
                      Expanded(
                        child: Text(
                          friend['username']?.toString() ?? 'Oyuncu',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
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

        /// MESAJ PANELİ
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0x5524362E),
              border: Border.all(color: const Color(0x334F8F75)),
            ),
            child: Column(
              children: [
                /// MESAJ LİSTESİ
                Expanded(
                  child: Stack(
                    children: [
                      /// ğŸ’¬ MESAJ LİSTESİ
                      _rightPanelLoading
                          ? Center(child: _premiumLoader(size: 32))
                          : ListView.builder(
                              controller: _chatScrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: _activeChatMessages.length,
                              itemBuilder: (_, i) {
                                final msg = _activeChatMessages[i];
                                final mine = msg['sender_id'] == _userId;

                                final isVoice = msg['type'] == 'voice';

                                return Align(
                                  alignment: mine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: AnimatedContainer(
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
                                    child: isVoice
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
                                  ),
                                );
                              },
                            ),

                      /// ğŸ”¥ FLOATING MENU (ÅİMDİ ÇALIÅIR)
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
                        /// â–¶ï¸ PLAY
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

                        /// ğŸ”Š WAVE
                        Expanded(child: _waveform(_previewPlaying)),

                        const SizedBox(width: 8),

                        /// âŒ DELETE
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

                        /// âœ… SEND
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
                        /// ğŸ¤ ICON
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

                        /// ğŸ”´ BLINK DOT
                        _recordDot(),

                        const SizedBox(width: 6),

                        /// â±ï¸ TIMER
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

                /// MESAJ GÖNDERME ALANI
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

                          // hala basılıysa başlat
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

                      /// ğŸ¤ VOICE BUTTON
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

                      /// GÖNDER BUTONU
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
                  /// ğŸ§  TITLE
                  const Text(
                    "Sohbeti sil",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  /// âš ï¸ DESCRIPTION
                  const Text(
                    "Bu kullanıcıyla tüm mesajlar ve ses kayıtları silinecek.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),

                  const SizedBox(height: 18),

                  /// ğŸ”˜ BUTTONS
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
    final uid = _userId;
    final other = _activeChatUserId;

    if (uid == null || other == null) return;

    try {
      /// 3. mesajları sil
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
    final uid = _userId ?? supabase.auth.currentUser?.id;
    final otherId = _activeChatUserId;
    final ftableid = _activeChatUserTableId ?? "";
    if (uid == null || otherId == null) return;

    try {
      final file = File(filePath);

      if (!await file.exists()) return;

      /// ğŸ†” message id
      final messageId = const Uuid().v4();

      final storagePath = 'friend/$ftableid/$messageId.m4a';

      /// ğŸ“¦ 1. STORAGE UPLOAD
      await supabase.storage.from('voice').upload(storagePath, file);

      /// ğŸ§¾ 2. DB INSERT (senin yapıya uyumlu)
      await supabase.from('messages').insert({
        'sender_id': uid,
        'receiver_id': otherId,
        'content': null, // â— text yok
        'type': 'voice',
        'voice_url': storagePath,
        'duration': 5, // şimdilik sabit
      });

      /// ğŸ§¹ 3. LOCAL TEMİZLE
      await file.delete();

      /// ğŸ”„ 4. CHAT REFRESH (senin sistem)
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
      mainAxisSize: MainAxisSize.min, // â— önemli
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

        /// â±ï¸ süre
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

      /// aynı mesaj â†’ stop
      if (_playingMessageId == msg['id']) {
        await _audioPlayer.stop();
        setState(() => _playingMessageId = null);
        return;
      }

      /// yeni mesaj başlat
      final url = await supabase.storage
          .from('voice')
          .createSignedUrl(path, 60);

      await _audioPlayer.stop(); // ğŸ’¥ önemli (önceki sesi kes)

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

    /// ğŸ’¥ EN KRİTİK (recorder warmup)
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

    /// â— ARTIK GÖNDERMEYİZ
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
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
                  'Titreşim',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
        const SizedBox(height: 8),
        lobbySideMenuButton(
          icon: Icons.support_agent_rounded,
          label: 'Destek / \u015Eikayet G\u00F6nder',
          onTap: () async {
            _closeRightPanel();
            await _openSupportRequestDialog();
          },
        ),
        const SizedBox(height: 8),
        lobbySideMenuButton(
          icon: Icons.notifications_active_rounded,
          label: 'Sistem Duyurular\u0131',
          onTap: () async {
            _closeRightPanel();
            await _showSystemMessagesDialog();
          },
        ),
        const SizedBox(height: 8),
        lobbySideMenuButton(
          icon: Icons.person_rounded,
          label: 'Profil Kartım',
          onTap: () => _showUserCard({
            'id': _userId,
            'username': userName,
            'avatar_url': _userAvatarUrl,
            'rating': userRating,
          }),
        ),

        const SizedBox(height: 16),

        // ğŸ”¥ YENİ EKLEDİÄİMİZ
        lobbySideMenuButton(
          icon: Icons.delete_forever_rounded,
          label: 'Hesabı Sil',
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
          title: Text("Hesabı Sil"),
          content: Text(
            "Bu işlem geri alınamaz. Hesabınız ve tüm verileriniz silinecek. Emin misiniz?",
          ),
          actions: [
            TextButton(
              child: Text("İptal"),
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

  Widget _modalActionButton({
    required String label,
    required VoidCallback onPressed,
    bool danger = false,
    bool primary = false,
  }) {
    final bgColor = danger
        ? const Color(0xFF7F2A2A)
        : primary
        ? const Color(0xFF2B7B55)
        : const Color(0x55314036);
    final borderColor = danger
        ? const Color(0xFFAA4A4A)
        : primary
        ? _goldBorderDark
        : const Color(0x886A4E2B);

    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1.6),
        ),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
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
    if (input.isEmpty) return input;
    return input
        .replaceAll('ü', 'ü')
        .replaceAll('Ü', 'Ü')
        .replaceAll('ç', 'ç')
        .replaceAll('Ç', 'Ç')
        .replaceAll('ı', 'ı')
        .replaceAll('İ', 'İ')
        .replaceAll('ö', 'ö')
        .replaceAll('Ö', 'Ö')
        .replaceAll('ş', 'ş')
        .replaceAll('Ş', 'Ş')
        .replaceAll('ğ', 'ğ')
        .replaceAll('Ğ', 'Ğ')
        .replaceAll('ü', 'ü')
        .replaceAll('Ü', 'Ü')
        .replaceAll('ç', 'ç')
        .replaceAll('Ç', 'Ç')
        .replaceAll('ı', 'ı')
        .replaceAll('İ', 'İ')
        .replaceAll('ö', 'ö')
        .replaceAll('Ö', 'Ö')
        .replaceAll('ş', 'ş')
        .replaceAll('Ş', 'Ş')
        .replaceAll('ğ', 'ğ')
        .replaceAll('Ğ', 'Ğ');
  }

  Widget _connectedLeagueAndTables({required double leagueWidth}) {
    return Row(
      children: [
        /// ğŸ”¥ SOL PANEL (GLASS EFFECT)
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Container(
              /// ğŸ”¥ biraz daha geniş
              width: leagueWidth + 60,

              margin: const EdgeInsets.fromLTRB(10, 2, 6, 8),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),

              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),

                /// ğŸ”¥ cam rengi (çok kritik)
                border: Border.all(color: const Color(0x33FFFFFF), width: 1.2),
              ),

              child: Column(
                children: [
                  /// ğŸ”¥ HEADER
                  Column(
                    children: [
                      Image.asset(
                        "assets/images/logo/okeyix_logo.png",
                        height: 34,
                        fit: BoxFit.contain,
                      ),

                      const Text(
                        "Adil Da\u011f\u0131t\u0131m \u2022 Ger\u00e7ek Rekabet",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD4A24C),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 2),

                  /// ğŸ”¥ GOLD DIVIDER
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

                  /// ğŸ”¥ LİG LİSTESİ
                  Expanded(
                    child: Stack(
                      children: [
                        LobbyLeagueList(
                          leagues: leagues,
                          selectedLeagueId: selectedLeague,
                          leagueActivePlayers: leagueActivePlayers,
                          userCoin: userCoin,
                          userRating: userRating,
                          loading: loadingLeagues,
                          onSelect: (league) {
                            final newLeague = league['id'];

                            if (newLeague != selectedLeague) {
                              setState(() {
                                selectedLeague = newLeague;

                                /// ğŸ”¥ HARD RESET
                                tables = [];
                                loadingTables = true;
                                _tablesInitialized = false;
                              });

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

        /// ğŸ”¥ MASALAR
        Expanded(
          child: LobbyTableWheel(
            tables: tables,
            loading: loadingTables,
            blockedUserIds: _blockedUserIds,
            onJoin: (table) => _joinTable(table),
            onSpectate: (table) => _handleSpectateTap(table),
            canSpectateAll: true,
            onUserTap: (user) => _showUserCard(user),
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

  Widget statChip(IconData icon, String value) {
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
          Icon(icon, size: 12, color: const Color(0xFFE7C06A)),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
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
          onTap: () => _showUserCard({
            'id': _userId,
            'username': userName,
            'avatar_url': _userAvatarUrl,
            'rating': userRating,
          }),
          borderRadius: BorderRadius.circular(999),
          child: LobbyAvatar(username: userName, avatarUrl: _userAvatarUrl),
        ),

        const SizedBox(width: 10),

        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              userName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 10), // ğŸ”¥ BURASI

            Row(
              children: [
                statChip(Icons.star, userRating.toString()),

                const SizedBox(width: 10),

                statChip(Icons.monetization_on, userCoin.toString()),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _dockCenter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        lobbyAssetIconCreateTable(
          asset: "assets/images/lobby/create_table1.png",
          onTap: _showCreateModal,
        ),
      ],
    );
  }

  Widget _dockRight() {
    return Row(
      children: [
        lobbyDockIcon(
          asset: "assets/images/lobby/quick_play.png",
          onTap: () {
            if (tables.isNotEmpty) {
              _joinTable(tables.first);
            } else {
              _showCreateModal();
            }
          },
        ),
        const SizedBox(width: 6),

        ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 1.08).animate(
            CurvedAnimation(parent: _storePulse, curve: Curves.easeInOut),
          ),
          child: lobbyDockIcon(
            asset: "assets/images/lobby/store.png",
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoreScreen(initialCoin: userCoin),
                ),
              );

              if (result == true) {
                await _loadUser(); // coin yeniden yüklenir
              }
            },
          ),
        ),

        const SizedBox(width: 6),

        lobbyDockIcon(
          asset: "assets/images/lobby/leaderboard.png",
          onTap: _openLeaderboard,
        ),

        const SizedBox(width: 3),

        lobbyDockIcon(
          asset: "assets/images/lobby/friends.png",
          badgeValue: _friendCount > 0 ? '$_friendCount' : null,
          onTap: () => _openRightPanel(_RightPanelType.friends),
        ),

        const SizedBox(width: 3),

        lobbyDockIcon(
          asset: "assets/images/lobby/messages.png",
          badgeValue: _unreadTotal > 0 ? '$_unreadTotal' : null,
          onTap: () => _openRightPanel(_RightPanelType.messages),
        ),
      ],
    );
  }

  void _openLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
    );
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

class _ProfileSetupResult {
  final String username;
  final String avatarRef;
  final int renameCoinSpent;
  final int avatarCoinSpent;
  final bool consumeFreeRename;
  final Set<String> newUnlockedPremiumAvatarRefs;
  int get spentCoins => renameCoinSpent + avatarCoinSpent;
  String? get unlockedAvatarRef => newUnlockedPremiumAvatarRefs.isEmpty
      ? null
      : newUnlockedPremiumAvatarRefs.first;

  const _ProfileSetupResult({
    required this.username,
    required this.avatarRef,
    required this.renameCoinSpent,
    required this.avatarCoinSpent,
    required this.consumeFreeRename,
    required this.newUnlockedPremiumAvatarRefs,
  });
}

class _ProfileSetupDialog extends StatefulWidget {
  final bool forceComplete;
  final String initialUsername;
  final String? initialAvatarRef;
  final String currentUserId;
  final int currentCoins;
  final int renameCoinCost;
  final bool freeRenameUsed;
  final Set<String> ownedPremiumAvatarRefs;

  const _ProfileSetupDialog({
    required this.forceComplete,
    required this.initialUsername,
    required this.initialAvatarRef,
    required this.currentUserId,
    required this.currentCoins,
    required this.renameCoinCost,
    required this.freeRenameUsed,
    required this.ownedPremiumAvatarRefs,
  });

  @override
  State<_ProfileSetupDialog> createState() => _ProfileSetupDialogState();
}

class _ProfileSetupDialogState extends State<_ProfileSetupDialog> {
  late final TextEditingController usernameController;
  late String selectedAvatarRef;
  late Set<String> ownedPremiumAvatarRefs;
  String? errorText;
  bool _saving = false;

  String get _initialUsername => widget.initialUsername.trim();

  bool get _didUsernameChange =>
      usernameController.text.trim() != _initialUsername;

  AvatarPreset get _selectedPreset => avatarPresetByRef(selectedAvatarRef);

  bool get _isSelectedPremiumLocked =>
      _selectedPreset.isPremium &&
      !ownedPremiumAvatarRefs.contains(_selectedPreset.id);

  bool get _willConsumeFreeRename =>
      _didUsernameChange && !widget.freeRenameUsed;

  int get _renameCoinCostToCharge =>
      (_didUsernameChange && widget.freeRenameUsed) ? widget.renameCoinCost : 0;

  int get _avatarCoinCostToCharge =>
      _isSelectedPremiumLocked ? _selectedPreset.unlockCost : 0;

  int get _computedCoinCost {
    return _renameCoinCostToCharge + _avatarCoinCostToCharge;
  }

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController(text: widget.initialUsername);
    selectedAvatarRef = avatarPresetByRef(widget.initialAvatarRef).id;
    ownedPremiumAvatarRefs = {...widget.ownedPremiumAvatarRefs};
    final initialPreset = avatarPresetByRef(widget.initialAvatarRef);
    if (initialPreset.isPremium) {
      ownedPremiumAvatarRefs.add(initialPreset.id);
    }
    usernameController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    usernameController.dispose();
    super.dispose();
  }

  Future<bool> _isUsernameTaken(String username) async {
    final rows = await Supabase.instance.client
        .from('users')
        .select('id')
        .ilike('username', username)
        .limit(5);
    for (final row in (rows as List)) {
      final id = row['id']?.toString();
      if (id != null && id != widget.currentUserId) {
        return true;
      }
    }
    return false;
  }

  Future<void> _save() async {
    if (_saving) return;
    final username = usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => errorText = 'Kullanıcı adı zorunlu.');
      return;
    }

    final renameCoinSpent = _renameCoinCostToCharge;
    final avatarCoinSpent = _avatarCoinCostToCharge;
    final spentCoins = renameCoinSpent + avatarCoinSpent;
    if (spentCoins > widget.currentCoins) {
      setState(() {
        errorText =
            'Yetersiz coin. Gereken: $spentCoins, mevcut: ${widget.currentCoins}.';
      });
      return;
    }

    if (_didUsernameChange) {
      setState(() {
        _saving = true;
        errorText = null;
      });
      try {
        final taken = await _isUsernameTaken(username);
        if (taken) {
          setState(() {
            _saving = false;
            errorText = 'Bu kullanıcı adı zaten kullanımda.';
          });
          return;
        }
      } catch (_) {
        setState(() {
          _saving = false;
          errorText = 'Kullanıcı adı kontrol edilemedi. Tekrar dene.';
        });
        return;
      }
      if (!mounted) return;
      setState(() => _saving = false);
    }

    final unlockedPremium = <String>{};
    if (_isSelectedPremiumLocked) {
      unlockedPremium.add(_selectedPreset.id);
    }

    Navigator.pop(
      context,
      _ProfileSetupResult(
        username: username,
        avatarRef: selectedAvatarRef,
        renameCoinSpent: renameCoinSpent,
        avatarCoinSpent: avatarCoinSpent,
        consumeFreeRename: _willConsumeFreeRename,
        newUnlockedPremiumAvatarRefs: unlockedPremium,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    final title = widget.forceComplete
        ? 'Profilini Tamamla'
        : 'Profili Düzenle';

    final viewInsets = MediaQuery.of(context).viewInsets;
    final keyboardOpen = viewInsets.bottom > 0;
    final maxDialogHeight = (size.height - viewInsets.bottom - 24).clamp(
      300.0,
      size.height * 0.94,
    );
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardOpen ? viewInsets.bottom + 20 : 0),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(18),
        child: Container(
        width: isLandscape ? 720 : 520,
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF17382E), Color(0xFF0D221B)],
          ),
          border: Border.all(color: const Color(0xD7D0A14A), width: 1.8),
          boxShadow: const [
            BoxShadow(
              color: Color(0xB3000000),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0x2CECCB79),
                    border: Border.all(color: const Color(0x66E9C46A)),
                  ),
                  child: const Icon(
                  Icons.person_rounded,
                  color: Color(0xFFFFE0A8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'Kullanıcı bilgilerini ve avatarını güncelle',
                        style: TextStyle(
                          color: Color(0xFFBBD2C4),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0x221A2520),
                    border: Border.all(color: const Color(0x55FFFFFF)),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: isLandscape
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _usernameSection(),
                        if (!keyboardOpen) ...[
                          const SizedBox(width: 18),
                          Expanded(child: _avatarGrid()),
                        ],
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _usernameSection(),
                        if (!keyboardOpen) ...[
                          const SizedBox(height: 14),
                          Expanded(child: _avatarGrid()),
                        ],
                      ],
                    ),
            ),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  errorText!,
                  style: const TextStyle(
                    color: Color(0xFFFF8E8E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x2A111A17),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x4DE7C06A)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Color(0xFFE9C46A),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _computedCoinCost > 0
                          ? 'Toplam maliyet: $_computedCoinCost coin'
                          : (_didUsernameChange && !widget.freeRenameUsed)
                          ? 'İlk isim değişikliği ücretsiz.'
                          : 'Bu kayıt için coin harcanmayacak.',
                      style: const TextStyle(
                        color: Color(0xFFD9EBDD),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(_saving ? 'Kontrol ediliyor' : 'Kaydet'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2B7B55),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(
                          color: Color(0xFF8F6215),
                          width: 1.4,
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
    );
  }

  Widget _usernameSection() {
    final renameInfo = !widget.freeRenameUsed
        ? 'İlk isim değişikliği ücretsiz. Sonrası ${widget.renameCoinCost} coin.'
        : 'Her isim değişikliği ${widget.renameCoinCost} coin.';

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kullanıcı adı',
            style: TextStyle(
              color: Color(0xFFD9EBDD),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: usernameController,
            maxLength: 20,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Örnek: OkeyUstasi',
              hintStyle: const TextStyle(color: Color(0x88D9EBDD)),
              filled: true,
              fillColor: const Color(0x33273830),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            renameInfo,
            style: const TextStyle(
              color: Color(0xFFB9CFBF),
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarGrid() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final crossAxisCount = isLandscape ? 5 : 4;

    final freeWomen = freeAvatarPresetsByGender('female');
    final freeMen = freeAvatarPresetsByGender('male');
    final premiumWomen = premiumAvatarPresetsByGender('female');
    final premiumMen = premiumAvatarPresetsByGender('male');

    return ListView(
      children: [
        _avatarSection(
          title: 'Standart Kadın Avatarları',
          subtitle: 'Ücretsiz',
          presets: freeWomen,
          crossAxisCount: crossAxisCount,
        ),
        const SizedBox(height: 14),
        _avatarSection(
          title: 'Standart Erkek Avatarları',
          subtitle: 'Ücretsiz',
          presets: freeMen,
          crossAxisCount: crossAxisCount,
        ),
        const SizedBox(height: 14),
        _avatarSection(
          title: 'Premium Kadın Avatarları',
          subtitle: 'Coin ile açılır',
          presets: premiumWomen,
          crossAxisCount: crossAxisCount,
          premiumHeader: true,
        ),
        const SizedBox(height: 14),
        _avatarSection(
          title: 'Premium Erkek Avatarları',
          subtitle: 'Coin ile açılır',
          presets: premiumMen,
          crossAxisCount: crossAxisCount,
          premiumHeader: true,
        ),
      ],
    );
  }

  Widget _avatarSection({
    required String title,
    required String subtitle,
    required List<AvatarPreset> presets,
    required int crossAxisCount,
    bool premiumHeader = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: premiumHeader
                    ? const Color(0xFFFFD27D)
                    : const Color(0xFFE3F4E8),
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: premiumHeader
                    ? const Color(0x33FFD27D)
                    : const Color(0x3345B47A),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: premiumHeader
                      ? const Color(0x66FFD27D)
                      : const Color(0x6645B47A),
                ),
              ),
              child: Text(
                subtitle,
                style: TextStyle(
                  color: premiumHeader
                      ? const Color(0xFFFFD27D)
                      : const Color(0xFFBFE5CC),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          itemCount: presets.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemBuilder: (_, index) => _avatarTile(presets[index]),
        ),
      ],
    );
  }

  Widget _avatarTile(AvatarPreset preset) {
    final selected = selectedAvatarRef == preset.id;
    final isLockedPremium =
        preset.isPremium && !ownedPremiumAvatarRefs.contains(preset.id);

    return InkWell(
      onTap: () => setState(() => selectedAvatarRef = preset.id),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: preset.isPremium
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x6640200D), Color(0x44401008)],
                )
              : null,
          color: preset.isPremium ? null : const Color(0x44213129),
          border: Border.all(
            color: selected
                ? const Color(0xFFE8C36A)
                : (preset.isPremium
                      ? const Color(0x66FFD27D)
                      : const Color(0x334F8F75)),
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: CircleAvatar(
                radius: 28,
                backgroundImage: AssetImage(preset.imageUrl),
              ),
            ),
            if (isLockedPremium)
              Positioned(
                left: 4,
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xCC111111),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${preset.unlockCost} coin',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFD27D),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (preset.isPremium)
              const Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.workspace_premium_rounded,
                  size: 14,
                  color: Color(0xFFFFD27D),
                ),
              ),
            if (isLockedPremium)
              const Positioned(
                top: 4,
                left: 4,
                child: Icon(
                  Icons.lock_rounded,
                  size: 14,
                  color: Color(0xFFFFD27D),
                ),
              ),
          ],
        ),
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



