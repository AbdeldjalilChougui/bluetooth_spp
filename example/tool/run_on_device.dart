// Host-side runner for the emulator integration tests.
//
// Runs `flutter test integration_test/plugin_test.dart` on a device and
// serves the adb requests the test prints (lines containing `@@ADB@@`), so
// the test can put the device into a known state (appops, settings, sensors,
// key events) before it asserts. Each answer is written into the app's
// private `files/bridge/` directory with `run-as`, which works for debug
// builds only.
//
// Usage, from the example directory:
//   dart run tool/run_on_device.dart <applicationId> [deviceId]
//
// The adb binary is taken from $ADB, else from $ANDROID_HOME/platform-tools,
// else from PATH.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
        'usage: dart run tool/run_on_device.dart <applicationId> [deviceId]');
    exit(64);
  }
  final appId = args[0];
  final device = args.length > 1 ? args[1] : 'emulator-5554';
  final adb = _adbPath();
  final marker = RegExp(r'@@ADB@@(\w+)@@(.*)$');

  final flutter = await Process.start(
    'flutter',
    ['test', 'integration_test/plugin_test.dart', '-d', device],
  );
  unawaited(stderr.addStream(flutter.stderr));

  var queue = Future<void>.value();
  final seen = <String>{};
  await flutter.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
    stdout.writeln(line);
    final match = marker.firstMatch(line);
    if (match == null || !seen.add(match.group(1)!)) return;
    final id = match.group(1)!;
    final command = match.group(2)!;
    queue = queue.then((_) => _serve(adb, device, appId, id, command));
  });
  await queue;
  exit(await flutter.exitCode);
}

Future<void> _serve(
    String adb, String device, String appId, String id, String command) async {
  final result =
      await Process.run('bash', ['-c', '"$adb" -s $device $command']);
  final answer = '${result.exitCode}\n${result.stdout}${result.stderr}';
  stdout.writeln('[bridge] $id: adb $command -> exit ${result.exitCode}');
  final writer = await Process.start(adb, [
    '-s',
    device,
    'shell',
    "run-as $appId sh -c 'mkdir -p files/bridge && "
        "cat > files/bridge/$id.tmp && mv files/bridge/$id.tmp files/bridge/$id'",
  ]);
  writer.stdin.write(answer);
  await writer.stdin.close();
  final code = await writer.exitCode;
  if (code != 0) stderr.writeln('[bridge] could not deliver answer $id');
}

String _adbPath() {
  final env = Platform.environment;
  final explicit = env['ADB'];
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final home = env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'];
  if (home != null) {
    final candidate = '$home/platform-tools/adb';
    if (File(candidate).existsSync()) return candidate;
  }
  return 'adb';
}
