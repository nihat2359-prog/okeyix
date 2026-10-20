import 'package:flutter/material.dart';
import 'package:okeyix/models/player_comparison.dart';
import 'package:okeyix/services/comparison_image_share.dart';
import 'package:okeyix/ui/avatar_preset.dart';
import 'package:okeyix/ui/comparison_arena.dart';
import 'package:okeyix/ui/lobby/lobby_avatar.dart';

Future<void> showComparisonShareDialog(
  BuildContext context,
  PlayerComparison data,
) => showDialog<void>(
  context: context,
  barrierColor: Colors.black87,
  builder: (_) => _ComparisonShareDialog(data: data),
);

class ComparisonShareCard extends StatelessWidget {
  const ComparisonShareCard({super.key, required this.data});
  final PlayerComparison data;
  static const logicalSize = Size(360, 640);

  @override
  Widget build(BuildContext context) {
    final tied = data.leftWins == data.rightWins;
    final leftLeading = data.leftWins > data.rightWins;
    return SizedBox.fromSize(
      size: logicalSize,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: 'Montserrat', color: Colors.white),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/images/lobby/lobby.png', fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xE4071719),
                      Color(0xB707161C),
                      Color(0xF0071016),
                    ],
                    stops: [0, .5, 1],
                  ),
                ),
              ),
              if (!tied)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(leftLeading ? -.65 : .65, -.15),
                      radius: .8,
                      colors: [
                        comparisonGold.withValues(alpha: .18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: comparisonGold.withValues(alpha: .4),
                        width: .8,
                      ),
                    ),
                  ),
                ),
              ),
              // Critical content stays inside the story's upper/lower UI margins.
              Padding(
                key: const ValueKey('comparison-story-safe-content'),
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 72),
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/logo/okeyix_logo.png',
                      width: 218,
                      height: 56,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'BİRBİRİNİZE KARŞI',
                      style: TextStyle(
                        color: comparisonGold,
                        fontSize: 10,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 5,
                      child: Row(
                        children: [
                          Expanded(child: _player(data.left, leftLeading)),
                          const SizedBox(
                            width: 42,
                            child: Center(
                              child: Text(
                                'VS',
                                style: TextStyle(
                                  color: comparisonGold,
                                  fontSize: 31,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                      color: Color(0x667C6536),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _player(data.right, !tied && !leftLeading),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      flex: 4,
                      child: Container(
                        key: const ValueKey('comparison-story-score'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            colors: [Color(0xE0192A27), Color(0xEC09171D)],
                          ),
                          border: Border.all(
                            color: tied
                                ? const Color(0x777C8981)
                                : comparisonGold.withValues(alpha: .7),
                          ),
                          boxShadow: [
                            if (!tied)
                              BoxShadow(
                                color: comparisonGold.withValues(alpha: .1),
                                blurRadius: 24,
                              ),
                          ],
                        ),
                        child: Row(
                          children: [
                            _score(data.leftWins, leftLeading, tied),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 5),
                              child: Text(
                                '—',
                                style: TextStyle(
                                  fontSize: 23,
                                  color: Colors.white38,
                                ),
                              ),
                            ),
                            _score(data.rightWins, !tied && !leftLeading, tied),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 30,
                      child: Center(
                        child: Text(
                          data.resultLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${data.meetings} ORTAK EL · KAYITLI SONUÇLAR',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: comparisonGold,
                        fontSize: 9,
                        letterSpacing: .7,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/logo/okeyix_logo.png',
                          width: 80,
                          height: 30,
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sıradaki el senin.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${data.asOf.toUtc().toIso8601String().substring(0, 10)} · okeyix.com',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 8,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _score(int wins, bool leading, bool tied) => Expanded(
    child: FittedBox(
      fit: BoxFit.contain,
      child: Text(
        '$wins',
        style: TextStyle(
          fontSize: 94,
          height: 1,
          fontWeight: FontWeight.w900,
          color: tied
              ? const Color(0xFFEEEBDD)
              : leading
              ? comparisonGold
              : const Color(0xFFB7C8BF),
          shadows: [
            if (leading) const Shadow(color: Color(0x447E6835), blurRadius: 18),
          ],
        ),
      ),
    ),
  );

  Widget _player(ComparedPlayer player, bool leading) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 104,
        height: 104,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: leading ? comparisonGold : const Color(0xFF7D9187),
            width: leading ? 2 : 1,
          ),
          boxShadow: [
            if (leading)
              BoxShadow(
                color: comparisonGold.withValues(alpha: .3),
                blurRadius: 22,
                spreadRadius: 1,
              ),
          ],
        ),
        child: ClipOval(
          child: ColoredBox(
            color: const Color(0xFF13231F),
            child: LobbyAvatar(
              username: player.name,
              avatarUrl: player.avatar,
              size: 48,
            ),
          ),
        ),
      ),
      const SizedBox(height: 7),
      SizedBox(
        height: 34,
        child: Center(
          child: Text(
            player.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
      ),
      const SizedBox(height: 2),
      Text(
        player.league ?? 'Lig bilgisi yok',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          color: leading ? comparisonGold : const Color(0xFFBEC9BE),
        ),
      ),
    ],
  );
}

class _ComparisonShareDialog extends StatefulWidget {
  const _ComparisonShareDialog({required this.data});
  final PlayerComparison data;
  @override
  State<_ComparisonShareDialog> createState() => _ComparisonShareDialogState();
}

class _ComparisonShareDialogState extends State<_ComparisonShareDialog> {
  final _capture = GlobalKey();
  final _button = GlobalKey();
  bool _busy = false;
  String? _error;

  Future<void> _precache() async {
    final providers = <ImageProvider>[
      const AssetImage('assets/images/lobby/lobby.png'),
      const AssetImage('assets/images/logo/okeyix_logo.png'),
    ];
    for (final player in [widget.data.left, widget.data.right]) {
      final ref = player.avatar?.trim() ?? '';
      if (ref.startsWith('http')) {
        providers.add(NetworkImage(ref));
      } else if (ref.startsWith('assets/')) {
        providers.add(AssetImage(ref));
      } else if (isKnownAvatarPreset(ref)) {
        providers.add(AssetImage(avatarPresetByRef(ref).imageUrl));
      }
    }
    for (final provider in providers) {
      if (!mounted) throw StateError('Share closed');
      Object? error;
      await precacheImage(
        provider,
        context,
        onError: (e, _) {
          error = e;
        },
      ).timeout(const Duration(seconds: 15));
      if (error != null) throw StateError('Avatar/image unavailable');
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _precache();
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final box = _button.currentContext!.findRenderObject()! as RenderBox;
      final origin = box.localToGlobal(Offset.zero) & box.size;
      final png = await captureComparisonCard(_capture);
      if (!mounted) return;
      await ComparisonImageShare().share(png, origin);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Paylaşım hazırlanamadı. Lütfen tekrar dene.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Dialog(
      backgroundColor: const Color(0xFF101E21),
      insetPadding: const EdgeInsets.all(6),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: InteractiveViewer(
                    key: const ValueKey('comparison-story-zoom'),
                    minScale: 1,
                    maxScale: 3,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: RepaintBoundary(
                        key: _capture,
                        child: ComparisonShareCard(data: widget.data),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 42, 12, 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'REKABETİ PAYLAŞ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: comparisonGold,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '1080 × 1920\nHikâye kartı',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: _button,
                            onPressed: _busy ? null : _share,
                            style: FilledButton.styleFrom(
                              backgroundColor: comparisonGold,
                              foregroundColor: const Color(0xFF14201B),
                              minimumSize: const Size(0, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.ios_share_rounded, size: 16),
                            label: Text(
                              _busy ? 'Hazırlanıyor…' : 'Paylaş',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (_error != null)
                          Flexible(
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFE5A7A0),
                                fontSize: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              key: const ValueKey('comparison-share-close'),
              tooltip: 'Kapat',
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              style: IconButton.styleFrom(
                foregroundColor: comparisonGold,
                disabledForegroundColor: Colors.white24,
                backgroundColor: const Color(0x662A3831),
                side: const BorderSide(color: Color(0x667E704B), width: .7),
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.close_rounded, size: 21),
            ),
          ),
        ],
      ),
    ),
  );
}
