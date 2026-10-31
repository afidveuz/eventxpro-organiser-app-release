import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/data/models/onsite_coupon_details_model.dart';
import 'package:qr_scanner/data/models/qr_blacklist_user_model.dart';
import 'package:qr_scanner/domain/repositories/i_qr_verification_repository.dart';
import 'package:qr_scanner/presentation/bloc/qr_blacklist/qr_blacklist_bloc.dart';
import 'package:qr_scanner/presentation/bloc/qr_blacklist/qr_blacklist_event.dart';
import 'package:qr_scanner/presentation/bloc/qr_blacklist/qr_blacklist_state.dart';

class FakeQrVerificationRepository implements IQrVerificationRepository {
  QrUserDetailsModel? mockUserDetails;
  String? mockUpdateMessage;
  Exception? shouldThrowOnGet;
  Exception? shouldThrowOnUpdate;

  @override
  Future<QrUserDetailsModel> getUserDetails({
    required int eventId,
    required String ticketId,
  }) async {
    if (shouldThrowOnGet != null) {
      throw shouldThrowOnGet!;
    }
    return mockUserDetails ??
        QrUserDetailsModel(
          status: true,
          message: 'Fetched successfully',
          ticketId: ticketId,
          userDetails: const QrAttendeeDetails(
            firstname: 'John',
            lastname: 'Doe',
            uniqueId: 'URN-100',
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
    if (shouldThrowOnUpdate != null) {
      throw shouldThrowOnUpdate!;
    }
    return mockUpdateMessage ??
        (blacklistStatus ? 'User successfully blacklisted' : 'User unblacklisted');
  }

  @override
  Future<OnsiteCouponModel> getCouponDetails({
    required String couponCode,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeQrVerificationRepository fakeRepository;
  late QrBlacklistBloc bloc;

  setUp(() {
    fakeRepository = FakeQrVerificationRepository();
    bloc = QrBlacklistBloc(
      repository: fakeRepository,
      eventId: 101,
      initialCameraActive: true,
    );
  });

  tearDown(() {
    bloc.close();
  });

  group('QrBlacklistBloc Tests', () {
    test('Initial state is QrBlacklistInitial with configured camera active mode', () {
      expect(bloc.state, isA<QrBlacklistInitial>());
      expect(bloc.state.isCameraActive, isTrue);

      final inactiveBloc = QrBlacklistBloc(
        repository: fakeRepository,
        eventId: 101,
        initialCameraActive: false,
      );
      expect(inactiveBloc.state, isA<QrBlacklistInitial>());
      expect(inactiveBloc.state.isCameraActive, isFalse);
      inactiveBloc.close();
    });

    test('ScanBlacklistQr with valid code emits Loading then Loaded', () async {
      final states = <QrBlacklistState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ScanBlacklistQr('TICKET-ABC'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.length, equals(2));
      expect(states[0], isA<QrBlacklistLoading>());
      expect((states[0] as QrBlacklistLoading).activeTicketId, equals('TICKET-ABC'));

      expect(states[1], isA<QrBlacklistLoaded>());
      final loaded = states[1] as QrBlacklistLoaded;
      expect(loaded.attendee.ticketId, equals('TICKET-ABC'));
      expect(loaded.attendee.userDetails.fullName, equals('John Doe'));
      expect(loaded.attendee.userDetails.blacklistStatus, isFalse);

      await sub.cancel();
    });

    test('ScanBlacklistQr with empty or whitespace string ignores scan event', () async {
      final states = <QrBlacklistState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ScanBlacklistQr('   '));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.isEmpty, isTrue);
      await sub.cancel();
    });

    test('ScanBlacklistQr with error emits Loading then QrBlacklistError', () async {
      fakeRepository.shouldThrowOnGet = Exception('Attendee ticket not found');

      final states = <QrBlacklistState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ScanBlacklistQr('INVALID-QR'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.length, equals(2));
      expect(states[0], isA<QrBlacklistLoading>());
      expect(states[1], isA<QrBlacklistError>());
      expect((states[1] as QrBlacklistError).message, equals('Attendee ticket not found'));

      await sub.cancel();
    });

    test('ToggleBlacklistStatus blocks unblocked attendee successfully', () async {
      // First, get into Loaded state
      bloc.add(const ScanBlacklistQr('TICKET-ABC'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state, isA<QrBlacklistLoaded>());

      final states = <QrBlacklistState>[];
      final sub = bloc.stream.listen(states.add);

      fakeRepository.mockUpdateMessage = 'Attendee blocked successfully';
      bloc.add(const ToggleBlacklistStatus(
        ticketId: 'TICKET-ABC',
        nextStatus: true,
        notes: 'Disruptive behavior at entrance',
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.length, equals(2));
      expect(states[0], isA<QrBlacklistUpdating>());
      expect(states[1], isA<QrBlacklistUpdateSuccess>());

      final successState = states[1] as QrBlacklistUpdateSuccess;
      expect(successState.message, equals('Attendee blocked successfully'));
      expect(successState.updatedAttendee.userDetails.blacklistStatus, isTrue);

      await sub.cancel();
    });

    test('ToggleBlacklistStatus unblocks blocked attendee successfully', () async {
      // Setup loaded state with blocked user
      fakeRepository.mockUserDetails = const QrUserDetailsModel(
        status: true,
        message: 'Fetched',
        ticketId: 'TICKET-BLOCKED',
        userDetails: QrAttendeeDetails(
          firstname: 'Jane',
          lastname: 'Smith',
          uniqueId: 'URN-200',
          blacklistStatus: true,
        ),
        sessionAccess: [],
      );

      bloc.add(const ScanBlacklistQr('TICKET-BLOCKED'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state, isA<QrBlacklistLoaded>());

      final states = <QrBlacklistState>[];
      final sub = bloc.stream.listen(states.add);

      fakeRepository.mockUpdateMessage = 'Attendee unblocked';
      bloc.add(const ToggleBlacklistStatus(
        ticketId: 'TICKET-BLOCKED',
        nextStatus: false,
        notes: 'Verified clearance with security director',
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.length, equals(2));
      expect(states[0], isA<QrBlacklistUpdating>());
      expect(states[1], isA<QrBlacklistUpdateSuccess>());

      final successState = states[1] as QrBlacklistUpdateSuccess;
      expect(successState.message, equals('Attendee unblocked'));
      expect(successState.updatedAttendee.userDetails.blacklistStatus, isFalse);

      await sub.cancel();
    });

    test('ToggleBlacklistStatus with server error emits QrBlacklistError', () async {
      bloc.add(const ScanBlacklistQr('TICKET-ABC'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      fakeRepository.shouldThrowOnUpdate = Exception('Forbidden: Insufficient privileges');

      final states = <QrBlacklistState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ToggleBlacklistStatus(
        ticketId: 'TICKET-ABC',
        nextStatus: true,
        notes: 'Notes',
      ));

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.length, equals(2));
      expect(states[0], isA<QrBlacklistUpdating>());
      expect(states[1], isA<QrBlacklistError>());
      expect((states[1] as QrBlacklistError).message, equals('Forbidden: Insufficient privileges'));

      await sub.cancel();
    });

    test('ToggleCameraMode toggles isCameraActive between true and false', () async {
      expect(bloc.state.isCameraActive, isTrue);

      bloc.add(const ToggleCameraMode());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.isCameraActive, isFalse);

      bloc.add(const ToggleCameraMode());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.isCameraActive, isTrue);
    });

    test('ToggleCameraMode after error emits Initial and does NOT re-emit QrBlacklistError', () async {
      fakeRepository.shouldThrowOnGet = Exception('Attendee ticket not found');

      bloc.add(const ScanBlacklistQr('INVALID-BADGE'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state, isA<QrBlacklistError>());

      // User taps "Switch to Laser Only"
      bloc.add(const ToggleCameraMode());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Should be Initial with isCameraActive = false, NOT an error!
      expect(bloc.state, isA<QrBlacklistInitial>());
      expect(bloc.state.isCameraActive, isFalse);
    });

    test('ResetBlacklistScanner resets state to QrBlacklistInitial keeping camera active', () async {
      bloc.add(const ScanBlacklistQr('TICKET-ABC'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state, isA<QrBlacklistLoaded>());

      bloc.add(const ResetBlacklistScanner());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bloc.state, isA<QrBlacklistInitial>());
      expect(bloc.state.isCameraActive, isTrue);
    });
  });
}
