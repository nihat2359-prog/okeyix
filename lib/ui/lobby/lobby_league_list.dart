import 'package:flutter/material.dart';
import 'lobby_shimmer_loaders.dart';
import 'lobby_metal_surface.dart';

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
    if (loading) return const LobbyLoading();
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
                            ? _card(
                                leagues[row * 2 + col],
                                row * 2 + col,
                                row == 2,
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
    final players = leagueActivePlayers[league['id']] ?? 0,
        tables = leagueActiveTables[league['id']] ?? 0;
    final unlocked =
        userCoin >= ((league['min_coin'] as num?)?.toInt() ?? 0) &&
        userRating >= ((league['min_rating'] as num?)?.toInt() ?? 0);
    return LayoutBuilder(
      builder: (context, box) {
        final cup = (box.maxHeight * .64).clamp(
          20.0,
          box.maxWidth * (wide ? 0.25 : 0.37),
        );
        return Semantics(
          selected: selected,
          button: true,
          label:
              '${league['name']}, $players oyuncu, $tables masa, ${unlocked ? 'Açık' : 'Kilitli'}',
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
                        ? BorderSide(color: metal, width: 2)
                        : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(17),
                    onTap: () => onSelect(Map<String, dynamic>.from(league)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: cup,
                            height: box.maxHeight - 12,
                            child: FractionallySizedBox(
                              widthFactor: .76,
                              heightFactor: .60,
                              child: LeagueTrophy(index: index),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Flexible(
                                  flex: 3,
                                  child: Row(
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
                                            style: TextStyle(
                                              color: const Color(0xFFFFF3DB),
                                              fontSize: wide ? 20 : 17,
                                              fontWeight: FontWeight.w700,
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
                                      if (!unlocked) ...[
                                        const SizedBox(width: 3),
                                        const Icon(
                                          Icons.lock_outline_rounded,
                                          size: 14,
                                          color: Color(0xFFB8BEC2),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Flexible(
                                  flex: 2,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.people_alt_outlined,
                                          size: 14,
                                          color: metal,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$players',
                                          style: const TextStyle(
                                            color: Color(0xFFD6D0C3),
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Icon(
                                          Icons.table_restaurant_outlined,
                                          size: 14,
                                          color: metal,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$tables',
                                          style: const TextStyle(
                                            color: Color(0xFFD6D0C3),
                                            fontSize: 12,
                                          ),
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
