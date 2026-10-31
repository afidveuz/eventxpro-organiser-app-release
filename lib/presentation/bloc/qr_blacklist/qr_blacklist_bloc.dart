import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/audio_feedback_service.dart';
import '../../../core/services/haptic_feedback_service.dart';
import '../../../domain/repositories/i_qr_verification_repository.dart';
import 'qr_blacklist_event.dart';
import 'qr_blacklist_state.dart';

class QrBlacklistBloc extends Bloc<QrBlacklistEvent, QrBlacklistState> {
  final IQrVerificationRepository _repository;
  final int eventId;

  QrBlacklistBloc({
    required IQrVerificationRepository repository,
    required this.eventId,
    bool initialCameraActive = true,
  })  : _repository = repository,
        super(QrBlacklistInitial(isCameraActive: initialCameraActive)) {
    on<ScanBlacklistQr>(_onScanBlacklistQr);
    on<ToggleBlacklistStatus>(_onToggleBlacklistStatus);
    on<ToggleCameraMode>(_onToggleCameraMode);
    on<ResetBlacklistScanner>(_onResetBlacklistScanner);
  }

  Future<void> _onScanBlacklistQr(
    ScanBlacklistQr event,
    Emitter<QrBlacklistState> emit,
  ) async {
    final cleanTicket = event.ticketId.trim();
    if (cleanTicket.isEmpty) return;

    emit(QrBlacklistLoading(
      isCameraActive: state.isCameraActive,
      activeTicketId: cleanTicket,
    ));

    try {
      final attendee = await _repository.getUserDetails(
        eventId: eventId,
        ticketId: cleanTicket,
      );

      AudioFeedbackService().playTone(AudioTone.success);
      HapticFeedbackService().trigger(HapticPattern.success);

      emit(QrBlacklistLoaded(
        attendee: attendee,
        isCameraActive: state.isCameraActive,
      ));
    } catch (e) {
      AudioFeedbackService().playTone(AudioTone.error);
      HapticFeedbackService().trigger(HapticPattern.error);

      final cleanMsg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      emit(QrBlacklistError(
        message: cleanMsg,
        isCameraActive: state.isCameraActive,
      ));
    }
  }

  Future<void> _onToggleBlacklistStatus(
    ToggleBlacklistStatus event,
    Emitter<QrBlacklistState> emit,
  ) async {
    if (state is! QrBlacklistLoaded && state is! QrBlacklistUpdating) return;

    final currentAttendee = (state is QrBlacklistLoaded)
        ? (state as QrBlacklistLoaded).attendee
        : (state as QrBlacklistUpdating).attendee;

    emit(QrBlacklistUpdating(
      attendee: currentAttendee,
      isCameraActive: state.isCameraActive,
    ));

    try {
      final message = await _repository.updateBlacklistStatus(
        ticketId: event.ticketId,
        blacklistStatus: event.nextStatus,
        notes: event.notes,
        eventId: eventId,
        uniqueId: currentAttendee.userDetails.uniqueId,
      );

      final updatedAttendee = currentAttendee.copyWith(
        userDetails: currentAttendee.userDetails.copyWith(
          blacklistStatus: event.nextStatus,
        ),
      );

      AudioFeedbackService().playTone(AudioTone.success);
      HapticFeedbackService().trigger(HapticPattern.success);

      emit(QrBlacklistUpdateSuccess(
        message: message,
        updatedAttendee: updatedAttendee,
        isCameraActive: state.isCameraActive,
      ));
    } catch (e) {
      AudioFeedbackService().playTone(AudioTone.error);
      HapticFeedbackService().trigger(HapticPattern.error);

      final cleanMsg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      emit(QrBlacklistError(
        message: cleanMsg,
        isCameraActive: state.isCameraActive,
      ));
    }
  }

  void _onToggleCameraMode(
    ToggleCameraMode event,
    Emitter<QrBlacklistState> emit,
  ) {
    final nextMode = !state.isCameraActive;
    if (state is QrBlacklistLoading) {
      emit(QrBlacklistLoading(
        activeTicketId: (state as QrBlacklistLoading).activeTicketId,
        isCameraActive: nextMode,
      ));
    } else {
      emit(QrBlacklistInitial(isCameraActive: nextMode));
    }
  }

  void _onResetBlacklistScanner(
    ResetBlacklistScanner event,
    Emitter<QrBlacklistState> emit,
  ) {
    emit(QrBlacklistInitial(isCameraActive: state.isCameraActive));
  }
}
