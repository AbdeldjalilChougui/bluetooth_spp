// Emulator integration test: drives the emulator's virtual Bluetooth
// controller (on/off with `cmd bluetooth_manager`) and checks permissions,
// adapter state, bonded devices, discovery and connect errors. A real SPP
// link needs a Bluetooth Classic device, which the emulator does not have.
// adb requests are served by tool/run_on_device.dart.
//
// Needs a fresh install (no permission granted). Bluetooth is restored to
// the state it had before the test.
//
// Run from example/:
//   dart run tool/run_on_device.dart \
//     dev.abdeldjalilchougui.bluetooth_spp_example emulator-5554

import 'dart:async';

import 'package:bluetooth_spp/bluetooth_spp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'adb_bridge.dart';

const _pkg = 'dev.abdeldjalilchougui.bluetooth_spp_example';
const _connect = 'android.permission.BLUETOOTH_CONNECT';
const _scan = 'android.permission.BLUETOOTH_SCAN';
// A well-formed address with no device behind it.
const _nobody = '00:11:22:33:44:55';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final adb = AdbBridge(_pkg);
  final bt = BluetoothSpp.instance;
  var wasOn = false;

  Future<void> setBluetooth(bool on) async {
    await adb.shell('cmd bluetooth_manager ${on ? 'enable' : 'disable'}');
    await adb.shell('cmd bluetooth_manager wait-for-state:'
        '${on ? 'STATE_ON' : 'STATE_OFF'}');
  }

  testWidgets('without permissions, Bluetooth off: state and typed errors',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    wasOn = (await adb.shell('settings get global bluetooth_on')).trim() == '1';
    debugPrint('Bluetooth on before the test: $wasOn');
    if (wasOn) await setBluetooth(false);

    final status = await bt.permissionsStatus();
    debugPrint('$status');
    expect(status.sdkInt, greaterThanOrEqualTo(31));
    expect(status.canConnect, isFalse,
        reason: 'run on a fresh install (uninstall the example first)');
    expect(status.canScan, isFalse);
    expect(status.missing, unorderedEquals([_connect, _scan]));

    expect(await bt.isEnabled(), isFalse);
    expect(await bt.currentAdapterState(), BluetoothAdapterState.off);
    // Android answers an empty set while the adapter is off, before it
    // checks BLUETOOTH_CONNECT (the check is covered with Bluetooth on).
    expect(await bt.bondedDevices(), isEmpty);
    await expectLater(
        bt.connect(_nobody), throwsA(isA<BluetoothDisabledException>()));
    await expectLater(bt.startDiscovery().toList(),
        throwsA(isA<BluetoothDisabledException>()));
    await expectLater(bt.connect('not-an-address'),
        throwsA(isA<BluetoothSppArgumentException>()));
  });

  testWidgets('adapterState streams off -> turningOn -> on', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final states = <BluetoothAdapterState>[];
    final sub = bt.adapterState.listen(states.add);
    try {
      await eventually(() async => states.length, (int n) => n > 0);
      await setBluetooth(true);
      final seen = await eventually(
          () async => states.toList(),
          (List<BluetoothAdapterState> s) =>
              s.contains(BluetoothAdapterState.on),
          timeout: const Duration(seconds: 15));
      debugPrint('adapter states: $seen');
      expect(seen.first, BluetoothAdapterState.off);
      expect(
          seen,
          containsAllInOrder([
            BluetoothAdapterState.off,
            BluetoothAdapterState.turningOn,
            BluetoothAdapterState.on,
          ]));
    } finally {
      await sub.cancel();
    }
    expect(await bt.isEnabled(), isTrue);
    expect(await bt.currentAdapterState(), BluetoothAdapterState.on);
    // Already on: no dialog, answers at once.
    expect(await bt.requestEnable(), isTrue);
  });

  testWidgets('Bluetooth on, no BLUETOOTH_CONNECT: permission errors',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    await expectLater(
        bt.bondedDevices(), throwsA(isA<BluetoothPermissionException>()));
    await expectLater(bt.connect(_nobody, timeout: const Duration(seconds: 5)),
        throwsA(isA<BluetoothPermissionException>()));
    await expectLater(bt.startDiscovery().toList(),
        throwsA(isA<BluetoothPermissionException>()));
  });

  testWidgets('with BLUETOOTH_CONNECT: bonded devices and connect failure',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    await adb.shell('pm grant $_pkg $_connect');
    final status = await bt.permissionsStatus();
    expect(status.canConnect, isTrue);
    expect(status.missing, [_scan]);

    final bonded = await bt.bondedDevices();
    final dump = await adb.shell('dumpsys bluetooth_manager');
    final count = RegExp(r'Bonded devices: (\d+)').firstMatch(dump)?.group(1);
    debugPrint('bonded: $bonded; dumpsys says $count');
    expect(bonded.length, int.parse(count ?? '0'));

    for (final secure in [true, false]) {
      final watch = Stopwatch()..start();
      Object? error;
      try {
        final c = await bt.connect(_nobody,
            secure: secure,
            insecureFallback: secure,
            rfcommChannelFallback: true,
            timeout: const Duration(seconds: 8));
        await c.close();
      } catch (e) {
        error = e;
      }
      watch.stop();
      debugPrint('connect($_nobody, secure: $secure) after '
          '${watch.elapsedMilliseconds} ms: $error');
      expect(error, isA<SppConnectException>());
      expect(watch.elapsed, lessThan(const Duration(seconds: 11)));
    }
    // Nothing is left open or reserved.
    expect(bt.connections, isEmpty);

    // Pairing with nobody fails; the bond state broadcast ends the wait.
    final watch = Stopwatch()..start();
    final paired = await bt.bond(_nobody).timeout(const Duration(seconds: 60));
    debugPrint('bond($_nobody) after ${watch.elapsed.inSeconds} s: $paired');
    expect(paired, isFalse);
    expect(await bt.bondedDevices(), isEmpty);
    await expectLater(bt.connect(_nobody, timeout: Duration.zero),
        throwsA(isA<ArgumentError>()));
  });

  testWidgets('with BLUETOOTH_SCAN: discovery runs and ends', (tester) async {
    await tester.pumpWidget(const SizedBox());
    await adb.shell('pm grant $_pkg $_scan');
    expect((await bt.permissionsStatus()).allGranted, isTrue);
    final found = <DiscoveryResult>[];
    Object? error;
    final done = Completer<void>();
    final watch = Stopwatch()..start();
    final sub = bt.startDiscovery().listen(found.add,
        onError: (Object e) => error = e, onDone: done.complete);
    try {
      await done.future.timeout(const Duration(seconds: 40));
    } finally {
      await sub.cancel();
    }
    watch.stop();
    debugPrint('discovery ended after ${watch.elapsed.inSeconds} s, '
        'error $error, found ${found.map((r) => '${r.device.address} '
            '${r.device.name} ${r.rssi}')}');
    expect(error, isNull);
    for (final r in found) {
      expect(
          RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(r.device.address),
          isTrue);
    }
    // A second discovery can be cancelled right away.
    final second = bt.startDiscovery().listen((_) {});
    await Future<void>.delayed(const Duration(seconds: 1));
    await second.cancel();
    await bt.cancelDiscovery();
  });

  testWidgets('restore Bluetooth', (tester) async {
    await tester.pumpWidget(const SizedBox());
    await setBluetooth(wasOn);
    expect(await bt.isEnabled(), wasOn);
    expect((await adb.shell('settings get global bluetooth_on')).trim(),
        wasOn ? '1' : '0');
  });
}
