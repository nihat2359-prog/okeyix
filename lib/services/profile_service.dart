import 'dart:math';

import 'package:flutter/material.dart';
import 'package:okeyix/main.dart';
import 'package:okeyix/services/celebration_service.dart';
import 'package:okeyix/services/user_state.dart';
import 'package:okeyix/ui/avatar_preset.dart';
import 'package:okeyix/ui/gift_selector_sheet.dart';
import 'package:okeyix/ui/lobby/lobby_avatar.dart';
import 'package:okeyix/ui/profile_setup_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  static bool _friendRequestPromptOpen = false;
  static const String _freeRenameUsedPrefix = 'profile.free_rename_used.';
  static const String _ownedPremiumAvatarPrefix = 'profile.premium_avatars.';
  static const int _renameCoinCost = 1000;

  static Future<void> showUserCard(
    Map<String, dynamic> user, {
    Future<void> Function()? onRefresh,
  }) async {
    final otherId = user['id']?.toString() ?? user['user_id']?.toString();
    if (otherId == null) return;
    final context = navigatorKey.currentContext!;

    if (context == null) {
      print("❌ context yok");
      return;
    }
    final isSelf = otherId == UserState.userId;
    final isFriend = UserState.friendIds.contains(otherId);
    final isBlocked = UserState.blockedUserIds.contains(otherId);
    final incoming = UserState.incomingRequestIds.contains(otherId);
    final outgoing = UserState.outgoingRequestIds.contains(otherId);

    final profile = await supabase
        .from('profiles')
        .select('coins, rating')
        .eq('id', otherId)
        .single();

    final coins = profile['coins'] ?? 0;
    final rating = (profile['rating'] as int?) ?? 1200;

    final username = (user['username']?.toString().trim().isNotEmpty ?? false)
        ? user['username'].toString().trim()
        : 'Oyuncu';

    final statusText = isSelf
        ? 'Bu senin profilin'
        : isBlocked
        ? 'Bu kullanıcı engellendi'
        : isFriend
        ? 'Arkadaşın'
        : incoming
        ? 'Sana arkadaşlık isteği gönderdi'
        : outgoing
        ? 'Arkadaşlık isteği gönderildi'
        : 'Henüz arkadaş değilsiniz';

    final statusColor = isBlocked
        ? const Color(0xFFE57373)
        : (isFriend || isSelf)
        ? const Color(0xFF7ED9A5)
        : const Color(0xFFF2C14E);

    final Color _goldBorderColor = Color(0xCCB07A1A);
    final double _goldBorderWidth = 0.3;

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(.78),
      builder: (_) {
        final screenSize = MediaQuery.of(context).size;
        final isLandscape = screenSize.width > screenSize.height;

        // ✅ Yatay ekranda daha dar yap
        final maxWidth = isLandscape ? screenSize.width * 0.55 : 430.0;
        final maxHeight = isLandscape
            ? screenSize.height * 0.92
            : double.infinity;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 40 : 18,
            vertical: isLandscape ? 12 : 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF17382E), Color(0xFF0D221B)],
                  ),
                  border: Border.all(
                    color: _goldBorderColor,
                    width: _goldBorderWidth,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0xCC000000),
                      blurRadius: 34,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // BAŞLIK
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: const Color(0x2CECCB79),
                            border: Border.all(color: const Color(0x66E9C46A)),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Color(0xFFFFE0A8),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Oyuncu Profili',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0x221A2520),
                            border: Border.all(color: const Color(0x55FFFFFF)),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            padding: const EdgeInsets.all(6),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // AVATAR & İSİM
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFE9C46A),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE9C46A).withOpacity(.28),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: LobbyAvatar(
                            username: username,
                            avatarUrl: user['avatar_url'],
                            size: 46,
                            blocked: isBlocked,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(.18),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: statusColor.withOpacity(.55),
                                  ),
                                ),
                                child: Text(
                                  statusText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // RATING & COIN

                    // 🏆 İSTATİSTİKLER (KOMPAKT)
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF1a2f2a).withOpacity(0.6),
                            const Color(0xFF0d1f1a).withOpacity(0.8),
                          ],
                        ),
                        border: Border.all(
                          color: const Color(0xFFD4AF37).withOpacity(0.3),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFD4AF37),
                                      Color(0xFFA68B3A),
                                    ],
                                  ),
                                ),
                                child: const Icon(
                                  Icons.emoji_events_rounded,
                                  color: Colors.white,
                                  size: 11,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Oyun İstatistikleri',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              Expanded(
                                child: _statPanel(
                                  icon: Icons.star_rounded,
                                  value: rating,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _statPanel(
                                  icon: Icons.monetization_on_rounded,
                                  value: coins,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // İSTATİSTİK KARTLARI (3 KOLON)
                          Row(
                            children: [
                              // KAZANILAN
                              Expanded(
                                child: _statPanel(
                                  icon: Icons.emoji_events,
                                  value: (user['wins'] ?? 0),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // KAYBEDILEN
                              Expanded(
                                child: _statPanel(
                                  icon: Icons.trending_down,
                                  value: (user['losses'] ?? 0),
                                  color: StatPanelColor.red,
                                ),
                              ),

                              const SizedBox(width: 10),

                              // TOPLAM
                              Expanded(
                                child: _statPanel(
                                  icon: Icons.casino,
                                  value:
                                      ((user['wins'] ?? 0) +
                                      (user['losses'] ?? 0)),
                                  color: StatPanelColor.gold,
                                ),
                              ),

                              const SizedBox(width: 10),

                              // TOPLAM
                              Expanded(
                                child: _statPanel(
                                  icon: Icons.percent_rounded,
                                  value: _getWinRateValue(
                                    user['wins'] ?? 0,
                                    user['losses'] ?? 0,
                                  ),
                                  color: StatPanelColor.yellow,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),
                    // BUTONLAR
                    if (isSelf)
                      Row(
                        children: [
                          Expanded(
                            child: _modalActionButton(
                              label: '✎ Düzenle',
                              primary: true,
                              onPressed: () async {
                                final navigator = navigatorKey.currentState;
                                navigator?.pop();

                                await openProfileSetupDialog(
                                  forceComplete: false,
                                  onSuccess: onRefresh,
                                );
                              },
                            ),
                          ),

                          const SizedBox(width: 10),

                          Expanded(
                            child: _modalActionButton(
                              label: '🎁 Hediyelerim',
                              primary: false, // 🔥 secondary style olsun
                              onPressed: () {
                                final navigator = navigatorKey.currentState;
                                navigator?.pop();

                                // 👉 Gift history aç
                                Navigator.push(
                                  navigatorKey.currentContext!,
                                  MaterialPageRoute(
                                    builder: (_) => const GiftHistoryScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    if (!isSelf)
                      Column(
                        children: [
                          // SATIR 1: Arkadaş Ekle + Hediye Gönder
                          if (!isFriend && !incoming && !outgoing && !isBlocked)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _modalActionButton(
                                      label: '👥 Arkadaş Ekle',
                                      primary: true,
                                      onPressed: () async {
                                        final navigator =
                                            navigatorKey.currentState;
                                        navigator?.pop();
                                        await sendFriendRequest(otherId);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _modalActionButton(
                                      label: '🎁 Hediye Gönder',
                                      onPressed: () async {
                                        final navigator =
                                            navigatorKey.currentState;
                                        navigator?.pop();
                                        await showModalBottomSheet(
                                          context: context,
                                          backgroundColor: Colors.transparent,
                                          isScrollControlled: true,
                                          builder: (_) => GiftSelectorSheet(
                                            receiverId: otherId,
                                            receiverName: username,
                                            onGiftSent: () {
                                              debugPrint('Hediye gönderildi!');
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // SATIR 2: İstek Yanıtı (Kabul + Reddet)
                          if (incoming)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _modalActionButton(
                                      label: '✓ Kabul',
                                      primary: true,
                                      onPressed: () async {
                                        final navigator =
                                            navigatorKey.currentState;
                                        navigator?.pop();
                                        await acceptFriendRequest(otherId);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _modalActionButton(
                                      label: '✕ Reddet',
                                      danger: true,
                                      onPressed: () async {
                                        final navigator =
                                            navigatorKey.currentState;
                                        navigator?.pop();
                                        await rejectFriendRequest(otherId);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // SATIR 3: Arkadaş Ise (Hediye + Çıkar)
                          if (isFriend && !isBlocked)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _modalActionButton(
                                      label: '🎁 Hediye Gönder',
                                      primary: true,
                                      onPressed: () async {
                                        final navigator =
                                            navigatorKey.currentState;
                                        navigator?.pop();
                                        await showModalBottomSheet(
                                          context: context,
                                          backgroundColor: Colors.transparent,
                                          isScrollControlled: true,
                                          builder: (_) => GiftSelectorSheet(
                                            receiverId: otherId,
                                            receiverName: username,
                                            onGiftSent: () {
                                              debugPrint('Hediye gönderildi!');
                                            },
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _modalActionButton(
                                      label: '👋 Çıkar',
                                      onPressed: () async {
                                        final navigator =
                                            navigatorKey.currentState;
                                        navigator?.pop();
                                        await removeFriend(otherId);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // SATIR 4: İstek Gönderildiyse
                          if (outgoing && !isBlocked)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SizedBox(
                                width: double.infinity,
                                child: _modalActionButton(
                                  label: '⏳ İstek Gönderildi',
                                  onPressed: null,
                                ),
                              ),
                            ),

                          // SATIR 5: Engelle (Tek başına)
                          if (!isBlocked)
                            SizedBox(
                              width: double.infinity,
                              child: _modalActionButton(
                                label: '🚫 Engelle',
                                danger: true,
                                onPressed: () async {
                                  final navigator = navigatorKey.currentState;
                                  navigator?.pop();
                                  await blockUser(otherId);
                                },
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  static Widget _statPanel({
    required IconData icon,
    required int value,
    StatPanelColor color = StatPanelColor.gold,
  }) {
    final bgColors = _getStatPanelBgColors(color);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: bgColors,
        ),
        border: Border.all(color: const Color(0x55E9C46A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center, // ✅ EKLE
        children: [
          Icon(icon, size: 14, color: const Color(0xFFE9C46A)),
          const SizedBox(width: 6),
          Text(
            _formatNumber(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> rejectFriendRequest(
    String otherUserId, {
    Future<void> Function()? onSuccess,
  }) async {
    if (UserState.userId == null) return;
    try {
      await supabase
          .from('friends')
          .delete()
          .eq('user_id', otherUserId)
          .eq('friend_id', UserState.userId!);
      if (onSuccess != null) {
        await onSuccess();
      }
      msg('İstek reddedildi.');
    } catch (e) {
      msg('İstek reddedilemedi.');
      debugPrint('REJECT FRIEND ERROR: $e');
    }
  }

  static Future<void> removeFriend(
    String otherUserId, {
    Future<void> Function()? onSuccess,
  }) async {
    if (UserState.userId == null) return;
    try {
      await supabase
          .from('friends')
          .delete()
          .eq('user_id', UserState.userId!)
          .eq('friend_id', otherUserId);
      await supabase
          .from('friends')
          .delete()
          .eq('user_id', otherUserId)
          .eq('friend_id', UserState.userId!);
      if (onSuccess != null) {
        await onSuccess();
      }
      msg('Arkadaşlıktan çıkarıldı.');
    } catch (e) {
      msg('İşlem başarısız.');
      debugPrint('REMOVE FRIEND ERROR: $e');
    }
  }

  static Future<void> blockUser(
    String otherUserId, {
    Future<void> Function()? onSuccess,
  }) async {
    if (UserState.userId == null || otherUserId == UserState.userId) return;
    try {
      await supabase.from('friends').upsert({
        'user_id': UserState.userId,
        'friend_id': otherUserId,
        'status': 'blocked',
      }, onConflict: 'user_id,friend_id');
      if (onSuccess != null) {
        await onSuccess();
      }
      msg('Kullanıcı engellendi.');
    } catch (e) {
      msg('Kullanıcı engellenemedi.');
      debugPrint('BLOCK USER ERROR: $e');
    }
  }

  static Future<void> unblockUser(
    String otherUserId, {
    Future<void> Function()? onSuccess,
  }) async {
    if (UserState.userId == null) return;
    try {
      await supabase
          .from('friends')
          .delete()
          .eq('user_id', UserState.userId!)
          .eq('friend_id', otherUserId)
          .eq('status', 'blocked');
      if (onSuccess != null) {
        await onSuccess();
      }
      msg('Engel kaldırıldı.');
    } catch (e) {
      msg('Engel kaldırılamadı.');
      debugPrint('UNBLOCK ERROR: $e');
    }
  }

  static Future<void> sendFriendRequest(
    String otherUserId, {
    Future<void> Function()? onSuccess,
  }) async {
    if (UserState.userId == null || otherUserId == UserState.userId) return;
    if (UserState.blockedUserIds.contains(otherUserId)) {
      return msg('Engellediğin kullanıcıya istek gönderemezsin.');
    }
    try {
      await supabase.from('friends').upsert({
        'user_id': UserState.userId,
        'friend_id': otherUserId,
        'status': 'pending',
      }, onConflict: 'user_id,friend_id');
      if (onSuccess != null) {
        await onSuccess();
      }
      msg('Arkadaşlık isteği gönderildi.');
    } catch (e) {
      debugPrint('FRIEND REQUEST ERROR: $e');
      msg('İstek gönderilemedi.');
    }
  }

  static Future<void> acceptFriendRequest(
    String otherUserId, {
    Future<void> Function()? onSuccess,
  }) async {
    if (UserState.userId == null) return;
    try {
      await supabase
          .from('friends')
          .update({'status': 'accepted'})
          .eq('user_id', otherUserId)
          .eq('friend_id', UserState.userId!);

      if (onSuccess != null) {
        await onSuccess();
      }
      //await _loadSocialData();
      msg('Arkadaşlık isteği kabul edildi.');
    } catch (e) {
      msg('İstek kabul edilemedi.');
      debugPrint('ACCEPT FRIEND ERROR: $e');
    }
  }

  static Widget _modalActionButton({
    required String label,
    required VoidCallback? onPressed,
    bool danger = false,
    bool primary = false,
  }) {
    final bgColor = danger
        ? const Color(0xFF7F2A2A)
        : primary
        ? const Color(0xFF2B7B55)
        : const Color(0x55314036);

    final borderColor = danger
        ? const Color(0xFFAA4A4A)
        : primary
        ? Color(0xFF8F6215)
        : const Color(0x886A4E2B);

    final shadowColor = danger
        ? Colors.red.withOpacity(0.3)
        : primary
        ? const Color(0xFF2B7B55).withOpacity(0.4)
        : Colors.transparent;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: onPressed != null
            ? [BoxShadow(color: shadowColor, blurRadius: 10, spreadRadius: 1)]
            : [],
      ),
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: onPressed != null
              ? bgColor
              : bgColor.withOpacity(0.5),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor, width: 1.6),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  static Future<void> showIncomingFriendRequestDialog(
    BuildContext context,
    String otherUserId,
    Map<String, dynamic>? user, {
    Future<void> Function()? onRefresh,
  }) async {
    if (_friendRequestPromptOpen) return;
    _friendRequestPromptOpen = true;

    final username = ((user?['username'] as String?) ?? '').trim().isEmpty
        ? 'Oyuncu'
        : user!['username'].toString();
    final avatarUrl = user?['avatar_url']?.toString();

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF13231C),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Color(0xCCB07A1A), width: 0.3),
        ),
        title: const Text(
          'Yeni arkadaşlık isteği',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Row(
          children: [
            LobbyAvatar(username: username, avatarUrl: avatarUrl, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$username sana arkadaşlık isteği gönderdi.',
                style: const TextStyle(color: Color(0xFFD5E9DF)),
              ),
            ),
          ],
        ),
        actions: [
          _modalActionButton(
            label: 'Reddet',
            danger: true,
            onPressed: () async {
              final navigator = navigatorKey.currentState;
              navigator?.pop();
              await rejectFriendRequest(otherUserId, onSuccess: onRefresh);
            },
          ),
          _modalActionButton(
            label: 'Engelle',
            danger: true,
            onPressed: () async {
              final navigator = navigatorKey.currentState;
              navigator?.pop();
              await blockUser(otherUserId, onSuccess: onRefresh);
            },
          ),
          _modalActionButton(
            label: 'Kabul Et',
            primary: true,
            onPressed: () async {
              final navigator = navigatorKey.currentState;
              navigator?.pop();
              await acceptFriendRequest(otherUserId, onSuccess: onRefresh);
            },
          ),
        ],
      ),
    );

    // if (mounted) {
    //   _friendRequestPromptOpen = false;
    // }
  }

  static int _getWinRateValue(int wins, int losses) {
    int total = wins + losses;
    if (total == 0) return 0;

    return ((wins / total) * 100).round();
  }

  static void msg(String text) {
    final context = navigatorKey.currentContext!;

    if (context == null) {
      print("❌ context yok");
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  static Future<void> openProfileSetupDialog({
    required bool forceComplete,
    Future<void> Function()? onSuccess,
  }) async {
    final context = navigatorKey.currentContext!;

    if (context == null) {
      print("❌ context yok");
      return;
    }
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await ensureUserRow();

    var initialUsername = UserState.userName == 'Oyuncu'
        ? ''
        : UserState.userName;
    var initialAvatar = UserState.userAvatarUrl;

    try {
      final row = await findUserRow(user, columns: 'id,username,avatar_url');
      if (row != null) {
        initialUsername = ((row['username'] as String?) ?? '').trim();
        initialAvatar = (row['avatar_url'] as String?)?.trim();
        UserState.userRowId = row['id']?.toString();
      }
    } catch (_) {}

    final freeRenameUsed = await isFreeRenameUsed(user.id);
    final ownedPremiumAvatars = await _getOwnedPremiumAvatars(user.id);

    final result = await showDialog<ProfileSetupResult>(
      context: context,
      barrierDismissible: !forceComplete,
      builder: (_) => ProfileSetupDialog(
        forceComplete: forceComplete,
        initialUsername: initialUsername,
        initialAvatarRef: initialAvatar,
        currentUserId: user.id,
        currentCoins: UserState.userCoin,
        renameCoinCost: _renameCoinCost,
        freeRenameUsed: freeRenameUsed,
        ownedPremiumAvatarRefs: ownedPremiumAvatars,
      ),
    );

    if (result == null) return;

    try {
      final payload = {
        'username': result.username,
        'avatar_url': normalizeAvatarForStorage(result.avatarRef),
      };
      final payloadprofiles = {'username': result.username};
      final targetId = UserState.userRowId ?? user.id;
      final updated = await supabase
          .from('users')
          .update(payload)
          .eq('id', targetId)
          .select('id')
          .limit(1);

      await supabase
          .from('profiles')
          .update(payloadprofiles)
          .eq('id', targetId)
          .select('id')
          .limit(1);

      if ((updated as List).isEmpty) {
        final email = user.email?.trim();
        if (email != null && email.isNotEmpty) {
          final updatedByEmail = await supabase
              .from('users')
              .update(payload)
              .eq('email', email)
              .select('id')
              .limit(1);
          if ((updatedByEmail as List).isNotEmpty) {
            UserState.userRowId = updatedByEmail.first['id']?.toString();
          } else {
            await supabase.from('users').insert({
              'id': user.id,
              'email': user.email,
              ...payload,
            });
            UserState.userRowId = user.id;
          }
        }
      } else {
        UserState.userRowId = updated.first['id']?.toString();
      }

      if (result.renameCoinSpent > 0) {
        await spendProfileCoins(
          userId: user.id,
          amount: result.renameCoinSpent,
          reason: 'profile_name_change',
          note: 'profile_name_change_coin_spend',
        );
      }
      if (result.avatarCoinSpent > 0) {
        final unlockedAvatarRef = result.unlockedAvatarRef;
        await spendProfileCoins(
          userId: user.id,
          amount: result.avatarCoinSpent,
          reason: 'avatar_purchase',
          note: unlockedAvatarRef == null
              ? 'profile_avatar_purchase'
              : 'profile_avatar_purchase:$unlockedAvatarRef',
        );
      }
      if (result.consumeFreeRename) {
        await setFreeRenameUsed(user.id);
      }
      if (result.newUnlockedPremiumAvatarRefs.isNotEmpty) {
        final merged = {
          ...ownedPremiumAvatars,
          ...result.newUnlockedPremiumAvatarRefs,
        };
        await _setOwnedPremiumAvatars(user.id, merged);
      }

      if (onSuccess != null) {
        await onSuccess();
      }

      if (result.spentCoins > 0) {
        msg('Profil guncellendi. ${result.spentCoins} coin harcandi.');
      } else {
        msg('Profil guncellendi.');
      }
      return;
    } catch (e) {
      if (e is PostgrestException && e.code == '23505') {
        msg('Bu kullanıcı adı zaten kullanımda.');
      } else {
        msg('Profil guncellenemedi.');
      }
      return;
    }
  }

  static Future<bool> isFreeRenameUsed(String userId) async {
    try {
      final rows = await supabase
          .from('wallet_transactions')
          .select('id')
          .eq('user_id', userId)
          .eq('reason', 'profile_name_change')
          .limit(1);
      if ((rows as List).isNotEmpty) {
        return true;
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_freeRenameUsedPrefix$userId') ?? false;
  }

  static Future<void> setFreeRenameUsed(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_freeRenameUsedPrefix$userId', true);
  }

  static Future<Set<String>> _getOwnedPremiumAvatars(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('$_ownedPremiumAvatarPrefix$userId');
    final owned = stored == null ? <String>{} : stored.toSet();
    try {
      final purchaseRows = await supabase
          .from('wallet_transactions')
          .select('reason,note')
          .eq('user_id', userId)
          .eq('reason', 'avatar_purchase');
      for (final row in (purchaseRows as List)) {
        final note = row['note']?.toString() ?? '';
        if (note.startsWith('profile_avatar_purchase:')) {
          final ref = note.split(':').last.trim();
          if (ref.isNotEmpty) owned.add(ref);
        }
      }
    } catch (_) {}
    return owned;
  }

  static Future<void> _setOwnedPremiumAvatars(
    String userId,
    Set<String> owned,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      '$_ownedPremiumAvatarPrefix$userId',
      owned.toList()..sort(),
    );
  }

  static Future<void> ensureUserRow() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final existing = await findUserRow(
        user,
        columns: 'id,email,username,avatar_url',
      );
      if (existing != null) return;
      await supabase.from('users').insert({'id': user.id, 'email': user.email});
    } catch (e) {
      debugPrint('ENSURE USER ROW ERROR: $e');
    }
  }

  static Future<Map<String, dynamic>?> findUserRow(
    User user, {
    required String columns,
  }) async {
    final byId = await supabase
        .from('users')
        .select(columns)
        .eq('id', user.id)
        .limit(1);
    if ((byId as List).isNotEmpty) {
      return Map<String, dynamic>.from(byId.first);
    }

    final email = user.email?.trim();
    if (email == null || email.isEmpty) return null;

    final byEmail = await supabase
        .from('users')
        .select(columns)
        .eq('email', email)
        .limit(1);
    if ((byEmail as List).isNotEmpty) {
      return Map<String, dynamic>.from(byEmail.first);
    }
    return null;
  }

  static Future<void> spendProfileCoins({
    required String userId,
    required int amount,
    required String reason,
    required String note,
  }) async {
    if (amount <= 0) return;
    final profileRows = await supabase
        .from('profiles')
        .select('coins')
        .eq('id', userId)
        .limit(1);
    final currentCoins = (profileRows as List).isNotEmpty
        ? (profileRows.first['coins'] as int?) ?? UserState.userCoin
        : UserState.userCoin;
    if (currentCoins < amount) {
      throw Exception('Insufficient profile balance');
    }
    final nextCoins = max(0, currentCoins - amount);

    await supabase.from('wallet_transactions').insert({
      'user_id': userId,
      'amount': -amount,
      'reason': reason,
      'type': 'debit',
      'store': 'system',
      'note': note,
    });

    if ((profileRows).isNotEmpty) {
      await supabase
          .from('profiles')
          .update({'coins': nextCoins})
          .eq('id', userId);
    }
  }
}

enum StatPanelColor { gold, red, yellow }

List<Color> _getStatPanelBgColors(StatPanelColor color) {
  switch (color) {
    case StatPanelColor.gold:
      return [const Color(0x2CF6E7C1), const Color(0x15F6E7C1)];
    case StatPanelColor.red:
      return [const Color(0x2CE87B7B), const Color(0x15E87B7B)];
    case StatPanelColor.yellow:
      return [const Color(0x2CD4AF37), const Color(0x15D4AF37)];
  }
}

class GiftHistoryScreen extends StatefulWidget {
  const GiftHistoryScreen({super.key});

  @override
  State<GiftHistoryScreen> createState() => _GiftHistoryScreenState();
}

class _GiftHistoryScreenState extends State<GiftHistoryScreen> {
  final List<dynamic> _gifts = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 0;
  final int _limit = 20;

  @override
  void initState() {
    super.initState();
    _loadGifts();
  }

  Future<void> _loadGifts({bool loadMore = false}) async {
    if (loadMore) {
      _loadingMore = true;
    } else {
      _loading = true;
    }
    setState(() {});

    final res = await supabase
        .from('gifts')
        .select('*, profiles:sender_id(username)')
        .eq('receiver_id', UserState.userId!)
        .order('created_at', ascending: false)
        .range(_page * _limit, (_page + 1) * _limit - 1);

    if (loadMore) {
      _gifts.addAll(res);
      _loadingMore = false;
    } else {
      _gifts.clear();
      _gifts.addAll(res);
      _loading = false;
    }

    setState(() {});
  }

  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // 🔥 KRİTİK
      appBar: AppBar(
        title: const Text("🎁 Hediyelerim"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),

      body: Stack(
        children: [
          // 🔥 TÜM EKRAN ARKA PLAN (AppBar dahil)
          Positioned.fill(
            child: Image.asset(
              "assets/images/lobby/lobby.png",
              fit: BoxFit.cover,
            ),
          ),

          // 🔥 OVERLAY
          Positioned.fill(
            child: Container(color: Colors.black.withOpacity(0.35)),
          ),

          // 🔥 CONTENT (AppBar altından başlat)
          Padding(
            padding: EdgeInsets.only(
              top: kToolbarHeight + MediaQuery.of(context).padding.top,
            ),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : NotificationListener<ScrollNotification>(
                    onNotification: (scroll) {
                      if (scroll.metrics.pixels >
                              scroll.metrics.maxScrollExtent - 200 &&
                          !_loadingMore) {
                        _page++;
                        _loadGifts(loadMore: true);
                      }
                      return false;
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.only(top: 10, bottom: 20),
                      itemCount: _gifts.length + (_loadingMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i >= _gifts.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final g = _gifts[i];
                        final username =
                            g['profiles']?['username'] ?? "Bilinmeyen";

                        final reward = (g['coin_cost'] ~/ 2);

                        return _giftCard(
                          username: username,
                          giftType: g['gift_type'],
                          reward: reward,
                          createdAt: g['created_at'],
                          senderId: g['sender_id'],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _giftCard({
    required String username,
    required String giftType,
    required int reward,
    required String createdAt,
    required String senderId,
  }) {
    final emoji = _giftEmoji(giftType);

    return GestureDetector(
      onTap: () {
        ProfileService.showUserCard({"id": senderId, "username": username});
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF173A2C).withOpacity(0.18), // 🔥 arttırıldı
              const Color(0xFF0A1511).withOpacity(0.22),
            ],
          ),
          border: Border.all(color: Colors.amber.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: const Color.fromARGB(255, 13, 43, 22).withOpacity(0.1),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          children: [
            // 🎁 ICON
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFFFD700)],
                ),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 22)),
              ),
            ),

            const SizedBox(width: 12),

            // TEXT
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    giftType,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),

            // 💰 REWARD
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "+$reward",
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(createdAt),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _giftEmoji(String type) {
    switch (type) {
      case "fire":
        return "🔥";
      case "heart":
        return "❤️";
      case "diamond":
        return "💎";
      default:
        return "🎁";
    }
  }

  String _formatDate(String date) {
    return date.substring(0, 16);
  }
}
