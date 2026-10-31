import 'package:equatable/equatable.dart';

abstract class QrBlacklistEvent extends Equatable {
  const QrBlacklistEvent();

  @override
  List<Object?> get props => [];
}

class ScanBlacklistQr extends QrBlacklistEvent {
  final String ticketId;

  const ScanBlacklistQr(this.ticketId);

  @override
  List<Object?> get props => [ticketId];
}

class ToggleBlacklistStatus extends QrBlacklistEvent {
  final String ticketId;
  final bool nextStatus;
  final String notes;

  const ToggleBlacklistStatus({
    required this.ticketId,
    required this.nextStatus,
    required this.notes,
  });

  @override
  List<Object?> get props => [ticketId, nextStatus, notes];
}

class ToggleCameraMode extends QrBlacklistEvent {
  const ToggleCameraMode();
}

class ResetBlacklistScanner extends QrBlacklistEvent {
  const ResetBlacklistScanner();
}

