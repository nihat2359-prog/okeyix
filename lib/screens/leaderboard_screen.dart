import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/services/profile_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ui/lobby/lobby_shimmer_loaders.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final supabase = Supabase.instance.client;
  int selectedTab = 0; // 0 = En İyiler, 1 = Günün İyileri

  List bestPlayers = [];
  List richPlayers = [];
  List dailyPlayers = [];

  bool loading = true;

  List get players {
    switch (selectedTab) {
      case 0:
        return bestPlayers;
      case 1:
        return richPlayers;
      case 2:
        return dailyPlayers;
      default:
        return [];
    }
  }

  int getScore(dynamic p) {
    switch (selectedTab) {
      case 0:
        print(p);
        return p['rating'] ?? 0;

      case 1:
        return p['coins'] ?? 0;

      case 2:
        return p['total_earned'] ?? 0;

      default:
        return 0;
    }
  }

  List<dynamic> get top3 => players.take(3).toList();
  List<dynamic> get rest => players.skip(3).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
    });

    final best = await supabase.rpc('get_best_players');
    final rich = await supabase.rpc('get_richest_players');
    final daily = await supabase.rpc('get_daily_leaderboard');

    setState(() {
      dailyPlayers = daily;
      bestPlayers = best;
      richPlayers = rich;
      loading = false;
    });
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),

      body: Stack(
        children: [
          /// BACKGROUND
          Positioned.fill(
            child: Image.asset(
              'assets/images/lobby/lobby.png',
              fit: BoxFit.cover,
            ),
          ),

          /// CONTENT
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      /// 🔥 TAB BAR (ORTA)
                      Expanded(
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(30),
                              color: Colors.black.withOpacity(0.45),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.6),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _tabItem("En İyiler", 0),
                                _tabItem("Zenginler", 1),
                                _tabItem("Bugün", 2),
                              ],
                            ),
                          ),
                        ),
                      ),

                      /// 🔥 CLOSE BUTTON (SAĞ)
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.5),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.3),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                /// BODY
                Expanded(
                  child: loading
                      ? const Center(child: LobbyLoading())
                      : players.isEmpty
                      ? _emptyState()
                      : Row(
                          children: [
                            Expanded(flex: 4, child: _buildTop3()),
                            Expanded(flex: 6, child: _buildList()),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<List<dynamic>> getBestPlayers() async {
    final res = await Supabase.instance.client.rpc('get_best_players');
    return res as List;
  }

  void _onPlayerTap(dynamic p) {
    final userId = p['user_id'];
    if (userId == null) return;
    ProfileService.showUserCard({'id': userId});
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: Colors.black.withOpacity(0.45),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 10),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _tabItem("En İyiler", 0),
              _tabItem("Zenginler", 1),
              _tabItem("Bugün", 2),
            ],
          ),
        ),
      ),
    );
  }

  IconData getTabIcon() {
    switch (selectedTab) {
      case 0:
        return Icons.emoji_events;
      case 1:
        return Icons.monetization_on;
      case 2:
        return Icons.bolt;
      default:
        return Icons.star;
    }
  }

  Widget _buildTop3() {
    final p1 = players.length > 0 ? players[0] : null;
    final p2 = players.length > 1 ? players[1] : null;
    final p3 = players.length > 2 ? players[2] : null;

    return SizedBox(
      height: 300,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          /// 🥈 SOL (2)
          Positioned(
            left: 20,
            bottom: 0,
            child: _podiumBlock(p2, 2, 60, Colors.grey.shade400, 80),
          ),

          /// 🥇 ORTA (1)
          Positioned(
            bottom: 0,
            child: _podiumBlock(p1, 1, 80, Colors.amber, 110),
          ),

          /// 🥉 SAĞ (3)
          Positioned(
            right: 20,
            bottom: 0,
            child: _podiumBlock(p3, 3, 60, const Color(0xFFCD7F32), 70),
          ),
        ],
      ),
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
            "Henüz veri yok",
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

    return GestureDetector(
      onTap: () => _onPlayerTap(player),

      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          /// 👑 CROWN (sadece 1.)

          /// 🔥 AVATAR
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.6),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: avatarSize / 2,
              backgroundImage: _getAvatar(player),
              backgroundColor: Colors.grey[800],
            ),
          ),

          const SizedBox(height: 6),

          /// 🔥 NAME
          SizedBox(
            width: 90,
            child: Text(
              player['username'] ?? '',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 4),

          /// 🔥 SCORE
          Text(
            _formatScore(player),
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 6),

          /// 🧱 PODIUM BLOCK
          Container(
            width: 60,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),

              /// 🔥 METAL EFFECT
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.9),
                  color.withOpacity(0.6),
                  color.withOpacity(0.9),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),

              boxShadow: [
                BoxShadow(color: color.withOpacity(0.4), blurRadius: 10),
              ],
            ),

            child: Text(
              "$rank",
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

  ImageProvider? _getAvatar(dynamic p) {
    final url = p['avatar_url'];

    if (url != null && url.toString().startsWith('http')) {
      return NetworkImage(url);
    } else if (url != null && url.toString().startsWith('assets/')) {
      return AssetImage(url);
    }
    return null;
  }

  Widget _podiumItem(dynamic player, int rank, double size) {
    if (player == null) return const SizedBox();

    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Colors.amber, Colors.orange],
            ),
            boxShadow: [
              BoxShadow(color: Colors.amber.withOpacity(0.5), blurRadius: 12),
            ],
          ),
          child: CircleAvatar(
            backgroundImage: NetworkImage(player['avatar_url'] ?? ''),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          player['username'] ?? '',
          style: const TextStyle(color: Colors.white),
        ),
        Text(_formatScore(player), style: const TextStyle(color: Colors.amber)),
      ],
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: rest.length,
      itemBuilder: (_, i) {
        final p = rest[i];
        final rank = i + 4;

        /// 🔥 avatar çöz
        final avatarUrl = p['avatar_url'];
        ImageProvider? avatar;

        if (avatarUrl != null && avatarUrl.toString().startsWith('http')) {
          avatar = NetworkImage(avatarUrl);
        } else if (avatarUrl != null &&
            avatarUrl.toString().startsWith('assets/')) {
          avatar = AssetImage(avatarUrl);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _onPlayerTap(p),

              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Colors.black.withOpacity(0.35),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),

                child: Row(
                  children: [
                    /// 🔥 RANK
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE7C66A), Color(0xFFB9932F)],
                        ),
                      ),
                      child: Text(
                        "$rank",
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    /// 🔥 AVATAR + GLOW
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE7C66A).withOpacity(0.4),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundImage: avatar,
                        backgroundColor: Colors.grey[800],
                      ),
                    ),

                    const SizedBox(width: 12),

                    /// 🔥 USER INFO
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

                    /// 🔥 SCORE
                    Text(
                      _formatScore(p),
                      style: const TextStyle(
                        color: Colors.amber,
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

  String _formatScore(dynamic p) {
    if (selectedTab == 0) {
      return Format.rating(p['rating'] ?? 0);
    } else if (selectedTab == 1) {
      return Format.coin(p['coins'] ?? 0);
    } else {
      return Format.coin(p['total_earned'] ?? 0);
    }
  }

  String _formatNumber(num? n) {
    if (n == null) return "0";
    return NumberFormat.decimalPattern('tr').format(n);
  }

  Widget _tabItem(String text, int index) {
    final selected = selectedTab == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedTab = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        margin: const EdgeInsets.symmetric(horizontal: 4),

        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),

          /// 🔥 SELECTED EFFECT
          gradient: selected
              ? const LinearGradient(
                  colors: [Color(0xFFFFD54F), Color(0xFFFFA000)],
                )
              : null,

          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.6),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : [],
        ),

        child: Row(
          children: [
            /// 🔥 ICON
            Icon(
              _getTabIcon(index),
              size: 16,
              color: selected ? Colors.black : Colors.white70,
            ),

            const SizedBox(width: 6),

            /// 🔥 TEXT
            Text(
              text,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 13,
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
      default:
        return Icons.star;
    }
  }
}
