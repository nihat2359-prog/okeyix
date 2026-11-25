import 'package:flutter/material.dart';
import 'package:okeyix/services/cross_promo_service.dart';
import 'cross_promo_scene.dart';

class CrossPromoDialog extends StatefulWidget {
  final List<CrossPromoGame> games;
  final Future<int> Function(CrossPromoGame) onDownload;
  final Future<bool> Function(CrossPromoGame) isClaimed;
  const CrossPromoDialog({
    super.key,
    required this.games,
    required this.onDownload,
    required this.isClaimed,
  });
  @override
  State<CrossPromoDialog> createState() => _CrossPromoDialogState();
}

class _CrossPromoDialogState extends State<CrossPromoDialog> {
  String? _busy;
  String? _message;
  final Set<String> _claimed = {};
  @override
  void initState() {
    super.initState();
    for (final game in widget.games) {
      widget.isClaimed(game).then((claimed) {
        if (claimed && mounted) setState(() => _claimed.add(game.id));
      });
    }
  }

  Future<void> _download(CrossPromoGame game) async {
    if (_busy != null) return;
    setState(() {
      _busy = game.id;
      _message = null;
    });
    try {
      final amount = await widget.onDownload(game);
      if (mounted) {
        setState(() {
          _claimed.add(game.id);
          _message = amount > 0
              ? '+5.000 çip hesabına eklendi!'
              : 'Bu oyunun ödülü daha önce alındı.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Ödül durumu doğrulanamadı. Tekrar deneyebilirsin.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => CrossPromoScene(
    games: widget.games,
    claimed: _claimed,
    busy: _busy,
    message: _message,
    onDownload: _download,
  );
}
