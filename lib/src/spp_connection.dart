part of 'bluetooth_spp.dart';

/// Lifecycle of an [SppConnection].
enum SppConnectionState {
  /// The socket is open.
  connected,

  /// The socket was closed locally or by the remote device.
  disconnected,
}

/// An open RFCOMM serial connection returned by `BluetoothSpp.connect`.
class SppConnection {
  SppConnection._(this.id, this.address, this._remove);

  /// Opaque id that routes native events to this connection.
  final String id;

  /// Address of the remote device.
  final String address;

  final void Function(String id) _remove;
  final _input = StreamController<Uint8List>();
  final _state = StreamController<SppConnectionState>.broadcast();
  bool _connected = false;
  bool _ended = false;
  String? _disconnectReason;

  /// Bytes received from the device, in order, in whatever chunks the radio
  /// delivered them. A reply such as `41 0C 1A F8\r\r>` can arrive split
  /// over several events; reassemble by your protocol's delimiter.
  ///
  /// Single subscription: data received before you listen is buffered. Use
  /// `asBroadcastStream()` for several listeners. The stream closes when the
  /// connection ends.
  Stream<Uint8List> get input => _input.stream;

  /// Emits [SppConnectionState.disconnected] once, when the connection ends.
  Stream<SppConnectionState> get state => _state.stream;

  /// Whether the socket is open.
  bool get isConnected => _connected;

  /// Native message explaining a remote disconnect, or null after a local
  /// [close] or a clean end of stream.
  String? get disconnectReason => _disconnectReason;

  void _markConnected() {
    if (!_ended) _connected = true;
  }

  /// Sends [bytes]. The future completes once the Android side has written
  /// and flushed them to the socket, so awaiting each write gives natural
  /// backpressure. Writes are sent in call order.
  ///
  /// Throws [SppNotConnectedException] after the connection ended, and
  /// [SppIoException] if the socket write fails.
  Future<void> write(List<int> bytes) {
    if (!_connected) {
      return Future.error(const SppNotConnectedException('Connection closed'));
    }
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    return guardPlatform(() =>
        methodChannel.invokeMethod<void>('write', {'id': id, 'bytes': data}));
  }

  /// Closes the socket. Safe to call more than once. Pending writes fail
  /// with [SppNotConnectedException].
  Future<void> close() async {
    if (_ended) return;
    _connected = false;
    try {
      await guardPlatform(
          () => methodChannel.invokeMethod<void>('disconnect', {'id': id}));
    } on SppNotConnectedException {
      // Already gone on the native side.
    } finally {
      _handleClosed(null);
    }
  }

  void _handleData(Uint8List bytes) {
    if (!_ended) _input.add(bytes);
  }

  void _handleClosed(String? reason) {
    if (_ended) return;
    _ended = true;
    _connected = false;
    _disconnectReason = reason;
    _remove(id);
    _input.close();
    _state
      ..add(SppConnectionState.disconnected)
      ..close();
  }

  @override
  String toString() =>
      'SppConnection($id, $address, ${_connected ? 'connected' : 'closed'})';
}
