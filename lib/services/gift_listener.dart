import 'package:okeyix/services/celebration_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../overlay/gift_overlay.dart';

final supabase = Supabase.instance.client;

// Tek sefer başlatma kontrolü
RealtimeChannel? _channel;

void listenIncomingGifts(String myUserId) {
  // tekrar tekrar açılmasını engelle
  if (_channel != null) {
    return;
  }

  _channel = supabase.channel('gifts-$myUserId');

  _channel!
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'gifts',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'receiver_id',
          value: myUserId,
        ),
        callback: (payload) async {
          final data = payload.newRecord;

          final senderId = data['sender_id'];
          final giftType = data['gift_type'];

          // 👤 gönderen adı
          String senderName = "Bir oyuncu";

          try {
            final res = await supabase
                .from('profiles')
                .select('username')
                .eq('id', senderId)
                .maybeSingle();

            if (res != null && res['username'] != null) {
              senderName = res['username'];
            }
          } catch (e) {
            print("⚠️ username alınamadı: $e");
          }

          // 🎁 gift info
          String emoji = "🎁";
          String giftName = "Hediye";

          try {
            final giftRes = await supabase
                .from('gift_types')
                .select('emoji, name')
                .eq('type', giftType)
                .maybeSingle();

            await supabase
                .from('gifts')
                .update({
                  'seen': true,
                  'seen_at': DateTime.now().toIso8601String(),
                })
                .eq('id', data['id']);

            if (giftRes != null) {
              emoji = giftRes['emoji'] ?? emoji;
              giftName = giftRes['name'] ?? giftName;
            }
          } catch (e) {
            print("⚠️ gift info alınamadı: $e");
          }

          CelebrationService.showConfetti();
          // 💥 overlay tetikle
          GiftOverlay.show(
            senderName: senderName,
            emoji: emoji,
            giftName: giftName,
            senderId: senderId,
          );
        },
      )
      .subscribe((status, error) {
        print("📡 GIFT CHANNEL STATUS: $status");

        if (error != null) {
          print("❌ GIFT CHANNEL ERROR: $error");
        }
      });
}
