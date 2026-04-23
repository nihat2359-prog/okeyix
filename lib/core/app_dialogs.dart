import 'package:flutter/material.dart';
import 'package:okeyix/ui/report_user_sheet.dart';
import '../main.dart'; // navigatorKey burada olmalı

class AppDialogs {
  static void openReport({required String userId, required String username}) {
    final context = navigatorKey.currentContext!;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ReportUserSheet(reportedUserId: userId, reportedUsername: username),
    );
  }
}
