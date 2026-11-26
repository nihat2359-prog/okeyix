import 'package:flutter/material.dart';

class TableGiftArt extends StatelessWidget {
  const TableGiftArt({
    super.key,
    required this.giftId,
    this.width,
    this.height,
    this.animate = false,
  });
  final String giftId;
  final double? width, height;
  final bool animate;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/hediyeler/$giftId.png',
    width: width,
    height: height,
    fit: BoxFit.contain,
  );
}
