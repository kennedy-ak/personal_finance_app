import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/bank_sms_parser.dart';

/// Reads transaction alerts from the device inbox via the platform channel
/// registered in MainActivity. Web/desktop return no messages — the feature
/// simply has nothing to do there.
class DeviceSmsReader {
  static const _channel = MethodChannel('personal_finance/sms');

  Future<bool> isGranted() async => await Permission.sms.status.isGranted;

  /// False when the user has permanently denied, so the app should send them
  /// to system settings instead of re-prompting forever.
  Future<bool> isPermanentlyDenied() async =>
      await Permission.sms.status.isPermanentlyDenied;

  Future<bool> request() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  Future<List<RawSms>> query({
    required List<String> addresses,
    DateTime? since,
    int limit = 400,
  }) async {
    if (addresses.isEmpty) return const [];
    try {
      final rows = await _channel.invokeListMethod<Map>('query', {
        'addresses': addresses,
        'since': since?.millisecondsSinceEpoch ?? 0,
        'limit': limit,
      });
      if (rows == null) return const [];
      return [
        for (final row in rows)
          RawSms(
            address: row['address'] as String? ?? '',
            body: row['body'] as String? ?? '',
            receivedAt: DateTime.fromMillisecondsSinceEpoch(
              (row['received_at'] as num?)?.toInt() ?? 0,
            ),
            providerId: row['provider_id'] as String? ?? '',
          ),
      ];
    } on PlatformException catch (e) {
      if (e.code == 'permission') {
        throw SmsPermissionException();
      }
      if (e.code == 'bad_args' || e.code == 'unimplemented') {
        return const [];
      }
      rethrow;
    }
  }
}

class SmsPermissionException implements Exception {
  @override
  String toString() => 'Permission to read SMS was not granted.';
}

final deviceSmsReaderProvider = Provider<DeviceSmsReader>((_) => DeviceSmsReader());
