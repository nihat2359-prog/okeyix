import 'package:flutter/material.dart';

class GiftAnimation extends StatefulWidget {
  final String emoji;
  final VoidCallback onComplete;

  const GiftAnimation({
    super.key,
    required this.emoji,
    required this.onComplete,
  });

  @override
  State<GiftAnimation> createState() => _GiftAnimationState();
}

class _GiftAnimationState extends State<GiftAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _scale = Tween<double>(
      begin: 0,
      end: 1.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _position = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(0, -200),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: SlideTransition(
        position: _position,
        child: Text(widget.emoji, style: const TextStyle(fontSize: 60)),
      ),
    );
  }
}
