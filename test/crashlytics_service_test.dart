import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/services/crashlytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CrashlyticsService & ServerDownException Tests', () {
    test('ServerDownException formats error message with status code and endpoint', () {
      final ex = ServerDownException(
        statusCode: 502,
        endpoint: 'organizer/event-entrance',
        baseUrl: 'https://api.eventxpro.com/',
        message: 'Bad Gateway upstream error',
      );

      expect(ex.statusCode, equals(502));
      expect(ex.endpoint, equals('organizer/event-entrance'));
      expect(ex.baseUrl, equals('https://api.eventxpro.com/'));
      expect(ex.message, equals('Bad Gateway upstream error'));
      expect(ex.toString(), contains('502'));
      expect(ex.toString(), contains('Bad Gateway upstream error'));
      expect(ex.toString(), contains('https://api.eventxpro.com/organizer/event-entrance'));
    });

    test('ServerDownException formats network failure without HTTP status code', () {
      final ex = ServerDownException(
        endpoint: 'organizer/login',
        baseUrl: 'https://api.eventxpro.com/',
        message: 'Connection timed out',
      );

      expect(ex.statusCode, isNull);
      expect(ex.toString(), contains('Network/Transport Failure'));
      expect(ex.toString(), contains('Connection timed out'));
    });

    test('CrashlyticsService singleton and safe execution when Firebase is uninitialized', () async {
      final service1 = CrashlyticsService();
      final service2 = CrashlyticsService();
      expect(identical(service1, service2), isTrue);

      // Should not throw even when Firebase is not running in test runner
      await service1.setDeviceContext(
        deviceId: 'TEST-DEV-1',
        eventId: 10,
        gateId: 2,
        username: 'staff_1',
      );

      await service1.recordServerDown(
        endpoint: 'organizer/event-entrance',
        baseUrl: 'https://test.eventxpro.com/',
        statusCode: 503,
        errorMessage: 'Service Unavailable',
      );

      // Throttled duplicate call within 60s should complete safely
      await service1.recordServerDown(
        endpoint: 'organizer/event-entrance',
        baseUrl: 'https://test.eventxpro.com/',
        statusCode: 503,
        errorMessage: 'Service Unavailable (duplicate)',
      );

      service1.log('Test breadcrumb');
    });
  });
}
