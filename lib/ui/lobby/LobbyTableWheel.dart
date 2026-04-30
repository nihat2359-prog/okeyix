import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/screens/store_screen.dart';
import 'package:okeyix/services/user_state.dart';
import 'lobby_table_card.dart';
import 'lobby_shimmer_loaders.dart';

class LobbyTableWheel extends StatefulWidget {
  final List<Map<String, dynamic>> tables;
  final Set<String> blockedUserIds;
  final Function(Map<String, dynamic>) onJoin;
  final Function(Map<String, dynamic>) onSpectate;
  final bool canSpectateAll;
  final Function(Map<String, dynamic>) onUserTap;
  final Future<void> Function() onRefresh;
  final bool loading;

  final bool isLocked;
  final dynamic lockedLeague;
  final int playerCoin;
  final int playerRating;
  final Future<void> Function()? onNeedRefreshUser;

  const LobbyTableWheel({
    super.key,
    required this.tables,
    required this.blockedUserIds,
    required this.onJoin,
    required this.onSpectate,
    required this.canSpectateAll,
    required this.onUserTap,
    required this.onRefresh,
    required this.loading,
    this.isLocked = false, // 🔥 BURASI KRİTİK
    this.lockedLeague,
    required this.playerCoin,
    required this.playerRating,
    this.onNeedRefreshUser,
  });

  @override
  State<LobbyTableWheel> createState() => _LobbyTableWheelState();
}

class _LobbyTableWheelState extends State<LobbyTableWheel> {
  int selectedIndex = 0;
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    /// 🔥 LOADING
    if (widget.loading) {
      return const Center(child: LobbyLoading());
    }

    if (widget.isLocked) {
      return _buildLockedLeagueCard(
        league: widget.lockedLeague,
        playerCoin: widget.playerCoin,
        playerRating: widget.playerRating,
      );
    }

    /// 🔥 EMPTY
    if (widget.tables.isEmpty) {
      return const Center(
        child: Text(
          "Masa bulunmamaktadır.",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,

      /// 🔥 KRİTİK: refresh için scrollable wrapper
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,

          child: ListWheelScrollView.useDelegate(
            controller: _controller,

            itemExtent: 200,

            /// 🔥 daha iyi his
            perspective: 0.003,
            diameterRatio: 2.2,
            squeeze: 1.1,

            physics: const FixedExtentScrollPhysics(),

            onSelectedItemChanged: (index) {
              setState(() {
                selectedIndex = index;
              });
            },

            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.tables.length,
              builder: (context, index) {
                final table = widget.tables[index];
                final isSelected = index == selectedIndex;

                return Center(
                  child: Transform.scale(
                    scale: isSelected ? 0.92 : 0.75,
                    child: Opacity(
                      opacity: isSelected ? 1 : 0.5,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),

                        decoration: BoxDecoration(
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(0x66F2C14E),
                                    blurRadius: 35,
                                    spreadRadius: 3,
                                  ),
                                ]
                              : [],
                        ),

                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: LobbyTableCard(
                            table: table,
                            blockedUserIds: widget.blockedUserIds,
                            onJoin: widget.onJoin,
                            onSpectate: widget.onSpectate,
                            canSpectateAll: widget.canSpectateAll,
                            onUserTap: widget.onUserTap,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLockedLeagueCard({
    required dynamic league,
    required int playerCoin,
    required int playerRating,
  }) {
    final minCoin = league['min_coin'];
    final minRating = league['min_rating'];

    final coinOk = playerCoin >= minCoin;
    final ratingOk = playerRating >= minRating;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),

            // 🔥 DARK GLASS + DEPTH
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F2A1E), Color(0xFF071A12)],
            ),

            border: Border.all(color: Colors.amber.withOpacity(0.35), width: 1),

            boxShadow: [
              // glow
              BoxShadow(
                color: Colors.amber.withOpacity(0.18),
                blurRadius: 20,
                spreadRadius: 1,
              ),

              // depth
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                offset: const Offset(0, 10),
                blurRadius: 18,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              /// 🔥 HEADER
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Colors.amber.shade300, Colors.orange.shade700],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.4),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.lock,
                      size: 18,
                      color: Colors.black,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      "${league['name']}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),

                  const Text(
                    "Kilitli",
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              /// 🔥 REQUIREMENTS (CARD STYLE)
              Row(
                children: [
                  Expanded(
                    child: _premiumReqItem(
                      icon: Icons.monetization_on,
                      title: "Coin",
                      value: Format.coin(minCoin),
                      ok: coinOk,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _premiumReqItem(
                      icon: Icons.star,
                      title: "Rating",
                      value: Format.rating(minRating),
                      ok: ratingOk,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              /// 🔥 CTA
              SizedBox(width: double.infinity, child: _buildCoinButton()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _premiumReqItem({
    required IconData icon,
    required String title,
    required String value,
    required bool ok,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),

        gradient: LinearGradient(
          colors: ok
              ? [const Color(0xFF1F3D2B), const Color(0xFF13251B)]
              : [const Color(0xFF3A1F1F), const Color(0xFF261313)],
        ),

        border: Border.all(
          color: ok
              ? Colors.greenAccent.withOpacity(0.35)
              : Colors.redAccent.withOpacity(0.35),
        ),
      ),

      child: Center(
        // 🔥 TÜM İÇERİĞİ ORTALAR
        child: Row(
          mainAxisSize: MainAxisSize.min, // 🔥 içerik kadar yer kaplar
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            /// 🔥 ICON
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (ok ? Colors.greenAccent : Colors.redAccent).withOpacity(
                  0.12,
                ),
              ),
              child: Icon(
                icon,
                size: 16,
                color: ok ? Colors.greenAccent : Colors.redAccent,
              ),
            ),

            const SizedBox(width: 10),

            /// 🔥 TEXTLER
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start, // soldan hizalı metin
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinButton() {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoreScreen(initialCoin: UserState.userCoin),
          ),
        );

        if (result == true && widget.onNeedRefreshUser != null) {
          await widget.onNeedRefreshUser!(); // 🔥 parent tetiklenir
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),

          /// 🔥 GOLD GRADIENT
          gradient: const LinearGradient(
            colors: [Color(0xFFF2C14E), Color(0xFFD4A24C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),

          /// 🔥 GLOW
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF2C14E).withOpacity(0.5),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // 🔥 ORTALA
          children: const [
            Icon(Icons.monetization_on, color: Colors.black, size: 18),
            SizedBox(width: 6),
            Text(
              "Coin Al",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
