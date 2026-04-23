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
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F2F2A).withOpacity(0.90),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xEE13291F), Color(0xEE0C1712)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔥 drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 16),

              // 🔥 başlık + iptal
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Kullanıcıyı Bildir",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Text(
                "@${widget.reportedUsername} hakkında şikayetini yaz",
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),

              const SizedBox(height: 16),

              // 🔥 premium input
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: TextField(
                  controller: _controller,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Şikayetini yaz...",
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 🔥 butonlar
              Row(
                children: [
                  // iptal
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white24),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text("İptal"),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // gönder
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _sending ? null : _sendReport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _sending
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Gönder"),
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

  Future<void> _sendReport() async {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      _toast("Lütfen açıklama yaz");
      return;
    }

    setState(() => _sending = true);

    try {
      await _sendReportToSystem(text);

      Navigator.pop(context);
      _toast("Şikayetin alındı 🙏");
    } catch (e) {
      debugPrint("REPORT ERROR: $e");
      _toast("Hata: $e");
    } finally {
      setState(() => _sending = false);
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
