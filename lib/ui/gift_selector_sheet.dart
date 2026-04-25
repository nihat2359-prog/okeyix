import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GiftSelectorSheet extends StatefulWidget {
  final String receiverId;
  final String receiverName;
  final VoidCallback onGiftSent;

  const GiftSelectorSheet({
    super.key,
    required this.receiverId,
    required this.receiverName,
    required this.onGiftSent,
  });

  @override
  State<GiftSelectorSheet> createState() => _GiftSelectorSheetState();
}

class _GiftSelectorSheetState extends State<GiftSelectorSheet>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _floatController;

  late Animation<Offset> _slideAnimation;
  int _selectedGiftIndex = -1;
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> gifts = [
    {
      'type': 'rose',
      'name': 'Gül',
      'cost': 100,
      'emoji': '🌹',
      'color': Colors.red,
    },
    {
      'type': 'cake',
      'name': 'Pasta',
      'cost': 150,
      'emoji': '🎂',
      'color': Colors.orange,
    },
    {
      'type': 'heart',
      'name': 'Kalp',
      'cost': 200,
      'emoji': '❤️',
      'color': Colors.pink,
    },
    {
      'type': 'star',
      'name': 'Yıldız',
      'cost': 250,
      'emoji': '⭐',
      'color': Colors.amber,
    },
    {
      'type': 'diamond',
      'name': 'Elmas',
      'cost': 500,
      'emoji': '💎',
      'color': Colors.lightBlue,
    },
    {
      'type': 'fire',
      'name': 'Ateş',
      'cost': 300,
      'emoji': '🔥',
      'color': Colors.deepOrange,
    },
  ];

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();

    _floatController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _slideAnimation =
        Tween<Offset>(
          begin: const Offset(0, 1), // 🔥 aşağıdan başlar
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _scaleController, curve: Curves.easeOutCubic),
        );
    _scaleController.forward();
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _sendGift(Map<String, dynamic> gift) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) throw Exception('Kullanıcı bulunamadı');

      // Kullanıcının coin'ini kontrol et
      final profile = await supabase
          .from('profiles')
          .select('coins')
          .eq('id', userId)
          .single();

      final userCoins = profile['coins'] ?? 0;
      final giftCost = gift['cost'];

      if (userCoins < giftCost) {
        setState(() {
          _errorMessage = 'Yetersiz coin! (${giftCost - userCoins} eksik)';
          _isLoading = false;
        });
        return;
      }

      // Hediye gönder
      try {
        await supabase.from('gifts').insert({
          'sender_id': userId,
          'receiver_id': widget.receiverId,
          'gift_type': gift['type'],
          'coin_cost': giftCost,
        });

        // ✅ başarı
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Hediye gönderildi 🎁")));
      } catch (e) {
        final msg = _parseGiftError(e);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onGiftSent();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${gift['emoji']} hediyesi ${widget.receiverName} gösterildi!',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green[600],
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Hata: ${e.toString()}';
        _isLoading = false;
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  String _parseGiftError(dynamic e) {
    final error = e.toString().toLowerCase();

    if (error.contains("yetersiz coin")) {
      return "Yeterli coin yok 💰";
    }

    if (error.contains("zaten hediye")) {
      return "Bugün bu kullanıcıya zaten hediye gönderdin 🎁";
    }

    return "Hediye gönderilemedi ⚠️";
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _scaleController,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.0).animate(_scaleController),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),

                  /// 🔥 AAA GLASS
                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFFE7C66A).withOpacity(0.35),
                      width: 1.5,
                    ),
                  ),
                ),

                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      14,
                      16,
                      14,
                      14 + MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        /// 🔹 HANDLE
                        Container(
                          width: 50,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 16),

                        /// 🔥 HEADER
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFD4AF37),
                                    Color(0xFFFFD700),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.amber.withOpacity(0.6),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.card_giftcard_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hediye Gönder',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      shadows: [
                                        Shadow(
                                          color: Colors.amber.withOpacity(0.6),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    widget.receiverName,
                                    style: const TextStyle(
                                      color: Color(0xFFE7C66A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),

                        /// ❗ ERROR
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: Colors.red.withOpacity(0.15),
                              border: Border.all(
                                color: Colors.red.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                        if (_errorMessage != null) const SizedBox(height: 12),

                        /// 🎁 GRID
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 6,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.9,
                              ),
                          itemCount: gifts.length,
                          itemBuilder: (context, index) {
                            final gift = gifts[index];
                            final isSelected = _selectedGiftIndex == index;

                            return GestureDetector(
                              onTap: _isLoading
                                  ? null
                                  : () {
                                      setState(
                                        () => _selectedGiftIndex = index,
                                      );
                                    },
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 150),
                                scale: isSelected ? 1.08 : 1.0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),

                                    /// 🔥 CHIP STYLE
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(
                                          0xFF1F5A43,
                                        ).withOpacity(0.25),
                                        const Color(
                                          0xFF0F2A20,
                                        ).withOpacity(0.45),
                                      ],
                                    ),

                                    border: Border.all(
                                      color: isSelected
                                          ? gift['color']
                                          : gift['color'].withOpacity(0.25),
                                      width: isSelected ? 2 : 1,
                                    ),

                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: gift['color'].withOpacity(
                                                0.6,
                                              ),
                                              blurRadius: 20,
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        gift['emoji'],
                                        style: TextStyle(
                                          fontSize: 26,
                                          shadows: isSelected
                                              ? [
                                                  Shadow(
                                                    color: gift['color'],
                                                    blurRadius: 12,
                                                  ),
                                                ]
                                              : [],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        gift['name'],
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 4),

                                      /// 💰 COST
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),

                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.amber.withOpacity(
                                                0.6,
                                              ),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                        child: Text(
                                          "${gift['cost']}",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 20),

                        /// 🔥 BUTTONS
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => Navigator.pop(context),

                                style: ButtonStyle(
                                  elevation: MaterialStateProperty.resolveWith((
                                    states,
                                  ) {
                                    if (states.contains(MaterialState.pressed))
                                      return 1;
                                    return 4;
                                  }),

                                  backgroundColor: MaterialStateProperty.all(
                                    Colors.transparent,
                                  ),

                                  shadowColor: MaterialStateProperty.all(
                                    Colors.black.withOpacity(0.6),
                                  ),

                                  shape: MaterialStateProperty.all(
                                    RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),

                                  padding: MaterialStateProperty.all(
                                    const EdgeInsets.symmetric(vertical: 14),
                                  ),

                                  overlayColor: MaterialStateProperty.all(
                                    Colors.white.withOpacity(0.05),
                                  ),
                                ),

                                child: Ink(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),

                                    /// 🔥 DOLU YÜZEY (AMA SAKİN)
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color.fromARGB(255, 92, 15, 2),
                                        Color.fromARGB(255, 68, 8, 1),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),

                                    /// 🔥 HAFİF BORDER
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.08),
                                      width: 1,
                                    ),
                                  ),

                                  child: Container(
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),

                                    child: const Text(
                                      'İptal',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 12),

                            Expanded(
                              child: ElevatedButton(
                                onPressed:
                                    (_selectedGiftIndex == -1 || _isLoading)
                                    ? null
                                    : () =>
                                          _sendGift(gifts[_selectedGiftIndex]),

                                style: ButtonStyle(
                                  elevation: MaterialStateProperty.resolveWith((
                                    states,
                                  ) {
                                    if (states.contains(MaterialState.pressed))
                                      return 1;
                                    return 6;
                                  }),

                                  backgroundColor: MaterialStateProperty.all(
                                    Colors.transparent,
                                  ),
                                  shadowColor: MaterialStateProperty.all(
                                    Colors.black.withOpacity(0.6),
                                  ),

                                  shape: MaterialStateProperty.all(
                                    RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),

                                  overlayColor: MaterialStateProperty.all(
                                    Colors.white.withOpacity(0.04),
                                  ),

                                  padding: MaterialStateProperty.all(
                                    const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),

                                child: Ink(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),

                                    /// 🔥 TEMİZ CAM YÜZEY
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF1A3F31),
                                        Color(0xFF0F2A20),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),

                                    /// 🔥 İNCE GOLD BORDER
                                    border: Border.all(
                                      color: const Color(
                                        0xFFE7C66A,
                                      ).withOpacity(0.8),
                                      width: 1,
                                    ),
                                  ),

                                  child: Container(
                                    alignment: Alignment.center,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),

                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Color(0xFFE7C66A),
                                            ),
                                          )
                                        : const Text(
                                            "Gönder",
                                            style: TextStyle(
                                              color: Color(0xFFE7C66A),
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
