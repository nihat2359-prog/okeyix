import 'profile_action_scenes.dart';

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

class _GiftSelectorSheetState extends State<GiftSelectorSheet> {
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
      if (!mounted) return;

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
        if (!mounted) return;

        // ✅ başarı
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Hediye gönderildi 🎁")));
      } catch (e) {
        final msg = _parseGiftError(e);

        if (mounted) {
          setState(() {
            _errorMessage = msg;
            _isLoading = false;
          });
        }
        return;
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
            backgroundColor: const Color(0xFF232B34),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Hata: ${e.toString()}';
          _isLoading = false;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
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
  Widget build(BuildContext context) => ProfileGiftScene(
    recipient: widget.receiverName,
    gifts: gifts,
    selected: _selectedGiftIndex,
    sending: _isLoading,
    error: _errorMessage,
    onSelect: (index) => setState(() => _selectedGiftIndex = index),
    onClose: () => Navigator.of(context).pop(),
    onSend: () => _sendGift(gifts[_selectedGiftIndex]),
  );
}
