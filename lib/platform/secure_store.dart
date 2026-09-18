import 'package:flutter/services.dart';

/// Secretos en el llavero de iOS (ver `KraftKeychain` en `AppDelegate.swift`).
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeychainStore implements SecureStore {
  const KeychainStore();

  static const channel = MethodChannel('kraft/secure');

  @override
  Future<String?> read(String key) async {
    try {
      return await channel.invokeMethod<String>('read', {'key': key});
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await channel.invokeMethod<bool>('write', {'key': key, 'value': value});
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await channel.invokeMethod<void>('delete', {'key': key});
    } on MissingPluginException {
      return;
    }
  }
}
