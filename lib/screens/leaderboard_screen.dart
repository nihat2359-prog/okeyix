import 'package:flutter/material.dart';
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

    players = ranked.map((r) {
      final id = r['id']?.toString();
      final user = id == null ? null : usersById[id];
      return <String, dynamic>{
        'username': user?['username'] ?? 'Oyuncu',
        'avatar_url': user?['avatar_url'],
        'rating': r['rating'] ?? 1200,
      };
    }).toList(growable: false);

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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),

      decoration: BoxDecoration(
        color: const Color(0xFF17191F).withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),

      child: Row(
        children: [
          /// SIRA
          Text(
            "#${index + 1}",
            style: const TextStyle(
              color: Colors.amber,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),

          const SizedBox(width: 12),

          /// AVATAR
          CircleAvatar(
            radius: 20,
            backgroundImage: avatar,
            backgroundColor: Colors.grey[700],
          ),

          const SizedBox(width: 12),

          /// USERNAME
          Expanded(
            child: Text(
              p['username'] ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          /// COIN ICON
          const Icon(Icons.emoji_events, color: Colors.amber, size: 20),

          const SizedBox(width: 6),

          /// RATING
          Text(
            "${p['rating']}",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
