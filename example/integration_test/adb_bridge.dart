import 'dart:async';
import 'dart:io';

/// Output of an adb command run on the host by `tool/run_on_device.dart`.
class AdbResult {
  /// Creates a result.
  AdbResult(this.exitCode, this.output);

  /// Exit code of the host `adb` process.
  final int exitCode;

  /// Combined stdout and stderr.
  final String output;

  @override
  String toString() => 'AdbResult($exitCode, $output)';
}

/// Asks the host runner to run adb commands against this device.
///
/// Only works when the test is started through `tool/run_on_device.dart`;
/// a plain `flutter test integration_test` run times out on the first call.
class AdbBridge {
  /// Creates a bridge for the app [applicationId].
  AdbBridge(this.applicationId);

  /// The application id of the example app (its `run-as` target).
  final String applicationId;

  int _counter = 0;

  /// Runs `adb -s <device> <command>` on the host and returns its output.
  Future<AdbResult> run(String command,
      {Duration timeout = const Duration(seconds: 60)}) async {
    final id = 'c${_counter++}x${DateTime.now().microsecondsSinceEpoch}';
    // ignore: avoid_print
    print('@@ADB@@$id@@$command');
    final file = File('/data/data/$applicationId/files/bridge/$id');
    final deadline = DateTime.now().add(timeout);
    while (!file.existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
            'No answer for "adb $command". Run this test through '
            'tool/run_on_device.dart so the host can serve adb requests.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final text = await file.readAsString();
    await file.delete();
    final newline = text.indexOf('\n');
    return AdbResult(
        int.parse(text.substring(0, newline)), text.substring(newline + 1));
  }

  /// Runs `adb shell <command>` and fails when it exits non-zero.
  Future<String> shell(String command) async {
    final result = await run('shell $command');
    if (result.exitCode != 0) {
      throw StateError('adb shell $command failed: ${result.output}');
    }
    return result.output;
  }

  /// Taps "Wait" on a system "isn't responding" dialog, if one has focus.
  ///
  /// A loaded emulator sometimes shows one for System UI; while it has
  /// focus, key events such as BACK do not reach the app under test.
  Future<void> dismissAnrDialog() async {
    final windows = await shell('dumpsys window');
    if (!windows.contains('Application Not Responding')) return;
    await shell('uiautomator dump /sdcard/bridge_ui.xml');
    final xml = await shell('cat /sdcard/bridge_ui.xml');
    await shell('rm -f /sdcard/bridge_ui.xml');
    final match = RegExp(r'resource-id="android:id/aerr_wait"[^>]*'
            r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"')
        .firstMatch(xml);
    if (match == null) return;
    final b = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
    await shell('input tap ${(b[0] + b[2]) ~/ 2} ${(b[1] + b[3]) ~/ 2}');
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  /// Presses BACK (dismissing a system ANR dialog first) until [package]
  /// owns the top resumed activity. Returns whether it got there.
  Future<bool> backTo(String package, {int maxPresses = 5}) async {
    for (var i = 0; i <= maxPresses; i++) {
      if ((await topResumedActivity()).contains(package)) return true;
      if (i == maxPresses) break;
      await dismissAnrDialog();
      await shell('input keyevent KEYCODE_BACK');
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    return false;
  }

  /// The `topResumedActivity` line of `dumpsys activity activities`.
  Future<String> topResumedActivity() async {
    final out = await shell('dumpsys activity activities');
    return out
        .split('\n')
        .firstWhere((l) => l.contains('topResumedActivity'), orElse: () => '')
        .trim();
  }
}

/// Polls [read] until [done] holds or [timeout] passes; returns the last value.
Future<T> eventually<T>(Future<T> Function() read, bool Function(T) done,
    {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  var value = await read();
  while (!done(value) && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    value = await read();
  }
  return value;
}
