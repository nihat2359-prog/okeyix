import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/ui/store/coin_store_scene.dart';
import 'package:okeyix/screens/login_screen.dart';
import 'package:okeyix/services/analytics_service.dart';
import 'package:okeyix/services/auth_service.dart';
import 'package:okeyix/services/celebration_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

Future<bool?> openStoreScreen(
  BuildContext context, {
  required int initialCoin,
}) async {
  if (kIsWeb) {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 520),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF17312A), Color(0xFF0F221D)],
              ),
              border: Border.all(color: const Color(0x88E4C57C), width: 1.4),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x88000000),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFF2D38D),
                      size: 24,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Web Mağazası Yakında',
                        style: TextStyle(
                          color: Color(0xFFF6E2B0),
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                        'Coin satın alma işlemleri şu anda sadece mobil uygulamada aktiftir.',
                  style: TextStyle(
                    color: Color(0xFFE4ECE7),
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Aynı hesabınızla mobil uygulamaya giriş yaparak satın alma yapabilirsiniz. Aldığınız coinler webde de anında hesabınıza yansır.',
                  style: TextStyle(
                    color: Color(0xBFE4ECE7),
                    fontSize: 13.5,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFE4B54E),
                      foregroundColor: const Color(0xFF1A1A1A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Anladım',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return false;
  }

  final result = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => StoreScreen(initialCoin: initialCoin)),
  );
  return result;
}

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
  // final Map<String, int> coinRewards = {
  //   // ANDROID
  //   "coin_pack_baslangic": 10000,
  //   "coin_pack_standart": 30000,
  //   "coin_pack_elit": 80000,
  //   "coin_pack_mega": 200000,

  //   // iOS
  //   "coin_pack_baslangic_ios": 10000,
  //   "coin_pack_standart_ios": 30000,
  //   "coin_pack_elit_ios": 80000,
  //   "coin_pack_mega_ios": 200000,
  // };

  //   final Map<String, int> coinRewards = {
  //   // ANDROID
  //   "coin_pack_baslangic": 80000,    // $0.99
  //   "coin_pack_standart": 200000,    // $1.99
  //   "coin_pack_elit": 600000,        // $3.99
  //   "coin_pack_mega": 2000000,       // $8.99

  //   // iOS
  //   "coin_pack_baslangic_ios": 80000,
  //   "coin_pack_standart_ios": 200000,
  //   "coin_pack_elit_ios": 600000,
  //   "coin_pack_mega_ios": 2000000,
  // };

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
    final ids = Platform.isIOS
        ? {
            'coin_pack_baslangic_ios',
            'coin_pack_standart_ios',
            'coin_pack_elit_ios',
            'coin_pack_mega_ios',
          }
        : {
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
        await AnalyticsService.instance.logCoinPurchase(
          productId: purchase.productID,
          coins: coins is int ? coins : 0,
          platform: Platform.isIOS ? 'ios' : 'android',
        );
        CelebrationService.showConfetti();
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

        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          _iap.completePurchase(purchase);
        }
      }
    });
  }

  void buy(ProductDetails product) {
    if (AuthService.isGuest()) {
      _showLoginRequiredDialog();
      return;
    }

    final purchaseParam = PurchaseParam(productDetails: product);

    _iap.buyConsumable(purchaseParam: purchaseParam);
  }

  void _showLoginRequiredDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Color(0xFF0F2A1F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.withOpacity(0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, color: Colors.amber, size: 36),
              SizedBox(height: 12),

              Text(
                "Hesap Gerekli",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),

              SizedBox(height: 10),

              Text(
                "Coin satın almak için hesabını bağlamalısın.\n\n"
                "Bu sayede satın aldıkların kaybolmaz.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),

              SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        "İptal",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Future.delayed(Duration(milliseconds: 200), () {
                          _signOutAndGoLogin();
                        });
                      },
                      child: Text("Giriş Yap"),
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

  Future<void> _signOutAndGoLogin() async {
    try {
      await supabase.auth.signOut();
    } catch (e) {
      debugPrint('SIGN OUT ERROR: $e');
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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
                  "+${Format.coin(coins)}",
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

  String normalizeId(String id) {
    return id.replaceAll("_ios", "");
  }

  @override
  Widget build(BuildContext context) {
    ProductDetails? packBaslangic;
    ProductDetails? packStandart;
    ProductDetails? packElit;
    ProductDetails? packMega;

    try {
      packBaslangic = products.firstWhere(
        (p) => normalizeId(p.id) == "coin_pack_baslangic",
      );
    } catch (_) {}

    try {
      packStandart = products.firstWhere(
        (p) => normalizeId(p.id) == "coin_pack_standart",
      );
    } catch (_) {}

    try {
      packElit = products.firstWhere(
        (p) => normalizeId(p.id) == "coin_pack_elit",
      );
    } catch (_) {}

    try {
      packMega = products.firstWhere(
        (p) => normalizeId(p.id) == "coin_pack_mega",
      );
    } catch (_) {}

    return CoinStoreScene(
      balance: widget.initialCoin,
      onClose: () => Navigator.pop(context),
      offers: [
        CoinStoreOffer(id: 'coin_pack_baslangic', title: 'BAŞLANGIÇ',
          coins: 80000, price: packBaslangic?.price ?? '...',
          onBuy: packBaslangic == null ? null : () => buy(packBaslangic!)),
        CoinStoreOffer(id: 'coin_pack_standart', title: 'STANDART',
          coins: 200000, price: packStandart?.price ?? '...',
          onBuy: packStandart == null ? null : () => buy(packStandart!)),
        CoinStoreOffer(id: 'coin_pack_elit', title: 'ELİT',
          coins: 600000, price: packElit?.price ?? '...',
          onBuy: packElit == null ? null : () => buy(packElit!)),
        CoinStoreOffer(id: 'coin_pack_mega', title: 'MEGA',
          coins: 2000000, price: packMega?.price ?? '...',
          onBuy: packMega == null ? null : () => buy(packMega!)),
      ],
    );
  }
}
class _PurchaseSuccessCard extends StatelessWidget {
  final int coins;

  const _PurchaseSuccessCard({required this.coins});

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
              "+${Format.coin(coins)} COIN",
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
