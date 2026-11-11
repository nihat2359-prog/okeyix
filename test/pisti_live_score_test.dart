import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/dev/pisti/pisti_model.dart';
import 'pisti_online_test.dart' as fixtures;

void main() {
  test('online badge uses server live score for each viewer', () {
    final data = fixtures.fixture()['game'] as Map<String, dynamic>;
    data['total'] = [30, 12];
    data['score'] = [40, 34];
    final first = PistiGame.remote(data, 0);
    expect(first.score(PistiSeat.player), 40);
    expect(first.score(PistiSeat.opponent), 34);
    final second = PistiGame.remote(data, 1);
    expect(second.score(PistiSeat.player), 34);
    expect(second.score(PistiSeat.opponent), 40);
    data['status'] = 'finished';
    data['total'] = [43, 34];
    data['score'] = [43, 34];
    expect(PistiGame.remote(data, 0).score(PistiSeat.player), 43);
    data.remove('score');
    expect(PistiGame.remote(data, 0).score(PistiSeat.player), 43);
  });
}
