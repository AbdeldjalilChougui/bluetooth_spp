import 'package:flutter/services.dart';

/// Base class of every error thrown by this plugin.
///
/// Native Android exceptions are mapped to one of the subclasses, so callers
/// can `switch` on the type instead of parsing message strings.
sealed class BluetoothSppException implements Exception {
  const BluetoothSppException(this.code, this.message);

  /// Maps a [PlatformException] from the Android side to a typed exception.
  factory BluetoothSppException.fromPlatformException(PlatformException e) {
    final message = e.message;
    return switch (e.code) {
      'bluetooth_unavailable' => BluetoothUnavailableException(message),
      'bluetooth_disabled' => BluetoothDisabledException(message),
      'permission_denied' => BluetoothPermissionException(message),
      'invalid_argument' => BluetoothSppArgumentException(message),
      'timeout' => SppTimeoutException(message),
      'connect_failed' => SppConnectException(message),
      'not_connected' => SppNotConnectedException(message),
      'io_error' => SppIoException(message),
      'activity_unavailable' => BluetoothActivityUnavailableException(message),
      'busy' => BluetoothBusyException(message),
      _ => UnknownBluetoothSppException(e.code, message),
    };
  }

  /// Stable error code shared with the Android side, e.g. `connect_failed`.
  final String code;

  /// Human-readable detail, usually the native exception message.
  final String? message;

  @override
  String toString() =>
      '$runtimeType($code${message == null ? '' : ': $message'})';
}

/// The device has no Bluetooth adapter.
final class BluetoothUnavailableException extends BluetoothSppException {
  /// Creates the exception.
  const BluetoothUnavailableException([String? message])
      : super('bluetooth_unavailable', message);
}

/// Bluetooth is turned off. See `BluetoothSpp.requestEnable`.
final class BluetoothDisabledException extends BluetoothSppException {
  /// Creates the exception.
  const BluetoothDisabledException([String? message])
      : super('bluetooth_disabled', message);
}

/// A runtime permission (BLUETOOTH_CONNECT, BLUETOOTH_SCAN or location) is
/// missing. The plugin never requests permissions itself.
final class BluetoothPermissionException extends BluetoothSppException {
  /// Creates the exception.
  const BluetoothPermissionException([String? message])
      : super('permission_denied', message);
}

/// An argument was rejected, for example a malformed address or UUID.
final class BluetoothSppArgumentException extends BluetoothSppException {
  /// Creates the exception.
  const BluetoothSppArgumentException([String? message])
      : super('invalid_argument', message);
}

/// Opening the RFCOMM socket failed on every attempt.
///
/// The classic `read failed, socket might closed or timeout, read ret: -1`
/// ends up here. See the README troubleshooting section.
final class SppConnectException extends BluetoothSppException {
  /// Creates the exception.
  const SppConnectException([String? message])
      : super('connect_failed', message);

  const SppConnectException._withCode(super.code, super.message);
}

/// The connect attempt did not finish within its timeout.
final class SppTimeoutException extends SppConnectException {
  /// Creates the exception.
  const SppTimeoutException([String? message])
      : super._withCode('timeout', message);
}

/// The connection is closed or unknown to the native side.
final class SppNotConnectedException extends BluetoothSppException {
  /// Creates the exception.
  const SppNotConnectedException([String? message])
      : super('not_connected', message);
}

/// Reading or writing an open socket failed.
final class SppIoException extends BluetoothSppException {
  /// Creates the exception.
  const SppIoException([String? message]) : super('io_error', message);
}

/// The call needs a foreground activity and none is attached.
final class BluetoothActivityUnavailableException
    extends BluetoothSppException {
  /// Creates the exception.
  const BluetoothActivityUnavailableException([String? message])
      : super('activity_unavailable', message);
}

/// Another request of the same kind is still pending.
final class BluetoothBusyException extends BluetoothSppException {
  /// Creates the exception.
  const BluetoothBusyException([String? message]) : super('busy', message);
}

/// A native error code this version does not know.
final class UnknownBluetoothSppException extends BluetoothSppException {
  /// Creates the exception.
  const UnknownBluetoothSppException(super.code, [super.message]);
}

/// Runs [body] and rethrows [PlatformException]s as [BluetoothSppException]s.
Future<T> guardPlatform<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PlatformException catch (e) {
    throw BluetoothSppException.fromPlatformException(e);
  }
}

/// Maps a stream error to a typed exception when it is a [PlatformException].
Object mapStreamError(Object error) => error is PlatformException
    ? BluetoothSppException.fromPlatformException(error)
    : error;
