// Browser-only regression fixture. No auth, game services or network data.
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:okeyix/ui/lobby/lobby_metal_surface.dart';
import 'package:okeyix/ui/lobby/lobby_bottom_dock.dart';
import 'package:okeyix/ui/lobby/create_table_scene.dart';

void main() => runApp(const MaterialApp(home: _Probe()));

class _Probe extends StatelessWidget {
  const _Probe();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      fit: StackFit.expand,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: ColoredBox(color: Color(0xFFFF0000))),
            Expanded(child: ColoredBox(color: Color(0xFF0000FF))),
          ],
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 20,
          height: 180,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: const LobbyMetalSurface(
                padding: EdgeInsets.all(12),
                child: Column(
                  children: [
                    Text(
                      'OUTER / NESTED GLASS',
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 12),
                    Expanded(
                      child: LobbyMetalSurface(child: SizedBox.expand()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          top: 230,
          width: 180,
          height: 44,
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierColor: const Color(0x33020507),
              builder: (context) => CreateTableScene(
                leagueName: 'GLASS TEST',
                stakes: const [1000, 2000, 4000],
                selectedIndex: 0,
                turnSeconds: 20,
                spectator: true,
                chat: true,
                canCreate: true,
                formatStake: (v) => '$v',
                onStake: (_) {},
                onSpeed: (_) {},
                onSpectator: () {},
                onChat: () {},
                onCreate: () {},
                onClose: () => Navigator.pop(context),
              ),
            ),
            child: const Text('OPEN', style: TextStyle(color: Colors.white)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: LobbyBottomDock(
            left: const SizedBox.shrink(),
            center: LobbyDockCreate(onTap: () {}),
            right: const SizedBox.shrink(),
          ),
        ),
      ],
    ),
  );
}
