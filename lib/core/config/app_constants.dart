/// Application and Scanner Constants based on EventXPro Hardware QR Scanning specification.
class AppConstants {
  // Native Platform Channels
  static const String scannerEventChannel = 'eventxpro/scanner';
  static const String scannerControlChannel = 'eventxpro/scanner_control';
  static const String dataWedgeIntentAction = 'com.eventxpro.SCAN';
  static const String dataWedgePayloadExtra = 'com.symbol.datawedge.data_string';
  static const String dataWedgeProfileName = 'EventXPro_Scanner';

  // API Endpoints
  static const String defaultBaseUrl = 'https://api.eventxpro.com';
  static const String scanValidateEndpoint = '/api/v1/access-control/scans/validate/';

  // Timing Benchmarks & Thresholds
  /// Initial benchmark: 300 ms suppression for identical barcode/QR value on the same device.
  static const int defaultDuplicateSuppressionMs = 300;

  /// Network timeout starting point: 3 seconds.
  static const Duration defaultNetworkTimeout = Duration(seconds: 3);

  /// Feedback display hold time before auto-resetting back to ready-to-scan state.
  static const Duration feedbackDisplayDuration = Duration(milliseconds: 1800);

  /// Safe bounded FIFO queue size to prevent out-of-memory or unbounded async backpressure.
  static const int maxQueueCapacity = 50;

  // Defaults
  static const int defaultEventId = 1024;
  static const int defaultGateId = 12;
  static const String defaultScanType = 'ENTRY'; // ENTRY, EXIT, SESSION, LEAD
  static const String appVersion = '1.0.0+1';
}
