import 'package:flutter/material.dart';
import 'lobby_table_card.dart';
import 'lobby_shimmer_loaders.dart';

class LobbyTableWheel extends StatefulWidget {
  final List<Map<String, dynamic>> tables;
  final Set<String> blockedUserIds;
  final Function(Map<String, dynamic>) onJoin;
  final Function(Map<String, dynamic>) onSpectate;
  final bool canSpectateAll;
  final Function(Map<String, dynamic>) onUserTap;
  final Future<void> Function() onRefresh;
  final bool loading;

  const LobbyTableWheel({
    super.key,
    required this.tables,
    required this.blockedUserIds,
    required this.onJoin,
    required this.onSpectate,
    required this.canSpectateAll,
    required this.onUserTap,
    required this.onRefresh,
    required this.loading,
  });

  @override
  State<LobbyTableWheel> createState() => _LobbyTableWheelState();
}

class _LobbyTableWheelState extends State<LobbyTableWheel> {
  int selectedIndex = 0;
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    /// 🔥 LOADING
    if (widget.loading) {
      return const Center(child: LobbyLoading());
    }

    /// 🔥 EMPTY
    if (widget.tables.isEmpty) {
      return const Center(
        child: Text(
          "Masa bulunmamaktadır.",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: widget.onRefresh,

      /// 🔥 KRİTİK: refresh için scrollable wrapper
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.85,

          child: ListWheelScrollView.useDelegate(
            controller: _controller,

            itemExtent: 200,

            /// 🔥 daha iyi his
            perspective: 0.003,
            diameterRatio: 2.2,
            squeeze: 1.1,

            physics: const FixedExtentScrollPhysics(),

            onSelectedItemChanged: (index) {
              setState(() {
                selectedIndex = index;
              });
            },

            childDelegate: ListWheelChildBuilderDelegate(
              childCount: widget.tables.length,
              builder: (context, index) {
                final table = widget.tables[index];
                final isSelected = index == selectedIndex;

                return Center(
                  child: Transform.scale(
                    scale: isSelected ? 0.92 : 0.75,
                    child: Opacity(
                      opacity: isSelected ? 1 : 0.5,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),

                        decoration: BoxDecoration(
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(0x66F2C14E),
                                    blurRadius: 35,
                                    spreadRadius: 3,
                                  ),
                                ]
                              : [],
                        ),

                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: LobbyTableCard(
                            table: table,
                            blockedUserIds: widget.blockedUserIds,
                            onJoin: widget.onJoin,
                            onSpectate: widget.onSpectate,
                            canSpectateAll: widget.canSpectateAll,
                            onUserTap: widget.onUserTap,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
