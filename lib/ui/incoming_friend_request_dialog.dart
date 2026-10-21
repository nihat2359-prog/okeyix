import 'package:flutter/material.dart';
import 'lobby/lobby_avatar.dart';
import 'lobby/lobby_metal_surface.dart';

class IncomingFriendRequestDialog extends StatelessWidget {
  final String username;
  final String? avatarUrl;
  final VoidCallback onAccept, onReject, onBlock, onClose;
  const IncomingFriendRequestDialog({super.key, required this.username,
    this.avatarUrl, required this.onAccept, required this.onReject,
    required this.onBlock, required this.onClose});

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(child: LobbyMetalSurface(
        flatBorder: true, radius: 24, surfaceOpacity: 2.3,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.person_add_alt_1_rounded, size: 16, color: Color(0xFFE4C88D)),
            const SizedBox(width: 8),
            const Expanded(child: Text('ARKADAŞLIK İSTEĞİ', style: TextStyle(
              color: Color(0xFFE4C88D), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1))),
            IconButton(tooltip: 'Vazgeç', onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFFBCC8C7))),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            LobbyAvatar(username: username, avatarUrl: avatarUrl, size: 32),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(username, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFF3EFE6), fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              const Text('Seninle arkadaş olmak istiyor.',
                style: TextStyle(color: Color(0xFFB9C4C3), fontSize: 12)),
            ])),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _action('Engelle', Icons.block_rounded, onBlock)),
            const SizedBox(width: 8),
            Expanded(child: _action('Reddet', Icons.person_remove_outlined, onReject)),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: _action('Kabul et', Icons.check_rounded, onAccept, primary: true)),
          ]),
        ]),
      )),
    ),
  );

  Widget _action(String label, IconData icon, VoidCallback onTap, {bool primary = false}) =>
    Material(color: Colors.transparent, child: Ink(
      decoration: BoxDecoration(
        gradient: primary ? const LinearGradient(begin: Alignment.topCenter,
          end: Alignment.bottomCenter, colors: [Color(0xFFF0D99D), Color(0xFFBC944A)]) : null,
        color: primary ? null : const Color(0x60253137),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primary ? const Color(0xFFEBD194) : const Color(0x557B8584)),
      ),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
          child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: primary ? const Color(0xFF302813) : const Color(0xFFC5CFCD)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
              color: primary ? const Color(0xFF302813) : const Color(0xFFC5CFCD))),
          ]))),
      ),
    ));
}
