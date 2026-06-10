import 'dart:math';

import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/main.dart';
import 'package:okeyix/services/user_state.dart';
import 'package:okeyix/ui/avatar_preset.dart';
import 'package:okeyix/ui/avatar_selection_screen.dart';
import 'package:okeyix/ui/gift_selector_sheet.dart';
import 'package:okeyix/ui/lobby/lobby_avatar.dart';
import 'package:okeyix/ui/profile_setup_dialog.dart';
import 'package:okeyix/ui/report_user_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  static final Random _profileRandom = Random();
  static bool _friendRequestPromptOpen = false;
  static const String _freeRenameUsedPrefix = 'profile.free_rename_used.';
  static const String _ownedPremiumAvatarPrefix = 'profile.premium_avatars.';
  static const int _renameCoinCost = 1000;

  static Future<void> showUserCard(
    Map<String, dynamic> userinfo, {
    Future<void> Function()? onRefresh,
  }) async {
    final otherId =
        userinfo['id']?.toString() ?? userinfo['user_id']?.toString();

    if (otherId == null) return;
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final userId = otherId ?? '';
    if (userId.isEmpty) return;

    final isSelf = userId == UserState.userId;
    final isFriend = UserState.friendIds?.contains(userId) ?? false;
    final isBlocked = UserState.blockedUserIds?.contains(userId) ?? false;
    final incoming = UserState.incomingRequestIds?.contains(userId) ?? false;
    final outgoing = UserState.outgoingRequestIds?.contains(userId) ?? false;

    int coins = (userinfo['coins'] as num?)?.toInt() ?? 0;
    int rating = (userinfo['rating'] as num?)?.toInt() ?? 1200;
    String username = (userinfo['username'] as String?) ?? "Oyuncu";
    int wins = (userinfo['wins'] as num?)?.toInt() ?? 0;
    int losses = (userinfo['losses'] as num?)?.toInt() ?? 0;
    String? avatarUrl = userinfo['avatar_url'] as String?;

    final profileFuture = supabase
        .from('profiles')
        .select('coins, rating, username')
        .eq('id', userId)
        .maybeSingle();

    final userFuture = supabase
        .from('users')
        .select('username, wins, losses, avatar_url')
        .eq('id', userId)
        .maybeSingle();

    try {
      final results = await Future.wait<dynamic>([
        profileFuture.catchError((_) => null),
        userFuture.catchError((_) => null),
      ]).timeout(const Duration(milliseconds: 900), onTimeout: () => [null, null]);

      final profileData = results[0] as Map<String, dynamic>?;
      final userData = results[1] as Map<String, dynamic>?;

      if (profileData != null) {
        coins = (profileData['coins'] as int?) ?? coins;
        rating = (profileData['rating'] as int?) ?? rating;
        username = (profileData['username'] as String?) ?? username;
      }
      if (userData != null) {
        username = (userData['username'] as String?) ?? username;
        wins = (userData['wins'] as int?) ?? wins;
        losses = (userData['losses'] as int?) ?? losses;
        avatarUrl = userData['avatar_url'] as String? ?? avatarUrl;
      }
    } catch (_) {
      // Some environments have incompatible id types between users/profiles.
      // Keep showing profile card with available fallback data.
    }

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
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF151B22).withOpacity(0.90),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xD7D0A14A),
                    width: 0.5,
                  ),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xEE222831), Color(0xEE131820)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // BAŞLIK
                    

                    // AVATAR & İSİM
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE9C46A).withOpacity(.28),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: LobbyAvatar(
                            username: username,
                            avatarUrl: avatarUrl,
                            size: 46,
                            blocked: isBlocked,
                            enablePreview: true,
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
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0x1A1A2520),
                            border: Border.all(color: const Color(0x44FFFFFF)),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            padding: const EdgeInsets.all(4),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white60,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // RATING & COIN
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF2A313C).withOpacity(0.10),
                            const Color(0xFF161B24).withOpacity(0.10),
                          ],
                        ),
                        border: Border.all(
                          color: const Color(0xFFD4AF37).withOpacity(0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          /// 🔥 SOL PANEL (COIN + RATING)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _infoTileWithProgress(
                                ratingValue: rating,
                              ),
                              const SizedBox(height: 8),
                              _infoTileLarge(
                                icon: Icons.monetization_on_rounded,
                                coinValue: coins,
                              ),
                            ],
                          ),

                          const SizedBox(width: 8),

                          /// 🔥 SAĞ PANEL (DİKEY BARLAR)
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _statBarVertical(
                                  label: "Win",
                                  value: wins,
                                  total: wins + losses,
                                  color: Colors.green,
                                ),
                                _statBarVertical(
                                  label: "Lose",
                                  value: losses,
                                  total: wins + losses,
                                  color: Colors.red,
                                ),
                                _statBarVertical(
                                  label: "Total",
                                  value: wins + losses,
                                  total: wins + losses,
                                  color: const Color(0xFFD4AF37),
                                ),
                                _statBarVertical(
                                  label: "%",
                                  value: _getWinRateValue(wins, losses),
                                  total: 100,
                                  color: const Color(0xFFE9C46A),
                                  isPercent: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 5),
                    // BUTONLAR
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // 👤 KENDİ PROFİLİ
                        if (isSelf) ...[
                          _iconBtn(
                            Icons.edit,
                            label: 'Düzenle',
                            onPressed: () async {
                              navigatorKey.currentState?.pop();
                              await openProfileSetupDialog(
                                forceComplete: false,
                                onSuccess: onRefresh,
                              );
                            },
                          ),

                          _iconBtn(
                            Icons.card_giftcard,
                            label: 'Geçmiş',
                            onPressed: () {
                              navigatorKey.currentState?.pop();
                              Navigator.push(
                                navigatorKey.currentContext!,
                                MaterialPageRoute(
                                  builder: (_) => const GiftHistoryScreen(),
                                ),
                              );
                            },
                          ),
                        ],

                        // 👥 BAŞKA KULLANICI
                        if (!isSelf) ...[
                          // Arkadaş değil
                          if (!isFriend &&
                              !incoming &&
                              !outgoing &&
                              !isBlocked) ...[
                            _iconBtn(
                              Icons.person_add,
                              label: 'Ekle',
                              onPressed: () async {
                                navigatorKey.currentState?.pop();
                                await sendFriendRequest(otherId);
                              },
                            ),

                            _iconBtn(
                              Icons.card_giftcard,
                              label: 'Hediye',
                              onPressed: () async {
                                navigatorKey.currentState?.pop();
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
                          ],

                          // Gelen istek
                          if (incoming) ...[
                            _iconBtn(
                              Icons.check,
                              label: 'Kabul',
                              onPressed: () async {
                                navigatorKey.currentState?.pop();
                                await acceptFriendRequest(otherId);
                              },
                            ),

                            _iconBtn(
                              Icons.close,
                              label: 'Reddet',
                              color: Colors.red,
                              onPressed: () async {
                                navigatorKey.currentState?.pop();
                                await rejectFriendRequest(otherId);
                              },
                            ),
                          ],

                          // Arkadaş ise
                          if (isFriend && !isBlocked) ...[
                            _iconBtn(
                              Icons.card_giftcard,
                              label: 'Hediye',
                              onPressed: () async {
                                navigatorKey.currentState?.pop();
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

                            _iconBtn(
                              Icons.person_remove,
                              label: 'Çıkar',
                              onPressed: () async {
                                navigatorKey.currentState?.pop();
                                await removeFriend(otherId);
                              },
                            ),
                          ],

                          // Gönderilmiş istek
                          if (outgoing && !isBlocked) ...[
                            _iconBtn(
                              Icons.hourglass_top,
                              label: 'Bekliyor',
                              onPressed: null,
                            ),
                          ],

                          // Engelle
                          if (!isBlocked) ...[
                            _iconBtn(
                              Icons.block,
                              label: 'Engelle',
                              color: Colors.red,
                              onPressed: () async {
                                navigatorKey.currentState?.pop();
                                await blockUser(otherId);
                              },
                            ),
                          ],
                          if (!isSelf) ...[
                            _iconBtn(
                              Icons.flag,
                              label: 'Şikayet',
                              color: Colors.orange,
                              onPressed: () {
                                navigatorKey.currentState
                                    ?.pop(); // profil modalı kapat
                                _openReportSheet(context, otherId, username);
                              },
                            ),
                          ],
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 18,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SelectableText.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'ID: ',
                                  style: TextStyle(
                                    color: Color(0x66FFFFFF),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    height: 1.1,
                                  ),
                                ),
                                TextSpan(
                                  text: userId,
                                  style: const TextStyle(
                                    color: Color(0x99FFFFFF),
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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

  static Widget _infoTile({required IconData icon, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.black.withOpacity(0.4),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Color(0xFFD4A24C)),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              fontFamily: "Orbitron",
              color: Color(0xFFF2C14E),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _statBarVertical({
    required String label,
    required int value,
    required int total,
    required Color color,
    bool isPercent = false,
  }) {
    final safeTotal = total == 0 ? 1 : total;
    final percent = isPercent
        ? value / 100
        : value.toDouble() / safeTotal.toDouble();

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        /// 🔥 BAR
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: percent.clamp(0, 1)),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, val, _) {
            return Container(
              width: 31,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6), // 🔥 radius düşürdük
                color: Colors.black.withOpacity(0.15), // 🔥 daha derin track
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  /// 🔥 DOLAN KISIM
                  FractionallySizedBox(
                    heightFactor: val,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            color.withOpacity(0.9),
                            color.withOpacity(0.6),
                          ],
                        ),

                        /// 🔥 glow
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.35),
                            blurRadius: 10,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                    ),
                  ),

                  /// 🔥 ÜST HIGHLIGHT (çok premium fark yaratır)
                  if (val > 0)
                    Positioned(
                      top: 0,
                      child: Container(
                        width: 16,
                        height: 5,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withOpacity(0.25),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),

                  /// 🔥 ORTADA VALUE
                  Positioned(
                    bottom: 3,
                    child: Text(
                      isPercent ? "${value.toInt()}%" : value.toString(),
                      style: const TextStyle(
                        fontFamily: "Orbitron",
                        fontSize: 8.8,
                        color: Color(0xFF142018),
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            color: Color(0x55FFFFFF),
                            blurRadius: 2,
                            offset: Offset(0, 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 4),

        /// LABEL
        Text(
          label,
          style: TextStyle(
            fontSize: 8.8,
            color: Colors.white.withOpacity(0.6),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  static void _openReportSheet(
    BuildContext context,
    String userId,
    String username,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ReportUserSheet(reportedUserId: userId, reportedUsername: username),
    );
  }

  static Widget _iconBtn(
    IconData icon, {
    required String label,
    VoidCallback? onPressed,
    Color? color,
  }) {
    final enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 66,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(enabled ? 0.05 : 0.03),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled ? (color ?? Colors.white) : Colors.white38,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: enabled ? Colors.white70 : Colors.white38,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
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
      final u1 = UserState.userId;
      final u2 = otherUserId;

      if (u1 == null || u2 == null) return;

      final existing = await supabase
          .from('friends')
          .select('id')
          .or(
            'and(user_id.eq.$u1,friend_id.eq.$u2),and(user_id.eq.$u2,friend_id.eq.$u1)',
          )
          .maybeSingle();

      if (existing == null) {
        await supabase.from('friends').insert({
          'user_id': u1,
          'friend_id': u2,
          'status': 'pending',
        });

        msg('Arkadaşlık isteği gönderildi.');
      }
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
        backgroundColor: const Color(0xCC121826),
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
                style: const TextStyle(color: Color(0xFFE6EDF7)),
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
    final context = navigatorKey.currentContext;

    if (context == null) {
      print("❌ context yok");
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    // 🔥 önce eski snack'leri temizle
    messenger.clearSnackBars();

    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating, // 🔥 daha güzel görünür
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  static Future<void> openProfileSetupDialog({
    required bool forceComplete,
    Future<void> Function()? onSuccess,
  }) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
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

    ProfileSetupResult? result;
    if (forceComplete) {
      final selectedAvatar = await Navigator.of(
        context,
        rootNavigator: true,
      ).push<String>(
        MaterialPageRoute(
          builder: (_) => AvatarSelectionScreen(
            ownedPremiumAvatarRefs: {...ownedPremiumAvatars},
            userCoins: 0,
            showPremium: false,
            title: 'Avatarını Seç, Oyuna Başla',
            canClose: false,
          ),
          fullscreenDialog: true,
        ),
      );
      if (selectedAvatar == null || selectedAvatar.trim().isEmpty) return;
      final autoUsername = await _generateAutoUsernameByAvatar(selectedAvatar);
      result = ProfileSetupResult(
        username: autoUsername,
        avatarRef: selectedAvatar,
        renameCoinSpent: 0,
        avatarCoinSpent: 0,
        consumeFreeRename: false,
        newUnlockedPremiumAvatarRefs: const <String>{},
      );
    } else {
      final setupWidget = ProfileSetupDialog(
        forceComplete: false,
        asPage: false,
        initialUsername: initialUsername,
        initialAvatarRef: initialAvatar,
        currentUserId: user.id,
        currentCoins: UserState.userCoin,
        renameCoinCost: _renameCoinCost,
        freeRenameUsed: freeRenameUsed,
        ownedPremiumAvatarRefs: ownedPremiumAvatars,
      );
      result = await showDialog<ProfileSetupResult>(
        context: context,
        barrierDismissible: true,
        builder: (_) => setupWidget,
      );
    }
    if (result == null) return;

    try {
      final payload = {'username': result.username};

      if (isCustomAvatar(result.avatarRef)) {
        payload['avatar_pending_url'] = normalizeAvatarForStorage(
          result.avatarRef,
        );
        payload['avatar_status'] = 'pending';
        payload['avatar_updated_at'] = DateTime.now().toIso8601String();
      } else {
        payload['avatar_url'] = normalizeAvatarForStorage(result.avatarRef);
      }

      final targetId = UserState.userId ?? user.id;
      final payloadprofiles = {
        'id': targetId,
        'username': result.username,
      };
      final updated = await supabase
          .from('users')
          .update(payload)
          .eq('id', targetId)
          .select('id')
          .limit(1);

      await supabase.from('profiles').upsert(payloadprofiles, onConflict: 'id');

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

      String message;

      final isCustom = isCustomAvatar(result.avatarRef);

      if (isCustom) {
        if (result.spentCoins > 0) {
          message =
              'Profil güncellendi. ${result.spentCoins} coin harcandı.\n⏳ Fotoğrafınız inceleniyor, onaylandıktan sonra diğer oyuncular görebilecek.';
        } else {
          message =
              'Profil güncellendi.\n⏳ Fotoğrafınız inceleniyor, onaylandıktan sonra diğer oyuncular görebilecek.';
          _checkAvatarApprovedLater();
        }
      } else {
        if (result.spentCoins > 0) {
          message = 'Profil güncellendi. ${result.spentCoins} coin harcandı.';
        } else {
          message = 'Profil güncellendi.';
        }
      }

      msg(message);

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

  static Widget _infoTileWithProgress({
    required int ratingValue,
  }) {
    return SizedBox(
      width: 118,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF243338), Color(0xFF161F23)],
          ),
          border: Border.all(color: const Color(0x40E7C06A), width: 1.0),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: ratingValue.toDouble()),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOutCubic,
              builder: (context, animatedRating, _) {
                final safeProgress = Format.ratingProgress(
                  animatedRating.round(),
                ).clamp(0.0, 1.0);
                final displayProgress = safeProgress > 0
                    ? safeProgress.clamp(0.08, 1.0).toDouble()
                    : 0.0;
                Color mix(Color a, Color b, double t) =>
                    Color.lerp(a, b, t) ?? a;

                Color startColor;
                Color endColor;
                if (safeProgress < 0.5) {
                  final t = safeProgress / 0.5;
                  startColor = mix(
                    const Color(0xFFFF8A65),
                    const Color(0xFFFFC75F),
                    t,
                  );
                  endColor = mix(
                    const Color(0xFFFFB74D),
                    const Color(0xFFF4D27A),
                    t,
                  );
                } else {
                  final t = (safeProgress - 0.5) / 0.5;
                  startColor = mix(
                    const Color(0xFFFFC75F),
                    const Color(0xFF8BE28B),
                    t,
                  );
                  endColor = mix(
                    const Color(0xFFF4D27A),
                    const Color(0xFF4FCB78),
                    t,
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final fillWidth = constraints.maxWidth * displayProgress;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF2A3A3E), Color(0xFF202D31)],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: displayProgress,
                            heightFactor: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    mix(Colors.white, startColor, 0.35),
                                    startColor,
                                    endColor,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (displayProgress > 0.12)
                          Positioned(
                            left: (fillWidth - 10).clamp(
                              0.0,
                              constraints.maxWidth - 10,
                            ),
                            child: Container(
                              width: 10,
                              height: constraints.maxHeight,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x66FFFFFF),
                                    Color(0x00FFFFFF),
                                  ],
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x66FFD36A),
                                    blurRadius: 6,
                                    spreadRadius: 0.5,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        IgnorePointer(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x22FFFFFF), Color(0x00FFFFFF)],
                              ),
                            ),
                          ),
                        ),
                        Text(
                          Format.rating(animatedRating.round()),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 21,
                            height: 1.0,
                            shadows: [
                              Shadow(
                                color: Color(0xAA000000),
                                blurRadius: 8,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static Widget _infoTileLarge({
    required IconData icon,
    required int coinValue,
  }) {
    return Container(
      width: 118,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2328), Color(0xFF11181C)],
        ),
        border: Border.all(color: const Color(0x33E7C06A)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: const Color(0xFFE9C46A)),
          const SizedBox(width: 6),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: coinValue.toDouble()),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (context, animatedCoins, _) {
              return Text(
                Format.coin(animatedCoins.round()),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  height: 1.0,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  static Future<bool> _isUsernameTakenForSetup(
    String username,
    String currentUserId,
  ) async {
    final rowsUsers = await supabase
        .from('users')
        .select('id')
        .ilike('username', username)
        .limit(5);
    for (final row in (rowsUsers as List)) {
      final id = row['id']?.toString();
      if (id != null && id != currentUserId) return true;
    }

    final rowsProfiles = await supabase
        .from('profiles')
        .select('id')
        .ilike('username', username)
        .limit(5);
    for (final row in (rowsProfiles as List)) {
      final id = row['id']?.toString();
      if (id != null && id != currentUserId) return true;
    }
    return false;
  }

  static Future<String> _generateAutoUsernameByAvatar(String avatarRef) async {
    final currentUserId = UserState.userId ?? supabase.auth.currentUser?.id ?? '';

    String buildSuffix(int length) {
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      final buffer = StringBuffer();
      for (var i = 0; i < length; i++) {
        buffer.write(alphabet[_profileRandom.nextInt(alphabet.length)]);
      }
      return buffer.toString();
    }

    // Oyuncu_ + 5/6 karakter: kisa, okunur, cakismaz olana kadar dener.
    for (var i = 0; i < 2000; i++) {
      final len = _profileRandom.nextBool() ? 5 : 6;
      final candidate = 'Oyuncu_${buildSuffix(len)}';
      final taken = await _isUsernameTakenForSetup(candidate, currentUserId);
      if (!taken) return candidate;
    }

    // Teorik fallback (pratikte buraya dusmez), yine uniqueness kontrolu var.
    while (true) {
      final raw =
          (DateTime.now().microsecondsSinceEpoch ^ _profileRandom.nextInt(1 << 20))
              .toRadixString(36)
              .toUpperCase();
      final suffix = raw.length > 6 ? raw.substring(raw.length - 6) : raw;
      final candidate = 'Oyuncu_$suffix';
      final taken = await _isUsernameTakenForSetup(candidate, currentUserId);
      if (!taken) return candidate;
    }
  }

  static Future<void> _checkAvatarApprovedLater() async {
    final userId = UserState.userId;

    if (userId == null) return;

    await Future.delayed(const Duration(seconds: 40));

    try {
      final res = await supabase
          .from('users')
          .select('avatar_status')
          .eq('id', userId)
          .maybeSingle();

      if (res != null && res['avatar_status'] == 'approved') {
        msg("✅ Fotoğrafınız onaylandı ve artık diğer oyuncular görebilir.");
      }
    } catch (_) {}
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
      final existing = await supabase
          .from('users')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (existing != null) return;

      await supabase.from('users').insert({
        'id': user.id,
        'email': user.email,
        'avatar_url': 'assets/images/avatars/avatar1.png',
      });
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
              const Color(0xFF2A313C).withOpacity(0.18),
              const Color(0xFF121820).withOpacity(0.22),
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
