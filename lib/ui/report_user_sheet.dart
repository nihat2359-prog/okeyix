import 'profile_action_scenes.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportUserSheet extends StatefulWidget {
  final String reportedUserId;
  final String reportedUsername;

  const ReportUserSheet({
    super.key,
    required this.reportedUserId,
    required this.reportedUsername,
  });

  @override
  State<ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends State<ReportUserSheet> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProfileReportScene(
    username: widget.reportedUsername,
    controller: _controller,
    sending: _sending,
    onClose: () => Navigator.of(context).pop(),
    onSend: _sendReport,
  );
  Future<void> _sendReport() async {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      _toast("Lütfen açıklama yaz");
      return;
    }

    setState(() => _sending = true);

    try {
      await _sendReportToSystem(text);
      if (!mounted) return;
      _toast("Şikayetin alındı 🙏");
      Navigator.pop(context);
    } catch (e) {
      debugPrint("REPORT ERROR: $e");
      if (mounted) _toast("Hata: $e");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendReportToSystem(String message) async {
    final supabase = Supabase.instance.client;
    final uid = supabase.auth.currentUser!.id;

    await supabase.from('support_requests').insert({
      'user_id': uid,
      'category': 'sikayet',
      'message': message,
      'reported_user_id': widget.reportedUserId, // 🔥 YENİ
      'status': 'open',
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
