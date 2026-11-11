import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../dev/pisti/pisti_cards.dart';
import '../dev/pisti/pisti_model.dart';
import 'lobby/lobby_metal_surface.dart';

const worldGold = Color(0xFFE5C586);
const worldPaper = Color(0xFFF5EFE2);

/// Scoped to the game centre and Pişti chrome; existing Okey widgets keep their theme.
ThemeData gameWorldTheme(BuildContext context) => Theme.of(context).copyWith(
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: worldGold,
    secondary: worldGold,
    surface: Color(0xFF10231B),
    onSurface: worldPaper,
    onPrimary: Color(0xFF211F19),
  ),
  textTheme: ThemeData.dark().textTheme.apply(
    fontFamily: 'Montserrat',
    bodyColor: worldPaper,
    displayColor: worldPaper,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: worldGold,
      foregroundColor: const Color(0xFF211F19),
      minimumSize: const Size(48, 42),
      textStyle: const TextStyle(
        fontFamily: 'Montserrat',
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: worldGold,
      minimumSize: const Size(48, 42),
      side: const BorderSide(color: Color(0x887C7057)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(foregroundColor: worldGold),
  ),
  iconTheme: const IconThemeData(color: worldGold),
  listTileTheme: const ListTileThemeData(
    textColor: worldPaper,
    iconColor: worldGold,
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    titleTextStyle: TextStyle(
      color: worldPaper,
      fontFamily: 'Montserrat',
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
    subtitleTextStyle: TextStyle(
      color: Color(0xFFB9C5BC),
      fontFamily: 'Montserrat',
      fontSize: 11,
      height: 1.4,
    ),
  ),
  chipTheme: ChipThemeData(
    selectedColor: const Color(0xFF665637),
    backgroundColor: const Color(0xFF14271F),
    labelStyle: const TextStyle(
      color: worldPaper,
      fontFamily: 'Montserrat',
      fontSize: 12,
    ),
    side: const BorderSide(color: Color(0x667C7057)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0x88040D09),
    hintStyle: const TextStyle(color: Colors.white54, fontSize: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0x667C7057)),
    ),
  ),
);

class GameWorldBackdrop extends StatelessWidget {
  const GameWorldBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: Image.asset('assets/images/lobby/lobby.png', fit: BoxFit.cover),
      ),
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB3081514), Color(0xD305110C)],
            ),
          ),
        ),
      ),
      child,
    ],
  );
}

class GameTray extends StatelessWidget {
  const GameTray({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xF0192C23), Color(0xF008140E)],
      ),
      boxShadow: const [
        BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, 6)),
      ],
    ),
    child: LobbyMetalSurface(radius: 18, padding: padding, child: child),
  );
}

/// Every app window shares the same felt tray, bounded content and visible actions.
class GameWindow extends StatelessWidget {
  const GameWindow({
    super.key,
    this.title,
    this.content,
    this.actions = const [],
    this.child,
    this.insetPadding = const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 12,
    ),
  });
  final Widget? title, content, child;
  final List<Widget> actions;
  final EdgeInsets insetPadding;
  @override
  Widget build(BuildContext context) => Theme(
    data: gameWorldTheme(context),
    child: Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: insetPadding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 740,
          maxHeight: math.max(
            100,
            MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                32,
          ),
        ),
        child: GameTray(
          child:
              child ??
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.style_rounded, size: 23),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            color: worldPaper,
                            fontFamily: 'Montserrat',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          child: title ?? const SizedBox(),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0x447C7057)),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: content ?? const SizedBox(),
                    ),
                  ),
                  if (actions.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: actions,
                      ),
                    ),
                ],
              ),
        ),
      ),
    ),
  );
}

class GameEmptyState extends StatelessWidget {
  const GameEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.style_rounded,
    this.action,
  });
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: worldGold),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFB9C5BC),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            if (action != null)
              Padding(padding: const EdgeInsets.only(top: 10), child: action),
          ],
        ),
      ),
    ),
  );
}

enum GameArtKind { okey, pisti, rummy, batak, king }

/// Uses the real card artwork. Each game has a different hand and staging.
class GameArtwork extends StatelessWidget {
  const GameArtwork({super.key, required this.kind});
  final GameArtKind kind;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: LayoutBuilder(
      builder: (context, c) {
        final h = math.min(c.maxHeight * .77, c.maxWidth * .70);
        final cards = switch (kind) {
          GameArtKind.pisti => const [
            PistiCard(PistiSuit.clubs, 11),
            PistiCard(PistiSuit.hearts, 11),
          ],
          GameArtKind.rummy => const [
            PistiCard(PistiSuit.hearts, 7),
            PistiCard(PistiSuit.hearts, 8),
            PistiCard(PistiSuit.hearts, 9),
          ],
          GameArtKind.batak => const [
            PistiCard(PistiSuit.spades, 13),
            PistiCard(PistiSuit.spades, 12),
            PistiCard(PistiSuit.spades, 1),
          ],
          GameArtKind.king => const [
            PistiCard(PistiSuit.hearts, 12),
            PistiCard(PistiSuit.spades, 13),
          ],
          GameArtKind.okey => const <PistiCard>[],
        };
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: h * 1.8,
              height: h * .8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x3389A482), Colors.transparent],
                ),
              ),
            ),
            if (kind == GameArtKind.okey) ...[
              Positioned(
                bottom: c.maxHeight * .12,
                child: Container(
                  width: h * 1.6,
                  height: h * .14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFB7915B), Color(0xFF513A24)],
                    ),
                  ),
                ),
              ),
              for (var i = 0; i < 3; i++)
                Transform.translate(
                  offset: Offset((i - 1) * h * .43, -i * 3),
                  child: Transform.rotate(
                    angle: (i - 1) * .09,
                    child: Container(
                      width: h * .46,
                      height: h * .70,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0E9D8),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFBBAE95),
                          width: 2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            offset: Offset(2, 5),
                            blurRadius: 5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${[7, 8, 9][i]}',
                          style: TextStyle(
                            fontSize: h * .36,
                            fontWeight: FontWeight.w800,
                            color: i == 1
                                ? const Color(0xFFB72C2F)
                                : const Color(0xFF244D83),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ] else
              for (var i = 0; i < cards.length; i++)
                Transform.translate(
                  offset: Offset(
                    (i - (cards.length - 1) / 2) * h * .32,
                    (i - (cards.length - 1) / 2).abs() * 7,
                  ),
                  child: Transform.rotate(
                    angle:
                        (i - (cards.length - 1) / 2) *
                        (kind == GameArtKind.rummy ? .07 : .24),
                    child: SizedBox(
                      width: h * .69,
                      height: h,
                      child: PistiCardView(card: cards[i]),
                    ),
                  ),
                ),
            if (kind == GameArtKind.king)
              Positioned(
                top: 0,
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: worldGold,
                  size: h * .28,
                ),
              ),
          ],
        );
      },
    ),
  );
}
