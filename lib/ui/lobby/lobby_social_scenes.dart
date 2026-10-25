import 'package:flutter/material.dart';
import 'package:okeyix/core/message_contacts.dart';
import 'package:okeyix/core/format.dart';

const _gold = Color(0xFFE4C98D);
typedef FriendAvatarBuilder = Widget Function(Map<String, dynamic> friend);

class LobbySocialHeader extends StatelessWidget {
  const LobbySocialHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.trailing,
    this.height = 34,
  });
  final String title;
  final VoidCallback onClose;
  final Widget? trailing;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Row(
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              style: const TextStyle(
                color: _gold,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        ?trailing,
        IconButton(
          key: const ValueKey('lobby-social-close'),
          tooltip: 'Paneli kapat',
          constraints: const BoxConstraints.tightFor(width: 34, height: 32),
          padding: EdgeInsets.zero,
          onPressed: () {
            FocusManager.instance.primaryFocus?.unfocus();
            onClose();
          },
          icon: const Icon(
            Icons.close_rounded,
            size: 21,
            color: Color(0xFFB6C0CD),
          ),
        ),
      ],
    ),
  );
}

class LobbyFriendsScene extends StatelessWidget {
  const LobbyFriendsScene({
    super.key,
    required this.friends,
    required this.avatarBuilder,
    required this.statusText,
    required this.onProfile,
    required this.onMessage,
    required this.onSpectate,
    required this.onClose,
  });
  final List<Map<String, dynamic>> friends;
  final FriendAvatarBuilder avatarBuilder;
  final String Function(Map<String, dynamic>) statusText;
  final ValueChanged<Map<String, dynamic>> onProfile, onMessage, onSpectate;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      LobbySocialHeader(
        title: 'Arkadaşlar',
        onClose: onClose,
        trailing: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            '${friends.length}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ),
      const Divider(color: Color(0x227F8D9D), height: 9),
      Expanded(
        child: friends.isEmpty
            ? const Center(
                child: Text(
                  'Henüz arkadaşın yok.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              )
            : GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 4,
                  mainAxisExtent: 84 + 42 *
                      (MediaQuery.textScalerOf(context).scale(12) / 12 - 1).clamp(0, 2),
                ),
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  final friend = friends[index];
                  return InkWell(
                    key: ValueKey('social-friend-${friend['id']}'),
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onProfile(friend),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: const Color(0x182F3946),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x227F8D9D), width: .6),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      child: Row(
                        children: [
                          avatarBuilder(friend),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  friend['username']?.toString() ?? 'Oyuncu',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFE5E9E6),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Seviye ${friend['rating'] is num ? Format.rating((friend['rating'] as num).toInt()) : '—'} · ${friend['coins'] is num ? Format.coin(friend['coins'] as num) : '—'} Coin',
                                    maxLines: 1,
                                    style: const TextStyle(color: _gold, fontSize: 11),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  statusText(friend),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: friend['is_online'] == true
                                        ? const Color(0xFFA3C1AF)
                                        : const Color(0xFF8895A5),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (friend['table_id'] != null &&
                              friend['table_spectators_enabled'] != false)
                            IconButton(
                              tooltip: 'Masayı izle',
                              onPressed: () => onSpectate(friend),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 30,
                                height: 36,
                              ),
                              icon: const Icon(
                                Icons.visibility_outlined,
                                color: _gold,
                                size: 18,
                              ),
                            ),
                          IconButton(
                            tooltip: 'Mesaj yaz',
                            onPressed: () => onMessage(friend),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 30,
                              height: 36,
                            ),
                            icon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: _gold,
                              size: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

class LobbyMessagesScene extends StatelessWidget {
  const LobbyMessagesScene({
    super.key,
    required this.friends,
    required this.activeId,
    required this.unread,
    required this.avatarBuilder,
    required this.onSelect,
    required this.onClose,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    required this.onEmoji,
    required this.microphone,
    required this.messageCount,
    required this.messageBuilder,
    required this.menu,
    this.loading = false,
    this.accessory,
  });
  final List<Map<String, dynamic>> friends;
  final String? activeId;
  final Map<String, int> unread;
  final FriendAvatarBuilder avatarBuilder;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback onClose, onSend, onEmoji;
  final TextEditingController controller;
  final ScrollController scrollController;
  final Widget microphone, menu;
  final Widget? accessory;
  final int messageCount;
  final IndexedWidgetBuilder messageBuilder;
  final bool loading;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, limits) {
      final compact = limits.maxHeight < 210;
      final tiny = limits.maxHeight < 90;
      final contacts = messageContacts(friends, unread);
      final selected = contacts
          .where((f) => f['id']?.toString() == activeId)
          .firstOrNull;
      return Column(
        children: [
          LobbySocialHeader(
            title: 'Mesajlar',
            height: tiny ? 22 : 34,
            onClose: onClose,
            trailing: SizedBox(
              width: 150,
              child: PopupMenuButton<String>(
                tooltip: 'Arkadaş seç',
                color: const Color(0xFF18212B),
                onSelected: (id) => onSelect(
                  contacts.firstWhere((f) => f['id']?.toString() == id),
                ),
                itemBuilder: (_) => contacts
                    .map(
                      (f) => PopupMenuItem<String>(
                        value: f['id']?.toString(),
                        child: Text(
                          '${f['username']}  ${(unread[f['id']?.toString()] ?? 0) > 0 ? '(${unread[f['id']?.toString()]} yeni)' : ''}',
                          style: TextStyle(
                            color: Color(0xFFE6D6B4),
                            fontSize: 12,
                            fontWeight: (unread[f['id']?.toString()] ?? 0) > 0
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selected?['username']?.toString() ?? 'Arkadaş seç',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFC3CBD2),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: _gold,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!compact && contacts.isNotEmpty)
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: contacts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final friend = contacts[index];
                  final active = friend['id']?.toString() == activeId;
                  final count = unread[friend['id']?.toString()] ?? 0;
                  return InkWell(
                    key: ValueKey('message-contact-${friend['id']}'),
                    onTap: () => onSelect(friend),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 80,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0x18DABF82)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active
                              ? const Color(0x66DABF82)
                              : Colors.transparent,
                          width: .6,
                        ),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            width: 44,
                            height: 32,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Center(child: avatarBuilder(friend)),
                                if (count > 0)
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      key: ValueKey(
                                        'message-unread-${friend['id']}',
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 16,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _gold,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Text(
                                        count > 99 ? '99+' : '$count',
                                        style: const TextStyle(
                                          color: Color(0xFF231D11),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                friend['username']?.toString() ?? 'Oyuncu',
                                style: const TextStyle(
                                  color: Color(0xFFBAC4CE),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                if (contacts.isEmpty)
                  const Center(
                    child: Text(
                      'Mesajlaşmak için arkadaş eklemelisin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  )
                else if (loading)
                  const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: _gold,
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    controller: scrollController,
                    itemCount: messageCount + 1,
                    padding: const EdgeInsets.only(top: 4, bottom: 3),
                    itemBuilder: (context, index) => index < messageCount
                        ? messageBuilder(context, index)
                        : accessory ?? const SizedBox.shrink(),
                  ),
                if (contacts.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: SizedBox(width: 30, height: 30, child: menu),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x227F8D9D)),
          SizedBox(
            height: tiny ? 24 : 38,
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 34,
                  child: FittedBox(child: microphone),
                ),
                IconButton(
                  tooltip: 'Emoji',
                  onPressed: onEmoji,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 34,
                  ),
                  icon: const Icon(
                    Icons.emoji_emotions_outlined,
                    color: _gold,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('social-message-input'),
                    controller: controller,
                    enabled: activeId != null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    style: const TextStyle(
                      color: Color(0xFFE7EBE8),
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Mesaj yaz...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('social-message-send'),
                  tooltip: 'Gönder',
                  onPressed: activeId == null ? null : onSend,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  icon: const Icon(Icons.send_rounded, color: _gold, size: 20),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
