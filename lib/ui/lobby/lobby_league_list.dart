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
    Color(0xFFD08B43),
    Color(0xFF9BC6E2),
    Color(0xFFEBC34D),
    Color(0xFFB56FE7),
    Color(0xFF4DD69C),
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

  Widget _card(Map<String, dynamic> league, int index, bool wide) {
    final metal = _metals[index], selected = league['id'] == selectedLeagueId;
    final unlocked =
        userCoin >= ((league['min_coin'] as num?)?.toInt() ?? 0) &&
        userRating >= ((league['min_rating'] as num?)?.toInt() ?? 0);
    return LayoutBuilder(
      builder: (context, box) {
        final cup = (box.maxHeight * .82).clamp(
          20.0,
          box.maxWidth * (wide ? 0.25 : 0.37),
        );
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
                          padding: const EdgeInsets.fromLTRB(9, 6, 30, 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: cup,
                                height: box.maxHeight - 12,
                                child: FractionallySizedBox(
                                  widthFactor: .96,
                                  heightFactor: .93,
                                  child: LeagueTrophy(index: index),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (selected) ...[
                                      Icon(
                                        Icons.check_circle_rounded,
                                        key: ValueKey(
                                          'selected-league-${league['id']}',
                                        ),
                                        size: 15,
                                        color: metal,
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          league['name']?.toString() ?? '',
                                          maxLines: 1,
                                          softWrap: false,
                                          style: TextStyle(
                                            color: const Color(0xFFFFF3DB),
                                            fontSize: wide ? 24 : 19,
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

/// Five transparent rendered trophies share one decoded texture.
class LeagueTrophy extends StatelessWidget {
  final int index;
  const LeagueTrophy({super.key, required this.index});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => ClipRect(
      child: OverflowBox(
        alignment: Alignment(-1 + index * .5, 0),
        minWidth: box.maxWidth * 5,
        maxWidth: box.maxWidth * 5,
        minHeight: box.maxHeight * 1.4,
        maxHeight: box.maxHeight * 1.4,
        child: Image.asset(
          'assets/images/lobby/leagues/trophy_atlas_v2.png',
          cacheWidth: 1536,
          width: box.maxWidth * 5,
          height: box.maxHeight * 1.4,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}
