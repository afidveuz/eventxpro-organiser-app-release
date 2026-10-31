import '../../data/models/onsite_coupon_details_model.dart';
import '../../data/models/qr_blacklist_user_model.dart';

abstract class IQrVerificationRepository {
  Future<QrUserDetailsModel> getUserDetails({
    required int eventId,
    required String ticketId,
  });

  Future<String> updateBlacklistStatus({
    required String ticketId,
    required bool blacklistStatus,
    required String notes,
    int? eventId,
    String? uniqueId,
  });

  Future<OnsiteCouponModel> getCouponDetails({
    required String couponCode,
  });
}

