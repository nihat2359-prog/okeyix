import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'lobby/lobby_metal_surface.dart';

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
          color: const Color(0xD9141B23),
          borderRadius: BorderRadius.circular(20),
        ),
        child: LobbyMetalSurface(
          metal: const Color(0xFFB7A17A), radius: 20, padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(children: [
              const Icon(Icons.person_add_alt_1_rounded, color: gold, size: 22),
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
                  TabBar(
                    labelColor: gold, unselectedLabelColor: const Color(0xFF9DA5B0),
                    indicatorColor: gold, dividerColor: const Color(0x337E8581),
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    tabs: [Tab(height: 34, text: 'Çevrimiçi (${online.length})'),
                      Tab(height: 34, text: 'Çevrimdışı (${offline.length})')]),
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
          crossAxisCount: columns, crossAxisSpacing: 8, mainAxisSpacing: 6,
          mainAxisExtent: largeText ? 82 : 64),
        itemCount: players.length,
        itemBuilder: (context, index) {
          final p = players[index];
          final name = p['username']?.toString() ?? 'Oyuncu';
          final id = p['id']?.toString();
          final sending = id != null && _sending == id;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(color: const Color(0x99262D36),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x337E8581))),
            child: Row(children: [
              SizedBox(width: 32, height: 32, child: FittedBox(
                child: widget.avatarBuilder(p['avatar_url']?.toString(), name))),
              const SizedBox(width: 8),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFF5EFE2), fontSize: 12,
                      fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text('${p['is_bot'] == true ? 'BOT · ' : ''}'
                      'Seviye ${Format.rating(p['rating'])} · ${Format.coin(p['coins'] ?? 0)} coin',
                      style: const TextStyle(color: Color(0xFFA8AFBA), fontSize: 10))),
                ])),
              const SizedBox(width: 6),
              SizedBox(width: 52, height: 44, child: TextButton(
                key: ValueKey('invite-player-$id'),
                onPressed: _sending != null || id == null ? null : () => _invite(p),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4),
                  foregroundColor: const Color(0xFFF0D298),
                  disabledForegroundColor: Colors.white38,
                  backgroundColor: const Color(0x66363B44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                child: sending ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFE5C586)))
                  : const FittedBox(child: Text('Davet', style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w700))),
              )),
            ]),
          );
        },
      );
    });
  }
}
