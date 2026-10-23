import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'lobby/lobby_metal_surface.dart';

const _gold = Color(0xFFE5C585);

class ProfileActionScene extends StatelessWidget {
  final String title, subtitle, action;
  final IconData icon;
  final Widget child;
  final VoidCallback onClose;
  final VoidCallback? onSubmit;
  final bool busy;
  final String? error;
  const ProfileActionScene({
    super.key,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.icon,
    required this.child,
    required this.onClose,
    required this.onSubmit,
    this.busy = false,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12 + media.padding.left,
        8 + media.padding.top,
        12 + media.padding.right,
        8 + math.max(media.viewInsets.bottom, media.viewPadding.bottom),
      ),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final height = math.min(bounds.maxHeight, 360.0);
          final compact = height < 230;
          return Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: math.min(bounds.maxWidth, 720),
              height: height,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xF0141B23),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: LobbyMetalSurface(
                    radius: 22,
                    flatBorder: true,
                    child: Padding(
                      padding: EdgeInsets.all(compact ? 10 : 16),
                      child: Column(
                        children: [
                          SizedBox(
                            height: compact ? 32 : 44,
                            child: Row(
                              children: [
                                Icon(
                                  icon,
                                  size: compact ? 21 : 25,
                                  color: _gold,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: const Color(0xFFF3E7D0),
                                            fontSize: compact ? 15 : 19,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (!compact)
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFFA7AFB8),
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey('profile-action-close'),
                                  tooltip: 'Kapat',
                                  padding: EdgeInsets.zero,
                                  onPressed: busy ? null : onClose,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 22,
                                    color: Color(0xFFB5BDC7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: compact ? 6 : 12),
                          Expanded(child: child),
                          if (error != null)
                            SizedBox(
                              height: 22,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  error!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFFFFB5AB),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          SizedBox(height: compact ? 6 : 12),
                          SizedBox(
                            height: compact ? 34 : 42,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _Action(
                                    label: 'Vazgeç',
                                    onTap: busy ? null : onClose,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: _Action(
                                    label: action,
                                    primary: true,
                                    busy: busy,
                                    onTap: busy ? null : onSubmit,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ProfileReportScene extends StatelessWidget {
  final String username;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onClose, onSend;
  const ProfileReportScene({
    super.key,
    required this.username,
    required this.controller,
    required this.sending,
    required this.onClose,
    required this.onSend,
  });
  @override
  Widget build(BuildContext context) => ProfileActionScene(
    title: 'Oyuncuyu Bildir',
    subtitle: '@$username',
    icon: Icons.flag_outlined,
    action: 'BİLDİRİMİ GÖNDER',
    busy: sending,
    onClose: onClose,
    onSubmit: onSend,
    child: TextField(
      key: const ValueKey('profile-report-message'),
      controller: controller,
      enabled: !sending,
      expands: true,
      minLines: null,
      maxLines: null,
      textAlignVertical: TextAlignVertical.top,
      cursorColor: _gold,
      style: const TextStyle(color: Color(0xFFF1EADD), fontSize: 13),
      decoration: InputDecoration(
        hintText: '@$username hakkında şikâyetini yaz…',
        hintStyle: const TextStyle(color: Color(0xFF8F9BA9), fontSize: 12),
        filled: true,
        fillColor: const Color(0x662C343F),
        contentPadding: const EdgeInsets.all(10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x557D8993)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x557D8993)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold),
        ),
      ),
    ),
  );
}

class ProfileGiftScene extends StatelessWidget {
  final String recipient;
  final List<Map<String, dynamic>> gifts;
  final int selected;
  final bool sending;
  final String? error;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose, onSend;
  const ProfileGiftScene({
    super.key,
    required this.recipient,
    required this.gifts,
    required this.selected,
    required this.sending,
    this.error,
    required this.onSelect,
    required this.onClose,
    required this.onSend,
  });
  @override
  Widget build(BuildContext context) => ProfileActionScene(
    title: 'Hediye Gönder',
    subtitle: recipient,
    icon: Icons.card_giftcard_outlined,
    action: selected < 0
        ? 'HEDİYE SEÇ'
        : 'GÖNDER · ${gifts[selected]['cost']} COIN',
    busy: sending,
    error: error,
    onClose: onClose,
    onSubmit: selected < 0 ? null : onSend,
    child: LayoutBuilder(
      builder: (context, bounds) => GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          mainAxisExtent: math.max(58, (bounds.maxHeight - 8) / 2),
        ),
        itemCount: gifts.length,
        itemBuilder: (context, index) {
          final gift = gifts[index], active = index == selected;
          return Semantics(
            selected: active,
            button: true,
            label: '${gift['name']}, ${gift['cost']} coin',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('profile-gift-${gift['type']}'),
                onTap: sending ? null : () => onSelect(index),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: active
                        ? const Color(0x77493F2A)
                        : const Color(0x55343E49),
                    border: Border.all(
                      color: active ? _gold : const Color(0x445F6C78),
                      width: active ? 1.2 : .7,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: Text(
                            gift['emoji'] as String,
                            style: const TextStyle(fontSize: 42),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 3,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                gift['name'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFF3E7D0),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${gift['cost']} coin',
                                  style: const TextStyle(
                                    color: _gold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (active)
                        const Icon(
                          Icons.check_circle_rounded,
                          color: _gold,
                          size: 14,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary, busy;
  const _Action({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: primary
              ? LinearGradient(
                  colors: onTap == null
                      ? const [Color(0xFF5D5748), Color(0xFF454136)]
                      : const [Color(0xFFF0DAA2), Color(0xFFB68A3E)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : null,
          border: Border.all(
            color: primary ? const Color(0x88E8CA8D) : const Color(0x556D7986),
          ),
        ),
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _gold,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: label == 'HEDİYE SEÇ'
                            ? Colors.white
                            : primary
                            ? const Color(0xFF30230E)
                            : const Color(0xFFC2C8D0),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
}
