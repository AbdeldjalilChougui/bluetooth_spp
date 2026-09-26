import 'package:flutter/services.dart';

const _prefix = 'dev.abdeldjalilchougui/bluetooth_spp';

/// Method calls to the Android side.
const methodChannel = MethodChannel('$_prefix/methods');

/// Adapter state changes as `BluetoothAdapter.STATE_*` ints.
const adapterStateChannel = EventChannel('$_prefix/adapter_state');

/// Discovery results; listening starts discovery, cancelling stops it.
const discoveryChannel = EventChannel('$_prefix/discovery');

/// Data and close events of every connection, tagged with the connection id.
const connectionsChannel = EventChannel('$_prefix/connections');
