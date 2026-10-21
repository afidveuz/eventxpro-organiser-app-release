import 'package:equatable/equatable.dart';
import 'scan_decision_code.dart';

/// Representation of a processed scan in the session audit log.
class ScanAuditItem extends Equatable {
  final DateTime timestamp;
  final String qrToken;
  final ScanDecisionCode code;
  final String status;
  final String message;
  final String? attendeeName;
  final String? badgeType;
  final String? company;
  final int latencyMs;
  final String scanRequestId;
  final String? testApiResponse;

  const ScanAuditItem({
    required this.timestamp,
    required this.qrToken,
    required this.code,
    required this.status,
    required this.message,
    this.attendeeName,
    this.badgeType,
    this.company,
    required this.latencyMs,
    required this.scanRequestId,
    this.testApiResponse,
  });

  @override
  List<Object?> get props => [
        timestamp,
        qrToken,
        code,
        status,
        message,
        attendeeName,
        badgeType,
        latencyMs,
        scanRequestId,
        testApiResponse,
      ];
}
