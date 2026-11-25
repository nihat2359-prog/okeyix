import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:okeyix/services/cross_promo_service.dart';

const _gold = Color(0xFFE5C585);
const _ivory = Color(0xFFF5E8CC);

/// The lobby's game-table presentation; store and wallet calls stay in the host.
class CrossPromoScene extends StatefulWidget {
  final List<CrossPromoGame> games;
  final Set<String> claimed;
  final String? busy, message;
  final ValueChanged<CrossPromoGame> onDownload;
  const CrossPromoScene({
    super.key,
    required this.games,
    required this.claimed,
    required this.onDownload,
    this.busy,
    this.message,
  });

  @override
  State<CrossPromoScene> createState() => _CrossPromoSceneState();
}

class _CrossPromoSceneState extends State<CrossPromoScene> {
  final _pages = PageController();
  int _page = 0;

  void _turn(int delta) {
    final next = (_page + delta).clamp(0, widget.games.length - 1);
    _pages.animateToPage(
      next,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final height = math.min(bounds.maxHeight, 440.0);
          final compact = height < 300;
          return SizedBox(
            width: math.min(bounds.maxWidth, 900.0),
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xAAA68B58)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 28,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      'assets/images/lobby/lobby.png',
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xD9101C1D),
                            Color(0xC70A1918),
                            Color(0xF0081117),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 12 : 22,
                        6,
                        compact ? 12 : 22,
                        compact ? 10 : 18,
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                Image.asset(
                                  'assets/images/logo/okeyix_logo.png',
                                  width: compact ? 84 : 108,
                                  fit: BoxFit.contain,
                                  semanticLabel: 'Okeyix',
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 1,
                                  height: 18,
                                  color: const Color(0x668F7950),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'OYUNLARIMIZ',
                                      style: TextStyle(
                                        color: _gold,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey('promo-close'),
                                  tooltip: 'Kapat',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: _gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: _RewardStage(compact: compact),
                                ),
                                SizedBox(width: compact ? 12 : 24),
                                Container(
                                  width: 1,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0x00B99B62),
                                        Color(0x66B99B62),
                                        Color(0x00B99B62),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(width: compact ? 12 : 24),
                                Expanded(
                                  flex: 7,
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: widget.games.isEmpty
                                            ? const Center(
                                                child: Text(
                                                  'Yeni oyunlar yolda.',
                                                  style: TextStyle(
                                                    color: _ivory,
                                                  ),
                                                ),
                                              )
                                            : PageView.builder(
                                                key: const ValueKey(
                                                  'promo-games',
                                                ),
                                                controller: _pages,
                                                itemCount: widget.games.length,
                                                onPageChanged: (page) =>
                                                    setState(
                                                      () => _page = page,
                                                    ),
                                                itemBuilder: (context, index) {
                                                  final game =
                                                      widget.games[index];
                                                  return _GameSpotlight(
                                                    game: game,
                                                    compact: compact,
                                                    claimed: widget.claimed
                                                        .contains(game.id),
                                                    busy:
                                                        widget.busy == game.id,
                                                    onDownload:
                                                        widget.busy == null
                                                        ? () => widget
                                                              .onDownload(game)
                                                        : null,
                                                  );
                                                },
                                              ),
                                      ),
                                      if (widget.games.length > 1)
                                        SizedBox(
                                          height: 44,
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              IconButton(
                                                key: const ValueKey(
                                                  'promo-previous',
                                                ),
                                                tooltip: 'Önceki oyun',
                                                onPressed: _page > 0
                                                    ? () => _turn(-1)
                                                    : null,
                                                icon: const Icon(
                                                  Icons.chevron_left_rounded,
                                                ),
                                                color: _gold,
                                                disabledColor: const Color(
                                                  0x446F7C7B,
                                                ),
                                              ),
                                              Flexible(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    '${_page + 1} / ${widget.games.length}',
                                                    style: const TextStyle(
                                                      color: _gold,
                                                      fontSize: 11,
                                                      letterSpacing: 2,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                key: const ValueKey(
                                                  'promo-next',
                                                ),
                                                tooltip: 'Sonraki oyun',
                                                onPressed:
                                                    _page + 1 <
                                                        widget.games.length
                                                    ? () => _turn(1)
                                                    : null,
                                                icon: const Icon(
                                                  Icons.chevron_right_rounded,
                                                ),
                                                color: _gold,
                                                disabledColor: const Color(
                                                  0x446F7C7B,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.message != null) ...[
                            const SizedBox(height: 6),
                            SizedBox(
                              height: compact ? 30 : 38,
                              child: SingleChildScrollView(
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    widget.message!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _gold,
                                      fontSize: 12,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _RewardStage extends StatelessWidget {
  final bool compact;
  const _RewardStage({required this.compact});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'OYNA · KEŞFET · KAZAN',
          style: TextStyle(
            color: _gold,
            fontSize: 10,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(height: 8),
      Flexible(
        flex: 3,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x446C4D1C), Color(0x006C4D1C)],
                ),
              ),
              child: SizedBox.expand(),
            ),
            Image.asset(
              'assets/images/coins/coins_large.png',
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '+5.000',
          style: TextStyle(
            color: _gold,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Color(0x99000000), blurRadius: 8)],
          ),
        ),
      ),
      const FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'ÇİP HEDİYESİ',
          style: TextStyle(color: _ivory, fontSize: 11, letterSpacing: 1.4),
        ),
      ),
      if (!compact) ...[
        const SizedBox(height: 12),
        const Flexible(
          child: Text(
            'Yeni oyunlar,\nyeni heyecanlar.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFBAC5BC),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    ],
  );
}

class _GameSpotlight extends StatelessWidget {
  final CrossPromoGame game;
  final bool compact, claimed, busy;
  final VoidCallback? onDownload;
  const _GameSpotlight({
    required this.game,
    required this.compact,
    required this.claimed,
    required this.busy,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (game.id) {
      'okix' => Icons.alt_route_rounded,
      'sirenix' => Icons.emergency_rounded,
      _ => Icons.style_rounded,
    };
    final accent = switch (game.id) {
      'okix' => const Color(0xFF5BA998),
      'sirenix' => const Color(0xFFC38362),
      _ => const Color(0xFF839FC5),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: bounds.maxHeight),
                  child: Row(
                    children: [
                      if (bounds.maxWidth >= 300) ...[
                        Expanded(
                          flex: 4,
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: _GameLogo(game: game, icon: icon),
                          ),
                        ),
                        const SizedBox(width: 18),
                      ],
                      Expanded(
                        flex: 6,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (bounds.maxWidth < 300)
                                  SizedBox.square(
                                    dimension: 32,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(7),
                                      child: _GameArtwork(
                                        game: game,
                                        icon: icon,
                                        size: 20,
                                      ),
                                    ),
                                  )
                                else
                                  Icon(icon, color: accent, size: 20),
                                const SizedBox(width: 6),
                                const Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'OKEYIX KOLEKSİYONU',
                                      style: TextStyle(
                                        color: _gold,
                                        fontSize: 9,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              game.name,
                              style: TextStyle(
                                color: _ivory,
                                fontSize: compact ? 24 : 32,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              game.description,
                              style: const TextStyle(
                                color: Color(0xFFBDC8C3),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              claimed
                                  ? 'Çip hediyen alındı.'
                                  : 'Bu oyuna özel, bir kez +5.000 çip.',
                              style: const TextStyle(
                                color: _gold,
                                fontSize: 11,
                                height: 1.4,
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
          const SizedBox(height: 10),
          _DownloadButton(
            game: game,
            claimed: claimed,
            busy: busy,
            onTap: onDownload,
          ),
        ],
      ),
    );
  }
}

class _GameLogo extends StatelessWidget {
  final CrossPromoGame game;
  final IconData icon;
  const _GameLogo({required this.game, required this.icon});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Center(
      child: FractionallySizedBox(
        widthFactor: .84,
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: _GameArtwork(
              game: game,
              icon: icon,
              size: bounds.maxWidth * .32,
            ),
          ),
        ),
      ),
    ),
  );
}

class _GameArtwork extends StatelessWidget {
  final CrossPromoGame game;
  final IconData icon;
  final double size;
  const _GameArtwork({
    required this.game,
    required this.icon,
    required this.size,
  });
  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Icon(icon, color: _gold, size: size),
    );
    if (game.artworkUrl == null) return fallback;
    return Semantics(
      label: '${game.name} logosu',
      image: true,
      child: Image.network(
        game.artworkUrl!,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        frameBuilder: (_, child, frame, _) => frame == null ? fallback : child,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final CrossPromoGame game;
  final bool claimed, busy;
  final VoidCallback? onTap;
  const _DownloadButton({
    required this.game,
    required this.claimed,
    required this.busy,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    const shape = BeveledRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(8)),
    );
    return SizedBox(
      height: 48,
      child: ClipPath(
        clipper: const ShapeBorderClipper(shape: shape),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF6E5B8), Color(0xFFD1B16D), Color(0xFFAD8342)],
              stops: [0, .55, 1],
            ),
          ),
          child: TextButton(
            key: ValueKey('promo-download-${game.id}'),
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2A2315),
              disabledForegroundColor: const Color(0xFF4F4735),
              shape: shape,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF4F4735),
                      ),
                    )
                  else
                    Icon(
                      claimed
                          ? Icons.open_in_new_rounded
                          : Icons.download_rounded,
                      size: 21,
                    ),
                  const SizedBox(width: 10),
                  Text(
                    busy
                        ? 'AÇILIYOR…'
                        : claimed
                        ? 'MAĞAZADA AÇ'
                        : 'İndir & +5.000 Çip Kazan',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
