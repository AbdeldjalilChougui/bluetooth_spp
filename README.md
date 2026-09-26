# bluetooth_spp

Bluetooth Classic serial (RFCOMM / SPP) for Flutter on Android: talk to ELM327 OBD-II dongles,
thermal printers, scales and barcode scanners over a plain byte stream. A maintained, clean-room
replacement for `flutter_bluetooth_serial`.

[![pub package](https://img.shields.io/pub/v/bluetooth_spp.svg)](https://pub.dev/packages/bluetooth_spp)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Android only; iOS does not allow Bluetooth Classic SPP without MFi** (Apple's accessory
program). There is no iOS implementation, so iOS is not supported.

## Features

- Adapter: `adapterState` stream, `isEnabled()`, `requestEnable()` (system dialog through
  `ACTION_REQUEST_ENABLE`).
- Paired devices with name, address, type, bond state and Class of Device.
- Discovery as a `Stream<DiscoveryResult>` with RSSI. Cancel the subscription or call
  `cancelDiscovery()` to stop it.
- `bond(address)` waits for the pairing result. `removeBond(address)` is best-effort (see below).
- `connect()` returns an `SppConnection` with:
  - `input`: a `Stream<Uint8List>`,
  - `write(bytes)`: its future completes after the bytes are flushed to the socket, which gives
    you backpressure,
  - `close()`, `isConnected`, a `state` stream and `disconnectReason`.
- Several connections at once. Each one has its own id, its own reader thread and its own
  writer thread.
- Opt-in fallbacks for difficult devices: an insecure RFCOMM socket, and the channel-1
  `createRfcommSocket` reflection trick for clone ELM327 dongles.
- Nothing blocks the Android main thread. Every native exception is mapped to a typed Dart
  exception (`SppConnectException`, `SppTimeoutException`, `BluetoothPermissionException`, ...).
- Manifest permissions are declared correctly for Android 12+ (`BLUETOOTH_CONNECT`,
  `BLUETOOTH_SCAN` with `neverForLocation`) and for older versions (`BLUETOOTH`,
  `BLUETOOTH_ADMIN` and location, all with `maxSdkVersion="30"`).
- The plugin never requests runtime permissions. It gives you a `permissionsStatus()` helper
  instead.
- Engine detach is clean: broadcast receivers are unregistered, discovery is cancelled, and
  pending and open sockets are closed.

## Install

```yaml
dependencies:
  bluetooth_spp: ^0.1.0
```

`minSdk` 21. The plugin's manifest merges the Bluetooth permissions into your app.

## Usage

```dart
import 'dart:convert';

import 'package:bluetooth_spp/bluetooth_spp.dart';

Future<void> readVoltage() async {
  final spp = BluetoothSpp.instance;

  if (!await spp.isEnabled() && !await spp.requestEnable()) return;

  final paired = await spp.bondedDevices();
  final dongle = paired.firstWhere((d) => (d.name ?? '').contains('OBD'));

  final SppConnection connection;
  try {
    connection = await spp.connect(
      dongle.address,
      timeout: const Duration(seconds: 10),
      rfcommChannelFallback: true, // clone ELM327 dongles, see below
    );
  } on SppTimeoutException {
    return;
  } on SppConnectException catch (e) {
    print('connect failed: ${e.message}');
    return;
  }

  // Replies arrive in arbitrary chunks; ELM327 ends each one with '>'.
  final buffer = StringBuffer();
  final prompt = connection.input.map(latin1.decode).map((s) {
    buffer.write(s);
    return buffer.toString();
  }).firstWhere((text) => text.endsWith('>'));

  await connection.write(latin1.encode('ATRV\r')); // completes when flushed
  print(await prompt); // e.g. "12.6V\r\r>"
  await connection.close();
}
```

Discovery:

```dart
final sub = BluetoothSpp.instance.startDiscovery().listen(
  (r) => print('${r.device.name} ${r.device.address} ${r.rssi} dBm'),
  onDone: () => print('inquiry finished'),
);
// Stop early:
await sub.cancel();
```

Several devices at once, for example a scale and a printer:

```dart
final scale = await BluetoothSpp.instance.connect(scaleAddress);
final printer = await BluetoothSpp.instance.connect(printerAddress);
scale.input.listen((bytes) => printer.write(bytes));
```

### Permissions (with `permission_handler`)

The plugin declares the permissions but does not ask for them, so you choose when and how to
show the dialog. On Android 12 and later you need `BLUETOOTH_CONNECT` for paired devices,
connect, bond and enable, plus `BLUETOOTH_SCAN` for discovery. On Android 6 to 11, discovery
needs location permission and location services turned on.

```dart
import 'package:bluetooth_spp/bluetooth_spp.dart';
import 'package:permission_handler/permission_handler.dart';

Future<bool> ensureBluetoothPermissions() async {
  final status = await BluetoothSpp.instance.permissionsStatus();
  if (status.allGranted) return true;
  await [
    if (status.sdkInt >= 31) ...[
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ] else
      Permission.locationWhenInUse,
  ].request();
  return (await BluetoothSpp.instance.permissionsStatus()).allGranted;
}
```

`status.missing` lists the exact Android permission names that are still denied.

**Manifest merge notes**

- If your app uses location for its own purposes on Android 11 and lower, add
  `tools:remove="android:maxSdkVersion"` to your own `ACCESS_FINE_LOCATION` entry. Otherwise
  the library's `maxSdkVersion="30"` is merged into it.
- If you do derive location from Bluetooth scan results, redeclare `BLUETOOTH_SCAN` with
  `tools:remove="android:usesPermissionFlags"`.

### Using it as an `obd2_kit` transport

`obd2_kit` (a sibling package, not yet published) talks to ELM327 adapters through an
`ObdTransport` interface. `SppConnection` already has the right shape, so the adapter is only a
few lines. Put it in your app; this package does not depend on `obd2_kit`.

```dart
import 'package:bluetooth_spp/bluetooth_spp.dart';
import 'package:obd2_kit/obd2_kit.dart';

class SppObdTransport implements ObdTransport {
  SppObdTransport(this.connection);

  final SppConnection connection;

  @override
  Stream<List<int>> get input => connection.input;

  @override
  Future<void> write(List<int> bytes) => connection.write(bytes);

  @override
  Future<void> close() => connection.close();
}
```

## Connection fallbacks

By default `connect()` makes one attempt: `createRfcommSocketToServiceRecord(uuid)`. This is an
authenticated socket, and Android looks up the RFCOMM channel through SDP. You can opt in to
more attempts. They share the same total `timeout`.

| Option | Attempt | Why |
|---|---|---|
| `secure: false` | `createInsecureRfcommSocketToServiceRecord` only | For devices that pair without a PIN or reject authenticated links. |
| `insecureFallback: true` | insecure socket after the secure one fails | Some printers and scanners only accept insecure links. |
| `rfcommChannelFallback: true` | hidden `createRfcommSocket(1)` through reflection, last | Many cheap ELM327 clones return a broken SDP record. The SDP lookup then fails with `read failed, socket might closed or timeout, read ret: -1`, although the serial service really is on channel 1. |

The channel-1 fallback is opt-in for three reasons. It uses a non-public API that Android may
restrict. It assumes channel 1, which is wrong for devices that expose several services. And it
skips the service UUID you asked for.

## Migrating from flutter_bluetooth_serial

| flutter_bluetooth_serial | bluetooth_spp |
|---|---|
| `FlutterBluetoothSerial.instance` | `BluetoothSpp.instance` |
| `onStateChanged()` / `state` | `adapterState` / `currentAdapterState()` |
| `isEnabled` (getter, `bool?`) | `isEnabled()` (`bool`) |
| `requestEnable()` | `requestEnable()` |
| `getBondedDevices()` | `bondedDevices()` |
| `startDiscovery()` / `cancelDiscovery()` | same names; results have `device` and `rssi` |
| `bondDeviceAtAddress(address)` | `bond(address)` |
| `removeDeviceBondWithAddress(address)` | `removeBond(address)` (best-effort) |
| `BluetoothConnection.toAddress(address)` | `BluetoothSpp.instance.connect(address)` |
| `connection.input` (nullable) | `connection.input` (non-null, buffers until listened) |
| `connection.output.add(bytes)` + `await output.allSent` | `await connection.write(bytes)` |
| `close()` / `finish()` / `dispose()` | `close()` |
| `PlatformException(connect_error, ...)` | `SppConnectException`, `SppTimeoutException`, ... |
| plugin asked for location itself | ask with `permission_handler`; check `permissionsStatus()` |

Not carried over: `setPairingRequestHandler`, `requestDiscoverable`, `changeName`,
`openSettings` and `address`/`name` of the local adapter. Pairing PINs are entered in the
system dialog. `input` is single-subscription; call `asBroadcastStream()` if you need several
listeners.

## Troubleshooting

- **Pairing PIN.** Most ELM327 dongles, HC-05/HC-06 modules and thermal printers use `1234` or
  `0000`, sometimes `6789` or `1111`. Pairing in the Android Bluetooth settings first is often
  the most reliable path. Then pick the device from `bondedDevices()`.
- **`read failed, socket might closed or timeout, read ret: -1`.** This is the most common
  complaint about the old plugin. Try, in this order:
  1. make sure the device is bonded and not connected to another phone;
  2. `insecureFallback: true`;
  3. `rfcommChannelFallback: true` (clone dongles);
  4. switch Bluetooth off and on (a stale socket from a crashed app can hold the link).
- **Clone ELM327 dongles** ("v2.1" and "v1.5" clones) often need the channel-1 fallback. Some of
  them also need a short pause after `ATZ` before the next command.
- **`BluetoothPermissionException` on Android 12+.** `BLUETOOTH_CONNECT` or `BLUETOOTH_SCAN` has
  not been granted. See the Permissions section.
- **Discovery finds nothing on Android 10 or 11.** Grant location permission *and* turn location
  services on.
- **`SppTimeoutException`.** Android's own connect has no timeout, so this plugin closes the
  socket when `timeout` expires. Most devices answer within 5 seconds; out-of-range devices
  otherwise block for about 12 seconds.
- **Garbled or split replies.** `input` delivers bytes in whatever chunks the radio produced.
  Reassemble them using your protocol's delimiter: `>` for ELM327, `\r\n` for most scales.

## Limitations

- Android only. There is no iOS, web or desktop implementation.
- Bluetooth Classic only. For BLE UART modules (HM-10, nRF UART) use a BLE plugin.
- Client side only. There is no RFCOMM server socket (`listenUsingRfcommWithServiceRecord`).
- `removeBond` and `rfcommChannelFallback` rely on hidden Android APIs and may stop working on
  future Android versions.
- No background service. Connections live as long as the Flutter engine; they are closed when it
  detaches.
- The Dart API is tested with mocked method and event channels, and the Kotlin logic (UUID
  parsing, error mapping, connection registry, chunked write queue, read loop, connect plan,
  permission policy, receiver flags) with JUnit.
- The example app has an emulator integration test (`example/integration_test/`, run with
  `dart run tool/run_on_device.dart <applicationId>` from `example/`) against the emulator's
  virtual Bluetooth controller. It checks `permissionsStatus` with and without
  `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN`, `adapterState` (off, turning on, on), `isEnabled`,
  `requestEnable` while on, `bondedDevices`, the typed errors (disabled, permission, invalid
  address), `connect` to an address with no device (`SppTimeoutException` or
  `SppConnectException` within the timeout, with every fallback), `bond` to it (returns false),
  and a discovery that ends after about 12 seconds.
- **Not tested: a real SPP link.** The emulator has no Bluetooth Classic device to talk to, so
  a successful connect, reading, writing, a remote disconnect, a successful bond, `removeBond`,
  and the `requestEnable` dialog were not exercised. Discovery found no devices.

**Tested on:** Android Emulator, Pixel 10 image, API 37 (physical phone not tested).

## License

MIT. See [LICENSE](LICENSE).

Made by [Abdeldjalil Chougui](https://abdeldjalilchougui.biz/).
