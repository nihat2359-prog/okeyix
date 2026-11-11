import 'dart:ui' show ImageFilter;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../game/components/finish_screen.dart';
import '../game/rack/tile_component.dart';

/// One foreground scene containing the winner and their complete finishing rack.
class SpectatorFinishNotice extends StatelessWidget {
  final String winnerName;
  final String? finishLabel;
  final List<Map<String, dynamic>> slots;
  final Map<String, dynamic> finishTile;
  final VoidCallback? onReady;
  const SpectatorFinishNotice({
    super.key,
    required this.winnerName,
    this.finishLabel,
    this.slots = const [],
    this.finishTile = const {},
    this.onReady,
  });

  @override
  Widget build(BuildContext context) => BlockSemantics(
    child: Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Center(
            child: LayoutBuilder(
              builder: (context, bounds) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (bounds.maxWidth * .82).clamp(0, 640),
                  maxHeight: bounds.maxHeight * .78,
                ),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    key: const ValueKey('spectator-finish-panel'),
                    width: 900,
                    height: 380,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: const Color(0x55FFFFFF),
                          width: 1,
                        ),
                        gradient: const RadialGradient(
                          center: Alignment(0, -.25),
                          radius: 1.1,
                          colors: [
                            Color(0xA62A2A2A),
                            Color(0xB3121212),
                            Color(0xBD060606),
                          ],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 40,
                            offset: Offset(0, 16),
                          ),
                          BoxShadow(
                            color: Color(0x12FFFFFF),
                            blurRadius: 24,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(29),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: 1.2,
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    32,
                                    14,
                                    32,
                                    8,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFFDAC18A),
                                          ),
                                          gradient: const LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFF6C5B32),
                                              Color(0xFF272E20),
                                            ],
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.emoji_events_rounded,
                                          color: Color(0xFFFFDF96),
                                          size: 38,
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'ELİN KAZANANI',
                                              style: TextStyle(
                                                color: Color(0xFFD9BE80),
                                                fontSize: 12,
                                                letterSpacing: 2.8,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 5),
                                            Text(
                                              winnerName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFFFFF4D9),
                                                fontSize: 28,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0x332A1710),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: const Color(0x667EAD91),
                                          ),
                                        ),
                                        child: Text(
                                          finishLabel ?? 'Bu eli kazandı',
                                          style: const TextStyle(
                                            color: Color(0xFFE9D8AD),
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  height: 1,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 30,
                                  ),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0x00CBAE71),
                                        Color(0x88CBAE71),
                                        Color(0x00CBAE71),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: slots.isEmpty
                                      ? const Center(
                                          child: Text(
                                            'Kazanan el hazırlanıyor…',
                                            style: TextStyle(
                                              color: Color(0xFFCCD6CC),
                                              fontSize: 18,
                                            ),
                                          ),
                                        )
                                      : _RackPreview(
                                          slots: slots,
                                          finishTile: finishTile,
                                          winnerName: winnerName,
                                          onReady: onReady,
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
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RackPreview extends StatefulWidget {
  final List<Map<String, dynamic>> slots;
  final Map<String, dynamic> finishTile;
  final String winnerName;
  final VoidCallback? onReady;
  const _RackPreview({
    required this.slots,
    required this.finishTile,
    required this.winnerName,
    this.onReady,
  });
  @override
  State<_RackPreview> createState() => _RackPreviewState();
}

class _RackPreviewState extends State<_RackPreview> {
  late final _FinishRackGame game = _FinishRackGame(
    widget.slots,
    widget.finishTile,
    widget.winnerName,
    () => WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call();
    }),
  );
  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: GameWidget(game: game));
}

class _FinishRackGame extends FlameGame {
  final List<Map<String, dynamic>> slots;
  final Map<String, dynamic> finishTile;
  final String winnerName;
  final VoidCallback onReady;
  FinishRackView? _view;
  bool _readyReported = false;
  _FinishRackGame(this.slots, this.finishTile, this.winnerName, this.onReady)
    : super(
        camera: CameraComponent.withFixedResolution(width: 1000, height: 360),
      );
  @override
  Color backgroundColor() => Colors.transparent;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final view = FinishRackView(
      List<Map<String, dynamic>>.from(slots),
      finishTile,
      winnerName,
      false,
      true,
      0,
      false,
      false,
      viewportSize: Vector2(1000, 360),
      rackOnly: true,
    );
    _view = view;
    await camera.viewport.add(view);
  }

  @override
  void update(double dt) {
    super.update(dt);
    final view = _view;
    if (_readyReported || view == null || !view.isMounted) return;
    if (view.rack.children.whereType<TileComponent>().length != slots.length)
      return;
    if (view.descendants().whereType<TileComponent>().any(
      (tile) => !tile.isMounted,
    ))
      return;
    _readyReported = true;
    onReady();
  }
}
