import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/screens/store_screen.dart';
import 'package:okeyix/services/user_state.dart';
import 'lobby_table_listing_card.dart';
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
  final String leagueName;

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
    this.leagueName = '',
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
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
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
      return LayoutBuilder(
        builder: (context, bounds) => Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: bounds.maxWidth,
              child: _buildLockedLeagueCard(
                league: widget.lockedLeague,
                playerCoin: widget.playerCoin,
                playerRating: widget.playerRating,
              ),
            ),
          ),
        ),
      );
    }

    /// ğŸ”¥ EMPTY
    if (widget.tables.isEmpty) {
      return LayoutBuilder(
        builder: (context, bounds) => Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(width: bounds.maxWidth, child: _buildEmptyCta()),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        final cardHeight = ((bounds.maxHeight - 12) / 2).clamp(1.0, 140.0);
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: GridView.builder(
            key: const ValueKey('vertical-tables'),
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(2),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: cardHeight,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: widget.tables.length,
            itemBuilder: (context, index) => LobbyTableListingCard(
              key: ValueKey(widget.tables[index]['id'].toString()),
              table: widget.tables[index],
              number: index + 1,
              blockedUserIds: widget.blockedUserIds,
              onJoin: widget.onJoin,
              onSpectate: widget.onSpectate,
              canSpectateAll: widget.canSpectateAll,
              onUserTap: widget.onUserTap,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyCta() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 18),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x8020252E), Color(0x99101319)],
            ),
            border: Border.all(color: const Color(0x38CBD0DC), width: .7),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x10DABF82),
                  border: Border.all(color: const Color(0x33DABF82), width: .7),
                ),
                child: const Icon(
                  Icons.table_restaurant_outlined,
                  size: 26,
                  color: Color(0xFFEAD6A5),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.leagueName.isEmpty
                    ? 'Açık masa yok'
                    : '${widget.leagueName} liginde açık masa yok',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFECE5D5),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Masayı sen aç, ilk el seninle başlasın.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFA9B3BF),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              if (widget.onCreateTable != null)
                SizedBox(
                  width: 160,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await widget.onCreateTable?.call();
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text(
                      'Masa Aç',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: const Color(0x14DABF82),
                      foregroundColor: const Color(0xFFEAD6A5),
                      side: const BorderSide(
                        color: Color(0x88DABF82),
                        width: .8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0x8020252E), Color(0x99101319)],
            ),
            border: Border.all(color: const Color(0x38CBD0DC), width: .7),
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
                      color: const Color(0x14DABF82),
                    ),
                    child: const Icon(
                      Icons.lock,
                      size: 18,
                      color: Color(0xFFEAD6A5),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      "${league['name']}",
                      style: const TextStyle(
                        color: Color(0xFFF3EFE3),
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
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
                      "LİG KİLİTLİ",
                      style: TextStyle(
                        color: Color(0xFFECC983),
                        fontWeight: FontWeight.w600,
                        fontSize: 9,
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
                "Bu lig için gereken coin ve seviyeye ulaşmalısın.",
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

        color: const Color(0x30191E26),

        border: Border.all(
          color: ok ? const Color(0x557C9A8B) : const Color(0x38DABF82),
        ),
      ),

      child: Center(
        // ğŸ”¥ TÃœM Ä°Ã‡ERÄ°ÄÄ° ORTALAR
        child: FittedBox(
          fit: BoxFit.scaleDown,
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
                  color: const Color(0x10DABF82),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: ok ? const Color(0xFF9BBCAF) : const Color(0xFFEAD6A5),
                ),
              ),

              const SizedBox(width: 8),

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
          color: const Color(0x14DABF82),
          border: Border.all(color: const Color(0x88DABF82), width: .8),

          /// ğŸ”¥ GLOW
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // ğŸ”¥ ORTALA
          children: const [
            Icon(Icons.toll_rounded, color: Color(0xFFEAD6A5), size: 18),
            SizedBox(width: 6),
            Text(
              "Coin Al",
              style: TextStyle(
                color: Color(0xFFEAD6A5),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
