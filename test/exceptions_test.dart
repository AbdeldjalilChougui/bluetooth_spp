import 'package:bluetooth_spp/bluetooth_spp.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BluetoothSppException map(String code) =>
      BluetoothSppException.fromPlatformException(
          PlatformException(code: code, message: 'm'));

  test('each native code maps to a typed exception', () {
    expect(map('bluetooth_unavailable'), isA<BluetoothUnavailableException>());
    expect(map('bluetooth_disabled'), isA<BluetoothDisabledException>());
    expect(map('permission_denied'), isA<BluetoothPermissionException>());
    expect(map('invalid_argument'), isA<BluetoothSppArgumentException>());
    expect(map('connect_failed'), isA<SppConnectException>());
    expect(map('timeout'), isA<SppTimeoutException>());
    expect(map('not_connected'), isA<SppNotConnectedException>());
    expect(map('io_error'), isA<SppIoException>());
    expect(map('activity_unavailable'),
        isA<BluetoothActivityUnavailableException>());
    expect(map('busy'), isA<BluetoothBusyException>());
    expect(map('something_new'), isA<UnknownBluetoothSppException>());
  });

  test('keeps code and message', () {
    final e = BluetoothSppException.fromPlatformException(PlatformException(
        code: 'connect_failed', message: 'read failed, socket might closed'));
    expect(e.code, 'connect_failed');
    expect(e.message, 'read failed, socket might closed');
    expect(e.toString(), contains('connect_failed'));
  });

  test('timeout is a connect exception', () {
    expect(map('timeout'), isA<SppConnectException>());
  });
}
