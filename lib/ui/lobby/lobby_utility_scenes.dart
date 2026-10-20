import 'dart:math' as math;
import 'package:flutter/material.dart';

const _gold = Color(0xFFE5C585);

class GameSupportScene extends StatelessWidget {
  final TextEditingController message;
  final String category;
  final String? error;
  final bool sending;
  final ValueChanged<String> onCategory;
  final VoidCallback onSend, onClose;
  const GameSupportScene({
    super.key,
    required this.message,
    required this.category,
    required this.onCategory,
    required this.onSend,
    required this.onClose,
    this.error,
    this.sending = false,
  });

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !sending,
    child: _GamePanel(
      builder: (context, height) {
        final compact = height < 240;
        return Column(
          children: [
            _Heading(
              'OYUNCU DESTEĞİ',
              'Destek & Şikâyet',
              Icons.support_agent_rounded,
              sending ? null : onClose,
              compact: compact,
            ),
            SizedBox(height: compact ? 2 : 6),
            SizedBox(
              height: compact ? 32 : 44,
              child: Row(
                children: [
                  for (final item in const {
                    'talep': ('Talep', Icons.edit_note_rounded),
                    'sikayet': ('Şikâyet', Icons.flag_outlined),
                    'hata': ('Hata', Icons.bug_report_outlined),
                  }.entries)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Material(
                          color: Colors.transparent,
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              color: category == item.key
                                  ? const Color(0x25E5C585)
                                  : Colors.transparent,
                              border: Border.all(
                                color: category == item.key
                                    ? const Color(0x99E5C585)
                                    : const Color(0x337C8693),
                                width: .8,
                              ),
                            ),
                            child: InkWell(
                              key: ValueKey('support-${item.key}'),
                              onTap: sending
                                  ? null
                                  : () => onCategory(item.key),
                              borderRadius: BorderRadius.circular(22),
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        item.value.$2,
                                        color: category == item.key
                                            ? _gold
                                            : const Color(0xFF9BA5B3),
                                        size: 17,
                                      ),
                                      const SizedBox(width: 7),
                                      Text(
                                        item.value.$1,
                                        style: TextStyle(
                                          color: category == item.key
                                              ? _gold
                                              : const Color(0xFFBDC4CF),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: compact ? 2 : 8),
            Expanded(
              child: TextField(
                key: const ValueKey('support-message'),
                controller: message,
                enabled: !sending,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                scrollPadding: const EdgeInsets.all(8),
                cursorColor: _gold,
                style: TextStyle(
                  color: Color(0xFFE6E8ED),
                  fontSize: compact ? 12 : 13,
                  height: compact ? 1.2 : 1.4,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0x40070D16),
                  hintText: 'Seni dinliyoruz. Detayları buraya yaz…',
                  hintStyle: const TextStyle(
                    color: Color(0xFF858F9F),
                    fontSize: 12,
                  ),
                  contentPadding: EdgeInsets.all(compact ? 4 : 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0x336E7C8E),
                      width: .7,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0x99E5C585),
                      width: .8,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0x336E7C8E),
                      width: .7,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: compact ? 2 : 8),
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      error ?? 'En az 8 karakter yaz.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: error == null
                            ? const Color(0xFF9CA6B5)
                            : const Color(0xFFF0A298),
                        fontSize: 10,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _GameAction(
                      'Vazgeç',
                      Icons.close_rounded,
                      sending ? null : onClose,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _GameAction(
                      sending ? 'Gönderiliyor…' : 'Gönder',
                      sending
                          ? Icons.hourglass_top_rounded
                          : Icons.send_rounded,
                      sending ? null : onSend,
                      primary: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}

class GameSettingsScene extends StatelessWidget {
  final bool sound, vibration, colorBlind, invites;
  final ValueChanged<bool> onSound, onVibration, onColorBlind, onInvites;
  final VoidCallback onClose, onDelete;
  const GameSettingsScene({
    super.key,
    required this.sound,
    required this.vibration,
    required this.colorBlind,
    required this.invites,
    required this.onSound,
    required this.onVibration,
    required this.onColorBlind,
    required this.onInvites,
    required this.onClose,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => _GamePanel(
    builder: (context, height) => Column(
      children: [
        _Heading('OYUN TERCİHLERİ', 'Ayarlar', Icons.tune_rounded, onClose),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final items = [
                _Preference(
                  'Ses',
                  'Oyun ve mesaj sesleri',
                  Icons.volume_up_outlined,
                  sound,
                  onSound,
                ),
                _Preference(
                  'Titreşim',
                  'Dokunuşlara haptic geri bildirim',
                  Icons.vibration_rounded,
                  vibration,
                  onVibration,
                ),
                _Preference(
                  'Renk Körü Modu',
                  'Sarı taşları yeşil göster',
                  Icons.palette_outlined,
                  colorBlind,
                  onColorBlind,
                ),
                _Preference(
                  'Oyun Davetleri',
                  'Arkadaşlarından davet al',
                  Icons.local_activity_outlined,
                  invites,
                  onInvites,
                ),
              ];
              if (bounds.maxWidth < 460) {
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: Color(0x227E8796), height: 1),
                  itemBuilder: (_, i) => items[i],
                );
              }
              return SingleChildScrollView(
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: items[0]),
                        const SizedBox(width: 20),
                        Expanded(child: items[1]),
                      ],
                    ),
                    const Divider(color: Color(0x227E8796), height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: items[2]),
                        const SizedBox(width: 20),
                        Expanded(child: items[3]),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Tercihlerin otomatik kaydedilir.',
                  maxLines: 2,
                  style: TextStyle(color: Color(0xFF929CAC), fontSize: 10),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: _GameAction(
                  'Hesabı Sil',
                  Icons.delete_outline_rounded,
                  onDelete,
                  danger: true,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Preference extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Preference(
    this.title,
    this.subtitle,
    this.icon,
    this.value,
    this.onChanged,
  );
  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: title,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('setting-$title'),
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 36,
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: value ? _gold : const Color(0xFF8E99A9),
                  size: 25,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFEFE4CF),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF929EAF),
                        fontSize: 10,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 23,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: value
                        ? const [Color(0xFFB58E4A), Color(0xFFE2C688)]
                        : const [Color(0xFF343C49), Color(0xFF202936)],
                  ),
                  border: Border.all(
                    color: value
                        ? const Color(0xFFE7CE97)
                        : const Color(0xFF566172),
                    width: .7,
                  ),
                ),
                child: Align(
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value
                          ? const Color(0xFF302719)
                          : const Color(0xFFACB4C2),
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
}

class _Heading extends StatelessWidget {
  final String eyebrow, title;
  final IconData icon;
  final VoidCallback? onClose;
  final bool compact;
  const _Heading(
    this.eyebrow,
    this.title,
    this.icon,
    this.onClose, {
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: compact ? 28 : 46,
    child: Row(
      children: [
        Icon(icon, color: _gold, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 9,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFF3E7D0),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('utility-close'),
          tooltip: 'Kapat',
          onPressed: onClose,
          icon: const Icon(
            Icons.close_rounded,
            color: Color(0xFFB4BECD),
            size: 22,
          ),
        ),
      ],
    ),
  );
}

class _GameAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool primary, danger;
  const _GameAction(
    this.label,
    this.icon,
    this.onTap, {
    this.primary = false,
    this.danger = false,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: primary
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: onTap != null
                      ? const [Color(0xFFF2DAA2), Color(0xFFBD914A)]
                      : const [Color(0xFF77725E), Color(0xFF514C3F)],
                )
              : null,
          border: Border.all(
            color: primary
                ? const Color(0xFFD8B673)
                : danger
                ? const Color(0x667F514D)
                : const Color(0x44737E8E),
            width: .8,
          ),
        ),
        child: InkWell(
          key: ValueKey('utility-$label'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 15,
                      color: primary
                          ? const Color(0xFF32250F)
                          : danger
                          ? const Color(0xFFC7958E)
                          : _gold,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: primary
                            ? const Color(0xFF32250F)
                            : danger
                            ? const Color(0xFFD6AAA3)
                            : const Color(0xFFDDE2EA),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _GamePanel extends StatelessWidget {
  final Widget Function(BuildContext, double) builder;
  const _GamePanel({required this.builder});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 400),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final height = math.min(400.0, bounds.maxHeight);
            return SizedBox(
              height: height,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: EdgeInsets.all(height < 240 ? 8 : 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xF01C222B), Color(0xED0B1119)],
                    ),
                    border: Border.all(
                      color: const Color(0x668D7951),
                      width: .8,
                    ),
                  ),
                  child: builder(context, height),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
