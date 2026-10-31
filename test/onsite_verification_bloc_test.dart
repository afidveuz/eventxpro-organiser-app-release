import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/data/models/onsite_coupon_details_model.dart';
import 'package:qr_scanner/data/models/qr_blacklist_user_model.dart';
import 'package:qr_scanner/domain/repositories/i_qr_verification_repository.dart';
import 'package:qr_scanner/presentation/bloc/onsite_verification/onsite_verification_bloc.dart';
import 'package:qr_scanner/presentation/bloc/onsite_verification/onsite_verification_event.dart';
import 'package:qr_scanner/presentation/bloc/onsite_verification/onsite_verification_state.dart';

class FakeOnsiteVerificationRepository implements IQrVerificationRepository {
  OnsiteCouponModel? mockCouponDetails;
  Exception? shouldThrowOnCoupon;

  @override
  Future<QrUserDetailsModel> getUserDetails({
    required int eventId,
    required String ticketId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<String> updateBlacklistStatus({
    required String ticketId,
    required bool blacklistStatus,
    required String notes,
    int? eventId,
    String? uniqueId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<OnsiteCouponModel> getCouponDetails({
    required String couponCode,
  }) async {
    if (shouldThrowOnCoupon != null) {
      throw shouldThrowOnCoupon!;
    }
    return mockCouponDetails ??
        OnsiteCouponModel(
          status: true,
          message: 'Coupon details verified',
          coupon: const CouponMeta(
            promocodeType: 'Exhibitor Pass',
            code: 'EXHIBIT2026',
          ),
          redeemedUsers: [
            const RedeemedUserItem(
              userImage: null,
              ticketState: 'new',
              usedDtTm: '2026-10-30T10:00:00Z',
              userInfo: RedeemedUserInfo(
                firstname: 'Alice',
                lastname: 'Wonderland',
                companyName: 'Tech Corp',
                designation: 'CTO',
                email: 'alice@tech.com',
                mobile: '+971501234567',
                uniqueId: 'URN-8871',
                exhibitorName: 'Stand B1',
                createdBy: 'Admin',
              ),
            ),
          ],
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeOnsiteVerificationRepository fakeRepository;
  late OnsiteVerificationBloc bloc;

  setUp(() {
    fakeRepository = FakeOnsiteVerificationRepository();
    bloc = OnsiteVerificationBloc(
      repository: fakeRepository,
      initialCameraActive: true,
    );
  });

  tearDown(() {
    bloc.close();
  });

  group('OnsiteVerificationBloc Tests', () {
    test('Initial state is OnsiteVerificationInitial with configured camera active mode', () {
      expect(bloc.state, isA<OnsiteVerificationInitial>());
      expect(bloc.state.isCameraActive, isTrue);

      final inactiveBloc = OnsiteVerificationBloc(
        repository: fakeRepository,
        initialCameraActive: false,
      );
      expect(inactiveBloc.state, isA<OnsiteVerificationInitial>());
      expect(inactiveBloc.state.isCameraActive, isFalse);
      inactiveBloc.close();
    });

    test('ScanCouponQr with valid coupon code emits Loading then Loaded', () async {
      final states = <OnsiteVerificationState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ScanCouponQr('COUPON-2026'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.length, equals(2));
      expect(states[0], isA<OnsiteVerificationLoading>());
      expect((states[0] as OnsiteVerificationLoading).activeCouponCode, equals('COUPON-2026'));

      expect(states[1], isA<OnsiteVerificationLoaded>());
      final loaded = states[1] as OnsiteVerificationLoaded;
      expect(loaded.couponDetails.status, isTrue);
      expect(loaded.couponDetails.coupon?.code, equals('EXHIBIT2026'));
      expect(loaded.couponDetails.redeemedUsers.length, equals(1));
      expect(loaded.couponDetails.redeemedUsers.first.userInfo.fullName, equals('Alice Wonderland'));

      await sub.cancel();
    });

    test('ScanCouponQr with unused coupon emits Loaded with empty redeemed_users', () async {
      fakeRepository.mockCouponDetails = const OnsiteCouponModel(
        status: true,
        message: 'Coupon unused',
        coupon: CouponMeta(
          promocodeType: 'General Voucher',
          code: 'UNUSED-VOUCHER',
        ),
        redeemedUsers: [],
      );

      final states = <OnsiteVerificationState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ScanCouponQr('UNUSED-VOUCHER'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.length, equals(2));
      expect(states[0], isA<OnsiteVerificationLoading>());
      expect(states[1], isA<OnsiteVerificationLoaded>());

      final loaded = states[1] as OnsiteVerificationLoaded;
      expect(loaded.couponDetails.redeemedUsers.isEmpty, isTrue);
      expect(loaded.couponDetails.coupon?.code, equals('UNUSED-VOUCHER'));

      await sub.cancel();
    });

    test('ScanCouponQr with empty or whitespace string ignores event', () async {
      final states = <OnsiteVerificationState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ScanCouponQr('    '));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.isEmpty, isTrue);
      await sub.cancel();
    });

    test('ScanCouponQr with error emits Loading then OnsiteVerificationError', () async {
      fakeRepository.shouldThrowOnCoupon = Exception('Invalid coupon code or expired');

      final states = <OnsiteVerificationState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ScanCouponQr('EXPIRED-CODE'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.length, equals(2));
      expect(states[0], isA<OnsiteVerificationLoading>());
      expect(states[1], isA<OnsiteVerificationError>());
      expect((states[1] as OnsiteVerificationError).message, equals('Invalid coupon code or expired'));

      await sub.cancel();
    });

    test('ToggleOnsiteCameraMode toggles isCameraActive between true and false', () async {
      expect(bloc.state.isCameraActive, isTrue);

      bloc.add(const ToggleOnsiteCameraMode());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.isCameraActive, isFalse);

      bloc.add(const ToggleOnsiteCameraMode());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.isCameraActive, isTrue);
    });

    test('ToggleOnsiteCameraMode after error emits Initial and does NOT re-emit OnsiteVerificationError', () async {
      fakeRepository.shouldThrowOnCoupon = Exception('Coupon code not found');

      bloc.add(const ScanCouponQr('INVALID-COUPON'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state, isA<OnsiteVerificationError>());

      // User taps "Switch to Laser Only"
      bloc.add(const ToggleOnsiteCameraMode());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Should be Initial with isCameraActive = false, NOT an error!
      expect(bloc.state, isA<OnsiteVerificationInitial>());
      expect(bloc.state.isCameraActive, isFalse);
    });

    test('ResetOnsiteScanner resets state to OnsiteVerificationInitial keeping camera active', () async {
      bloc.add(const ScanCouponQr('COUPON-123'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state, isA<OnsiteVerificationLoaded>());

      bloc.add(const ResetOnsiteScanner());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bloc.state, isA<OnsiteVerificationInitial>());
      expect(bloc.state.isCameraActive, isTrue);
    });
  });
}

