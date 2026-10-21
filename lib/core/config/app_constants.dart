import 'package:flutter/material.dart';

/// Application and Scanner Constants based on EventXPro specification.
class AppConstants {
  // Native Platform Channels
  static const String scannerEventChannel = 'eventxpro/scanner';
  static const String scannerControlChannel = 'eventxpro/scanner_control';
  static const String dataWedgeIntentAction = 'com.eventxpro.SCAN';
  static const String dataWedgePayloadExtra = 'com.symbol.datawedge.data_string';
  static const String dataWedgeProfileName = 'EventXPro_Scanner';

  // API Endpoints & Configuration
  static const String defaultBaseUrl = 'https://api-ism-plme-gfm-ghf-staging.eventxpro.com/';
  static const String loginEndpoint = 'organizer/login';
  static const String countriesEndpoint = 'microsite/v2/countries/';
  static const String refreshTokenEndpoint = 'exhibitor/refresh_token';
  static const String generateOtpEndpoint = 'organizer/generate-otp';
  static const String scanValidateEndpoint = '/api/v1/access-control/scans/validate/';

  // Master Secret for changing backend Base URL
  static const String masterPassword = 'Veuz@url4788';

  // Debug Test Credentials
  static const String debugUsername = 'amar';
  static const String debugPassword = 'Amar@1234788';

  // Branding Colors matching React Native theme
  static const Color brandAccent = Color(0xFFC10067); // rgba(193, 0, 103, 1)
  static const Color brandBg = Color(0xFF171C26);
  static const Color brandBorder = Color(0x99FFFFFF); // rgba(255, 255, 255, 0.60)
  static const Color brandError = Color(0xFFF14C4C);
  static const Color brandGrey = Color(0xFFABABAB);

  // Timing Benchmarks & Thresholds
  /// Benchmark: 300 ms suppression for identical barcode/QR value on the same device.
  static const int defaultDuplicateSuppressionMs = 300;

  /// Network timeout
  static const Duration defaultNetworkTimeout = Duration(seconds: 10);

  /// Feedback display hold time before auto-resetting back to ready-to-scan state.
  static const Duration feedbackDisplayDuration = Duration(milliseconds: 1800);

  /// Safe bounded FIFO queue size to prevent out-of-memory or unbounded async backpressure.
  static const int maxQueueCapacity = 50;

  // Defaults
  static const int defaultEventId = 1024;
  static const int defaultGateId = 12;
  static const String defaultScanType = 'ENTRY';
  static const String appVersion = '1.0.0+1';
}
