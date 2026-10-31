import 'package:equatable/equatable.dart';
import '../../../data/models/onsite_coupon_details_model.dart';

abstract class OnsiteVerificationState extends Equatable {
  final bool isCameraActive;

  const OnsiteVerificationState({required this.isCameraActive});

  @override
  List<Object?> get props => [isCameraActive];
}

class OnsiteVerificationInitial extends OnsiteVerificationState {
  const OnsiteVerificationInitial({super.isCameraActive = true});
}

class OnsiteVerificationLoading extends OnsiteVerificationState {
  final String? activeCouponCode;

  const OnsiteVerificationLoading({
    super.isCameraActive = true,
    this.activeCouponCode,
  });

  @override
  List<Object?> get props => [isCameraActive, activeCouponCode];
}

class OnsiteVerificationLoaded extends OnsiteVerificationState {
  final OnsiteCouponModel couponDetails;

  const OnsiteVerificationLoaded({
    super.isCameraActive = true,
    required this.couponDetails,
  });

  @override
  List<Object?> get props => [isCameraActive, couponDetails];
}

class OnsiteVerificationError extends OnsiteVerificationState {
  final String message;

  const OnsiteVerificationError({
    super.isCameraActive = true,
    required this.message,
  });

  @override
  List<Object?> get props => [isCameraActive, message];
}

