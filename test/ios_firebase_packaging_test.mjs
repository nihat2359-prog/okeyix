// Read-only project checks; macOS integration uses a temporary fixture only.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const read = path => readFileSync(join(root, path), 'utf8');
const project = read('ios/Runner.xcodeproj/project.pbxproj');
const script = join(root, 'tool/codemagic_ios_firebase.sh');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : '/bin/bash';
const bashAvailable = existsSync(bash);

test('one plist reference is connected to Runner and its resources phase', () => {
  assert.equal((project.match(/path = "GoogleService-Info\.plist"/g) || []).length, 1);
  const reference = 'F12710000000000000000001';
  const build = 'F12710000000000000000002';
  assert.match(project, new RegExp(`${build}[^\n]+fileRef = ${reference}`));
  const group = project.split('97C146F01CF9000F007C117D /* Runner */ = {')[1].split('\n\t\t};')[0];
  assert.ok(group.includes(reference));
  const resources = project.split('97C146EC1CF9000F007C117D /* Resources */ = {')[1].split('\n\t\t};')[0];
  assert.ok(resources.includes(build));
  assert.match(resources, /runOnlyForDeploymentPostprocessing = 0/);
  const target = project.split('97C146ED1CF9000F007C117D /* Runner */ = {')[1].split('\n\t\t};')[0];
  assert.ok(target.includes('97C146EC1CF9000F007C117D'));
});

test('script expects the existing Dart Firebase iOS identities', () => {
  const options = read('lib/firebase_options.dart').split('static const FirebaseOptions ios = FirebaseOptions(')[1];
  const source = read('tool/codemagic_ios_firebase.sh');
  for (const key of ['appId', 'iosBundleId', 'projectId', 'messagingSenderId']) {
    const value = options.match(new RegExp(`${key}: '([^']+)'`))[1];
    assert.ok(source.includes(`'${value}'`), `Missing guard for ${key}`);
  }
  assert.ok(read('.gitignore').split(/\r?\n/).includes('/ios/Runner/GoogleService-Info.plist'));
});

test('bash syntax is valid', { skip: !bashAvailable }, () => {
  const result = spawnSync(bash, ['-n', script], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
});

for (const [label, value, expected] of [
  ['missing', undefined, 'missing or empty'],
  ['empty', '', 'missing or empty'],
  ['invalid alphabet', 'DO-NOT-LOG-THIS-SECRET!', 'Invalid Base64 encoding'],
  ['invalid padding', 'c2VjcmV0===', 'Invalid Base64 encoding'],
]) {
  test(`prepare fails safely for ${label} environment`, { skip: !bashAvailable }, () => {
    const env = { ...process.env, CM_BUILD_DIR: root };
    delete env.IOS_GOOGLE_SERVICE_INFO_PLIST_B64;
    if (value !== undefined) env.IOS_GOOGLE_SERVICE_INFO_PLIST_B64 = value;
    const before = read('ios/Runner/GoogleService-Info.plist');
    const result = spawnSync(bash, ['-x', script, 'prepare'], { env, encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    const output = result.stdout + result.stderr;
    assert.ok(output.includes(expected), output);
    if (value) assert.ok(!output.includes(value), 'Secret appeared in output');
    assert.equal(read('ios/Runner/GoogleService-Info.plist'), before);
  });
}

test('macOS prepares, rejects invalid plist/identity and verifies actual app bundle',
  { skip: process.platform !== 'darwin' }, () => {
    const dir = mkdtempSync(join(tmpdir(), 'okeyix-ios-firebase-'));
    try {
      mkdirSync(join(dir, 'ios/Runner'), { recursive: true });
      mkdirSync(join(dir, 'ios/Runner.xcodeproj'));
      writeFileSync(join(dir, 'ios/Runner.xcodeproj/project.pbxproj'), project);
      const source = read('ios/Runner/GoogleService-Info.plist');
      const run = (value, args = ['prepare']) => spawnSync(bash, [script, ...args], {
        encoding: 'utf8', env: { ...process.env, CM_BUILD_DIR: dir,
          IOS_GOOGLE_SERVICE_INFO_PLIST_B64: Buffer.from(value).toString('base64') },
      });
      const success = run(source);
      assert.equal(success.status, 0, success.stderr);
      for (const invalid of ['not a plist', source.replace('com.okeyix.game', 'com.wrong.app'),
        source.replace('488f00b9d026798bc3f960', 'wrong'), '<plist version="1.0"><array/></plist>']) {
        assert.notEqual(run(invalid).status, 0);
        assert.equal(readFileSync(join(dir, 'ios/Runner/GoogleService-Info.plist'), 'utf8'), source);
      }
      const app = join(dir, 'Runner.app');
      mkdirSync(app);
      writeFileSync(join(app, 'GoogleService-Info.plist'), source);
      writeFileSync(join(app, 'Info.plist'), '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.okeyix.game</string></dict></plist>');
      const verified = run(source, ['verify', app]);
      assert.equal(verified.status, 0, verified.stderr);
      assert.equal(spawnSync('/usr/bin/plutil', ['-convert', 'binary1', join(app, 'GoogleService-Info.plist')]).status, 0);
      assert.equal(run(source, ['verify', app]).status, 0, 'Binary plist must verify too');
      rmSync(join(app, 'GoogleService-Info.plist'));
      assert.notEqual(run(source, ['verify', app]).status, 0);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
