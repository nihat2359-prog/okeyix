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
  final Future<void> Function()? onCreateTable;

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
    this.isLocked = false, // ğŸ”¥ BURASI KRÄ°TÄ°K
    this.lockedLeague,
    required this.playerCoin,
    required this.playerRating,
    this.onNeedRefreshUser,
    this.onCreateTable,
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
    /// ğŸ”¥ LOADING
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

    /// ğŸ”¥ EMPTY
    if (widget.tables.isEmpty) {
      if (widget.onCreateTable == null) {
        return const Center(
          child: Text(
            "Masa bulunmamaktadï¿½r.",
            style: TextStyle(color: Colors.white70),
          ),
        );
      }
      return _buildEmptyCta();
    }
    return RefreshIndicator(
      onRefresh: widget.onRefresh,

      /// ğŸ”¥ KRÄ°TÄ°K: refresh iÃ§in scrollable wrapper
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,

          child: ListWheelScrollView.useDelegate(
            controller: _controller,

            itemExtent: 200,

            /// ğŸ”¥ daha iyi his
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
                      child: IgnorePointer(
                        ignoring: !isSelected,
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
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCta() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 18),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xDD1E232A), Color(0xDD12161C)],
            ),
            border: Border.all(color: const Color(0x88E7C66A), width: 1.1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.table_restaurant_rounded,
                size: 34,
                color: Color(0xFFE7C66A),
              ),
              const SizedBox(height: 10),
              const Text(
                'Bu ligde şu an açık masa yok',
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
                style: TextStyle(color: Color(0xC7E0ECE5), fontSize: 13.2),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: 210,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await widget.onCreateTable?.call();
                  },
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: const Text(
                    'Masa Aç',
                    style: TextStyle(fontWeight: FontWeight.w800),
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xDD1E232A), Color(0xDD12161C)],
            ),
            border: Border.all(color: const Color(0xBFE7C66A), width: 1.2),

            boxShadow: [
              BoxShadow(
                color: const Color(0xAA000000).withOpacity(0.9),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: const Color(0x44E7C66A),
                blurRadius: 18,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              /// ğŸ”¥ HEADER
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD77A), Color(0xFFC98A2D)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0x66F0C878),
                          blurRadius: 8,
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
                        color: Color(0xFFF3EFE3),
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: const Color(0x223B2A1A),
                      border: Border.all(
                        color: const Color(0x99E3B766),
                        width: 0.8,
                      ),
                    ),
                    child: const Text(
                      "Kilitli",
                      style: TextStyle(
                        color: Color(0xFFECC983),
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              /// ğŸ”¥ REQUIREMENTS (CARD STYLE)
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
                      title: "Seviye",
                      value: Format.rating(minRating),
                      ok: ratingOk,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              const Text(
                "Oynadıkça kazan, kazandıkça üst liglere katıl.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xB7DCE6DF),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 12),

              /// ğŸ”¥ CTA
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
              ? [const Color(0xFF232932), const Color(0xFF121720)]
              : [const Color(0xFF3A2318), const Color(0xFF130D09)],
        ),

        border: Border.all(
          color: ok ? const Color(0xAA8B96A8) : const Color(0xCCB17254),
        ),
      ),

      child: Center(
        // ğŸ”¥ TÃœM Ä°Ã‡ERÄ°ÄÄ° ORTALAR
        child: Row(
          mainAxisSize: MainAxisSize.min, // ğŸ”¥ iÃ§erik kadar yer kaplar
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            /// ğŸ”¥ ICON
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ok ? const Color(0x33343C4A) : const Color(0x334A2820),
              ),
              child: Icon(
                icon,
                size: 16,
                color: ok ? const Color(0xFFC5CEDD) : const Color(0xFFE3A27F),
              ),
            ),

            const SizedBox(width: 10),

            /// ğŸ”¥ TEXTLER
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start, // soldan hizalÄ± metin
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFC9D1CD),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFFF6F2E8),
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
        final result = await openStoreScreen(
          context,
          initialCoin: UserState.userCoin,
        );

        if (result == true && widget.onNeedRefreshUser != null) {
          await widget.onNeedRefreshUser!(); // ğŸ”¥ parent tetiklenir
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),

          /// ğŸ”¥ GOLD GRADIENT
          gradient: const LinearGradient(
            colors: [Color(0xFFE8C77A), Color(0xFFB17833)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),

          /// ğŸ”¥ GLOW
          boxShadow: [
            BoxShadow(
              color: const Color(0xAA5A391A).withOpacity(0.75),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // ğŸ”¥ ORTALA
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
