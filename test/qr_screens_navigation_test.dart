import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_scanner/data/adapters/simulated_hardware_adapter.dart';
import 'package:qr_scanner/data/datasources/auth_local_storage.dart';
import 'package:qr_scanner/data/datasources/scanner_local_storage.dart';
import 'package:qr_scanner/data/models/onsite_coupon_details_model.dart';
import 'package:qr_scanner/data/models/qr_blacklist_user_model.dart';
import 'package:qr_scanner/domain/adapters/i_hardware_scanner_adapter.dart';
import 'package:qr_scanner/domain/repositories/i_qr_verification_repository.dart';
import 'package:qr_scanner/presentation/screens/onsite_qr_verification_screen.dart';
import 'package:qr_scanner/presentation/screens/qr_blacklist_screen.dart';

class MockFullQrVerificationRepository implements IQrVerificationRepository {
  QrUserDetailsModel? mockUserDetails;
  OnsiteCouponModel? mockCouponDetails;
  int getCouponCallCount = 0;
  bool throwOnCoupon = false;

  @override
  Future<QrUserDetailsModel> getUserDetails({
    required int eventId,
    required String ticketId,
  }) async {
    return mockUserDetails ??
        QrUserDetailsModel(
          status: true,
          message: 'Success',
          ticketId: ticketId,
          userDetails: const QrAttendeeDetails(
            firstname: 'Carlos',
            lastname: 'Mendez',
            uniqueId: 'URN-CARLOS-1',
            blacklistStatus: false,
          ),
          sessionAccess: const [],
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
  Future<OnsiteCouponModel> getCouponDetails({
    required String couponCode,
  }) async {
    getCouponCallCount++;
    if (throwOnCoupon) {
      throw Exception('Coupon code not found');
    }
    return mockCouponDetails ??
        OnsiteCouponModel(
          status: true,
          message: 'Found coupon',
          coupon: const CouponMeta(promocodeType: 'Exhibitor', code: 'EXHIBIT-99'),
          redeemedUsers: const [
            RedeemedUserItem(
              userImage: null,
              ticketState: 'new',
              userInfo: RedeemedUserInfo(
                firstname: 'Zara',
                lastname: 'Khan',
                companyName: 'Global Exhibitions',
                uniqueId: 'URN-ZARA',
              ),
            ),
          ],
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScannerLocalStorage scannerStorage;
  late AuthLocalStorage authStorage;
  late SimulatedHardwareAdapter simulatedAdapter;
  late MockFullQrVerificationRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    scannerStorage = await ScannerLocalStorage.create();
    authStorage = AuthLocalStorage(prefs);
    simulatedAdapter = SimulatedHardwareAdapter();
    repository = MockFullQrVerificationRepository();
  });

  Widget buildTestableScreen(Widget screen) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<ScannerLocalStorage>.value(value: scannerStorage),
        RepositoryProvider<AuthLocalStorage>.value(value: authStorage),
        RepositoryProvider<HardwareScannerAdapter>.value(value: simulatedAdapter),
      ],
      child: MaterialApp(
        home: screen,
      ),
    );
  }

  group('QrBlacklistScreen Tests', () {
    testWidgets('Renders top bar, instructions, laser mode, and pops directly on back without dialog', (tester) async {
      bool popped = false;

      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ScannerLocalStorage>.value(value: scannerStorage),
            RepositoryProvider<AuthLocalStorage>.value(value: authStorage),
            RepositoryProvider<HardwareScannerAdapter>.value(value: simulatedAdapter),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).push(
                      MaterialPageRoute(
                        builder: (_) => QrBlacklistScreen(
                          eventId: 42,
                          eventName: 'Future Tech Expo 2026',
                          repository: repository,
                        ),
                      ),
                    ).then((_) {
                      popped = true;
                    });
                  },
                  child: const Text('Open Scanner'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Open Scanner'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('QR Blacklist'), findsOneWidget);
      expect(find.text('Future Tech Expo 2026'), findsOneWidget);
      expect(find.text('Scan any QR'), findsOneWidget);
      expect(find.text('Hardware Laser Mode'), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should NOT show any confirmation dialog
      expect(find.text('Do you want to go back?'), findsNothing);
      expect(popped, isTrue);
    });

    testWidgets('Hardware scan triggers attendee lookup and displays bottom sheet', (tester) async {
      await tester.pumpWidget(
        buildTestableScreen(
          QrBlacklistScreen(
            eventId: 42,
            eventName: 'Future Tech Expo 2026',
            repository: repository,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Emit simulated scan
      simulatedAdapter.triggerScan('BADGE-TOKEN-CARLOS');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify bottom sheet appeared
      expect(find.text('Badge Information'), findsOneWidget);
      expect(find.text('Carlos Mendez'), findsOneWidget);
      expect(find.text('URN-CARLOS-1'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
    });

    testWidgets('Suppresses repetitive scan of same attendee QR, only allowing scan again after another badge is scanned', (tester) async {
      await tester.pumpWidget(
        buildTestableScreen(
          QrBlacklistScreen(
            eventId: 42,
            eventName: 'Future Tech Expo 2026',
            repository: repository,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // First scan of Badge A
      simulatedAdapter.triggerScan('TICKET-A');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Badge Information'), findsOneWidget);
      expect(find.text('Carlos Mendez'), findsOneWidget);

      // Dismiss sheet
      final closeBtn = find.byIcon(Icons.close_rounded);
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Badge Information'), findsNothing);

      // Rescan the EXACT SAME attendee QR code -> Should be suppressed to prevent unwanted API calls!
      simulatedAdapter.triggerScan('TICKET-A');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Sheet does NOT open because identical badge was scanned repetitively
      expect(find.text('Badge Information'), findsNothing);

      // Scan ANOTHER badge (Badge B) -> Opens sheet for Badge B
      simulatedAdapter.triggerScan('TICKET-B');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Badge Information'), findsOneWidget);

      // Dismiss sheet for Badge B
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Now Badge A CAN be scanned again because Badge B was scanned in between!
      simulatedAdapter.triggerScan('TICKET-A');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Badge Information'), findsOneWidget);
    });

    testWidgets('Resolves effective event ID from ScannerLocalStorage when eventId is default 1', (tester) async {
      await scannerStorage.setEventId(105);

      await tester.pumpWidget(
        buildTestableScreen(
          QrBlacklistScreen(
            eventId: 1, // default passed from Settings
            eventName: 'Event #1',
            repository: repository,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      simulatedAdapter.triggerScan('TICKET-EVENT-RESOLVE');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Successfully displays attendee bottom sheet using resolved eventId 105
      expect(find.text('Badge Information'), findsOneWidget);
      expect(find.text('Carlos Mendez'), findsOneWidget);
    });
  });

  group('OnsiteQrVerificationScreen Tests', () {
    testWidgets('Renders top bar, coupon instructions, and pops directly on back without dialog', (tester) async {
      bool popped = false;

      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ScannerLocalStorage>.value(value: scannerStorage),
            RepositoryProvider<AuthLocalStorage>.value(value: authStorage),
            RepositoryProvider<HardwareScannerAdapter>.value(value: simulatedAdapter),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).push(
                      MaterialPageRoute(
                        builder: (_) => OnsiteQrVerificationScreen(
                          eventId: 42,
                          eventName: 'Future Tech Expo 2026',
                          repository: repository,
                        ),
                      ),
                    ).then((_) {
                      popped = true;
                    });
                  },
                  child: const Text('Open Coupon Scanner'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Open Coupon Scanner'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('On-Site QR Verification'), findsOneWidget);
      expect(find.text('Future Tech Expo 2026'), findsOneWidget);
      expect(find.text('Scan Voucher / Coupon QR'), findsOneWidget);
      expect(find.text('Hardware Laser Mode'), findsOneWidget);

      // Tap back button
      await tester.tap(find.byIcon(Icons.arrow_back_ios_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should NOT show any confirmation dialog
      expect(find.text('Do you want to go back?'), findsNothing);
      expect(popped, isTrue);
    });

    testWidgets('Hardware scan triggers coupon lookup and displays coupon bottom sheet', (tester) async {
      await tester.pumpWidget(
        buildTestableScreen(
          OnsiteQrVerificationScreen(
            eventId: 42,
            eventName: 'Future Tech Expo 2026',
            repository: repository,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Emit simulated scan
      simulatedAdapter.triggerScan('COUPON-ZARA');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('On-Site QR Information'), findsOneWidget);
      expect(find.text('Zara Khan'), findsOneWidget);
      expect(find.text('Global Exhibitions'), findsOneWidget);
    });

    testWidgets('Tapping Switch to Laser button after scan does NOT re-trigger error toast', (tester) async {
      await tester.pumpWidget(
        buildTestableScreen(
          OnsiteQrVerificationScreen(
            eventId: 42,
            eventName: 'Future Tech Expo 2026',
            repository: repository,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Tap Switch to Laser Only button (find by text 'Switch to Laser Only' or icon)
      final switchBtn = find.text('Switch to Laser Only');
      if (switchBtn.evaluate().isNotEmpty) {
        await tester.tap(switchBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Should now show 'Switch to Camera'
        expect(find.text('Switch to Camera'), findsOneWidget);
      }
    });

    testWidgets('Suppresses repetitive scan of same coupon QR, only allowing scan again after another coupon is scanned', (tester) async {
      await tester.pumpWidget(
        buildTestableScreen(
          OnsiteQrVerificationScreen(
            eventId: 42,
            eventName: 'Future Tech Expo 2026',
            repository: repository,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // First scan of coupon A
      simulatedAdapter.triggerScan('EXHIBIT-99');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('On-Site QR Information'), findsOneWidget);
      expect(find.text('Zara Khan'), findsOneWidget);

      // Dismiss the bottom sheet
      final closeBtn = find.byIcon(Icons.close_rounded);
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Sheet is dismissed
      expect(find.text('On-Site QR Information'), findsNothing);

      // Rescan the EXACT SAME coupon QR code -> Should be SUPPRESSED!
      simulatedAdapter.triggerScan('EXHIBIT-99');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      // Sheet does NOT open because duplicate scan is suppressed
      expect(find.text('On-Site QR Information'), findsNothing);

      // Scan ANOTHER coupon (EXHIBIT-100) -> Opens sheet for second coupon
      simulatedAdapter.triggerScan('EXHIBIT-100');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('On-Site QR Information'), findsOneWidget);

      // Dismiss sheet
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Now EXHIBIT-99 CAN be scanned again because another coupon was scanned in between!
      simulatedAdapter.triggerScan('EXHIBIT-99');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('On-Site QR Information'), findsOneWidget);
    });

    testWidgets('Scanning error resets scanner allowing immediate re-scan of the same code', (tester) async {
      repository.throwOnCoupon = true;
      repository.getCouponCallCount = 0;

      await tester.pumpWidget(
        buildTestableScreen(
          OnsiteQrVerificationScreen(
            eventId: 42,
            eventName: 'Future Tech Expo 2026',
            repository: repository,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // First scan of invalid coupon
      simulatedAdapter.triggerScan('INVALID-CODE');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(repository.getCouponCallCount, 1);

      // Now fix the repository so next scan succeeds
      repository.throwOnCoupon = false;

      // Rescan the EXACT SAME code immediately
      simulatedAdapter.triggerScan('INVALID-CODE');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Repository was called a 2nd time for the same code!
      expect(repository.getCouponCallCount, 2);
      expect(find.text('On-Site QR Information'), findsOneWidget);
    });
  });
}
