import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'coin_store_scene.dart';

/// Uses the store's actual offer cards; buying still happens in the store.
class DailyRewardStoreShelf extends StatefulWidget {
  const DailyRewardStoreShelf({super.key, required this.onOpen});
  final VoidCallback? onOpen;
  @override
  State<DailyRewardStoreShelf> createState() => _DailyRewardStoreShelfState();
}

class _DailyRewardStoreShelfState extends State<DailyRewardStoreShelf> {
  final Map<String, String> _prices = {};
  static const _ids = [
    'coin_pack_baslangic',
    'coin_pack_standart',
    'coin_pack_elit',
    'coin_pack_mega',
  ];
  static const _titles = ['BAŞLANGIÇ', 'STANDART', 'ELİT', 'MEGA'];
  static const _coins = [500000, 1500000, 4000000, 20000000];

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrices());
  }

  Future<void> _loadPrices() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS))
      return;
    try {
      final suffix = defaultTargetPlatform == TargetPlatform.iOS ? '_ios' : '';
      final result = await InAppPurchase.instance
          .queryProductDetails(_ids.map((id) => '$id$suffix').toSet())
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        for (final p in result.productDetails) {
          _prices[p.id.replaceFirst(RegExp(r'_ios$'), '')] = p.price;
        }
      });
    } catch (_) {
      /* Prices are never invented. The store can retry. */
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SizedBox(
        height: 25,
        child: Row(
          children: [
            const Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'COIN MAĞAZASI',
                  style: TextStyle(
                    color: Color(0xFFE6C98B),
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('daily-store-open'),
              onPressed: widget.onOpen,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                foregroundColor: const Color(0xFFE6C98B),
                minimumSize: const Size(0, 25),
              ),
              child: const Text(
                'Mağazaya git ›',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 5),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: CoinStoreOfferCard(
                  tier: i,
                  offer: CoinStoreOffer(
                    id: _ids[i],
                    title: _titles[i],
                    coins: _coins[i],
                    price: _prices[_ids[i]] ?? 'İncele',
                    onBuy: widget.onOpen,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
