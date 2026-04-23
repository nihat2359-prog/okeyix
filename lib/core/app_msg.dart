import 'package:flutter/material.dart';
import '../main.dart'; // navigatorKey buradaysa

class AppMsg {
  static void show(String text) {
    final context = navigatorKey.currentContext;

    if (context == null) return;

    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
