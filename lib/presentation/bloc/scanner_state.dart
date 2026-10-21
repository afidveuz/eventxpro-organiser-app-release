import 'package:equatable/equatable.dart';
import '../../domain/entities/scan_audit_item.dart';
import '../../domain/entities/scan_request.dart';
import '../../domain/entities/scan_response.dart';
import '../../domain/entities/telemetry_data.dart';

abstract class ScannerState extends Equatable {
  final int eventId;
  final int gateId;
  final String scanType;
  final String deviceId;
  final String adapterName;
  final bool isOfflineMode;
  final int queueDepth;
  final TelemetryData telemetry;
  final List<ScanAuditItem> recentScans;

  const ScannerState({
    required this.eventId,
    required this.gateId,
    required this.scanType,
    required this.deviceId,
    required this.adapterName,
    required this.isOfflineMode,
    required this.queueDepth,
    required this.telemetry,
    this.recentScans = const [],
  });

  @override
  List<Object?> get props => [
        eventId,
        gateId,
        scanType,
        deviceId,
        adapterName,
        isOfflineMode,
        queueDepth,
        telemetry.totalScans,
        telemetry.acceptedCount,
        telemetry.rejectedCount,
        telemetry.duplicateSuppressedCount,
        telemetry.queueDropCount,
        recentScans.length,
      ];
}

/// Initial state while binding to hardware EventChannel and loading storage
class ScannerInitialState extends ScannerState {
  const ScannerInitialState({
    required super.eventId,
    required super.gateId,
    required super.scanType,
    required super.deviceId,
    required super.adapterName,
    required super.isOfflineMode,
    required super.queueDepth,
    required super.telemetry,
    super.recentScans,
  });
}

/// Idle ready-to-scan state - pulse radar animation, awaits physical hardware scan
class ScannerReadyState extends ScannerState {
  final String statusMessage;

  const ScannerReadyState({
    required super.eventId,
    required super.gateId,
    required super.scanType,
    required super.deviceId,
    required super.adapterName,
    required super.isOfflineMode,
    required super.queueDepth,
    required super.telemetry,
    this.statusMessage = 'READY TO SCAN',
    super.recentScans,
  });

  @override
  List<Object?> get props => [...super.props, statusMessage];
}

/// In-flight processing state - scan received, bounded queue evaluating or in-flight API call
class ScannerProcessingState extends ScannerState {
  final String tokenSnippet;
  final String scanRequestId;

  const ScannerProcessingState({
    required super.eventId,
    required super.gateId,
    required super.scanType,
    required super.deviceId,
    required super.adapterName,
    required super.isOfflineMode,
    required super.queueDepth,
    required super.telemetry,
    required this.tokenSnippet,
    required this.scanRequestId,
    super.recentScans,
  });

  @override
  List<Object?> get props => [...super.props, tokenSnippet, scanRequestId];
}

/// Authoritative decision outcome state - renders full-screen visual feedback
class ScannerDecisionState extends ScannerState {
  final ScanRequest request;
  final ScanResponse response;
  final int autoResetSecondsRemaining;

  const ScannerDecisionState({
    required super.eventId,
    required super.gateId,
    required super.scanType,
    required super.deviceId,
    required super.adapterName,
    required super.isOfflineMode,
    required super.queueDepth,
    required super.telemetry,
    required this.request,
    required this.response,
    this.autoResetSecondsRemaining = 2,
    super.recentScans,
  });

  bool get isSuccess => response.code.isSuccess;
  bool get isWarning => response.code.isWarning;
  bool get isRejected => response.code.isRejected;
  bool get isNetworkError => response.code.isNetworkError;

  @override
  List<Object?> get props => [
        ...super.props,
        request,
        response,
        autoResetSecondsRemaining,
      ];
}
