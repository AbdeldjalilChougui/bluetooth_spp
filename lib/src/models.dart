/// State of the local Bluetooth adapter.
enum BluetoothAdapterState {
  /// No adapter, or the state could not be read.
  unavailable,

  /// Bluetooth is off.
  off,

  /// Bluetooth is turning on.
  turningOn,

  /// Bluetooth is on.
  on,

  /// Bluetooth is turning off.
  turningOff;

  /// Maps Android's `BluetoothAdapter.STATE_*` constants.
  static BluetoothAdapterState fromNative(int value) => switch (value) {
        10 => off,
        11 => turningOn,
        12 => on,
        13 => turningOff,
        _ => unavailable,
      };
}

/// Radio type of a remote device.
enum BluetoothDeviceType {
  /// Unknown.
  unknown,

  /// Bluetooth Classic (BR/EDR). SPP devices are classic or dual.
  classic,

  /// Bluetooth Low Energy only. Cannot be used with SPP.
  le,

  /// Both classic and Low Energy.
  dual;

  /// Maps Android's `BluetoothDevice.DEVICE_TYPE_*` constants.
  static BluetoothDeviceType fromNative(int? value) => switch (value) {
        1 => classic,
        2 => le,
        3 => dual,
        _ => unknown,
      };
}

/// Pairing state of a remote device.
enum BluetoothBondState {
  /// Not paired.
  none,

  /// Pairing in progress.
  bonding,

  /// Paired.
  bonded;

  /// Maps Android's `BluetoothDevice.BOND_*` constants.
  static BluetoothBondState fromNative(int? value) => switch (value) {
        11 => bonding,
        12 => bonded,
        _ => none,
      };
}

/// A remote Bluetooth device.
class BluetoothDevice {
  /// Creates a device description.
  const BluetoothDevice({
    required this.address,
    this.name,
    this.type = BluetoothDeviceType.unknown,
    this.bondState = BluetoothBondState.none,
    this.deviceClass,
  });

  /// Parses the map sent by the Android side.
  factory BluetoothDevice.fromMap(Map<Object?, Object?> map) => BluetoothDevice(
        address: map['address']! as String,
        name: map['name'] as String?,
        type: BluetoothDeviceType.fromNative(map['type'] as int?),
        bondState: BluetoothBondState.fromNative(map['bondState'] as int?),
        deviceClass: map['deviceClass'] as int?,
      );

  /// MAC address, e.g. `00:1D:A5:68:98:8B`.
  final String address;

  /// Friendly name, or null if unknown.
  final String? name;

  /// Radio type.
  final BluetoothDeviceType type;

  /// Pairing state when the device was read.
  final BluetoothBondState bondState;

  /// Full Class of Device (`BluetoothClass.getDeviceClass()`), or null.
  final int? deviceClass;

  /// Major device class bits (`deviceClass & 0x1F00`), e.g. `0x0600` imaging
  /// (printers), `0x1F00` uncategorized (most OBD-II dongles).
  int? get majorDeviceClass =>
      deviceClass == null ? null : deviceClass! & 0x1F00;

  /// Whether the device is paired.
  bool get isBonded => bondState == BluetoothBondState.bonded;

  @override
  bool operator ==(Object other) =>
      other is BluetoothDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;

  @override
  String toString() => 'BluetoothDevice($address, ${name ?? '?'}, '
      '${type.name}, ${bondState.name})';
}

/// A device found during discovery.
class DiscoveryResult {
  /// Creates a discovery result.
  const DiscoveryResult({required this.device, this.rssi});

  /// Parses the map sent by the Android side.
  factory DiscoveryResult.fromMap(Map<Object?, Object?> map) => DiscoveryResult(
        device: BluetoothDevice.fromMap(map),
        rssi: map['rssi'] as int?,
      );

  /// The device.
  final BluetoothDevice device;

  /// Signal strength in dBm, or null if Android did not report it.
  final int? rssi;

  @override
  String toString() => 'DiscoveryResult($device, rssi: $rssi)';
}

/// Snapshot of the runtime permissions this plugin needs.
///
/// The plugin never requests permissions. Use `permission_handler` (see the
/// README) and check this status before calling the API.
class BluetoothPermissionsStatus {
  /// Creates a status.
  const BluetoothPermissionsStatus({
    required this.sdkInt,
    required this.canConnect,
    required this.canScan,
    required this.missing,
  });

  /// Parses the map sent by the Android side.
  factory BluetoothPermissionsStatus.fromMap(Map<Object?, Object?> map) =>
      BluetoothPermissionsStatus(
        sdkInt: map['sdkInt']! as int,
        canConnect: map['connectGranted']! as bool,
        canScan: map['scanGranted']! as bool,
        missing: List<String>.unmodifiable(
            (map['missing'] as List<Object?>? ?? const []).cast<String>()),
      );

  /// Android API level of the device.
  final int sdkInt;

  /// Whether bonded devices, connect, bond and enable are allowed
  /// (BLUETOOTH_CONNECT on API 31+, always true below).
  final bool canConnect;

  /// Whether discovery is allowed (BLUETOOTH_SCAN on API 31+, location on
  /// API 23-30).
  final bool canScan;

  /// Android permission names still missing, e.g.
  /// `android.permission.BLUETOOTH_SCAN`.
  final List<String> missing;

  /// Whether everything is granted.
  bool get allGranted => canConnect && canScan;

  @override
  String toString() => 'BluetoothPermissionsStatus(sdk $sdkInt, '
      'connect: $canConnect, scan: $canScan, missing: $missing)';
}
