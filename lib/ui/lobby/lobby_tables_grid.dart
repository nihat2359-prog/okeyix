import 'package:flutter/material.dart';
import 'package:okeyix/core/format.dart';
import 'lobby_table_card.dart';
import 'lobby_shimmer_loaders.dart';

class LobbyTablesGrid extends StatelessWidget {
  final List<Map<String, dynamic>> tables;
  final bool loading;
  final Set<String> blockedUserIds;

  final Function(Map<String, dynamic>) onJoin;
  final Function(Map<String, dynamic>) onSpectate;
  final bool canSpectateAll;
  final Function(Map<String, dynamic>) onUserTap;
  final Future<void> Function() onRefresh;

  static void _defaultOnSpectate(Map<String, dynamic> _) {}

  const LobbyTablesGrid({
    super.key,
    required this.tables,
    required this.loading,
    required this.blockedUserIds,
    required this.onJoin,
    this.onSpectate = _defaultOnSpectate,
    this.canSpectateAll = false,
    required this.onUserTap,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (tables.isEmpty) {
      return const Center(child: LobbyLoading());
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.all(12),

        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.32,
        ),

        itemCount: tables.length,

        itemBuilder: (context, i) {},
      ),
    );
  }
}
