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
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),

                  // 🔥 CAM EFEKTİ (gradient)
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.12), // üst daha şeffaf
                      Colors.black.withOpacity(0.25), // alt daha koyu
                    ],
                  ),

                  border: Border(
                    top: BorderSide(
                      color: const Color(0xFFD4AF37).withOpacity(0.25),
                      width: 1.5,
                    ),
                  ),

                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 30,
                      offset: const Offset(0, -10),
                    ),
                  ],
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
                        // 🔹 HANDLE
                        Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white30,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 🔥 HEADER
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
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
                                    color: Colors.amber.withOpacity(0.4),
                                    blurRadius: 10,
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
                                  const Text(
                                    'Hediye Gönder',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    widget.receiverName,
                                    style: const TextStyle(
                                      color: Color(0xFFD4AF37),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ❗ ERROR
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

                        // 🎁 GRID (KÜÇÜLTÜLDÜ)
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 6, // 🔥 en önemli
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.9, // 🔥 dikey kart küçültme
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
                                scale: isSelected ? 1.06 : 1.0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: Colors.white.withOpacity(0.04),
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
                                                0.4,
                                              ),
                                              blurRadius: 16,
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
                                          fontSize: 22,
                                          shadows: isSelected
                                              ? [
                                                  Shadow(
                                                    color: gift['color'],
                                                    blurRadius: 10,
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

                                      // 💰 COST
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFD4AF37),
                                              Color(0xFFFFD700),
                                            ],
                                          ),
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

                        const SizedBox(height: 18),

                        // 🔥 BUTTONS
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: _isLoading
                                    ? null
                                    : () => Navigator.pop(context),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  backgroundColor: Colors.white10,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  'İptal',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(width: 10),

                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFD4AF37),
                                      Color(0xFFFFD700),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.amber.withOpacity(0.5),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed:
                                      _selectedGiftIndex == -1 || _isLoading
                                      ? null
                                      : () => _sendGift(
                                          gifts[_selectedGiftIndex],
                                        ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text(
                                          'Gönder',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
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
