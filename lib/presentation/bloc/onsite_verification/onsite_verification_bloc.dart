import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/audio_feedback_service.dart';
import '../../../core/services/haptic_feedback_service.dart';
import '../../../domain/repositories/i_qr_verification_repository.dart';
import 'onsite_verification_event.dart';
import 'onsite_verification_state.dart';

class OnsiteVerificationBloc
    extends Bloc<OnsiteVerificationEvent, OnsiteVerificationState> {
  final IQrVerificationRepository _repository;

  OnsiteVerificationBloc({
    required IQrVerificationRepository repository,
    bool initialCameraActive = true,
  })  : _repository = repository,
        super(OnsiteVerificationInitial(isCameraActive: initialCameraActive)) {
    on<ScanCouponQr>(_onScanCouponQr);
    on<ToggleOnsiteCameraMode>(_onToggleOnsiteCameraMode);
    on<ResetOnsiteScanner>(_onResetOnsiteScanner);
  }

  Future<void> _onScanCouponQr(
    ScanCouponQr event,
    Emitter<OnsiteVerificationState> emit,
  ) async {
    final cleanCode = event.couponCode.trim();
    if (cleanCode.isEmpty) return;

    emit(OnsiteVerificationLoading(
      isCameraActive: state.isCameraActive,
      activeCouponCode: cleanCode,
    ));

    try {
      final couponDetails = await _repository.getCouponDetails(
        couponCode: cleanCode,
      );

      AudioFeedbackService().playTone(AudioTone.success);
      HapticFeedbackService().trigger(HapticPattern.success);

      emit(OnsiteVerificationLoaded(
        couponDetails: couponDetails,
        isCameraActive: state.isCameraActive,
      ));
    } catch (e) {
      AudioFeedbackService().playTone(AudioTone.error);
      HapticFeedbackService().trigger(HapticPattern.error);

      final cleanMsg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      emit(OnsiteVerificationError(
        message: cleanMsg,
        isCameraActive: state.isCameraActive,
      ));
    }
  }

  void _onToggleOnsiteCameraMode(
    ToggleOnsiteCameraMode event,
    Emitter<OnsiteVerificationState> emit,
  ) {
    final nextMode = !state.isCameraActive;
    if (state is OnsiteVerificationLoading) {
      emit(OnsiteVerificationLoading(
        activeCouponCode: (state as OnsiteVerificationLoading).activeCouponCode,
        isCameraActive: nextMode,
      ));
    } else {
      emit(OnsiteVerificationInitial(isCameraActive: nextMode));
    }
  }

  void _onResetOnsiteScanner(
    ResetOnsiteScanner event,
    Emitter<OnsiteVerificationState> emit,
  ) {
    emit(OnsiteVerificationInitial(isCameraActive: state.isCameraActive));
  }
}
