import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/data/models/onsite_coupon_details_model.dart';
import 'package:qr_scanner/data/models/qr_blacklist_user_model.dart';
import 'package:qr_scanner/presentation/widgets/blacklist_confirm_dialog.dart';
import 'package:qr_scanner/presentation/widgets/blacklist_info_bottom_sheet.dart';
import 'package:qr_scanner/presentation/widgets/onsite_qr_info_bottom_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BlacklistInfoBottomSheet Widget Tests', () {
    const testAttendee = QrUserDetailsModel(
      status: true,
      message: 'Found',
      ticketId: 'TICKET-999',
      userDetails: QrAttendeeDetails(
        firstname: 'Marcus',
        lastname: 'Vance',
        companyName: 'Apex Innovations',
        uniqueId: 'URN-4820',
        seatNo: 'B-14',
        displayTicketCode: 'VIP-09',
        country: 'United Arab Emirates',
        email: 'marcus@apex.io',
        displayTicketName: 'VIP Speaker',
        blacklistStatus: false,
      ),
      lastCheckinSession: 'Morning Keynote',
      lastCheckinTime: '09:30 AM',
      sessionAccess: [
        SessionAccessItem(
          title: 'Cybersecurity Summit',
          startTm: '11:00 AM',
          hallName: 'Hall B',
        ),
      ],
    );

    testWidgets('Renders all attendee profile fields, checkin info, and Block button for unblocked user', (tester) async {
      bool toggleCalled = false;
      bool toggleState = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlacklistInfoBottomSheet(
              data: testAttendee,
              mediaBaseUrl: 'https://cdn.example.com',
              onClose: () {},
              onToggleBlacklist: (isBlocked) {
                toggleCalled = true;
                toggleState = isBlocked;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Badge Information'), findsOneWidget);
      expect(find.text('Marcus Vance'), findsOneWidget);
      expect(find.text('Apex Innovations'), findsOneWidget);
      expect(find.text('URN-4820'), findsOneWidget);
      expect(find.text('B-14'), findsOneWidget);
      expect(find.text('VIP-09'), findsOneWidget);
      expect(find.text('United Arab Emirates'), findsOneWidget);
      expect(find.text('marcus@apex.io'), findsOneWidget);
      expect(find.text('VIP Speaker'), findsOneWidget);

      expect(find.textContaining('Last Checkin: Morning Keynote at 09:30 AM'), findsOneWidget);
      expect(find.text('Cybersecurity Summit'), findsOneWidget);
      expect(find.text('11:00 AM • Hall B'), findsOneWidget);

      // Button should say "Block" when user is not blacklisted
      expect(find.text('Block'), findsOneWidget);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);

      // Tap Block
      await tester.tap(find.text('Block'));
      await tester.pump();

      expect(toggleCalled, isTrue);
      expect(toggleState, isFalse); // Passed isCurrentlyBlocked = false
    });

    testWidgets('Renders ticketCategory correctly when displayTicketName is empty string and ticketTypeCat is provided', (tester) async {
      const arnoldModel = QrUserDetailsModel(
        status: true,
        message: 'Found',
        ticketId: '271333914225',
        userDetails: QrAttendeeDetails(
          firstname: 'Arnold',
          lastname: 'Schwarzenegger',
          companyName: 'VEUZ',
          uniqueId: '271333914225',
          country: 'India',
          email: 'arnold0@yopmail.com',
          displayTicketName: '',
          ticketTypeCat: 'ism-test',
          blacklistStatus: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlacklistInfoBottomSheet(
              data: arnoldModel,
              mediaBaseUrl: 'https://cdn.example.com',
              onClose: () {},
              onToggleBlacklist: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Arnold Schwarzenegger'), findsOneWidget);
      expect(find.text('ism-test'), findsOneWidget);
    });

    testWidgets('Renders Unblock button when attendee is currently blacklisted', (tester) async {
      final blockedAttendee = testAttendee.copyWith(
        userDetails: testAttendee.userDetails.copyWith(blacklistStatus: true),
      );

      bool toggleCalled = false;
      bool toggleState = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlacklistInfoBottomSheet(
              data: blockedAttendee,
              mediaBaseUrl: 'https://cdn.example.com',
              onClose: () {},
              onToggleBlacklist: (isBlocked) {
                toggleCalled = true;
                toggleState = isBlocked;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Unblock'), findsOneWidget);
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);

      await tester.tap(find.text('Unblock'));
      await tester.pump();

      expect(toggleCalled, isTrue);
      expect(toggleState, isTrue); // Passed isCurrentlyBlocked = true
    });

    testWidgets('Tapping close button triggers onClose callback', (tester) async {
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlacklistInfoBottomSheet(
              data: testAttendee,
              mediaBaseUrl: 'https://cdn.example.com',
              onClose: () {
                closed = true;
              },
              onToggleBlacklist: (_) {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();

      expect(closed, isTrue);
    });

    testWidgets('BlacklistInfoBottomSheet includes bottom SafeArea to protect from device navigation bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 48),
            ),
            child: Scaffold(
              body: BlacklistInfoBottomSheet(
                data: testAttendee,
                mediaBaseUrl: 'https://cdn.example.com',
                onClose: () {},
                onToggleBlacklist: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final safeAreaFinder = find.descendant(
        of: find.byType(BlacklistInfoBottomSheet),
        matching: find.byType(SafeArea),
      );
      expect(safeAreaFinder, findsOneWidget);
      final safeArea = tester.widget<SafeArea>(safeAreaFinder);
      expect(safeArea.bottom, isTrue);
    });
  });

  group('BlacklistConfirmDialog Widget Tests', () {
    testWidgets('Shows block confirmation and dispatches onConfirm with notes', (tester) async {
      String? confirmedNotes;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: ctx,
                    builder: (_) => BlacklistConfirmDialog(
                      isCurrentlyBlocked: false,
                      onConfirm: (notes) {
                        confirmedNotes = notes;
                      },
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure to block?'), findsOneWidget);
      expect(find.textContaining('barred from entry'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);

      // Enter notes
      await tester.enterText(find.byType(TextField), 'Badge shared with unauthorized guest');
      await tester.pump();

      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();

      expect(confirmedNotes, equals('Badge shared with unauthorized guest'));
      expect(find.text('Are you sure to block?'), findsNothing); // Dialog dismissed
    });

    testWidgets('Shows unblock confirmation and cancel does not call onConfirm', (tester) async {
      bool confirmCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: ctx,
                    builder: (_) => BlacklistConfirmDialog(
                      isCurrentlyBlocked: true,
                      onConfirm: (_) {
                        confirmCalled = true;
                      },
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Are you sure to unblock?'), findsOneWidget);
      expect(find.textContaining('restored to active status'), findsOneWidget);
      expect(find.text('Unblock'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(confirmCalled, isFalse);
      expect(find.text('Are you sure to unblock?'), findsNothing);
    });
  });

  group('OnsiteQrInfoBottomSheet Widget Tests', () {
    testWidgets('Renders QR Code Unused empty state when redeemed_users is empty', (tester) async {
      const emptyModel = OnsiteCouponModel(
        status: true,
        message: 'Unused coupon',
        coupon: CouponMeta(promocodeType: 'Exhibitor Pass', code: 'EXHIBIT100'),
        redeemedUsers: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnsiteQrInfoBottomSheet(
              data: emptyModel,
              mediaBaseUrl: 'https://cdn.example.com',
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('On-Site QR Information'), findsOneWidget);
      expect(find.text('QR Code Unused'), findsOneWidget);
      expect(find.text('This voucher code has not been redeemed by any attendee yet.'), findsOneWidget);
    });

    testWidgets('Renders single redeemed attendee with all attributes', (tester) async {
      const singleUserModel = OnsiteCouponModel(
        status: true,
        message: 'Verified',
        coupon: CouponMeta(promocodeType: 'VIP Delegate Pass', code: 'VIP-PASS-2026'),
        redeemedUsers: [
          RedeemedUserItem(
            userImage: null,
            ticketState: 'new',
            usedDtTm: '2026-10-30T14:45:00Z',
            userInfo: RedeemedUserInfo(
              firstname: 'Elena',
              lastname: 'Rostova',
              companyName: 'Global Media Group',
              designation: 'Managing Director',
              email: 'elena@gmg.com',
              mobile: '+971509998877',
              uniqueId: 'URN-9011',
              exhibitorName: 'Booth 401',
              createdBy: 'Registration Desk',
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnsiteQrInfoBottomSheet(
              data: singleUserModel,
              mediaBaseUrl: 'https://cdn.example.com',
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Elena Rostova'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
      expect(find.text('Global Media Group'), findsOneWidget);
      expect(find.text('Managing Director'), findsOneWidget);
      expect(find.text('elena@gmg.com'), findsOneWidget);
      expect(find.text('+971509998877'), findsOneWidget);
      expect(find.text('URN-9011'), findsOneWidget);
      expect(find.text('Booth 401'), findsOneWidget);
      expect(find.text('VIP Delegate Pass'), findsOneWidget);
      expect(find.text('Registration Desk'), findsOneWidget);

      // Single user does not show counter "1 / 1"
      expect(find.text('1 / 1'), findsNothing);
    });

    testWidgets('Renders multiple redeemed attendees with pagination counter and carousel swipe', (tester) async {
      const multiUserModel = OnsiteCouponModel(
        status: true,
        message: 'Multi users',
        coupon: CouponMeta(promocodeType: 'Group Pass', code: 'GROUP-PASS'),
        redeemedUsers: [
          RedeemedUserItem(
            userImage: null,
            ticketState: 'new',
            usedDtTm: null,
            userInfo: RedeemedUserInfo(
              firstname: 'User',
              lastname: 'One',
              companyName: 'Company 1',
              uniqueId: 'URN-001',
            ),
          ),
          RedeemedUserItem(
            userImage: null,
            ticketState: 'used',
            usedDtTm: null,
            userInfo: RedeemedUserInfo(
              firstname: 'User',
              lastname: 'Two',
              companyName: 'Company 2',
              uniqueId: 'URN-002',
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OnsiteQrInfoBottomSheet(
              data: multiUserModel,
              mediaBaseUrl: 'https://cdn.example.com',
              onClose: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show counter "1 / 2"
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('User One'), findsOneWidget);

      // Swipe carousel to second page
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('User Two'), findsOneWidget);
      expect(find.text('USED'), findsOneWidget);
    });

    testWidgets('OnsiteQrInfoBottomSheet includes bottom SafeArea to protect from device navigation bar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(bottom: 48),
            ),
            child: Scaffold(
              body: OnsiteQrInfoBottomSheet(
                data: const OnsiteCouponModel(status: true, message: 'OK', redeemedUsers: []),
                mediaBaseUrl: 'https://cdn.example.com',
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final safeAreaFinder = find.descendant(
        of: find.byType(OnsiteQrInfoBottomSheet),
        matching: find.byType(SafeArea),
      );
      expect(safeAreaFinder, findsOneWidget);
      final safeArea = tester.widget<SafeArea>(safeAreaFinder);
      expect(safeArea.bottom, isTrue);
    });
  });
}

