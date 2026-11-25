import 'package:flutter/material.dart';
import 'lobby_columns.dart';

/// One subdued sweep, shared by all placeholders in the opening scene.
class LobbyShimmer extends StatefulWidget {
  final Widget child;
  const LobbyShimmer({super.key, required this.child});
  @override
  State<LobbyShimmer> createState() => _LobbyShimmerState();
}

class _LobbyShimmerState extends State<LobbyShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _sweep.stop();
    } else {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: _sweep,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment(-3 + _sweep.value * 6, -.3),
          end: Alignment(-1 + _sweep.value * 6, .3),
          colors: const [
            Color(0x00E6D1A1),
            Color(0x33E6D1A1),
            Color(0x00E6D1A1),
          ],
          stops: const [0, .5, 1],
        ).createShader(bounds),
        child: child,
      ),
    ),
  );
}

class LobbySkeletonCard extends StatelessWidget {
  const LobbySkeletonCard({super.key});
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0x30263337),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0x447F765A)),
    ),
    child: const SizedBox.expand(),
  );
}

class LobbyLeagueSkeleton extends StatelessWidget {
  const LobbyLeagueSkeleton({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var row = 0; row < 3; row++) ...[
        if (row > 0) const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              for (var col = 0; col < (row == 2 ? 1 : 2); col++) ...[
                if (col > 0) const SizedBox(width: 6),
                Expanded(
                  child: LobbySkeletonCard(
                    key: ValueKey('league-skeleton-${row * 2 + col}'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ],
  );
}

class LobbyCardsReveal extends StatelessWidget {
  final bool ready;
  final Widget child;
  const LobbyCardsReveal({super.key, required this.ready, required this.child});
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240),
    switchInCurve: Curves.easeOutCubic,
    child: KeyedSubtree(
      key: ValueKey(ready),
      child: ready
          ? child
          : const LobbyShimmer(
              child: LobbyColumns(
                leagues: Padding(
                  padding: EdgeInsets.fromLTRB(9, 38, 9, 8),
                  child: LobbyLeagueSkeleton(),
                ),
                tables: Padding(
                  padding: EdgeInsets.all(9),
                  child: LobbySkeletonCard(),
                ),
              ),
            ),
    ),
  );
}

/// Small placeholders for secondary refreshes; never an opening spinner.
class LobbyLoading extends StatelessWidget {
  const LobbyLoading({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 160,
    height: 64,
    child: LobbyShimmer(child: LobbySkeletonCard()),
  );
}
