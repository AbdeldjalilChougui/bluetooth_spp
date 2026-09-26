import 'dart:async';

import 'package:bluetooth_spp/bluetooth_spp.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _methods = MethodChannel('dev.abdeldjalilchougui/bluetooth_spp/methods');
const _adapterState =
    EventChannel('dev.abdeldjalilchougui/bluetooth_spp/adapter_state');
const _discovery =
    EventChannel('dev.abdeldjalilchougui/bluetooth_spp/discovery');
const _connections =
    EventChannel('dev.abdeldjalilchougui/bluetooth_spp/connections');

const _address = '00:1D:A5:68:98:8B';

Map<String, Object?> _device(String address, {String? name}) => {
      'name': name,
      'address': address,
      'type': 1,
      'bondState': 12,
      'deviceClass': 0x1F00,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late BluetoothSpp spp;
  late List<MethodCall> calls;
  late Future<Object?> Function(MethodCall call) onCall;
  MockStreamHandlerEventSink? connectionSink;
  late int connectionListens;

  setUp(() {
    spp = BluetoothSpp.newInstance();
    calls = [];
    connectionListens = 0;
    connectionSink = null;
    onCall = (call) async => null;
    messenger.setMockMethodCallHandler(_methods, (call) {
      calls.add(call);
      return onCall(call);
    });
    messenger.setMockStreamHandler(
      _connections,
      MockStreamHandler.inline(onListen: (args, sink) {
        connectionListens++;
        connectionSink = sink;
      }),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockStreamHandler(_connections, null);
    messenger.setMockStreamHandler(_discovery, null);
    messenger.setMockStreamHandler(_adapterState, null);
  });

  void emit(Map<String, Object?> event) => connectionSink!.success(event);

  group('adapter', () {
    test('isEnabled and currentAdapterState', () async {
      onCall = (call) async => switch (call.method) {
            'isEnabled' => true,
            'adapterState' => 12,
            _ => null,
          };
      expect(await spp.isEnabled(), isTrue);
      expect(await spp.currentAdapterState(), BluetoothAdapterState.on);
    });

    test('adapterState stream maps native ints', () async {
      messenger.setMockStreamHandler(
        _adapterState,
        MockStreamHandler.inline(onListen: (args, sink) {
          sink
            ..success(10)
            ..success(11)
            ..success(12)
            ..endOfStream();
        }),
      );
      expect(
        await spp.adapterState.toList(),
        [
          BluetoothAdapterState.off,
          BluetoothAdapterState.turningOn,
          BluetoothAdapterState.on,
        ],
      );
    });

    test('requestEnable returns the activity result', () async {
      onCall = (call) async => call.method == 'requestEnable' ? false : null;
      expect(await spp.requestEnable(), isFalse);
    });

    test('requestEnable maps a missing activity', () async {
      onCall =
          (call) async => throw PlatformException(code: 'activity_unavailable');
      await expectLater(spp.requestEnable(),
          throwsA(isA<BluetoothActivityUnavailableException>()));
    });

    test('bondedDevices parses every device', () async {
      onCall = (call) async => [
            _device(_address, name: 'OBDII'),
            _device('11:22:33:44:55:66', name: 'Printer'),
          ];
      final devices = await spp.bondedDevices();
      expect(calls.single.method, 'bondedDevices');
      expect(devices.map((d) => d.name), ['OBDII', 'Printer']);
      expect(devices.first.bondState, BluetoothBondState.bonded);
    });

    test('bond and removeBond pass the address', () async {
      onCall = (call) async => true;
      expect(await spp.bond(_address), isTrue);
      expect(await spp.removeBond(_address), isTrue);
      expect(calls.map((c) => c.method), ['bond', 'removeBond']);
      expect(calls.map((c) => (c.arguments as Map)['address']),
          [_address, _address]);
    });

    test('permissionsStatus', () async {
      onCall = (call) async => {
            'sdkInt': 34,
            'connectGranted': false,
            'scanGranted': false,
            'missing': [
              'android.permission.BLUETOOTH_CONNECT',
              'android.permission.BLUETOOTH_SCAN',
            ],
          };
      final s = await spp.permissionsStatus();
      expect(s.canConnect, isFalse);
      expect(s.missing, hasLength(2));
    });

    test('permission errors are typed', () async {
      onCall = (call) async => throw PlatformException(
          code: 'permission_denied', message: 'Need BLUETOOTH_CONNECT');
      await expectLater(
          spp.bondedDevices(), throwsA(isA<BluetoothPermissionException>()));
    });
  });

  group('discovery', () {
    test('emits results with rssi and ends when native finishes', () async {
      messenger.setMockStreamHandler(
        _discovery,
        MockStreamHandler.inline(onListen: (args, sink) {
          sink
            ..success({..._device(_address, name: 'OBDII'), 'rssi': -58})
            ..success({..._device('11:22:33:44:55:66'), 'rssi': null})
            ..endOfStream();
        }),
      );
      final results = await spp.startDiscovery().toList();
      expect(results, hasLength(2));
      expect(results[0].device.name, 'OBDII');
      expect(results[0].rssi, -58);
      expect(results[1].rssi, isNull);
    });

    test('maps discovery errors', () async {
      messenger.setMockStreamHandler(
        _discovery,
        MockStreamHandler.inline(onListen: (args, sink) {
          sink.error(code: 'bluetooth_disabled', message: 'off');
        }),
      );
      await expectLater(spp.startDiscovery().first,
          throwsA(isA<BluetoothDisabledException>()));
    });

    test('cancelling the subscription cancels native discovery', () async {
      var cancelled = false;
      MockStreamHandlerEventSink? sink;
      messenger.setMockStreamHandler(
        _discovery,
        MockStreamHandler.inline(
          onListen: (args, s) => sink = s,
          onCancel: (args) => cancelled = true,
        ),
      );
      final sub = spp.startDiscovery().listen((_) {});
      await pumpEventQueue();
      expect(sink, isNotNull);
      await sub.cancel();
      await pumpEventQueue();
      expect(cancelled, isTrue);
    });

    test('cancelDiscovery calls native', () async {
      await spp.cancelDiscovery();
      expect(calls.single.method, 'cancelDiscovery');
    });
  });

  group('connect', () {
    test('success sends options and returns a connected SppConnection',
        () async {
      final conn = await spp.connect(
        _address,
        timeout: const Duration(seconds: 3),
        insecureFallback: true,
        rfcommChannelFallback: true,
      );
      final call = calls.single;
      expect(call.method, 'connect');
      final args = call.arguments as Map;
      expect(args['address'], _address);
      expect(args['uuid'], BluetoothSpp.sppUuid);
      expect(args['secure'], isTrue);
      expect(args['timeoutMs'], 3000);
      expect(args['insecureFallback'], isTrue);
      expect(args['channelFallback'], isTrue);
      expect(args['id'], conn.id);
      expect(conn.address, _address);
      expect(conn.isConnected, isTrue);
      expect(spp.connections, [conn]);
      expect(connectionListens, 1);
    });

    test('fallbacks are off by default', () async {
      await spp.connect(_address);
      final args = calls.single.arguments as Map;
      expect(args['insecureFallback'], isFalse);
      expect(args['channelFallback'], isFalse);
      expect(args['secure'], isTrue);
      expect(args['timeoutMs'], 15000);
    });

    test('failure maps to SppConnectException and leaves no connection',
        () async {
      onCall = (call) async => throw PlatformException(
          code: 'connect_failed',
          message: 'read failed, socket might closed or timeout, read ret: -1');
      await expectLater(
        spp.connect(_address),
        throwsA(isA<SppConnectException>()
            .having((e) => e.message, 'message', contains('read failed'))),
      );
      expect(spp.connections, isEmpty);
    });

    test('timeout maps to SppTimeoutException', () async {
      onCall = (call) async => throw PlatformException(code: 'timeout');
      await expectLater(
          spp.connect(_address), throwsA(isA<SppTimeoutException>()));
    });

    test('disabled adapter maps to BluetoothDisabledException', () async {
      onCall =
          (call) async => throw PlatformException(code: 'bluetooth_disabled');
      await expectLater(
          spp.connect(_address), throwsA(isA<BluetoothDisabledException>()));
    });

    test('a non-positive timeout is rejected before calling native', () {
      expect(() => spp.connect(_address, timeout: Duration.zero),
          throwsArgumentError);
      expect(calls, isEmpty);
    });
  });

  group('SppConnection', () {
    test('input stream delivers chunks split across events in order', () async {
      final conn = await spp.connect(_address);
      final received = <int>[];
      final done = Completer<void>();
      conn.input.listen(received.addAll, onDone: done.complete);
      emit({'id': conn.id, 'event': 'data', 'bytes': utf8Bytes('41 0')});
      emit({'id': conn.id, 'event': 'data', 'bytes': utf8Bytes('C 1A F8')});
      emit({'id': conn.id, 'event': 'data', 'bytes': utf8Bytes('\r\r>')});
      emit({'id': conn.id, 'event': 'closed'});
      await done.future;
      expect(String.fromCharCodes(received), '41 0C 1A F8\r\r>');
      expect(conn.isConnected, isFalse);
    });

    test('data that arrives before a listener is buffered', () async {
      final conn = await spp.connect(_address);
      emit({'id': conn.id, 'event': 'data', 'bytes': utf8Bytes('ELM327')});
      await pumpEventQueue();
      final first = await conn.input.first;
      expect(String.fromCharCodes(first), 'ELM327');
    });

    test('write completes when native reports the flush', () async {
      final flushed = Completer<Object?>();
      onCall =
          (call) => call.method == 'write' ? flushed.future : Future.value();
      final conn = await spp.connect(_address);
      var completed = false;
      final write =
          conn.write(utf8Bytes('ATZ\r')).then((_) => completed = true);
      await pumpEventQueue();
      expect(completed, isFalse, reason: 'must wait for the native flush');
      final args = calls.last.arguments as Map;
      expect(args['id'], conn.id);
      expect(args['bytes'], isA<Uint8List>());
      expect(args['bytes'], utf8Bytes('ATZ\r'));
      flushed.complete(null);
      await write;
      expect(completed, isTrue);
    });

    test('write errors are typed', () async {
      final conn = await spp.connect(_address);
      onCall = (call) async =>
          throw PlatformException(code: 'io_error', message: 'Broken pipe');
      await expectLater(conn.write([1, 2, 3]), throwsA(isA<SppIoException>()));
    });

    test('close disconnects natively, ends input and state', () async {
      final conn = await spp.connect(_address);
      final states = <SppConnectionState>[];
      conn.state.listen(states.add);
      final inputDone = Completer<void>();
      conn.input.listen(null, onDone: inputDone.complete);
      await conn.close();
      expect(calls.last.method, 'disconnect');
      expect((calls.last.arguments as Map)['id'], conn.id);
      await inputDone.future;
      await pumpEventQueue();
      expect(conn.isConnected, isFalse);
      expect(states, [SppConnectionState.disconnected]);
      expect(spp.connections, isEmpty);
      await expectLater(
          conn.write([1]), throwsA(isA<SppNotConnectedException>()));
      // A second close is a no-op.
      final before = calls.length;
      await conn.close();
      expect(calls.length, before);
    });

    test('close tolerates a connection the native side already dropped',
        () async {
      final conn = await spp.connect(_address);
      onCall = (call) async => throw PlatformException(code: 'not_connected');
      await conn.close();
      expect(conn.isConnected, isFalse);
    });

    test('remote disconnect ends input and records the reason', () async {
      final conn = await spp.connect(_address);
      final states = <SppConnectionState>[];
      conn.state.listen(states.add);
      emit({
        'id': conn.id,
        'event': 'closed',
        'error': 'bt socket closed, read return: -1',
      });
      await expectLater(conn.input, emitsDone);
      expect(conn.isConnected, isFalse);
      expect(conn.disconnectReason, 'bt socket closed, read return: -1');
      await pumpEventQueue();
      expect(states, [SppConnectionState.disconnected]);
      expect(spp.connections, isEmpty);
    });

    test('several connections at once are routed by id', () async {
      final a = await spp.connect(_address);
      final b = await spp.connect('11:22:33:44:55:66');
      expect(a.id, isNot(b.id));
      expect(spp.connections, hasLength(2));
      expect(connectionListens, 1, reason: 'one shared event subscription');

      final gotA = <int>[];
      final gotB = <int>[];
      a.input.listen(gotA.addAll);
      b.input.listen(gotB.addAll);
      emit({'id': b.id, 'event': 'data', 'bytes': utf8Bytes('scale:12.5')});
      emit({'id': a.id, 'event': 'data', 'bytes': utf8Bytes('41 0D 32')});
      emit({'id': 'unknown', 'event': 'data', 'bytes': utf8Bytes('x')});
      await pumpEventQueue();
      expect(String.fromCharCodes(gotA), '41 0D 32');
      expect(String.fromCharCodes(gotB), 'scale:12.5');

      await a.close();
      expect(a.isConnected, isFalse);
      expect(b.isConnected, isTrue);
      expect(spp.connections, [b]);

      await b.write([0x1B, 0x40]);
      expect((calls.last.arguments as Map)['id'], b.id);
    });

    test('connection ids are unique across instances', () async {
      final other = BluetoothSpp.newInstance();
      final a = await spp.connect(_address);
      final b = await other.connect(_address);
      expect(a.id, isNot(b.id));
    });
  });
}

Uint8List utf8Bytes(String s) => Uint8List.fromList(s.codeUnits);
