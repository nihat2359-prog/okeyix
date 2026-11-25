import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/services/player_metadata_cache.dart';

void main() {
  test('metadata is bounded by viewer and TTL and excludes game secrets', () {
    final now = DateTime.utc(2026);
    PlayerMetadataCache.put('viewer', [
      {
        'id': 'a',
        'username': 'A',
        'avatar_url': 'avatar.png',
        'hand': ['secret'],
        'coins': 42,
      },
    ], now: now);
    final first = PlayerMetadataCache.get('viewer', 'a', now: now)!;
    expect(first, {'id': 'a', 'username': 'A', 'avatar_url': 'avatar.png'});
    first['username'] = 'mutated';
    expect(PlayerMetadataCache.get('viewer', 'a', now: now)!['username'], 'A');
    expect(
      PlayerMetadataCache.get(
        'viewer',
        'a',
        now: now.add(const Duration(seconds: 60)),
      ),
      isNull,
    );
    expect(PlayerMetadataCache.get('another', 'a', now: now), isNull);
    expect(PlayerMetadataCache.get('viewer', 'a', now: now), isNull);
  });
}
