import 'package:flutter/material.dart';
import 'lobby_table_card.dart';

class LobbyCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> tables;
  final Set<String> blockedUserIds;
  final Function(Map<String, dynamic>) onJoin;
  final Function(Map<String, dynamic>) onUserTap;

  const LobbyCarousel({
    super.key,
    required this.tables,
    required this.blockedUserIds,
    required this.onJoin,
    required this.onUserTap,
  });

  @override
  State<LobbyCarousel> createState() => _LobbyCarouselState();
}

class _LobbyCarouselState extends State<LobbyCarousel> {
  final PageController _controller = PageController(viewportFraction: 0.72);
  double _page = 0;

  @override
  void initState() {
    super.initState();

    _controller.addListener(() {
      setState(() {
        _page = _controller.page ?? 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      itemCount: widget.tables.length,
      itemBuilder: (context, index) {
        final diff = (_page - index);
        final scale = (1 - (diff.abs() * 0.2)).clamp(0.75, 1.0);
        final opacity = (1 - (diff.abs() * 0.5)).clamp(0.4, 1.0);

        return Center(
          child: Transform.scale(
            scale: scale,
            child: Opacity(
              opacity: opacity,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: LobbyTableCard(
                  table: widget.tables[index],
                  blockedUserIds: widget.blockedUserIds,
                  onJoin: widget.onJoin,
                  onUserTap: widget.onUserTap,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
