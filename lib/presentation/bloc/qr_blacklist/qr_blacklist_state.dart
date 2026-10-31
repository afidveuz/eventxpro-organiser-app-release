import 'package:equatable/equatable.dart';
import '../../../data/models/qr_blacklist_user_model.dart';

abstract class QrBlacklistState extends Equatable {
  final bool isCameraActive;

  const QrBlacklistState({required this.isCameraActive});

  @override
  List<Object?> get props => [isCameraActive];
}

class QrBlacklistInitial extends QrBlacklistState {
  const QrBlacklistInitial({super.isCameraActive = true});
}

class QrBlacklistLoading extends QrBlacklistState {
  final String? activeTicketId;

  const QrBlacklistLoading({
    super.isCameraActive = true,
    this.activeTicketId,
  });

  @override
  List<Object?> get props => [isCameraActive, activeTicketId];
}

class QrBlacklistLoaded extends QrBlacklistState {
  final QrUserDetailsModel attendee;

  const QrBlacklistLoaded({
    super.isCameraActive = true,
    required this.attendee,
  });

  @override
  List<Object?> get props => [isCameraActive, attendee];
}

class QrBlacklistUpdating extends QrBlacklistState {
  final QrUserDetailsModel attendee;

  const QrBlacklistUpdating({
    super.isCameraActive = true,
    required this.attendee,
  });

  @override
  List<Object?> get props => [isCameraActive, attendee];
}

class QrBlacklistUpdateSuccess extends QrBlacklistState {
  final String message;
  final QrUserDetailsModel updatedAttendee;

  const QrBlacklistUpdateSuccess({
    super.isCameraActive = true,
    required this.message,
    required this.updatedAttendee,
  });

  @override
  List<Object?> get props => [isCameraActive, message, updatedAttendee];
}

class QrBlacklistError extends QrBlacklistState {
  final String message;

  const QrBlacklistError({
    super.isCameraActive = true,
    required this.message,
  });

  @override
  List<Object?> get props => [isCameraActive, message];
}

