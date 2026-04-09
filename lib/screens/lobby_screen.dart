import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:okeyix/screens/spectator_screen.dart';
import 'package:okeyix/ui/lobby/LobbyTableWheel.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

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
  final _audioPlayer = AudioPlayer();
  String? _playingMessageId;
  final supabase = Supabase.instance.client;
  Timer? _leagueActivityTimer;
  Timer? _socialRefreshTimer;
  Timer? _tablesRefreshTimer;
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
  int userRating = 1000;
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

    supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;

      if (session != null) {
        _initDevice(); // 🔥 SADECE BURADA
      }
    });
  }

  Future<void> _initDevice() async {
    if (_initCalled) return; // 🔥 EN KRİTİK SATIR
    _initCalled = true;

    try {
      Session? session;

      for (int i = 0; i < 10; i++) {
        session = supabase.auth.currentSession;

        if (session != null) break;

        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (session == null) {
        throw Exception("Session oluşmadı");
      }
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        await registerDevice();
      } catch (e) {
        print("Device register error: $e"); // 🔥 sadece log
      }
      if (!mounted) return;

      setState(() {
        _deviceReady = true;
      });
    } catch (e) {
      print(e);
    }
  }

  Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();

    String? storedId = prefs.getString("device_id");

    if (storedId != null) {
      return storedId;
    }

    final deviceInfo = DeviceInfoPlugin();
    String id;

    if (kIsWeb) {
      id = const Uuid().v4();
    } else if (Platform.isAndroid) {
      final android = await deviceInfo.androidInfo;
      id = android.id;
    } else if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      id = ios.identifierForVendor ?? const Uuid().v4();
    } else {
      id = const Uuid().v4();
    }

    await prefs.setString("device_id", id);

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

      /// 🔥 HATA KONTROLÜ BURADA
    } catch (e) {
      print(e);

      /// 🔥 SADECE SIGNOUT + FORWARD

      rethrow; // 🔥 EN DOĞRU
    }
  }

  @override
  void dispose() {
    _leagueActivityTimer?.cancel();
    _socialRefreshTimer?.cancel();
    _tablesRefreshTimer?.cancel();
    _chatController.dispose();
    _bgController.dispose();
    _storePulse.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadUser();
    await _checkOnboarding();
    await _loadSocialData();
    await _loadLeagues();
    await _loadLeagueActivity();
    await _loadTables();
  }

  Future<void> _ensureUserRow() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final existing = await _findUserRow(
        user,
        columns: 'id,email,username,avatar_url,rating',
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
        columns: 'id,username,rating,avatar_url',
      );
      final walletRows = await supabase
          .from('wallet_transactions')
          .select('amount')
          .eq('user_id', user.id);
      final profileRows = await supabase
          .from('profiles')
          .select('rating,coins')
          .eq('id', user.id)
          .limit(1);

      var balance = 0;
      for (final row in walletRows) {
        balance += (row['amount'] as int?) ?? 0;
      }
      final profileCoin = (profileRows as List).isNotEmpty
          ? (profileRows.first['coins'] as int?) ?? 0
          : 0;
      final profileRating = (profileRows as List).isNotEmpty
          ? (profileRows.first['rating'] as int?) ?? 100
          : 0;
      final resolvedCoin = balance > profileCoin ? balance : profileCoin;
      final effectiveCoin = resolvedCoin;

      if (!mounted) return;
      if (row != null) {
        setState(() {
          _userId = user.id;
          _userRowId = row['id']?.toString();
          userName = ((row['username'] as String?) ?? '').trim().isEmpty
              ? (user.email?.split('@').first ?? 'Oyuncu')
              : row['username'] as String;
          userRating = profileRating;
          _userAvatarUrl = (row['avatar_url'] as String?)?.trim();
          userCoin = effectiveCoin;
        });
      } else {
        setState(() {
          _userId = user.id;
          _userRowId = null;
          userName = user.email?.split('@').first ?? 'Oyuncu';
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

    if (!mounted) return;
    final result = await showDialog<_ProfileSetupResult>(
      context: context,
      barrierDismissible: !forceComplete,
      builder: (_) => _ProfileSetupDialog(
        forceComplete: forceComplete,
        initialUsername: initialUsername,
        initialAvatarRef: initialAvatar,
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

      await _loadUser();
      await _loadTables();
      if (!mounted) return;
      _msg('Profil güncellendi.');
      return;
    } catch (e) {
      if (e is PostgrestException && e.code == '23505') {
        _msg('Bu kullanıcı adı zaten kullanımda.');
      } else {
        _msg('Profil güncellenemedi.');
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

  Future<void> _loadTables() async {
    if (!mounted) return;

    const minTables = 5;
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
          .eq('status', 'waiting')
          .order('created_at', ascending: false);

      final tableRows = (response as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

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

      final usernameById = <String, String>{};
      final avatarById = <String, String?>{};
      final ratingById = <String, int>{};

      if (allUserIds.isNotEmpty) {
        final users = await supabase
            .from('users')
            .select('id,username,avatar_url,rating')
            .inFilter('id', allUserIds.toList());

        for (final raw in (users as List)) {
          final row = Map<String, dynamic>.from(raw);
          final id = row['id']?.toString();
          if (id == null) continue;

          final name = ((row['username'] as String?) ?? '').trim();

          usernameById[id] = name.isEmpty ? 'Oyuncu' : name;
          avatarById[id] = row['avatar_url']?.toString();
          ratingById[id] = (row['rating'] as int?) ?? 1000;
        }
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
              'rating': uid == null ? 1000 : (ratingById[uid] ?? 1000),
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

      /// ---------------- BOT USERS ----------------

      final botRows = await supabase
          .from('users')
          .select('id,username,avatar_url,rating')
          .eq('is_bot', true)
          .limit(40);

      final bots = (botRows as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      /// ---------------- FAKE TABLE GENERATOR ----------------

      final rnd = Random();

      if (merged.length < minTables) {
        final missing = minTables - merged.length;

        for (int i = 0; i < missing; i++) {
          final fakePlayers = <Map<String, dynamic>>[];

          final playerCount = 2 + rnd.nextInt(2); // 2-3 oyuncu

          final shuffledBots = List.from(bots)..shuffle();

          for (int p = 0; p < playerCount; p++) {
            final bot = shuffledBots[p];

            fakePlayers.add({
              'seat_index': p,
              'user_id': bot['id'],
              'username': bot['username'],
              'avatar_url': bot['avatar_url'],
              'rating': bot['rating'],
              'blocked': false,
            });
          }

          final leagueCoin = (league['entry_coin'] as int?) ?? 100;

          merged.add({
            'id': 'fake_$i',
            'league_id': league['id'],
            'status': 'waiting',
            'entry_coin': leagueCoin,
            'is_fake': true,
            '_players': fakePlayers,
          });
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
    _openGame(tableId, true);
  }

  Future<void> _joinTable(Map<String, dynamic> table) async {
    final user = supabase.auth.currentUser;
    final tableId = table['id'] as String?;
    if (user == null || tableId == null) return;
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
    _openGame(tableId, false);
  }

  void _openGame(String tableId, bool isCreator) {
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
      if (counterpartIds.isNotEmpty) {
        final userRows = await supabase
            .from('users')
            .select('id,username,avatar_url,rating')
            .inFilter('id', counterpartIds.toList());

        for (final raw in (userRows as List)) {
          final row = Map<String, dynamic>.from(raw);
          final id = row['id']?.toString();
          if (id != null) usersById[id] = row;
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
          'rating': user?['rating'] ?? 1000,
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
    final rating = profile['rating'] ?? user['rating'] ?? 1000;

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (_) {
        return Center(
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0F1F18),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _goldBorderColor,
                width: _goldBorderWidth,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black87,
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                /// 🔥 AVATAR
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withOpacity(0.4),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: LobbyAvatar(
                    username: user['username'] ?? 'Oyuncu',
                    avatarUrl: user['avatar_url'],
                    size: 55,
                    blocked: isBlocked,
                  ),
                ),

                const SizedBox(height: 12),

                /// 🔥 USERNAME
                Text(
                  user['username'] ?? 'Oyuncu',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 10),

                /// 🔥 STATS (AAA)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _statChip(Icons.star, rating),
                    const SizedBox(width: 8),
                    _statChip(Icons.monetization_on, coins),
                  ],
                ),

                const SizedBox(height: 14),

                /// 🔥 STATUS TEXT
                Text(
                  isSelf
                      ? 'Bu senin profilin'
                      : isBlocked
                      ? 'Bu kullanıcı engelli'
                      : isFriend
                      ? 'Arkadaşın'
                      : incoming
                      ? 'Sana istek gönderdi'
                      : outgoing
                      ? 'İstek gönderildi'
                      : 'Arkadaş değilsiniz',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),

                const SizedBox(height: 16),

                /// 🔥 ACTIONS
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

                    if (!isSelf &&
                        !isBlocked &&
                        !isFriend &&
                        !incoming &&
                        !outgoing)
                      _modalActionButton(
                        label: 'Arkadaşlık',
                        onPressed: () async {
                          Navigator.pop(context);
                          await _sendFriendRequest(otherId);
                        },
                      ),

                    if (!isSelf && incoming)
                      _modalActionButton(
                        label: 'Kabul',
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
                        label: 'Çıkar',
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

                const SizedBox(height: 10),

                /// 🔥 CLOSE
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Kapat',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                                              "👥 2 Oyuncu",
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
                                              "👥 4 Oyuncu • Yakında",
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
                                              "🐢 20 sn  Yavaş",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),

                                          Center(
                                            child: Text(
                                              "⚡ 15 sn  Normal",
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),

                                          Center(
                                            child: Text(
                                              "🔥 10 sn  Hızlı",
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
                const SizedBox(height: 8),
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
        /// SOL ARKADAŞ LİSTESİ
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
                      /// 💬 MESAJ LİSTESİ
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

                      /// 🔥 FLOATING MENU (ŞİMDİ ÇALIŞIR)
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
                              await _audioPlayer.setFilePath(_previewPath!);
                              await _audioPlayer.play();
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
                    "Bu kullanıcıyla tüm mesajlar ve ses kayıtları silinecek.",
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

      /// 🆔 message id
      final messageId = const Uuid().v4();

      final storagePath = 'friend/$ftableid/$messageId.m4a';

      /// 📦 1. STORAGE UPLOAD
      await supabase.storage.from('voice').upload(storagePath, file);

      /// 🧾 2. DB INSERT (senin yapıya uyumlu)
      await supabase.from('messages').insert({
        'sender_id': uid,
        'receiver_id': otherId,
        'content': null, // ❗ text yok
        'type': 'voice',
        'voice_url': storagePath,
        'duration': 5, // şimdilik sabit
      });

      /// 🧹 3. LOCAL TEMİZLE
      await file.delete();

      /// 🔄 4. CHAT REFRESH (senin sistem)
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
      mainAxisSize: MainAxisSize.min, // ❗ önemli
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

        /// ⏱️ süre
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

      /// aynı mesaj → stop
      if (_playingMessageId == msg['id']) {
        await _audioPlayer.stop();
        setState(() => _playingMessageId = null);
        return;
      }

      /// yeni mesaj başlat
      final url = await supabase.storage
          .from('voice')
          .createSignedUrl(path, 60);

      await _audioPlayer.stop(); // 💥 önemli (önceki sesi kes)

      await _audioPlayer.setUrl(url);

      setState(() => _playingMessageId = msg['id']);

      await _audioPlayer.play();
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

    /// 💥 EN KRİTİK (recorder warmup)
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

    /// ❗ ARTIK GÖNDERMEYİZ
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
    return Column(
      children: [
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
        const SizedBox(height: 8),
        lobbySideMenuButton(
          icon: Icons.logout_rounded,
          label: 'Çıkış Yap',
          danger: true,
          onTap: () async {
            _closeRightPanel();
            await _signOutAndGoLogin();
          },
        ),
      ],
    );
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
        .replaceAll('Ã¼', 'ü')
        .replaceAll('Ãœ', 'Ü')
        .replaceAll('Ã§', 'ç')
        .replaceAll('Ã‡', 'Ç')
        .replaceAll('Ä±', 'ı')
        .replaceAll('Ä°', 'İ')
        .replaceAll('Ã¶', 'ö')
        .replaceAll('Ã–', 'Ö')
        .replaceAll('ÅŸ', 'ş')
        .replaceAll('Åž', 'Ş')
        .replaceAll('ÄŸ', 'ğ')
        .replaceAll('Äž', 'Ğ');
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
              /// 🔥 biraz daha geniş
              width: leagueWidth + 60,

              margin: const EdgeInsets.fromLTRB(10, 10, 6, 10),
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),

              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),

                /// 🔥 cam rengi (çok kritik)
                border: Border.all(color: const Color(0x33FFFFFF), width: 1.2),
              ),

              child: Column(
                children: [
                  /// 🔥 HEADER
                  Column(
                    children: [
                      Image.asset(
                        "assets/images/logo/okeyix_logo.png",
                        height: 46,
                        fit: BoxFit.contain,
                      ),

                      const Text(
                        "Adil Dağıtım • Gerçek Rekabet",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFFD4A24C),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  /// 🔥 GOLD DIVIDER
                  Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
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

                  /// 🔥 LİG LİSTESİ
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

                                /// 🔥 HARD RESET
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

        /// 🔥 MASALAR
        Expanded(
          child: LobbyTableWheel(
            tables: tables,
            loading: loadingTables,
            blockedUserIds: _blockedUserIds,
            onJoin: (table) => _joinTable(table),
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
              fontSize: 11,
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

            const SizedBox(height: 10), // 🔥 BURASI

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

  const _ProfileSetupResult({required this.username, required this.avatarRef});
}

class _ProfileSetupDialog extends StatefulWidget {
  final bool forceComplete;
  final String initialUsername;
  final String? initialAvatarRef;

  const _ProfileSetupDialog({
    required this.forceComplete,
    required this.initialUsername,
    required this.initialAvatarRef,
  });

  @override
  State<_ProfileSetupDialog> createState() => _ProfileSetupDialogState();
}

class _ProfileSetupDialogState extends State<_ProfileSetupDialog> {
  late final TextEditingController usernameController;
  late String selectedAvatarRef;
  String? errorText;

  @override
  void initState() {
    super.initState();
    usernameController = TextEditingController(text: widget.initialUsername);
    selectedAvatarRef = avatarPresetByRef(widget.initialAvatarRef).id;
  }

  @override
  void dispose() {
    usernameController.dispose();
    super.dispose();
  }

  void _save() {
    final username = usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => errorText = 'Kullanıcı adı zorunlu.');
      return;
    }
    Navigator.pop(
      context,
      _ProfileSetupResult(username: username, avatarRef: selectedAvatarRef),
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

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(18),
      child: Container(
        width: isLandscape ? 720 : 520,
        constraints: BoxConstraints(maxHeight: size.height * 0.92),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF132A22), Color(0xFF0D1C17)],
          ),
          border: Border.all(color: const Color(0xCCB07A1A), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            /// HEADER
            Row(
              children: [
                const Icon(
                  Icons.person_rounded,
                  color: Color(0xFFFFE0A8),
                  size: 26,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                if (!widget.forceComplete)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            Expanded(
              child: isLandscape
                  ? Row(
                      children: [
                        _usernameSection(),
                        const SizedBox(width: 18),
                        Expanded(child: _avatarGrid()),
                      ],
                    )
                  : Column(
                      children: [
                        _usernameSection(),
                        const SizedBox(height: 14),
                        Expanded(child: _avatarGrid()),
                      ],
                    ),
            ),

            if (errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  errorText!,
                  style: const TextStyle(color: Color(0xFFFF7A7A)),
                ),
              ),

            const SizedBox(height: 10),

            /// BUTTONS
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!widget.forceComplete)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Vazgeç'),
                  ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Kaydet'),
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
          ],
        ),
      ),
    );
  }

  Widget _usernameSection() {
    return SizedBox(
      width: 220,
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
        ],
      ),
    );
  }

  Widget _avatarGrid() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return GridView.builder(
      itemCount: avatarPresetIds.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isLandscape ? 6 : 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (_, index) {
        final avatarRef = avatarPresetIds[index];
        final preset = avatarPresetByRef(avatarRef);
        final selected = selectedAvatarRef == avatarRef;

        return InkWell(
          onTap: () => setState(() => selectedAvatarRef = avatarRef),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: const Color(0x44213129),
              border: Border.all(
                color: selected
                    ? const Color(0xFFE8C36A)
                    : const Color(0x334F8F75),
                width: selected ? 2 : 1,
              ),
            ),
            child: Center(
              child: CircleAvatar(
                radius: 28,
                backgroundImage: AssetImage(preset.imageUrl),
              ),
            ),
          ),
        );
      },
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
