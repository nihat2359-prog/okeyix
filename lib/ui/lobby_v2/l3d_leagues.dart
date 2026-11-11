import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/ui/lobby/lobby_shimmer_loaders.dart';
import 'l3d_theme.dart';

/// Five holographic league cards in the fixed 2–2–1 arrangement. The wall
/// faces the tables (slight Y rotation); the selected card lifts toward the
/// camera. Never scrolls and never collapses to one column.
class L3dLeagueWall extends StatelessWidget {
  final List<Map<String, dynamic>> leagues;
  final dynamic selectedLeagueId;
  final Map<String, int> leagueActivePlayers, leagueActiveTables;
  final int userCoin, userRating;
  final bool loading;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const L3dLeagueWall({
    super.key,
    required this.leagues,
    required this.selectedLeagueId,
    required this.leagueActivePlayers,
    required this.leagueActiveTables,
    required this.userCoin,
    required this.userRating,
    required this.loading,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) return const LobbyLoading();
    if (leagues.isEmpty) {
      return const Center(child: Text('Ligler yüklenemedi', style: TextStyle(color: L3d.soft, fontSize: 13)));
    }
    return LayoutBuilder(builder: (context, bounds) {
      final gap = (bounds.maxHeight * .04).clamp(5.0, 10.0);
      Widget slot(int i, {required double rotY, bool wide = false}) => Expanded(
        child: i < leagues.length
            ? L3dLeagueCard(
                key: ValueKey('v2-league-${leagues[i]['id']}'),
                league: leagues[i],
                index: i,
                wide: wide,
                rotY: rotY,
                selected: leagues[i]['id'] == selectedLeagueId,
                players: leagueActivePlayers[leagues[i]['id']] ?? 0,
                tables: leagueActiveTables[leagues[i]['id']] ?? 0,
                userCoin: userCoin,
                userRating: userRating,
                onTap: () => onSelect(Map<String, dynamic>.from(leagues[i])),
              )
            : const SizedBox.shrink(),
      );
      return Column(children: [
        Expanded(child: Row(children: [slot(0, rotY: .16), SizedBox(width: gap), slot(1, rotY: .10)])),
        SizedBox(height: gap),
        Expanded(child: Row(children: [slot(2, rotY: .16), SizedBox(width: gap), slot(3, rotY: .10)])),
        SizedBox(height: gap),
        Expanded(child: Row(children: [slot(4, rotY: .08, wide: true)])),
      ]);
    });
  }
}

class L3dLeagueCard extends StatefulWidget {
  final Map<String, dynamic> league;
  final int index, players, tables, userCoin, userRating;
  final bool wide, selected;
  final double rotY;
  final VoidCallback onTap;

  const L3dLeagueCard({
    super.key,
    required this.league,
    required this.index,
    required this.wide,
    required this.rotY,
    required this.selected,
    required this.players,
    required this.tables,
    required this.userCoin,
    required this.userRating,
    required this.onTap,
  });

  @override
  State<L3dLeagueCard> createState() => _L3dLeagueCardState();
}

class _L3dLeagueCardState extends State<L3dLeagueCard> with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool _down = false;

  int get _minCoin => (widget.league['min_coin'] as num?)?.toInt() ?? 0;
  int get _minRating => (widget.league['min_rating'] as num?)?.toInt() ?? 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFloat();
  }

  @override
  void didUpdateWidget(L3dLeagueCard old) {
    super.didUpdateWidget(old);
    _syncFloat();
  }

  /// Only the selected trophy hovers, and only when motion is allowed.
  void _syncFloat() {
    final animate = widget.selected && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_float.isAnimating) {
      _float.repeat();
    } else if (!animate && _float.isAnimating) {
      _float
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final art = L3dLeagueArt.of(widget.league, widget.index);
    final name = L3d.upper(widget.league['name']?.toString() ?? '');
    final unlocked = widget.userCoin >= _minCoin && widget.userRating >= _minRating;
    final selected = widget.selected;
    final tint = unlocked ? art.tint : const Color(0xFF8A93AA);

    return Semantics(
      button: true,
      selected: selected,
      label: '${widget.league['name']}, ${widget.players} oyuncu, ${widget.tables} masa, ${unlocked ? 'açık' : 'kilitli'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          // Too small to lay out text beside the trophy without negative sizes.
          if (w < 60 || h < 24) return const SizedBox.expand();
          // Narrow cards shrink the trophy so the league name stays legible.
          final cupH = math.min(h * (widget.wide ? 1.0 : .96), w * (widget.wide ? .30 : .50) / .86);
          final cupW = cupH * .86;
          final textLeft = widget.wide ? w * .06 + cupW * 1.0 : cupW * .86;
          return TweenAnimationBuilder<double>(
            tween: Tween(end: selected ? 1 : 0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            builder: (context, lift, child) => Transform(
              alignment: Alignment.center,
              transform: L3d.camera(rotX: .05, rotY: widget.rotY * (1 - lift), depth: lift * 38 - (_down ? 16 : 0) - 20),
              child: child,
            ),
            child: Stack(clipBehavior: Clip.none, children: [
              // Card body.
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: const Color(0xAA000000), blurRadius: selected ? 22 : 12, offset: Offset(0, selected ? 12 : 6)),
                      if (selected) BoxShadow(color: tint.withValues(alpha: .55), blurRadius: 24, spreadRadius: -2),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(fit: StackFit.expand, children: [
                      ColorFiltered(
                        colorFilter: unlocked
                            ? const ColorFilter.mode(Color(0x00000000), BlendMode.dst)
                            : L3d.desaturate,
                        child: Image.asset(
                          art.background,
                          fit: BoxFit.cover,
                          alignment: Alignment.centerRight,
                          filterQuality: FilterQuality.medium,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => ColoredBox(color: tint.withValues(alpha: .3)),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              tint.withValues(alpha: selected ? .40 : .22),
                              const Color(0x660A0F24),
                              const Color(0xE6060914),
                            ],
                            stops: const [0, .5, 1],
                          ),
                        ),
                      ),
                      // Specular sheen across the glass.
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-1, -1),
                            end: Alignment(.2, .3),
                            colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
                          ),
                        ),
                      ),
                      CustomPaint(painter: _RimPainter(tint, selected)),
                    ]),
                  ),
                ),
              ),
              // Floor glow under the trophy.
              Positioned(
                left: (widget.wide ? w * .06 : 0) + cupW * .12,
                width: cupW * .76,
                bottom: h * .04,
                height: h * .16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(Radius.elliptical(100, 30)),
                    gradient: RadialGradient(colors: [tint.withValues(alpha: unlocked ? .55 : .2), tint.withValues(alpha: 0)]),
                  ),
                ),
              ),
              // Floating trophy, breaking the card's top edge.
              AnimatedBuilder(
                animation: _float,
                builder: (context, child) => Positioned(
                  left: widget.wide ? w * .06 : -h * .02,
                  bottom: h * .10 + math.sin(_float.value * math.pi * 2) * h * .04,
                  width: cupW,
                  height: cupH,
                  child: child!,
                ),
                child: IgnorePointer(
                  child: Opacity(
                    opacity: unlocked ? 1 : .55,
                    child: ColorFiltered(
                      colorFilter: unlocked ? const ColorFilter.mode(Color(0x00000000), BlendMode.dst) : L3d.desaturate,
                      child: Image.asset(
                        art.trophy,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: textLeft,
                right: 8,
                top: h * .12,
                bottom: h * .10,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 5,
                    child: L3dFit(
                      name,
                      alignment: Alignment.centerLeft,
                      style: TextStyle(
                        color: unlocked ? L3d.white : const Color(0xFFB9C0D2),
                        fontSize: widget.wide ? 24 : 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        height: 1,
                        shadows: [
                          ...L3d.shadow,
                          if (unlocked) Shadow(color: tint.withValues(alpha: .8), blurRadius: 14),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: h * .04),
                  Expanded(
                    flex: 4,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: unlocked ? _stats(tint) : _requirement(),
                    ),
                  ),
                ]),
              ),
              if (selected || !unlocked)
                Positioned(
                  right: 7,
                  top: 6,
                  child: Container(
                    width: (h * .24).clamp(16.0, 22.0),
                    height: (h * .24).clamp(16.0, 22.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? tint : const Color(0xCC1A2138),
                      border: Border.all(color: Colors.white.withValues(alpha: .7), width: 1.2),
                      boxShadow: [if (selected) BoxShadow(color: tint, blurRadius: 10)],
                    ),
                    child: Icon(
                      selected ? Icons.check_rounded : Icons.lock_rounded,
                      size: (h * .16).clamp(11.0, 15.0),
                      color: selected ? const Color(0xFF0A0F24) : Colors.white,
                    ),
                  ),
                ),
            ]),
          );
        }),
      ),
    );
  }

  Widget _stats(Color tint) => Row(mainAxisSize: MainAxisSize.min, children: [
    _Chip(Icons.person_rounded, '${widget.players}', tint),
    const SizedBox(width: 4),
    _Chip(Icons.table_restaurant_rounded, '${widget.tables}', tint),
  ]);

  Widget _requirement() => Row(mainAxisSize: MainAxisSize.min, children: [
    _Chip(Icons.monetization_on_rounded, Format.coin(_minCoin), widget.userCoin >= _minCoin ? L3d.green : L3d.amber),
    const SizedBox(width: 4),
    _Chip(Icons.star_rounded, 'Sv ${Format.ratingLevel(_minRating)}', widget.userRating >= _minRating ? L3d.green : L3d.amber),
  ]);
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color tint;
  const _Chip(this.icon, this.text, this.tint);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0x99060914),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: tint.withValues(alpha: .6), width: 1),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: tint),
      const SizedBox(width: 3),
      Text(text,
          style: const TextStyle(
            color: L3d.white,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          )),
    ]),
  );
}

class _RimPainter extends CustomPainter {
  final Color tint;
  final bool selected;
  const _RimPainter(this.tint, this.selected);

  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius((Offset.zero & s).deflate(.75), const Radius.circular(15.25));
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2 : 1.2
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: .75),
            tint.withValues(alpha: selected ? 1 : .55),
            tint.withValues(alpha: .1),
          ],
        ).createShader(Offset.zero & s),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.tint != tint || old.selected != selected;
}
