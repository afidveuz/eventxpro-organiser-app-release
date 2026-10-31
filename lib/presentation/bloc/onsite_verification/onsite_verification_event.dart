import 'package:equatable/equatable.dart';

abstract class OnsiteVerificationEvent extends Equatable {
  const OnsiteVerificationEvent();

  @override
  List<Object?> get props => [];
}

class ScanCouponQr extends OnsiteVerificationEvent {
  final String couponCode;

  const ScanCouponQr(this.couponCode);

  @override
  List<Object?> get props => [couponCode];
}

class ToggleOnsiteCameraMode extends OnsiteVerificationEvent {
  const ToggleOnsiteCameraMode();
}

class ResetOnsiteScanner extends OnsiteVerificationEvent {
  const ResetOnsiteScanner();
}

