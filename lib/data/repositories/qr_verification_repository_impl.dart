import '../../domain/repositories/i_qr_verification_repository.dart';
import '../datasources/qr_verification_remote_datasource.dart';
import '../models/onsite_coupon_details_model.dart';
import '../models/qr_blacklist_user_model.dart';

class QrVerificationRepositoryImpl implements IQrVerificationRepository {
  final QrVerificationRemoteDatasource _remoteDatasource;

  QrVerificationRepositoryImpl({
    required QrVerificationRemoteDatasource remoteDatasource,
  }) : _remoteDatasource = remoteDatasource;

  @override
  Future<QrUserDetailsModel> getUserDetails({
    required int eventId,
    required String ticketId,
  }) =>
      _remoteDatasource.getUserDetails(eventId: eventId, ticketId: ticketId);

  @override
  Future<String> updateBlacklistStatus({
    required String ticketId,
    required bool blacklistStatus,
    required String notes,
    int? eventId,
    String? uniqueId,
  }) =>
      _remoteDatasource.updateBlacklistStatus(
        ticketId: ticketId,
        blacklistStatus: blacklistStatus,
        notes: notes,
        eventId: eventId,
        uniqueId: uniqueId,
      );

  @override
  Future<OnsiteCouponModel> getCouponDetails({
    required String couponCode,
  }) =>
      _remoteDatasource.getCouponDetails(couponCode: couponCode);
}

