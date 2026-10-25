import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/services/profile_service.dart';
import 'package:okeyix/services/user_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ui/lobby/lobby_shimmer_loaders.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final supabase = Supabase.instance.client;
  int selectedTab = 0; // 0=En Iyiler, 1=Zenginler, 2=Bugun, 3=Son Oynadiklarim

  List bestPlayers = [];
  List richPlayers = [];
  List dailyPlayers = [];
  List recentPlayers = [];

  bool loading = true;

  List get players {
    switch (selectedTab) {
      case 0:
        return bestPlayers;
      case 1:
        return richPlayers;
      case 2:
        return dailyPlayers;
      case 3:
        return recentPlayers;
      default:
        return [];
    }
  }

  List<dynamic> get rest => players.skip(3).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);

    final best = await supabase.rpc('get_best_players');
    final rich = await supabase.rpc('get_richest_players');
    final daily = await supabase.rpc('get_daily_leaderboard');

    List recent = [];
    final myUserId = supabase.auth.currentUser?.id ?? UserState.userId;
    if (myUserId != null && myUserId.isNotEmpty) {
      try {
        final res = await supabase.rpc(
          'get_recent_opponents',
          params: {'p_user_id': myUserId, 'p_limit': 20},
        );
        if (res is List) recent = res;
      } catch (_) {
        recent = [];
      }
    }

    if (!mounted) return;
    setState(() {
      bestPlayers = best;
      richPlayers = rich;
      dailyPlayers = daily;
      recentPlayers = recent;
      loading = false;
    });
  }

  void _onPlayerTap(dynamic p) {
    if (!mounted) return;
    final userId = p['user_id'] ?? p['id'];
    if (userId == null) return;
    final payload = Map<String, dynamic>.from(p as Map)
      ..putIfAbsent('id', () => userId);
    ProfileService.showUserCard(payload);
  }

  String get _scoreCaption => switch (selectedTab) {
    1 => 'COİN', 2 => 'KAZANÇ', _ => 'SEVİYE',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E141B),
      body: Stack(children: [
        Positioned.fill(child: Image.asset('assets/images/lobby/lobby.png', fit: BoxFit.cover)),
        const Positioned.fill(child: ColoredBox(color: Color(0x66070D15))),
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.emoji_events_outlined, color: Color(0xFFE5C586), size: 22),
              const SizedBox(width: 8),
              const Text('SIRALAMA', style: TextStyle(color: Color(0xFFE5C586),
                fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 14),
              Expanded(child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: const Color(0xE6111A20),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x447E8581))),
                child: SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _tabItem('En İyiler', 0), _tabItem('Zenginler', 1),
                    _tabItem('Bugün', 2), _tabItem('Son Oynadıklarım', 3),
                  ])),
              )),
              const SizedBox(width: 8),
              IconButton(tooltip: 'Kapat', onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(backgroundColor: const Color(0xCC152027),
                  side: const BorderSide(color: Color(0x557E8581))),
                icon: const Icon(Icons.close_rounded, color: Color(0xFFD5D9E1), size: 21)),
            ]),
            const SizedBox(height: 12),
            Expanded(child: loading ? const Center(child: LobbyLoading())
              : players.isEmpty ? _emptyState()
              : selectedTab == 3 ? _section('SON RAKİPLERİN', '', _buildRecentList())
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(flex: 4, child: _section('ZİRVENİN SAHİPLERİ', 'İLK 3', _buildTop3())),
                const SizedBox(width: 12),
                Expanded(flex: 6, child: _section('OYUNCULAR', _scoreCaption, _buildList())),
              ])),
          ]),
        )),
      ]),
    );
  }

  Widget _section(String title, String caption, Widget child) => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xE6262D36), Color(0xE610161C)]),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0x667F775E))),
    child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Row(children: [
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFE5C586), fontSize: 9,
              letterSpacing: 1.1, fontWeight: FontWeight.w700))),
          const SizedBox(width: 6),
          Text(caption, style: const TextStyle(color: Color(0xFF969EAA), fontSize: 9)),
        ])),
      Expanded(child: child),
    ]),
  );

  Widget _buildTop3() {
    final p1 = players.isNotEmpty ? players[0] : null;
    final p2 = players.length > 1 ? players[1] : null;
    final p3 = players.length > 2 ? players[2] : null;
    return Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
      child: Center(child: FittedBox(fit: BoxFit.contain,
        child: SizedBox(width: 330, height: 300,
          child: Stack(alignment: Alignment.bottomCenter, children: [
            Positioned(left: 6, bottom: 0,
              child: _podiumBlock(p2, 2, 66, const Color(0xFFBBC7CF), 65)),
            Positioned(bottom: 0,
              child: _podiumBlock(p1, 1, 84, const Color(0xFFE5C586), 92)),
            Positioned(right: 6, bottom: 0,
              child: _podiumBlock(p3, 3, 66, const Color(0xFFCF9968), 52)),
          ])),
      )),
    );
  }
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 60,
            color: Colors.white.withOpacity(0.2),
          ),
          const SizedBox(height: 12),
          Text(
            'Henuz veri yok',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _podiumBlock(
    dynamic player,
    int rank,
    double avatarSize,
    Color color,
    double height,
  ) {
    if (player == null) return const SizedBox();
    final isChampion = rank == 1;
    final medal = switch (rank) {
      1 => const [Color(0xFFFFE38A), Color(0xFFE0B325), Color(0xFFB78411)],
      2 => const [Color(0xFFE5EAEE), Color(0xFFB8C2CC), Color(0xFF8A96A1)],
      _ => const [Color(0xFFE3B57A), Color(0xFFB87933), Color(0xFF8C5520)],
    };

    return GestureDetector(
      onTap: () => _onPlayerTap(player),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: .18),
                  blurRadius: isChampion ? 12 : 6,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  padding: const EdgeInsets.all(2.2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: medal,
                    ),
                  ),
                  child: CircleAvatar(
                    radius: avatarSize / 2,
                    backgroundImage: _avatarProvider(
                      player['avatar_url']?.toString(),
                    ),
                    backgroundColor: Colors.grey[800],
                  ),
                ),
                Positioned(
                  top: isChampion ? -28 : -24,
                  left: 0,
                  right: 0,
                  child: Icon(
                    Icons.emoji_events_rounded,
                    size: isChampion ? 28 : 24,
                    color: medal[0],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: 96,
            child: Text(
              player['username'] ?? '',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                shadows: [
                  Shadow(
                    color: Color(0x99000000),
                    blurRadius: 8,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _formatScore(player),
            style: TextStyle(
              color: medal[0],
              fontWeight: FontWeight.w900,
              fontSize: 16,
              shadows: const [
                Shadow(
                  color: Color(0x99000000),
                  blurRadius: 6,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 60,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: medal,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 3)),
              ],
              border: Border.all(color: const Color(0x66FFF1C8), width: 0.8),
            ),
            child: Text(
              '$rank',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: rest.length,
      itemBuilder: (_, i) {
        final p = rest[i];
        final rank = i + 4;
        final avatar = _avatarProvider(p['avatar_url']?.toString());

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _onPlayerTap(p),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: const Color(0x99262D36),
                  border: Border.all(color: const Color(0x337E8581)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 25,
                      height: 25,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF343B46),
                      ),
                      child: Text(
                        '$rank',
                        style: const TextStyle(
                          color: Color(0xFFD8C593),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE7C66A).withValues(alpha: .1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 17,
                        backgroundImage: avatar,
                        backgroundColor: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p['username'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _formatScore(p),
                      style: const TextStyle(
                        color: Color(0xFFE5C586),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: players.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = players[i];
        final username = p['username']?.toString() ?? 'Oyuncu';
        final avatar = _avatarProvider(p['avatar_url']?.toString());
        final rating = (p['rating'] as num?)?.toInt() ?? 1200;
        final coins = (p['coins'] as num?)?.toInt() ?? 0;
        final parsed = DateTime.tryParse(p['last_played_at']?.toString() ?? '');

        return InkWell(
          onTap: () => _onPlayerTap(p),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: const Color(0x99262D36),
              border: Border.all(color: const Color(0x447E8581)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: avatar,
                  backgroundColor: Colors.grey[800],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        parsed == null
                            ? 'Son oynama bilinmiyor'
                            : 'Son oynama: ${DateFormat('dd.MM.yyyy HH:mm').format(parsed.toLocal())}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Format.rating(rating),
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Format.coin(coins),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
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
  }

  String _formatScore(dynamic p) {
    if (selectedTab == 0) return Format.rating(_asInt(p['rating']));
    if (selectedTab == 1) return Format.coin(_asInt(p['coins']));
    if (selectedTab == 2) return Format.coin(_asInt(p['total_earned']));
    return Format.rating(_asInt(p['rating']));
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final raw = value.toString().trim();
    if (raw.isEmpty) return 0;
    final normalized = raw.replaceAll(RegExp(r'[^0-9\-]'), '');
    return int.tryParse(normalized) ?? 0;
  }


  Widget _tabItem(String text, int index) {
    final selected = selectedTab == index;

    return GestureDetector(
      onTap: () => setState(() => selectedTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFEAD6A4), Color(0xFFC49C55)],
                )
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .25),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(
              _getTabIcon(index),
              size: 16,
              color: selected ? Colors.black : Colors.white70,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getTabIcon(int index) {
    switch (index) {
      case 0:
        return Icons.emoji_events;
      case 1:
        return Icons.monetization_on;
      case 2:
        return Icons.bolt;
      case 3:
        return Icons.history;
      default:
        return Icons.star;
    }
  }

  ImageProvider? _avatarProvider(String? raw) {
    final url = (raw ?? '').trim();
    if (url.isEmpty) return null;
    if (url.startsWith('http')) return NetworkImage(url);
    if (url.startsWith('assets/')) return AssetImage(url);
    return null;
  }
}
