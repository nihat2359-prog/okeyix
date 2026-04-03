import 'dart:async';
import 'package:flutter/material.dart';
import '../models/player_model.dart';
import 'avatar_card.dart';
import 'menu_panel.dart';
import 'chat_panel.dart';
import 'rack_action_buttons.dart';
import 'top_coin_button.dart';

class GameUiLayer extends StatefulWidget {
  const GameUiLayer({super.key});

  @override
  State<GameUiLayer> createState() => _GameUiLayerState();
}

class _GameUiLayerState extends State<GameUiLayer> {
  final List<PlayerModel> players = [];

  bool isMenuOpen = false;
  bool isChatOpen = false;

  Timer? _timer;

  @override
  void initState() {
    super.initState();

    players.addAll([
      PlayerModel(
        id: "you",
        name: "You",
        avatarPath: "assets/images/m1.png",
        coins: 12450,
        isActive: true,
      ),
      PlayerModel(
        id: "p2",
        name: "Alex",
        avatarPath: "assets/images/m2.png",
        coins: 8700,
      ),
      PlayerModel(
        id: "p3",
        name: "Murat",
        avatarPath: "assets/images/m3.png",
        coins: 15600,
      ),
      PlayerModel(
        id: "p4",
        name: "Elif",
        avatarPath: "assets/images/m4.png",
        coins: 9400,
      ),
    ]);
    startTurn(players[0]);
  }

  void startTurn(PlayerModel player) {
    player.remainingTime = 15;

    _timer?.cancel();

    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        player.remainingTime -= 0.1;

        if (player.remainingTime <= 0) {
          timer.cancel();
          handleTimeout(player);
        }
      });
    });
  }

  void handleTimeout(PlayerModel player) {
    // buraya game engine auto draw + discard bağlayacağız
    debugPrint("Timeout: ${player.name}");
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ..._buildAvatars(),
        _buildMenuButton(),
        _buildChatButton(),
        MenuPanel(
          isOpen: isMenuOpen,
          onClose: () => setState(() => isMenuOpen = false),
          onExit: () {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: const Color(0xFF141A20),
                title: const Text("Masadan Çık"),
                content: const Text(
                  "Masadan çıkmak istediğinize emin misiniz?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("İptal"),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      debugPrint("Çıkıldı");
                    },
                    child: const Text("Çık"),
                  ),
                ],
              ),
            );
          },
          onSettings: () {
            debugPrint("Ayarlar");
          },
        ),

        Positioned(
          bottom: 100, // rack hizasına göre ayarla
          right: 35,
          child: RackActionButtons(
            onSelected: (index) {
              if (index == 0) {
                debugPrint("Seri Diz");
              } else if (index == 1) {
                debugPrint("Çift Diz");
              } else if (index == 2) {
                debugPrint("Çifte Git");
              }
            },
          ),
        ),
        Positioned(
          top: 40,
          right: 100,
          child: TopCoinButton(
            onTap: () {
              debugPrint("Coin Al Tıklandı");
            },
          ),
        ),
        ChatPanel(
          isOpen: isChatOpen,
          onClose: () => setState(() => isChatOpen = false),
        ),
      ],
    );
  }

  List<Widget> _buildAvatars() {
    final screenHeight = MediaQuery.of(context).size.height;

    if (players.length == 4) {
      return [
        // BOTTOM (YOU)
        Positioned(
          bottom: 190,
          left: 0,
          right: 0,
          child: Center(
            child: AvatarCard(
              player: players[0],
              position: AvatarPosition.bottom,
            ),
          ),
        ),

        // LEFT (ORTALI DİKEY)
        Positioned(
          left: 60,
          top: screenHeight / 2 - 100, // dikey ortalama
          child: AvatarCard(player: players[1], position: AvatarPosition.left),
        ),

        // TOP
        Positioned(
          top: 50,
          left: 0,
          right: 0,
          child: Center(
            child: AvatarCard(player: players[2], position: AvatarPosition.top),
          ),
        ),

        // RIGHT (ORTALI DİKEY)
        Positioned(
          right: 60,
          top: screenHeight / 2 - 100,
          child: AvatarCard(player: players[3], position: AvatarPosition.right),
        ),
      ];
    }

    if (players.length == 2) {
      return [
        Positioned(
          bottom: 190,
          left: 0,
          right: 0,
          child: Center(
            child: AvatarCard(
              player: players[0],
              position: AvatarPosition.bottom,
            ),
          ),
        ),
        Positioned(
          top: 20,
          left: 0,
          right: 0,
          child: Center(
            child: AvatarCard(player: players[1], position: AvatarPosition.top),
          ),
        ),
      ];
    }

    return [];
  }

  Widget _buildMenuButton() {
    return Positioned(
      top: 40,
      left: 30,
      child: _circleButton(Icons.menu, () => setState(() => isMenuOpen = true)),
    );
  }

  Widget _buildChatButton() {
    return Positioned(
      top: 40,
      right: 30,
      child: _circleButton(
        Icons.chat_bubble_outline,
        () => setState(() => isChatOpen = true),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 42,
        width: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0x66141A20), Color(0x33141A20)],
          ),
          border: Border.all(color: const Color(0x55D4AF37), width: 1),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)],
        ),
        child: Icon(icon, size: 18, color: const Color(0xFFD4AF37)),
      ),
    );
  }
}
