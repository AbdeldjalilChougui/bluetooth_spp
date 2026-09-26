import 'dart:async';
import 'dart:convert';

import 'package:bluetooth_spp/bluetooth_spp.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: DevicesPage()));

/// Lists paired and discovered devices.
class DevicesPage extends StatefulWidget {
  /// Creates the page.
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _spp = BluetoothSpp.instance;
  BluetoothPermissionsStatus? _permissions;
  List<BluetoothDevice> _bonded = [];
  final Map<String, DiscoveryResult> _found = {};
  StreamSubscription<DiscoveryResult>? _discovery;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _discovery?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final permissions = await _spp.permissionsStatus();
      // Request missing permissions with permission_handler here; this
      // plugin never requests them itself. See the README.
      final bonded = permissions.canConnect
          ? await _spp.bondedDevices()
          : <BluetoothDevice>[];
      setState(() {
        _permissions = permissions;
        _bonded = bonded;
        _error = null;
      });
    } on BluetoothSppException catch (e) {
      setState(() => _error = e.toString());
    }
  }

  void _toggleDiscovery() {
    if (_discovery != null) {
      _discovery!.cancel();
      setState(() => _discovery = null);
      return;
    }
    _found.clear();
    setState(() {
      _discovery = _spp.startDiscovery().listen(
            (r) => setState(() => _found[r.device.address] = r),
            onError: (Object e) => setState(() => _error = e.toString()),
            onDone: () => setState(() => _discovery = null),
          );
    });
  }

  void _open(BluetoothDevice device) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TerminalPage(device: device),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = _permissions;
    return Scaffold(
      appBar: AppBar(
        title: const Text('bluetooth_spp'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: _toggleDiscovery,
            icon: Icon(_discovery == null ? Icons.search : Icons.stop),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (p != null && !p.allGranted)
            ListTile(
              leading: const Icon(Icons.warning),
              title: const Text('Missing permissions'),
              subtitle: Text(p.missing.join('\n')),
            ),
          if (_error != null)
            ListTile(leading: const Icon(Icons.error), title: Text(_error!)),
          const ListTile(title: Text('Paired')),
          for (final d in _bonded)
            ListTile(
              title: Text(d.name ?? d.address),
              subtitle: Text(d.address),
              onTap: () => _open(d),
            ),
          const ListTile(title: Text('Discovered')),
          for (final r in _found.values)
            ListTile(
              title: Text(r.device.name ?? r.device.address),
              subtitle: Text('${r.device.address}  ${r.rssi ?? '?'} dBm'),
              onTap: () => _open(r.device),
            ),
        ],
      ),
    );
  }
}

/// A minimal serial terminal for one device.
class TerminalPage extends StatefulWidget {
  /// Creates the page.
  const TerminalPage({super.key, required this.device});

  /// The device to connect to.
  final BluetoothDevice device;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _log = StringBuffer();
  final _input = TextEditingController(text: 'ATZ');
  SppConnection? _connection;
  bool _connecting = true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final c = await BluetoothSpp.instance.connect(
        widget.device.address,
        insecureFallback: true,
        rfcommChannelFallback: true,
      );
      if (!mounted) {
        await c.close();
        return;
      }
      c.input.listen(
        (bytes) => setState(() => _log.write(latin1.decode(bytes))),
        onDone: () {
          if (!mounted) return;
          setState(() =>
              _log.writeln('\n[disconnected ${c.disconnectReason ?? ''}]'));
        },
      );
      setState(() => _connection = c);
    } on BluetoothSppException catch (e) {
      if (mounted) setState(() => _log.writeln('[$e]'));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _send() async {
    final c = _connection;
    if (c == null) return;
    try {
      // Completes once the bytes are flushed to the socket.
      await c.write(latin1.encode('${_input.text}\r'));
    } on BluetoothSppException catch (e) {
      setState(() => _log.writeln('[$e]'));
    }
  }

  @override
  void dispose() {
    _connection?.close();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.device.name ?? widget.device.address)),
      body: Column(
        children: [
          if (_connecting) const LinearProgressIndicator(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Text(_log.toString(),
                  style: const TextStyle(fontFamily: 'monospace')),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(controller: _input),
                ),
              ),
              IconButton(onPressed: _send, icon: const Icon(Icons.send)),
            ],
          ),
        ],
      ),
    );
  }
}
