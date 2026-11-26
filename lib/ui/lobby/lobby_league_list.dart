import 'package:flutter/material.dart';
import 'lobby_shimmer_loaders.dart';
import 'lobby_metal_surface.dart';
import 'lobby_entrance.dart';

class LobbyLeagueList extends StatelessWidget {
  final List<Map<String, dynamic>> leagues;
  final dynamic selectedLeagueId;
  final Map<String, int> leagueActivePlayers, leagueActiveTables;
  final Function(Map<String, dynamic>) onSelect;
  final int userCoin, userRating;
  final bool loading;
  const LobbyLeagueList({
    super.key,
    required this.leagues,
    required this.selectedLeagueId,
    required this.leagueActivePlayers,
    required this.leagueActiveTables,
    required this.onSelect,
    required this.userCoin,
    required this.userRating,
    required this.loading,
  });
  static const _metals = [
    Color(0xFFB18A60),
    Color(0xFFADB8BD),
    Color(0xFFD0B078),
    Color(0xFF9983AC),
    Color(0xFF73A68C),
  ];
  @override
  Widget build(BuildContext context) {
    if (loading) return const LobbyShimmer(child: LobbyLeagueSkeleton());
    if (leagues.isEmpty) {
      return const Center(
        child: Text(
          'No leagues available',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        final gap = (bounds.maxHeight * .027).clamp(4.0, 8.0);
        final cardHeight = (bounds.maxHeight - gap * 2) / 3;
        // The four compact cards share a size; the full-width final has emphasis.
        var labelSize = 19.0;
        var wideLabelSize = 24.0;
        final inheritedStyle = DefaultTextStyle.of(context).style;
        for (var i = 0; i < leagues.length && i < 5; i++) {
          final wide = i == 4;
          final width = wide ? bounds.maxWidth : (bounds.maxWidth - gap) / 2;
          final emblem = _emblemSize(width, cardHeight, wide);
          final available = (width - emblem - 27).clamp(1.0, double.infinity);
          final painter = TextPainter(
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          );
          var low = 1.0, high = wide ? wideLabelSize : labelSize;
          for (var step = 0; step < 12; step++) {
            final candidate = (low + high) / 2;
            painter.text = TextSpan(
              text: leagues[i]['name']?.toString() ?? '',
              style: inheritedStyle.copyWith(
                fontSize: candidate,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            );
            painter.layout();
            if (painter.width <= available &&
                painter.height <= cardHeight - 12) {
              low = candidate;
            } else {
              high = candidate;
            }
          }
          if (wide) {
            wideLabelSize = low;
          } else {
            labelSize = low;
          }
          painter.dispose();
        }
        return Column(
          children: [
            for (var row = 0; row < 3; row++) ...[
              if (row > 0) SizedBox(height: gap),
              Expanded(
                child: Row(
                  children: [
                    for (var col = 0; col < (row == 2 ? 1 : 2); col++) ...[
                      if (col > 0) SizedBox(width: gap),
                      Expanded(
                        child: row * 2 + col < leagues.length
                            ? LobbyEntrance(
                                key: ValueKey(
                                  'league-entrance-${leagues[row * 2 + col]['id']}',
                                ),
                                from: const Offset(-.07, 0),
                                delay: Duration(
                                  milliseconds: (row * 2 + col) * 40,
                                ),
                                child: _card(
                                  leagues[row * 2 + col],
                                  row * 2 + col,
                                  row == 2,
                                  row == 2 ? wideLabelSize : labelSize,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  static double _emblemSize(double width, double height, bool wide) =>
      (height * .72).clamp(20.0, width * (wide ? .25 : .32));

  Widget _card(
    Map<String, dynamic> league,
    int index,
    bool wide,
    double labelSize,
  ) {
    final metal = _metals[index], selected = league['id'] == selectedLeagueId;
    final unlocked =
        userCoin >= ((league['min_coin'] as num?)?.toInt() ?? 0) &&
        userRating >= ((league['min_rating'] as num?)?.toInt() ?? 0);
    return LayoutBuilder(
      builder: (context, box) {
        final emblem = _emblemSize(box.maxWidth, box.maxHeight, wide);
        return Semantics(
          selected: selected,
          button: true,
          label: '${league['name']}, ${unlocked ? 'Açık' : 'Kilitli'}',
          child: Tooltip(
            message: unlocked
                ? '${league['name']}'
                : 'Gereken: ${league['min_coin']} coin · ${league['min_rating']} puan',
            child: LobbyPlatePress(
              child: LobbyMetalSurface(
                metal: metal,
                selected: selected,
                surfaceOpacity: 1.35,
                child: Material(
                  key: ValueKey('league-${league['id']}'),
                  color: selected
                      ? metal.withValues(alpha: .18)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                    side: selected
                        ? const BorderSide(color: Color(0xFFF5CC7C), width: 1.4)
                        : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(17),
                    onTap: () => onSelect(Map<String, dynamic>.from(league)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(9, 6, 10, 6),
                          child: Row(
                            children: [
                              SizedBox.square(
                                dimension: emblem,
                                child: LeagueEmblem(index: index),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        league['name']?.toString() ?? '',
                                        maxLines: 1,
                                        softWrap: false,
                                        style: TextStyle(
                                          color: const Color(0xFFFFF3DB),
                                          fontSize: labelSize,
                                          fontWeight: FontWeight.w800,
                                          height: 1.15,
                                          shadows: const [
                                            Shadow(
                                              color: Colors.black,
                                              offset: Offset(0, 2),
                                              blurRadius: 2,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 9,
                          right: 11,
                          child: Tooltip(
                            message: 'Açık ve vitrin masa sayısı',
                            child: Container(
                              key: ValueKey(
                                'league-open-tables-${league['id']}',
                              ),
                              constraints: const BoxConstraints(minWidth: 20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Color.lerp(
                                  const Color(0xFF10191C),
                                  metal,
                                  .22,
                                ),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: metal.withValues(alpha: .7),
                                ),
                              ),
                              child: Text(
                                '${leagueActiveTables[league['id'].toString()] ?? 0}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: metal,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                ),
                              ),
                            ),
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
    );
  }
}

/// Matched metal medallions remain crisp without stretching or atlas cropping.
class LeagueEmblem extends StatelessWidget {
  final int index;
  const LeagueEmblem({super.key, required this.index});
  static const assets = [
    'assets/images/lobby/leagues/emblem_bronze_v1.png',
    'assets/images/lobby/leagues/emblem_silver_v1.png',
    'assets/images/lobby/leagues/emblem_gold_v1.png',
    'assets/images/lobby/leagues/emblem_amethyst_v1.png',
    'assets/images/lobby/leagues/emblem_emerald_v1.png',
  ];
  @override
  Widget build(BuildContext context) => Image.asset(
    assets[index],
    key: ValueKey('league-emblem-$index'),
    cacheWidth: 256,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    excludeFromSemantics: true,
  );
}
