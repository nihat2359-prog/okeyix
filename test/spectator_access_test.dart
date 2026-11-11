import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:okeyix/services/spectator_access.dart';

void main() {
  const denied = PostgrestException(
    message: 'TABLE_VIEW_ACCESS_REQUIRED',
    code: '42501',
  );

  test('concurrent reads wait for a single completed registration', () async {
    final joined = Completer<void>();
    var registrations = 0;
    var reads = 0;
    final access = SpectatorAccess(
      register: () {
        registrations++;
        return joined.future;
      },
    );
    Future<int> load() async => ++reads;
    final first = access.read(load);
    final second = access.read(load);
    expect(registrations, 1);
    expect(reads, 0);
    joined.complete();
    expect(await Future.wait([first, second]), [1, 2]);
  });

  test('failed join blocks reads and can be retried', () async {
    var registrations = 0;
    var reads = 0;
    final access = SpectatorAccess(
      register: () async {
        if (++registrations == 1) throw denied;
      },
    );
    Future<int> load() async => ++reads;
    await expectLater(access.read(load), throwsA(denied));
    expect(reads, 0);
    expect(await access.read(load), 1);
    expect(registrations, 2);
  });

  test('missing membership is restored before retrying finish read', () async {
    var registrations = 0;
    var reads = 0;
    final access = SpectatorAccess(
      register: () async {
        registrations++;
      },
    );
    final result = await access.read(() async {
      if (++reads == 1) throw denied;
      return 'finish';
    });
    expect(result, 'finish');
    expect(registrations, 2);
    expect(reads, 2);
  });

  test('real access denial is propagated after one recovery attempt', () async {
    var registrations = 0;
    var reads = 0;
    final access = SpectatorAccess(
      register: () async {
        registrations++;
      },
    );
    await expectLater(
      access.read(() async {
        reads++;
        throw denied;
      }),
      throwsA(denied),
    );
    expect(registrations, 2);
    expect(reads, 2);
  });

  test('unrelated failures do not trigger membership writes', () async {
    var registrations = 0;
    final access = SpectatorAccess(
      register: () async {
        registrations++;
      },
    );
    const failure = PostgrestException(
      message: 'missing function',
      code: '42883',
    );
    await expectLater(
      access.read(() async {
        throw failure;
      }),
      throwsA(failure),
    );
    expect(registrations, 1);
  });
}
