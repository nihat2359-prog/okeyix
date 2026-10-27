import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'coin_store_artwork.dart';
import '../../services/store_diagnostics.dart';

class CoinStoreOffer {
  const CoinStoreOffer({
    required this.id,
    required this.title,
    required this.coins,
    required this.price,
    required this.onBuy,
  });
  final String id, title, price;
  final int coins;
  final VoidCallback? onBuy;
}

class CoinStoreScene extends StatelessWidget {
  const CoinStoreScene({
    super.key,
    required this.balance,
    required this.offers,
    required this.onClose,
  });
  final int balance;
  final List<CoinStoreOffer> offers;
  final VoidCallback onClose;
  static const gold = Color(0xFFE6C98B);

  @override
  Widget build(BuildContext context) => StorePaintProbe(child: Scaffold(
    backgroundColor: const Color(0xFF080D15),
    body: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/lobby/lobby.png',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x77080D15),
                  Color(0xB30A111A),
                  Color(0xED080C13),
                ],
                stops: [0, .4, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, limits) {
              StoreDiagnostics.once('scene_layout', {
                'width': limits.maxWidth, 'height': limits.maxHeight,
                'offers': offers.length,
              });
              final compact = limits.maxHeight < 370;
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 12 : 24,
                  6,
                  compact ? 12 : 24,
                  10,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: compact ? 48 : 62,
                      child: Row(
                        children: [
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'OKEYIX  /  MAĞAZA',
                                    style: TextStyle(
                                      color: gold,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 2.1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Coin Mağazası',
                                    style: TextStyle(
                                      color: const Color(0xFFF6EAD3),
                                      fontSize: compact ? 23 : 29,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.6,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: limits.maxWidth * .28,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.toll_rounded,
                                    color: gold,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 7),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'BAKİYEN',
                                        style: TextStyle(
                                          color: Color(0xFF9EA8B4),
                                          fontSize: 8,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                      Text(
                                        Format.balance(balance),
                                        key: const ValueKey('store-balance'),
                                        style: const TextStyle(
                                          color: Color(0xFFF1E3C4),
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          IconButton(
                            key: const ValueKey('store-close'),
                            tooltip: 'Mağazayı kapat',
                            onPressed: onClose,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFFC3CCD7),
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: 1100,
                            maxHeight: 440,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (
                                var index = 0;
                                index < offers.length;
                                index++
                              ) ...[
                                if (index > 0)
                                  SizedBox(width: compact ? 8 : 12),
                                Expanded(
                                  child: _Offer(
                                    offer: offers[index],
                                    tier: index,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
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
  ));
}

class _Offer extends StatelessWidget {
  const _Offer({required this.offer, required this.tier});
  final CoinStoreOffer offer;
  final int tier;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      StoreDiagnostics.once('offer_layout_$tier', {
        'width': bounds.maxWidth, 'height': bounds.maxHeight,
      });
      final small = bounds.maxHeight < 240;
      final best = tier == 2;
      return Container(
        key: ValueKey('store-offer-${offer.id}'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: best
                ? [const Color(0xD5322D25), const Color(0xB3101720)]
                : [const Color(0xB3232C36), const Color(0xB30B121D)],
          ),
          border: Border.all(
            color: best ? const Color(0xBBD4B273) : const Color(0x487F7867),
            width: best ? 1 : .6,
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: small ? 23 : 30,
              child: Center(
                child: best
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0x22DABF82),
                          borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(8),
                          ),
                        ),
                        child: const FittedBox(
                          child: Text(
                            'EN İYİ FİYAT',
                            style: TextStyle(
                              color: CoinStoreScene.gold,
                              fontSize: 9,
                              letterSpacing: .6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        ['I', 'II', 'III', 'IV'][tier],
                        style: const TextStyle(
                          color: Color(0xFF9D8965),
                          fontSize: 10,
                          letterSpacing: 2,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                child: Text(
                  Format.coin(offer.coins),
                  style: TextStyle(
                    color: const Color(0xFFFFE7B7),
                    fontSize: small ? 26 : 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.7,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: FittedBox(
                child: Text(
                  offer.title,
                  style: const TextStyle(
                    color: Color(0xFFCAD0D5),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            Expanded(child: CoinStoreArtwork(tier: tier)),
            Padding(
              padding: EdgeInsets.fromLTRB(
                small ? 8 : 12,
                0,
                small ? 8 : 12,
                small ? 8 : 12,
              ),
              child: SizedBox(
                height: small ? 36 : 42,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF4DC9F),
                        Color(0xFFD3AF66),
                        Color(0xFFB98D44),
                        Color(0xFFE1BF78),
                      ],
                      stops: [0, .36, .74, 1],
                    ),
                    border: Border.all(
                      color: const Color(0xFFEAD19B),
                      width: .8,
                    ),
                  ),
                  child: TextButton(
                    key: ValueKey('store-buy-${offer.id}'),
                    onPressed: offer.onBuy,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF30210B),
                      disabledForegroundColor: const Color(0xFF756446),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shopping_bag_outlined,
                            size: math.min(bounds.maxWidth * .12, 16),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            offer.price,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
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
