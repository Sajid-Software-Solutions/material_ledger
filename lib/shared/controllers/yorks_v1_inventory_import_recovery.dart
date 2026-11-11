import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One durable pending import per signed-in authority. Not an offline queue:
/// replay always requires an explicit user action and server confirmation.
class YorksV1InventoryImportRecovery {
  YorksV1InventoryImportRecovery(this.preferences, this.key);
  final SharedPreferences preferences;
  final String key;
  bool active = true;
  bool busy = false;
  bool get exists => preferences.containsKey(key);
  Map<String, dynamic> read() {
    try {
      final stored = preferences.getString(key)!;
      final json = stored.startsWith('gz1:')
          ? utf8.decode(
              GZipDecoder().decodeBytes(base64Decode(stored.substring(4))),
            )
          : stored;
      return Map<String, dynamic>.from(jsonDecode(json) as Map);
    } catch (_) {
      throw const FormatException('Invalid inventory import recovery record');
    }
  }

  Future<void> persist(Map<String, Object?>? record) async {
    if (record != null && !active) throw StateError('Authority changed');
    await preferences.reload();
    if (record != null && exists) {
      final old = read();
      if (old['key'] != record['key'] ||
          jsonEncode(old['payload']) != jsonEncode(record['payload'])) {
        throw StateError('Resolve the previous import first');
      }
    }
    // Large supported workbooks contain repeated field names and values.
    // Compress the recovery copy so those rows do not exhaust browser storage.
    final encoded = record == null
        ? null
        : 'gz1:${base64Encode(GZipEncoder().encode(utf8.encode(jsonEncode(record))))}';
    final saved = encoded == null
        ? await preferences.remove(key)
        : await preferences.setString(key, encoded);
    if (!saved) throw StateError('Recovery storage unavailable');
  }
}
