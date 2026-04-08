import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';

class StoreScreen extends StatefulWidget {
  final int initialCoin;

  const StoreScreen({super.key, required this.initialCoin});

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final supabase = Supabase.instance.client;
  final InAppPurchase _iap = InAppPurchase.instance;

  List<ProductDetails> products = [];

  late StreamSubscription<List<PurchaseDetails>> _subscription;
  final Map<String, int> coinRewards = {
    "coin_pack_baslangic": 10000,
    "coin_pack_standart": 30000,
    "coin_pack_elit": 80000,
    "coin_pack_mega": 200000,
  };

  @override
  void initState() {
    super.initState();
    loadProducts();
    listenPurchases();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> loadProducts() async {
    const ids = {
      'coin_pack_baslangic',
      'coin_pack_standart',
      'coin_pack_elit',
      'coin_pack_mega',
    };

    final response = await _iap.queryProductDetails(ids);

    setState(() {
      products = response.productDetails;
    });
  }

  Future<void> verifyPurchase(PurchaseDetails purchase) async {
    final userId = supabase.auth.currentUser!.id;

    try {
      final session = supabase.auth.currentSession;

      final res = await supabase.functions.invoke(
        "verify_purchase",
        body: {
          "userId": userId,
          "productId": purchase.productID,
          "token": purchase.verificationData.serverVerificationData,
          "platform": Platform.isIOS ? "ios" : "android",
        },
        headers: {"Authorization": "Bearer ${session?.accessToken}"},
      );

      final data = res.data is String ? jsonDecode(res.data) : res.data;

      if (!mounted) return;

      if (data["success"] == true) {
        final coins = data["coins"];
        showPurchaseSuccess(context, coins);
      } else {
        print("VERIFY FAILED: $data");
      }
    } catch (e) {
      print("VERIFY ERROR: $e");
    }
  }

  void showPurchaseSuccess(BuildContext context, int coins) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Center(child: _PurchaseSuccessCard(coins: coins));
      },
      transitionBuilder: (context, anim, secondary, child) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(anim.value),
          child: child,
        );
      },
    );
  }

  void listenPurchases() {
    _subscription = _iap.purchaseStream.listen((purchases) {
      for (var purchase in purchases) {
        print("PURCHASE STATUS: ${purchase.status}");

        if (purchase.status == PurchaseStatus.pending) {
          print("Purchase pending...");
        }

        if (purchase.status == PurchaseStatus.purchased) {
          verifyPurchase(purchase);
        }

        if (purchase.status == PurchaseStatus.error) {
          print("Purchase error: ${purchase.error}");
        }

        if (purchase.pendingCompletePurchase) {
          _iap.completePurchase(purchase);
        }
      }
    });
  }

  void buy(ProductDetails product) {
    final purchaseParam = PurchaseParam(productDetails: product);

    _iap.buyConsumable(purchaseParam: purchaseParam);
  }

  void showCoinAnimation(int coins) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: const Color(0xFF11181C),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE7C06A)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset("assets/images/coins/coins_large.png", height: 90),

                const SizedBox(height: 10),

                Text(
                  "+${formatCoins(coins)}",
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFE7C06A),
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  "COIN KAZANDIN",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
        );
      },
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.pop(context);
    });
  }

  String formatCoins(int value) {
    if (value >= 1000000) {
      return "${(value / 1000000).toStringAsFixed(1)}M";
    }
    if (value >= 1000) {
      return "${(value / 1000).toStringAsFixed(1)}K";
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0E0F12),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFE7C06A)),
        ),
      );
    }
    ProductDetails? packBaslangic;
    ProductDetails? packStandart;
    ProductDetails? packElit;
    ProductDetails? packMega;

    try {
      packBaslangic = products.firstWhere((p) => p.id == "coin_pack_baslangic");
    } catch (_) {}

    try {
      packStandart = products.firstWhere((p) => p.id == "coin_pack_standart");
    } catch (_) {}

    try {
      packElit = products.firstWhere((p) => p.id == "coin_pack_elit");
    } catch (_) {}

    try {
      packMega = products.firstWhere((p) => p.id == "coin_pack_mega");
    } catch (_) {}

    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              "assets/images/lobby/lobby.png",
              fit: BoxFit.cover,
            ),
          ),

          Positioned.fill(child: Container(color: const Color(0xCC000000))),

          SafeArea(
            child: Column(
              children: [
                /// HEADER
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1A2328), Color(0xFF11181C)],
                          ),
                          border: Border.all(color: const Color(0x55E7C06A)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.monetization_on,
                              color: Color(0xFFE7C06A),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              formatCoins(widget.initialCoin),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                /// HERO
                const Text(
                  "COIN MAĞAZASI",
                  style: TextStyle(
                    color: Color(0xFFE7C06A),
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 10),

                /// CARDS
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: CoinCard(
                            title: "BAŞLANGIÇ",
                            coins: "10.000",
                            price: packBaslangic?.price ?? "...",
                            asset: "assets/images/coins/coins_small.png",
                            onTap: () {
                              if (packBaslangic != null) {
                                buy(packBaslangic);
                              }
                            },
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: CoinCard(
                            title: "STANDART",
                            coins: "30.000",
                            price: packStandart?.price ?? "...",
                            asset: "assets/images/coins/coins_medium.png",
                            onTap: () {
                              if (packStandart != null) {
                                buy(packStandart);
                              }
                            },
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: CoinCard(
                            title: "ELİT",
                            coins: "80.000",
                            price: packElit?.price ?? "...",
                            best: true,
                            asset: "assets/images/coins/coins_large.png",
                            onTap: () {
                              if (packElit != null) {
                                buy(packElit);
                              }
                            },
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: CoinCard(
                            title: "MEGA",
                            coins: "200.000",
                            price: packMega?.price ?? "...",
                            asset: "assets/images/coins/coins_huge.png",
                            onTap: () {
                              if (packMega != null) {
                                buy(packMega);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseSuccessCard extends StatelessWidget {
  final int coins;

  const _PurchaseSuccessCard({required this.coins});

  String formatCoins(int value) {
    if (value >= 1000000) {
      return "${(value / 1000000).toStringAsFixed(1)}M";
    }
    if (value >= 1000) {
      return "${(value / 1000).toStringAsFixed(1)}K";
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF1A2328), Color(0xFF11181C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFFE7C06A), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55E7C06A),
              blurRadius: 25,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            /// COIN IMAGE
            Image.asset("assets/images/coins/coins_large.png", height: 90),

            const SizedBox(height: 12),

            const Text(
              "SATIN ALMA BAŞARILI",
              style: TextStyle(
                color: Color(0xFFE7C06A),
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              "+${formatCoins(coins)} COIN",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 16),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE7C06A),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context, true);
              },
              child: const Text(
                "DEVAM",
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoinCard extends StatefulWidget {
  final String title;
  final String coins;
  final String price;
  final String asset;
  final bool best;
  final VoidCallback? onTap;

  const CoinCard({
    super.key,
    required this.title,
    required this.coins,
    required this.price,
    required this.asset,
    this.best = false,
    this.onTap,
  });

  @override
  State<CoinCard> createState() => _CoinCardState();
}

class _CoinCardState extends State<CoinCard> {
  double scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) {
        setState(() => scale = 0.96);
      },
      onTapUp: (_) {
        setState(() => scale = 1);
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: scale,
        child: Stack(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A2328), Color(0xFF11181C)],
                ),
                border: Border.all(
                  color: widget.best
                      ? const Color(0xFFE7C06A)
                      : const Color(0x33E7C06A),
                  width: 2,
                ),
                boxShadow: widget.best
                    ? [
                        const BoxShadow(
                          color: Color(0x55E7C06A),
                          blurRadius: 20,
                        ),
                      ]
                    : [],
              ),

              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    const SizedBox(height: 10),

                    Image.asset(widget.asset, height: 70),

                    const SizedBox(height: 6),

                    Text(
                      widget.coins,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    Text(
                      widget.title,
                      style: const TextStyle(color: Colors.white70),
                    ),

                    const Spacer(),

                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7C06A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          widget.price,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (widget.best)
              Positioned(
                top: 0,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7C06A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "EN İYİ FİYAT",
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
