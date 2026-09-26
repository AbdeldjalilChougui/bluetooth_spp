import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'channels.dart';
import 'exceptions.dart';
import 'models.dart';

part 'spp_connection.dart';

/// Entry point: adapter, discovery, bonding and SPP connections.
///
/// Android only. All calls run off the Android main thread; failures are
/// thrown as [BluetoothSppException] subclasses.
class BluetoothSpp {
  BluetoothSpp._();

  /// Creates an independent instance with its own connection table. Meant
  /// for tests; apps should use [instance].
  @visibleForTesting
  factory BluetoothSpp.newInstance() => BluetoothSpp._();

  /// The shared instance.
  static final BluetoothSpp instance = BluetoothSpp._();

  /// The Serial Port Profile service UUID.
  static const String sppUuid = '00001101-0000-1000-8000-00805F9B34FB';

  static final _random = Random();
  static int _counter = 0;

  final Map<String, SppConnection> _connections = {};
  StreamSubscription<Object?>? _connectionEvents;
  StreamSubscription<Object?>? _discoverySub;
  StreamController<DiscoveryResult>? _discoveryController;

  /// Adapter state changes. The first event is the current state.
  late final Stream<BluetoothAdapterState> adapterState = adapterStateChannel
      .receiveBroadcastStream()
      .map((event) => BluetoothAdapterState.fromNative(event! as int))
      .transform(_errorMapper());

  /// The adapter state right now.
  Future<BluetoothAdapterState> currentAdapterState() async =>
      BluetoothAdapterState.fromNative(
          await _invoke<int>('adapterState') ?? -1);

  /// Whether Bluetooth is on. False when there is no adapter.
  Future<bool> isEnabled() async => await _invoke<bool>('isEnabled') ?? false;

  /// Shows the system dialog asking the user to turn Bluetooth on
  /// (`ACTION_REQUEST_ENABLE`). Returns whether it is on afterwards.
  ///
  /// Needs a foreground activity and, on Android 12+, BLUETOOTH_CONNECT.
  Future<bool> requestEnable() async =>
      await _invoke<bool>('requestEnable') ?? false;

  /// Paired devices.
  Future<List<BluetoothDevice>> bondedDevices() async {
    final list = await _invoke<List<Object?>>('bondedDevices') ?? const [];
    return [
      for (final m in list) BluetoothDevice.fromMap(m! as Map<Object?, Object?>)
    ];
  }

  /// Starts discovery; results arrive as they are found and the stream ends
  /// when Android finishes the inquiry (about 12 seconds). Cancelling the
  /// subscription cancels discovery. Starting a new discovery ends the
  /// previous stream.
  ///
  /// Needs BLUETOOTH_SCAN on Android 12+, location permission (and location
  /// turned on) on Android 6-11.
  Stream<DiscoveryResult> startDiscovery() {
    _stopDiscoveryStream();
    late final StreamController<DiscoveryResult> controller;
    controller = StreamController<DiscoveryResult>(
      onListen: () {
        _discoverySub = discoveryChannel.receiveBroadcastStream().listen(
              (e) => controller
                  .add(DiscoveryResult.fromMap(e! as Map<Object?, Object?>)),
              onError: (Object e, StackTrace st) =>
                  controller.addError(mapStreamError(e), st),
              onDone: controller.close,
            );
      },
      onCancel: () {
        final sub = _discoverySub;
        if (identical(_discoveryController, controller)) {
          _discoverySub = null;
          _discoveryController = null;
        }
        return sub?.cancel();
      },
    );
    _discoveryController = controller;
    return controller.stream;
  }

  void _stopDiscoveryStream() {
    _discoverySub?.cancel();
    _discoverySub = null;
    _discoveryController?.close();
    _discoveryController = null;
  }

  /// Cancels a running discovery. Android recommends this before connecting;
  /// [connect] does it for you.
  Future<void> cancelDiscovery() => _invoke<void>('cancelDiscovery');

  /// Pairs with [address] and waits for the result. Returns true if the
  /// device ends up bonded. Android may show a PIN or confirmation dialog.
  Future<bool> bond(String address) async =>
      await _invoke<bool>('bond', {'address': address}) ?? false;

  /// Removes the pairing with [address].
  ///
  /// Best effort: Android has no public API for this, so it calls the hidden
  /// `BluetoothDevice.removeBond()` through reflection. It can fail or be
  /// blocked on some devices and future Android versions; returns false then.
  Future<bool> removeBond(String address) async =>
      await _invoke<bool>('removeBond', {'address': address}) ?? false;

  /// Which runtime permissions are granted. Does not request anything.
  Future<BluetoothPermissionsStatus> permissionsStatus() async =>
      BluetoothPermissionsStatus.fromMap(
          (await _invoke<Map<Object?, Object?>>('permissionsStatus'))!);

  /// Open connections of this instance.
  List<SppConnection> get connections => List.unmodifiable(_connections.values);

  /// Opens an RFCOMM connection to [address] for service [uuid] (SPP by
  /// default; 16-bit short forms like `1101` are accepted).
  ///
  /// * [secure]: use an authenticated link (`createRfcommSocketToServiceRecord`).
  ///   Set false for devices that only pair without a PIN.
  /// * [timeout]: total time for all attempts. Android's own connect has no
  ///   timeout, so the socket is closed when it expires.
  /// * [insecureFallback]: if the secure socket fails, try an insecure one.
  /// * [rfcommChannelFallback]: finally try the hidden
  ///   `createRfcommSocket(1)` through reflection, skipping the SDP service
  ///   lookup. Many cheap ELM327 clone dongles answer SDP wrongly and only
  ///   connect this way. Opt-in because it uses a non-public API and
  ///   assumes the service is on channel 1.
  ///
  /// Throws [SppConnectException] (or [SppTimeoutException]) when every
  /// attempt fails.
  Future<SppConnection> connect(
    String address, {
    String uuid = sppUuid,
    bool secure = true,
    Duration timeout = const Duration(seconds: 15),
    bool insecureFallback = false,
    bool rfcommChannelFallback = false,
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    _listenToConnectionEvents();
    final id = _nextId();
    final connection = SppConnection._(id, address, _connections.remove);
    // Registered before the call so no early data event is lost.
    _connections[id] = connection;
    try {
      await _invoke<void>('connect', {
        'id': id,
        'address': address,
        'uuid': uuid,
        'secure': secure,
        'timeoutMs': timeout.inMilliseconds,
        'insecureFallback': insecureFallback,
        'channelFallback': rfcommChannelFallback,
      });
    } catch (_) {
      connection._handleClosed(null);
      rethrow;
    }
    connection._markConnected();
    return connection;
  }

  void _listenToConnectionEvents() {
    _connectionEvents ??= connectionsChannel
        .receiveBroadcastStream()
        .listen(_onConnectionEvent, onError: (Object _) {});
  }

  void _onConnectionEvent(Object? event) {
    final map = event! as Map<Object?, Object?>;
    final connection = _connections[map['id']];
    if (connection == null) return;
    switch (map['event']) {
      case 'data':
        connection._handleData(map['bytes']! as Uint8List);
      case 'closed':
        connection._handleClosed(map['error'] as String?);
    }
  }

  static String _nextId() {
    _counter++;
    // Random prefix so ids stay unique across hot restarts, when native
    // connections from the previous Dart isolate may still be open.
    final prefix = _random.nextInt(1 << 32).toRadixString(16);
    return '$prefix-$_counter';
  }

  Future<T?> _invoke<T>(String method, [Object? args]) =>
      guardPlatform(() => methodChannel.invokeMethod<T>(method, args));

  static StreamTransformer<T, T> _errorMapper<T>() =>
      StreamTransformer<T, T>.fromHandlers(
        handleError: (e, st, sink) => sink.addError(mapStreamError(e), st),
      );
}
