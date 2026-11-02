import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/data/models/onsite_coupon_details_model.dart';
import 'package:qr_scanner/data/models/qr_blacklist_user_model.dart';
import 'package:qr_scanner/domain/repositories/i_qr_verification_repository.dart';
import 'package:qr_scanner/presentation/screens/qr_verification_screen.dart';
import 'package:qr_scanner/presentation/widgets/attendee_info_sheet.dart';

class MockQrVerificationRepo implements IQrVerificationRepository {
  QrUserDetailsModel? mockUserDetails;
  bool shouldThrow = false;
  String? lastScannedTicketId;
  int? lastScannedEventId;

  @override
  Future<QrUserDetailsModel> getUserDetails({
    required int eventId,
    required String ticketId,
  }) async {
    lastScannedEventId = eventId;
    lastScannedTicketId = ticketId;

    if (shouldThrow) {
      throw Exception('Attendee not found with badge ID');
    }

    return mockUserDetails ??
        QrUserDetailsModel(
          status: true,
          message: 'Verified User',
          ticketId: ticketId,
          userDetails: const QrAttendeeDetails(
            firstname: 'John',
            lastname: 'Doe',
            companyName: 'Acme Global Inc',
            uniqueId: 'URN-JOHN-123',
            email: 'john.doe@example.com',
            country: 'United Arab Emirates',
            displayTicketName: 'VIP Delegate Pass',
            seatNo: 'A-42',
          ),
          lastCheckinSession: 'Main Entrance Hall 1',
          lastCheckinTime: '10:30:00',
          sessionAccess: const [
            SessionAccessItem(
              title: 'Opening Keynote Speech',
              startTm: '11:00',
              hallName: 'Grand Ballroom',
            ),
            SessionAccessItem(
              title: 'AI in Event Management',
              startTm: '14:00',
              hallName: 'Hall 2',
            ),
          ],
        );
  }

  @override
  Future<String> updateBlacklistStatus({
    required String ticketId,
    required bool blacklistStatus,
    required String notes,
    int? eventId,
    String? uniqueId,
  }) async {
    return 'Status updated';
  }

  @override
  Future<OnsiteCouponModel> getCouponDetails({required String couponCode}) async {
    throw UnimplementedError();
  }
}

void main() {
  group('QrVerificationScreen & AttendeeInfoSheet Tests', () {
    late MockQrVerificationRepo mockRepo;

    setUp(() {
      mockRepo = MockQrVerificationRepo();
    });

    testWidgets('Renders QR Verification screen UI with top bar and scan prompts',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: QrVerificationScreen(
            eventId: 108,
            eventName: 'Tech Summit 2026',
            repository: mockRepo,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Verify title & event name
      expect(find.text('QR Verification'), findsOneWidget);
      expect(find.text('Tech Summit 2026'), findsOneWidget);
      expect(find.text('Scan any QR'), findsOneWidget);
      expect(
        find.text('Position the attendee QR code within the frame'),
        findsOneWidget,
      );
      expect(find.text('Camera Active'), findsOneWidget);
    });

    testWidgets('AttendeeInfoSheet displays verified user credentials correctly',
        (tester) async {
      const attendee = QrUserDetailsModel(
        status: true,
        message: 'Verified User',
        ticketId: 'TICKET-TEST-1',
        userDetails: QrAttendeeDetails(
          firstname: 'Sarah',
          lastname: 'Connor',
          companyName: 'Cyberdyne Systems',
          uniqueId: 'URN-SC-999',
          email: 'sarah@cyberdyne.com',
          country: 'United States',
          displayTicketName: 'Platinum VIP',
          seatNo: 'B-12',
          displayTicketCode: 'CODE-99',
        ),
        lastCheckinSession: 'VIP Entrance',
        lastCheckinTime: '09:15:00',
        sessionAccess: [
          SessionAccessItem(
            title: 'Robotics Workshop',
            startTm: '10:00',
            hallName: 'Hall C',
          ),
        ],
      );

      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendeeInfoSheet(
              attendee: attendee,
              onClose: () => closed = true,
            ),
          ),
        ),
      );

      // Verify Header
      expect(find.text('Verified User'), findsOneWidget);

      // Verify attendee name & company
      expect(find.text('SARAH CONNOR'), findsOneWidget);
      expect(find.text('Cyberdyne Systems'), findsOneWidget);
      expect(find.text('Ticket ID: URN-SC-999'), findsOneWidget);
      expect(find.text('Seat No: B-12'), findsOneWidget);
      expect(find.text('Display Code: CODE-99'), findsOneWidget);
      expect(find.text('Country: United States'), findsOneWidget);
      expect(find.text('Email: sarah@cyberdyne.com'), findsOneWidget);
      expect(find.text('Platinum VIP'), findsOneWidget);

      // Verify Last Checkin & Session Access
      expect(find.textContaining('VIP Entrance'), findsOneWidget);
      expect(find.text('Access'), findsOneWidget);
      expect(find.text('Robotics Workshop'), findsOneWidget);

      // Test close button
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(closed, isTrue);
    });

    testWidgets('Toggling camera switch toggles hardware ready / camera active states',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: QrVerificationScreen(
            eventId: 108,
            eventName: 'Tech Summit 2026',
            repository: mockRepo,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Camera Active'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);

      // Tap to toggle to hardware scanner mode
      await tester.tap(find.byIcon(Icons.qr_code_scanner_rounded));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Hardware Scanner Ready'), findsOneWidget);
      expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
    });
  });
}
