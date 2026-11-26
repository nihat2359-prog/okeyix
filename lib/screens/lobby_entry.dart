import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/lobby_data_cache.dart';
import 'login_screen.dart';
import 'lobby_screen.dart';
import '../ui/lobby/lobby_entrance.dart';
import '../ui/lobby/lobby_league_list.dart';

class LobbyEntry extends StatefulWidget {
  const LobbyEntry({super.key});
  @override
  State<LobbyEntry> createState() => _LobbyEntryState();
}

class _LobbyEntryState extends State<LobbyEntry> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  Future<void> _enter() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Future.wait<void>([
            LobbyDataCache.prepare(client, uid),
            precacheImage(
              const AssetImage('assets/images/lobby/lobby.png'),
              context,
            ),
            for (final asset in LeagueEmblem.assets)
              precacheImage(
                ResizeImage(AssetImage(asset), width: 256),
                context,
              ),
          ])
          .then<void>((_) {})
          .timeout(const Duration(milliseconds: 1200), onTimeout: () {});
    } catch (_) {
      // Optional local storage must not prevent entry to the lobby.
    }
    if (!mounted || client.auth.currentUser?.id != uid) return;
    Navigator.of(context).pushReplacement(
      lobbyCinemaRoute(
        login: const LoginScreen(preparingLobby: true),
        lobby: const LobbyScreen(),
        reducedMotion: MediaQuery.disableAnimationsOf(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const LoginScreen(preparingLobby: true);
}
