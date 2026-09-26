import 'package:bluetooth_spp/bluetooth_spp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BluetoothAdapterState', () {
    test('maps Android BluetoothAdapter.STATE_* values', () {
      expect(BluetoothAdapterState.fromNative(10), BluetoothAdapterState.off);
      expect(BluetoothAdapterState.fromNative(11),
          BluetoothAdapterState.turningOn);
      expect(BluetoothAdapterState.fromNative(12), BluetoothAdapterState.on);
      expect(BluetoothAdapterState.fromNative(13),
          BluetoothAdapterState.turningOff);
      expect(BluetoothAdapterState.fromNative(-1),
          BluetoothAdapterState.unavailable);
      expect(BluetoothAdapterState.fromNative(99),
          BluetoothAdapterState.unavailable);
    });
  });

  group('BluetoothDevice', () {
    test('parses a native map', () {
      final d = BluetoothDevice.fromMap(const {
        'name': 'OBDII',
        'address': '00:1D:A5:68:98:8B',
        'type': 1,
        'bondState': 12,
        'deviceClass': 0x1F00,
      });
      expect(d.name, 'OBDII');
      expect(d.address, '00:1D:A5:68:98:8B');
      expect(d.type, BluetoothDeviceType.classic);
      expect(d.bondState, BluetoothBondState.bonded);
      expect(d.isBonded, isTrue);
      expect(d.deviceClass, 0x1F00);
      expect(d.majorDeviceClass, 0x1F00);
    });

    test('tolerates missing name, unknown codes and missing class', () {
      final d = BluetoothDevice.fromMap(const {
        'address': 'AA:BB:CC:DD:EE:FF',
        'type': 42,
        'bondState': 7,
      });
      expect(d.name, isNull);
      expect(d.type, BluetoothDeviceType.unknown);
      expect(d.bondState, BluetoothBondState.none);
      expect(d.deviceClass, isNull);
      expect(d.majorDeviceClass, isNull);
    });

    test('maps every device type and bond state', () {
      expect(BluetoothDeviceType.fromNative(0), BluetoothDeviceType.unknown);
      expect(BluetoothDeviceType.fromNative(2), BluetoothDeviceType.le);
      expect(BluetoothDeviceType.fromNative(3), BluetoothDeviceType.dual);
      expect(BluetoothBondState.fromNative(10), BluetoothBondState.none);
      expect(BluetoothBondState.fromNative(11), BluetoothBondState.bonding);
    });

    test('equality is by address', () {
      final a = BluetoothDevice.fromMap(const {'address': '11:22:33:44:55:66'});
      final b = BluetoothDevice.fromMap(
          const {'address': '11:22:33:44:55:66', 'name': 'x'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('11:22:33:44:55:66'));
    });
  });

  test('DiscoveryResult parses device and rssi', () {
    final r = DiscoveryResult.fromMap(const {
      'name': 'Printer',
      'address': '11:22:33:44:55:66',
      'type': 1,
      'bondState': 10,
      'deviceClass': 0x0680,
      'rssi': -61,
    });
    expect(r.device.name, 'Printer');
    expect(r.rssi, -61);
    expect(
      DiscoveryResult.fromMap(const {'address': '11:22:33:44:55:66'}).rssi,
      isNull,
    );
  });

  test('BluetoothPermissionsStatus parses and summarises', () {
    final s = BluetoothPermissionsStatus.fromMap(const {
      'sdkInt': 33,
      'connectGranted': true,
      'scanGranted': false,
      'missing': ['android.permission.BLUETOOTH_SCAN'],
    });
    expect(s.sdkInt, 33);
    expect(s.canConnect, isTrue);
    expect(s.canScan, isFalse);
    expect(s.missing, ['android.permission.BLUETOOTH_SCAN']);
    expect(s.allGranted, isFalse);
  });
}
