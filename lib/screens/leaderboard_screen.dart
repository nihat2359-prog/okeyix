import 'package:flutter/material.dart';
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

  List<Map<String, dynamic>> players = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
    });
    final profileRows = await supabase
        .from('profiles')
        .select('id,rating')
        .order('rating', ascending: false)
        .limit(20);
    final ranked = (profileRows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final ids = ranked
        .map((r) => r['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    final usersById = <String, Map<String, dynamic>>{};
    if (ids.isNotEmpty) {
      final userRows = await supabase
          .from('users')
          .select('id,username,avatar_url')
          .inFilter('id', ids);
      for (final raw in (userRows as List)) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['id']?.toString();
        if (id != null && id.isNotEmpty) usersById[id] = row;
      }
    }

    players = ranked
        .map((r) {
          final id = r['id']?.toString();
          final user = id == null ? null : usersById[id];
          return <String, dynamic>{
            'username': user?['username'] ?? 'Oyuncu',
            'avatar_url': user?['avatar_url'],
            'rating': r['rating'] ?? 1200,
            'id': user?['id'],
          };
        })
        .toList(growable: false);

    setState(() {
      loading = false;
    });
  }

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
                /// HEADER
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),

                      const Expanded(
                        child: Text(
                          "En İyi Oyuncular",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(width: 40),
                    ],
                  ),
                ),

                /// LIST
                Expanded(
                  child: loading
                      ? const Center(child: LobbyLoading())
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: players.length,
                          itemBuilder: (_, i) {
                            final p = players[i];
                            return _playerRow(i, p);
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playerRow(int index, Map<String, dynamic> p) {
    final avatarUrl = p['avatar_url'];

    ImageProvider? avatar;

    if (avatarUrl != null && avatarUrl.toString().startsWith('http')) {
      avatar = NetworkImage(avatarUrl);
    } else if (avatarUrl != null &&
        avatarUrl.toString().startsWith('assets/')) {
      avatar = AssetImage(avatarUrl);
    }

    final name = p['username'] ?? '';
    final rating = Format.rating(p['rating']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),

      /// 🔥 CLICK + RIPPLE
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onPlayerTap(p),

          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),

            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),

              /// 🔥 GLASS + GRADIENT
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1B2A24).withOpacity(0.85),
                  const Color(0xFF0F1B17).withOpacity(0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),

              border: Border.all(color: Colors.white.withOpacity(0.05)),

              /// 🔥 DEPTH
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),

            child: Row(
              children: [
                /// 🔥 RANK BADGE
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE7C66A), Color(0xFFB9932F)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE7C66A).withOpacity(0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Text(
                    "${index + 1}",
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                /// 🔥 AVATAR (GLOW)
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE7C66A).withOpacity(0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 22,
                    backgroundImage: avatar,
                    backgroundColor: Colors.grey[800],
                  ),
                ),

                const SizedBox(width: 12),

                /// 🔥 USER INFO
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Row(
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            size: 14,
                            color: Color(0xFFE7C66A),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            rating,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                /// 🔥 RIGHT SIDE ICON (action hint)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Colors.white.withOpacity(0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onPlayerTap(dynamic p) {
    final userId = p['id'];
    if (userId == null) return;
    ProfileService.showUserCard({'id': userId});
  }
}
