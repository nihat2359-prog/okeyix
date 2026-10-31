import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/screens/pisti_lobby_screen.dart';
import 'package:okeyix/screens/pisti_table_screen.dart';
import 'pisti_online_test.dart' as fixtures;

class BreakService extends fixtures.FakePistiService {
  BreakService({this.invited = false}) {
    data['room']['casual'] = true;
    data['room']['entry_coin'] = 0;
    data['room']['seats'][1]['bot'] = !invited;
  }
  final bool invited;
  @override
  Future<Map<String, dynamic>> lobby() async => {
    ...await super.lobby(),
    'invites': [
      if (invited) {'id': 'direct-invite', 'table_id': 'local-room'},
    ],
  };
  @override
  Future<Map<String, dynamic>> command(
    String action,
    Map<String, dynamic> args, {
    String? request,
  }) async {
    if (action == 'forfeit') {
      data = fixtures.fixture(status: 'finished');
      data['room']['casual'] = true;
      data['room']['entry_coin'] = 0;
    }
    return super.command(action, args, request: request);
  }
}

void main() {
  for (final invited in [false, true]) {
    testWidgets(
      invited
          ? 'direct friend invite accepts into match and exits to Okey'
          : 'bot break has no setup and exits directly to Okey',
      (tester) async {
        tester.view.physicalSize = const Size(568, 280);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = BreakService(invited: invited);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Okey lobisi'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PistiLobbyScreen(
                        service: service,
                        initialInviteId: invited ? 'direct-invite' : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Okey lobisi'));
        await tester.pumpAndSettle();
        if (invited) {
          expect(find.text('Katıl'), findsOneWidget);
          await tester.tap(find.text('Katıl'));
        } else {
          expect(find.text('Masa oluştur'), findsNothing);
          expect(find.text('Hızlı katıl'), findsNothing);
          await tester.tap(find.widgetWithText(FilledButton, 'Botla Oyna'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(PistiTableScreen), findsOneWidget);
        expect(find.byType(PistiLobbyScreen), findsNothing);
        final entry = service.calls.firstWhere(
          (c) => c.action == (invited ? 'accept' : 'create'),
        );
        expect(
          entry.args,
          invited ? {'invite_id': 'direct-invite'} : {'mode': 'break_bot'},
        );
        if (!invited) expect(find.textContaining(' · BOT'), findsWidgets);
        await tester.tap(find.byIcon(Icons.exit_to_app));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Coin veya rating etkilenmez'),
          findsOneWidget,
        );
        await tester.tap(find.text('Ayrıl'));
        await tester.pumpAndSettle();
        expect(find.text('Okey lobisi'), findsOneWidget);
        expect(find.byType(PistiTableScreen), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
