import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';

class GameInviteDialog extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() loadPlayers;
  final Future<void> Function(Map<String, dynamic>) onInvite;
  final Widget Function(String?, String) avatarBuilder;
  const GameInviteDialog({super.key, required this.loadPlayers,
    required this.onInvite, required this.avatarBuilder});
  @override
  State<GameInviteDialog> createState() => _GameInviteDialogState();
}

class _GameInviteDialogState extends State<GameInviteDialog> {
  late Future<List<Map<String, dynamic>>> _players;
  String? _sending;
  String? _sendError;
  @override
  void initState() { super.initState(); _players = Future.sync(widget.loadPlayers); }

  Future<void> _invite(Map<String, dynamic> player) async {
    if (_sending != null) return;
    setState(() { _sending = player['id'].toString(); _sendError = null; });
    try {
      await widget.onInvite(player);
    } catch (_) {
      if (mounted) setState(() => _sendError = 'Davet gönderilemedi. Tekrar dene.');
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE5C586);
    final media = MediaQuery.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        width: math.min(840, media.size.width - media.viewPadding.horizontal - 32),
        height: math.max(120, media.size.height - media.viewPadding.vertical - 24),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: _InviteTray(
          child: Column(children: [
            Row(children: [
              Container(width: 36, height: 36,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [Color(0xCC1A2B24), Color(0xBB09150F)]),
                  border: Border.all(color: const Color(0x778F826B)),
                  boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(0, 3), blurRadius: 5)]),
                child: const Icon(Icons.person_add_alt_1_rounded, color: gold, size: 22)),
              const SizedBox(width: 10),
              const Expanded(child: Text('Masana oyuncu davet et',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Color(0xFFF5EFE2), fontSize: 17,
                  fontWeight: FontWeight.w700))),
              IconButton(key: const ValueKey('invite-close'),
                tooltip: 'Kapat', onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white70)),
            ]),
            if (_sendError != null) Text(_sendError!,
              style: const TextStyle(color: Color(0xFFF0B4A4), fontSize: 12)),
            Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _players,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 24, height: 24, child: CircularProgressIndicator(
                      strokeWidth: 2, color: gold)),
                    SizedBox(height: 12),
                    Text('Uygun oyuncular listeleniyor…',
                      style: TextStyle(color: Color(0xFFD0D4DC), fontSize: 13)),
                  ]));
                }
                if (snapshot.hasError) return Center(child: TextButton.icon(
                  onPressed: () => setState(() => _players = Future.sync(widget.loadPlayers)),
                  icon: const Icon(Icons.refresh_rounded, color: gold),
                  label: const Text('Liste yüklenemedi · Tekrar dene',
                    style: TextStyle(color: gold))));
                final rows = snapshot.data ?? [];
                final online = rows.where((p) => p['is_online'] == true).toList();
                final offline = rows.where((p) => p['is_online'] != true).toList();
                return DefaultTabController(length: 2, child: Column(children: [
                  Container(
                    decoration: BoxDecoration(color: const Color(0x77040D09),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0x447C7057))),
                    child: TabBar(
                    labelColor: gold, unselectedLabelColor: const Color(0xFF9DA5B0),
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [Color(0xCC24362C), Color(0xBB102218)]),
                      border: Border.all(color: const Color(0x778F826B))),
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    tabs: [Tab(height: 34, text: 'Çevrimiçi (${online.length})'),
                      Tab(height: 34, text: 'Çevrimdışı (${offline.length})')])),
                  const SizedBox(height: 8),
                  Expanded(child: TabBarView(children: [_grid(online), _grid(offline)])),
                ]));
              },
            )),
          ]),
        ),
      ),
    );
  }

  Widget _grid(List<Map<String, dynamic>> players) {
    if (players.isEmpty) return const Center(child: Text('Bu sekmede uygun oyuncu yok.',
      style: TextStyle(color: Colors.white60, fontSize: 13)));
    return LayoutBuilder(builder: (context, bounds) {
      final columns = bounds.maxWidth >= 440 ? 2 : 1;
      final largeText = MediaQuery.textScalerOf(context).scale(12) > 16;
      return GridView.builder(
        padding: const EdgeInsets.only(bottom: 4),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns, crossAxisSpacing: 10, mainAxisSpacing: 8,
          mainAxisExtent: largeText ? 106 : 78),
        itemCount: players.length,
        itemBuilder: (context, index) {
          final p = players[index];
          final name = p['username']?.toString() ?? 'Oyuncu';
          final id = p['id']?.toString();
          final sending = id != null && _sending == id;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Color(0xAA182C23), Color(0xAA0A1C13), Color(0x9907110C)]),
              border: Border.all(color: const Color(0x55758B75), width: .8),
              boxShadow: const [BoxShadow(color: Color(0x55000000), offset: Offset(0, 3), blurRadius: 4)]),
            child: Row(children: [
              Container(width: 48, height: 48,
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(shape: BoxShape.circle,
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFCEBF9D), Color(0xFF7C7C77), Color(0xFF9CA4AE)]),
                  boxShadow: [BoxShadow(color: Color(0x66000000), offset: Offset(0, 2), blurRadius: 4)]),
                child: FittedBox(child: widget.avatarBuilder(p['avatar_url']?.toString(), name))),
              const SizedBox(width: 8),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFF5EFE2), fontSize: 13,
                      fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text('${p['is_bot'] == true ? 'BOT · ' : ''}'
                      'Seviye ${Format.rating(p['rating'])} · ${Format.balance(p['coins'] ?? 0)} Coin',
                      style: const TextStyle(color: Color(0xFFD4C4A0), fontSize: 11))),
                  if (p['is_online'] != true) ...[
                    const SizedBox(height: 3),
                    Text(inviteLastSeenLabel(p['last_seen_at']), maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFADB5C1), fontSize: 10)),
                  ],
                ])),
              const SizedBox(width: 6),
              SizedBox(width: 48, height: 48, child: DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFFE3D6B6), Color(0xFFC6B48D), Color(0xFFAC9972)]),
                  border: Border.all(color: const Color(0x88E7D9BC), width: .7),
                  boxShadow: const [BoxShadow(color: Color(0x66000000),
                    blurRadius: 4, offset: Offset(0, 3))]),
                child: TextButton(
                key: ValueKey('invite-player-$id'),
                onPressed: _sending != null || id == null ? null : () => _invite(p),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4),
                  foregroundColor: const Color(0xFF211F24),
                  disabledForegroundColor: const Color(0xFF211F24),
                  shape: const CircleBorder()),
                child: sending ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF211F24)))
                  : const FittedBox(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.person_add_alt_1_rounded, size: 17),
                      SizedBox(height: 1),
                      Text('Davet', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
                    ])),
              ))),
            ]),
          );
        },
      );
    });
  }
}

String inviteLastSeenLabel(dynamic raw, {DateTime? now}) {
  final date = raw is DateTime ? raw : DateTime.tryParse(raw?.toString() ?? '');
  if (date == null) return 'Son görülme: bilinmiyor';
  final elapsed = (now ?? DateTime.now()).difference(date);
  if (elapsed.inSeconds < 60) return 'Son görülme: az önce';
  if (elapsed.inMinutes < 60) return 'Son görülme: ${elapsed.inMinutes} dk önce';
  if (elapsed.inHours < 24) return 'Son görülme: ${elapsed.inHours} sa önce';
  return 'Son görülme: ${elapsed.inDays} gün önce';
}

/// A shallow satin frame with a dark green felt interior matching the table.
class _InviteTray extends StatelessWidget {
  final Widget child;
  const _InviteTray({required this.child});
  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(
    painter: const _InviteTrayPainter(),
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  ));
}

class _InviteTrayPainter extends CustomPainter {
  const _InviteTrayPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = RRect.fromRectAndRadius(rect, const Radius.circular(22));
    canvas.drawShadow(Path()..addRRect(outer), Colors.black, 8, false);
    canvas.drawRRect(outer.deflate(1.5), Paint()..style = PaintingStyle.stroke
      ..strokeWidth = 2 ..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xAA8C8677), Color(0x6645474A), Color(0x55252A31), Color(0x88696861)],
      stops: [0, .22, .72, 1],
    ).createShader(rect));
    final inner = RRect.fromRectAndRadius(rect.deflate(3), const Radius.circular(19));
    canvas.drawRRect(inner, Paint()..shader = const LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color(0xD012231B), Color(0xE0030C08), Color(0xD5091710)],
    ).createShader(rect));
    canvas.drawRRect(inner, Paint()..style = PaintingStyle.stroke
      ..strokeWidth = .7 ..color = const Color(0x668E8570));
  }
  @override
  bool shouldRepaint(covariant _InviteTrayPainter oldDelegate) => false;
}
