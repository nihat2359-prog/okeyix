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

    return Center(
      // 🔥 ORTALA
      child: ConstrainedBox(
        // 🔥 MAX GENİŞLİK VER
        constraints: const BoxConstraints(maxWidth: 340),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),

            gradient: LinearGradient(
              colors: [
                Colors.black.withOpacity(0.75),
                Colors.black.withOpacity(0.55),
              ],
            ),

            border: Border.all(
              color: Colors.amber.withOpacity(0.4),
              width: 1.2,
            ),

            boxShadow: [
              BoxShadow(color: Colors.amber.withOpacity(0.25), blurRadius: 12),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, // 🔥 BOYUTU İÇERİĞE GÖRE
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(
                    "${league['name']} Kilitli",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _reqItem("Coin", Format.coin(minCoin), playerCoin >= minCoin),
                  _reqItem(
                    "Rating",
                    Format.rating(minRating),
                    playerRating >= minRating,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerRight,
                child: _buildCoinButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reqItem(String title, String value, bool ok) {
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.cancel,
          color: ok ? Colors.green : Colors.red,
          size: 16,
        ),
        const SizedBox(width: 6),
        Text("$title: $value", style: TextStyle(color: Colors.white70)),
      ],
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
          mainAxisSize: MainAxisSize.min,
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
