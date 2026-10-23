import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/services/guest_identity_service.dart';

void main() {
  test('debug guest identity stays constant across browser sessions', () {
    final first = developmentGuestIdentity(debugBuild: true, localKey: 'private-test-key');
    expect(first, developmentGuestIdentity(debugBuild: true, localKey: 'private-test-key'));
    expect(first, isNot(developmentGuestIdentity(debugBuild: true, localKey: 'other-developer')));
  });
  test('release/profile and unconfigured debug preserve normal guest behavior', () {
    expect(developmentGuestIdentity(debugBuild: false, localKey: 'private-test-key'), isNull);
    expect(developmentGuestIdentity(debugBuild: true, localKey: ''), isNull);
    expect(developmentGuestIdentity(debugBuild: true, localKey: '  '), isNull);
  });
  test('Chrome debug without the private key cannot fall back to a new guest', () {
    expect(() => developmentGuestIdentity(debugBuild: true, localKey: '',
      requireConfigured: true), throwsStateError);
    expect(developmentGuestIdentity(debugBuild: true, localKey: 'same-private-key',
      requireConfigured: true), 'okeyix-dev-guest:same-private-key');
    expect(developmentGuestIdentity(debugBuild: false, localKey: '',
      requireConfigured: true), isNull);
  });
  test('phones always keep their device identity even with a developer key', () {
    expect(developmentGuestIdentity(debugBuild: true, localKey: 'shared-local-key',
      browserBuild: false), isNull);
    expect(developmentGuestIdentity(debugBuild: false, localKey: 'shared-local-key',
      browserBuild: false), isNull);
  });
}
