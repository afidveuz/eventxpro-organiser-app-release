import 'package:equatable/equatable.dart';

/// Request entity for validating a scan against the Django DRF admission service.
class ScanRequest extends Equatable {
  final String qrToken;
  final int eventId;
  final int gateId;
  final String scanType;
  final String deviceId;
  final String scanRequestId;
  final DateTime scannedAt;
  final DateTime hardwareReceivedAt;

  ScanRequest({
    required this.qrToken,
    required this.eventId,
    required this.gateId,
    this.scanType = 'ENTRY',
    required this.deviceId,
    required this.scanRequestId,
    DateTime? scannedAt,
    DateTime? hardwareReceivedAt,
  })  : scannedAt = scannedAt ?? DateTime.now(),
        hardwareReceivedAt = hardwareReceivedAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'qr_token': qrToken,
      'event_id': eventId,
      'gate_id': gateId,
      'scan_type': scanType,
      'device_id': deviceId,
      'scan_request_id': scanRequestId,
      'scanned_at': scannedAt.toUtc().toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        qrToken,
        eventId,
        gateId,
        scanType,
        deviceId,
        scanRequestId,
        scannedAt,
      ];
}
