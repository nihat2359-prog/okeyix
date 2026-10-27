import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'lobby/lobby_metal_surface.dart';
import 'package:okeyix/core/format.dart';
import 'package:okeyix/models/profile_statistics.dart';

class ProfileCardAction {
  const ProfileCardAction(
    this.icon, {
    required this.label,
    this.onPressed,
    this.color,
    this.secondary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  /// Administrative actions live in the menu, leaving room for social actions.
  final bool secondary;
}

class PlayerProfileCard extends StatefulWidget {
  const PlayerProfileCard({
    super.key,
    required this.userId,
    required this.username,
    required this.avatar,
    required this.rating,
    required this.coins,
    this.careerWins,
    this.careerLosses,
    required this.status,
    required this.statusColor,
    required this.actions,
    required this.loadStatistics,
    required this.onClose,
  });
  final String userId;
  final String username;
  final Widget avatar;
  final int rating;
  final int coins;
  final int? careerWins;
  final int? careerLosses;
  final String status;
  final Color statusColor;
  final List<ProfileCardAction> actions;
  final Future<ProfileStatistics> Function() loadStatistics;
  final VoidCallback onClose;

  @override
  State<PlayerProfileCard> createState() => _PlayerProfileCardState();
}

class _PlayerProfileCardState extends State<PlayerProfileCard> {
  static const gold = Color(0xFFE5C585);
  bool get _compact =>
      MediaQuery.sizeOf(context).height -
          MediaQuery.viewPaddingOf(context).vertical <
      380;
  late Future<ProfileStatistics> _statistics;
  void _load() {
    _statistics = Future.sync(widget.loadStatistics);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PlayerProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _load();
  }

  TextStyle _text(
    double size, {
    Color color = const Color(0xFFF5EFDF),
    FontWeight weight = FontWeight.w600,
  }) => TextStyle(fontSize: size, color: color, fontWeight: weight);

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    child: Container(
      constraints: const BoxConstraints(maxWidth: 610, maxHeight: 370),
      decoration: BoxDecoration(
        color: const Color(0x80141B23),
        borderRadius: BorderRadius.circular(24),
      ),
      child: LobbyMetalSurface(
        radius: 24,
        surfaceOpacity: 2.5,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _ProfileInlay()),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  _compact ? 7 : 12,
                  12,
                  _compact ? 6 : 10,
                ),
                child: Column(
                  children: [
                    _identity(),
                    SizedBox(height: _compact ? 5 : 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, bounds) => FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: bounds.maxWidth,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FutureBuilder<ProfileStatistics>(
                                  key: ValueKey('career-${widget.userId}'),
                                  future: _statistics,
                                  builder: (_, snapshot) => _career(
                                    snapshot.connectionState ==
                                            ConnectionState.done
                                        ? snapshot.data
                                        : null,
                                  ),
                                ),
                                SizedBox(height: _compact ? 5 : 10),
                                FutureBuilder<ProfileStatistics>(
                                  key: ValueKey(widget.userId),
                                  future: _statistics,
                                  builder: (context, snapshot) {
                                    final stats = snapshot.connectionState == ConnectionState.done
                                        ? snapshot.data : null;
                                    final totalWins = _displayedCareerWins(stats);
                                    final normalWins = stats == null ? null : math.max(0,
                                        (totalWins ?? stats.wins) - stats.okeyWins
                                        - stats.doubleWins + stats.okeyDoubleWins);
                                    return Column(
                                      children: [
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'GALİBİYETLER',
                                            style: _text(
                                              9,
                                              color: gold,
                                            ).copyWith(letterSpacing: 1.4),
                                          ),
                                        ),
                                        SizedBox(height: _compact ? 3 : 8),
                                        Row(
                                          children: [
                                            _winBadge(
                                              'Normal',
                                              normalWins,
                                              Icons.style_outlined,
                                              'Normal bitişle kazanılan eller.',
                                            ),
                                            _winBadge(
                                              'Okeyli',
                                              stats?.okeyWins,
                                              Icons.star_border_rounded,
                                              'Okeyli bitişler. Okeyli çift: ${stats?.okeyDoubleWins ?? '—'}; iki başlığa da dahildir.',
                                            ),
                                            _winBadge(
                                              'Çiftli',
                                              stats?.doubleWins,
                                              Icons.filter_2_outlined,
                                              'Çiftli bitişler. Okeyli çift: ${stats?.okeyDoubleWins ?? '—'}; iki başlığa da dahildir.',
                                            ),
                                          ],
                                        ),
                                        if (snapshot.hasError)
                                          Row(mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Flexible(child: Text('Bitiş kayıtları yüklenemedi',
                                                style: _text(10, color: Colors.white54))),
                                              TextButton(onPressed: () => setState(_load),
                                                child: Text('Tekrar dene', style: _text(10, color: gold))),
                                            ]),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: _compact ? 4 : 8),
                    _actions(),
                    SizedBox(height: _compact ? 2 : 5),
                    _playerId(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _playerId() => LayoutBuilder(
    builder: (context, bounds) {
      final base = _compact ? 7.0 : 8.0;
      final style = DefaultTextStyle.of(
        context,
      ).style.merge(_text(base, color: Colors.white38));
      final scale = MediaQuery.textScalerOf(context).scale(base) / base;
      final painter = TextPainter(
        text: TextSpan(text: 'ID: ${widget.userId}', style: style),
        textScaler: TextScaler.linear(scale),
        textDirection: TextDirection.ltr,
      )..layout();
      final fit = painter.width == 0
          ? 1.0
          : ((bounds.maxWidth - 8) / painter.width).clamp(0.0, 1.0);
      painter.dispose();
      return Align(
        alignment: Alignment.centerLeft,
        child: SelectableText(
          'ID: ${widget.userId}',
          maxLines: 1,
          style: style,
          textScaler: TextScaler.linear(scale * fit),
        ),
      );
    },
  );

  Widget _identity() => Row(
    children: [
      Container(
        width: _compact ? 44 : 58,
        height: _compact ? 44 : 58,
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [gold, Color(0xFF675537), gold]),
        ),
        child: ClipOval(
          child: ColoredBox(
            color: const Color(0x66151B22),
            child: widget.avatar,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(20, weight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: widget.statusColor.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: widget.statusColor.withValues(alpha: .35),
                ),
              ),
              child: Text(
                widget.status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _text(10, color: widget.statusColor),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      IconButton(
        tooltip: 'Kapat',
        onPressed: widget.onClose,
        style: IconButton.styleFrom(
          side: const BorderSide(color: Color(0x557E8581)),
        ),
        icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 21),
      ),
    ],
  );

  int? _displayedCareerWins(ProfileStatistics? stats) {
    if (stats == null) return widget.careerWins;
    final career = stats.hasCareerSnapshot
        ? stats.careerWins ?? widget.careerWins : widget.careerWins;
    return math.max(career ?? 0, stats.wins);
  }

  int? _displayedCareerLosses(ProfileStatistics? stats) {
    if (stats == null) return widget.careerLosses;
    final career = stats.hasCareerSnapshot
        ? stats.careerLosses ?? widget.careerLosses : widget.careerLosses;
    return math.max(career ?? 0, stats.losses);
  }

  Widget _career(ProfileStatistics? stats) => TweenAnimationBuilder<double>(
    key: ValueKey((widget.userId, _displayedCareerWins(stats),
      _displayedCareerLosses(stats), widget.coins, widget.rating)),
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : const Duration(milliseconds: 650),
    curve: Curves.easeOutCubic,
    builder: (_, value, __) => _careerContent(stats, value),
  );

  Widget _careerContent(ProfileStatistics? stats, double animation) {
    final wins = _displayedCareerWins(stats);
    final losses = _displayedCareerLosses(stats);
    final total = wins != null && losses != null ? wins + losses : null;
    final rate = total == null
        ? null
        : total == 0
        ? 0.0
        : wins! * 100 / total;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0x3310161C),
        border: Border.all(color: const Color(0x887D704B), width: .8),
      ),
      child: CustomPaint(
        painter: _ProfileChartGrid(height: _compact ? 55 : 75),
        child: Row(
        children: [
          SizedBox(
            width: 126,
            child: Column(
              children: [
                Container(
                  height: _compact ? 32 : 41,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0x99262D36),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x667D704B)),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: Format.ratingLevelProgress(
                            widget.rating,
                          ) * animation,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFF8B8151), Color(0xFFB1A369)],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Text(
                              'Seviye ${(Format.ratingLevel(widget.rating) * animation).round()}',
                              style: _text(16, weight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: _compact ? 32 : 41,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: const Color(0x6610161C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x557D704B)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.monetization_on_outlined,
                        color: gold,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            Format.balance((widget.coins * animation).round()),
                            style: _text(18, weight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _bar(
            'Galibiyet',
            wins == null ? '—' : '${(wins * animation).round()}',
            total == null || total == 0 ? 0 : wins! / total * animation,
            const Color(0xFF6DAC78),
          ),
          _bar(
            'Mağlubiyet',
            losses == null ? '—' : '${(losses * animation).round()}',
            total == null || total == 0 ? 0 : losses! / total * animation,
            const Color(0xFFBD7069),
          ),
          _bar(
            'Toplam',
            total == null ? '—' : '${(total * animation).round()}',
            total == null || total == 0 ? 0 : animation,
            gold,
          ),
          _bar(
            'Kazanma',
            rate == null ? '—' : '%${(rate * animation).toStringAsFixed(1)}',
            (rate ?? 0) / 100 * animation,
            gold,
          ),
        ],
        ),
      ),
    );
  }

  Widget _bar(String label, String value, double progress, Color color) =>
      Expanded(
        child: Column(
          children: [
            Semantics(
              label: '$label: $value',
              child: Container(
                width: 43,
                height: _compact ? 55 : 75,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: const Color(0x9910161C),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0x225D6A68)),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.bottomCenter,
                        heightFactor: progress.clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [color.withValues(alpha: .65), color],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 3,
                      left: 12,
                      right: 12,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: const Color(0x447D8781),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 3,
                      right: 3,
                      bottom: 7,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          value,
                          style: _text(
                            12,
                            weight: FontWeight.w800,
                            color: progress > .18
                                ? const Color(0xFF16221C)
                                : const Color(0xFFF5EFDF),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: _text(10, color: Colors.white60)),
              ),
            ),
          ],
        ),
      );

  Widget _detailMessage(String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(message, style: _text(11, color: Colors.white54)),
  );

  Widget _winBadge(String label, int? count, IconData icon, String help) =>
      Expanded(
        child: Tooltip(
          message: help,
          triggerMode: TooltipTriggerMode.tap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x222B333D),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: gold, size: 17),
                    const SizedBox(width: 4),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: (count ?? 0).toDouble()),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero : const Duration(milliseconds: 650),
                          curve: Curves.easeOutCubic,
                          builder: (_, value, __) => Text(
                          count == null ? '—' : '${value.round()}',
                          style: _text(
                            17,
                            color: gold,
                            weight: FontWeight.w800,
                          ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 10,
                      color: Colors.white38,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 26,
                  child: Center(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: _text(9, color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _actions() {
    // Keep up to five actions visible, including a future comparison action.
    // Larger action sets use a labelled menu without expanding the footer.
    final main = [
      ...widget.actions.where((a) => !a.secondary),
      ...widget.actions.where((a) => a.secondary),
    ].take(5).toList();
    final extra = widget.actions.where((a) => !main.contains(a)).toList();
    return LayoutBuilder(
      builder: (context, bounds) {
        final count = main.length + (extra.isEmpty ? 0 : 1);
        if (count == 0) return const SizedBox.shrink();
        final width = ((bounds.maxWidth - 7 * (count - 1)) / count).clamp(
          0.0,
          150.0,
        );
        Widget face(
          IconData icon,
          String label,
          Color? color, {
          bool enabled = true,
        }) => Container(
          width: width,
          height: _compact ? 42 : 48,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x55303943), Color(0x33161E27)],
            ),
            border: Border.all(color: const Color(0x667D704B), width: .7),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled ? color ?? gold : Colors.white38,
              ),
              const SizedBox(height: 2),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: _text(
                      10,
                      color: enabled ? const Color(0xFFE8DFCA) : Colors.white38,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (final action in main) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: action.onPressed,
                  child: face(
                    action.icon,
                    action.label,
                    action.color,
                    enabled: action.onPressed != null,
                  ),
                ),
              ),
              if (action != main.last || extra.isNotEmpty)
                const SizedBox(width: 7),
            ],
            if (extra.isNotEmpty)
              PopupMenuButton<ProfileCardAction>(
                tooltip: 'Diğer işlemler',
                padding: EdgeInsets.zero,
                color: const Color(0xFF182029),
                onSelected: (action) => action.onPressed?.call(),
                itemBuilder: (_) => [
                  for (final action in extra)
                    PopupMenuItem(
                      value: action,
                      enabled: action.onPressed != null,
                      child: Row(
                        children: [
                          Icon(
                            action.icon,
                            size: 18,
                            color: action.color ?? gold,
                          ),
                          const SizedBox(width: 10),
                          Text(action.label, style: _text(12)),
                        ],
                      ),
                    ),
                ],
                child: face(Icons.more_horiz_rounded, 'Diğer', gold),
              ),
          ],
        );
      },
    );
  }
}

class _ProfileChartGrid extends CustomPainter {
  final double height;
  const _ProfileChartGrid({required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    // Level and balance stay outside the graph; labels sit below its baseline.
    const left = 138.0;
    if (size.width <= left) return;
    final paint = Paint()..strokeWidth = .5;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(left, 0, size.width, height));
    for (var x = left; x <= size.width; x += 10) {
      paint.color = const Color(0x12FFFFFF);
      canvas.drawLine(Offset(x, 0), Offset(x, height), paint);
    }
    for (var y = 0.0; y <= height; y += 10) {
      paint.color = const Color(0x18FFFFFF);
      canvas.drawLine(Offset(left, y), Offset(size.width, y), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ProfileChartGrid oldDelegate) => oldDelegate.height != height;
}

/// Static table-style inlay: no blur, animation or image decoding per frame.
class _ProfileInlay extends CustomPainter {
  const _ProfileInlay();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x107B8794)
      ..strokeWidth = .6;
    for (double y = 7; y < size.height; y += 7) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y - size.width * .08),
        paint,
      );
    }
    paint
      ..color = const Color(0x3AAB8D53)
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset(5, 5) & Size(size.width - 10, size.height - 10),
        const Radius.circular(20),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProfileInlay oldDelegate) => false;
}
