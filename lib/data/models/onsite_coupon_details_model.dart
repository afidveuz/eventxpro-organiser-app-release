import 'package:equatable/equatable.dart';

/// Represents the response model for on-site voucher / coupon verification.
/// Corresponds to backend endpoint: `organizer/get-coupon-details?coupon_code={code}`
class OnsiteCouponModel extends Equatable {
  final bool status;
  final String message;
  final CouponMeta? coupon;
  final List<RedeemedUserItem> redeemedUsers;

  const OnsiteCouponModel({
    required this.status,
    required this.message,
    this.coupon,
    this.redeemedUsers = const [],
  });

  factory OnsiteCouponModel.fromJson(Map<String, dynamic> json) {
    final root = (json['data'] is Map<String, dynamic>)
        ? json['data'] as Map<String, dynamic>
        : json;

    final rawCoupon = (root['coupon'] is Map<String, dynamic>)
        ? root['coupon'] as Map<String, dynamic>
        : (root['coupon_details'] is Map<String, dynamic>)
            ? root['coupon_details'] as Map<String, dynamic>
            : null;

    final rawUsers = (root['redeemed_users'] is List)
        ? root['redeemed_users'] as List<dynamic>
        : (root['users'] is List)
            ? root['users'] as List<dynamic>
            : (root['user_list'] is List)
                ? root['user_list'] as List<dynamic>
                : <dynamic>[];

    final statusVal = root['status'];
    final isSuccess = statusVal == true ||
        statusVal == 1 ||
        statusVal?.toString().toLowerCase() == 'true' ||
        statusVal?.toString().toLowerCase() == 'success';

    return OnsiteCouponModel(
      status: isSuccess,
      message: (root['message'] ?? root['msg'] ?? '').toString(),
      coupon: rawCoupon != null ? CouponMeta.fromJson(rawCoupon) : null,
      redeemedUsers: rawUsers
          .whereType<Map<String, dynamic>>()
          .map((u) => RedeemedUserItem.fromJson(u))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [status, message, coupon, redeemedUsers];
}

class CouponMeta extends Equatable {
  final String? promocodeType;
  final String? code;
  final dynamic totalUses;

  const CouponMeta({
    this.promocodeType,
    this.code,
    this.totalUses,
  });

  factory CouponMeta.fromJson(Map<String, dynamic> json) {
    return CouponMeta(
      promocodeType: (json['promocode_type'] ?? json['coupon_type'] ?? json['type'])?.toString(),
      code: (json['code'] ?? json['coupon_code'])?.toString(),
      totalUses: json['total_uses'] ?? json['uses'],
    );
  }

  @override
  List<Object?> get props => [promocodeType, code, totalUses];
}

class RedeemedUserItem extends Equatable {
  final String? userImage;
  final String ticketState;
  final String? usedDtTm;
  final RedeemedUserInfo userInfo;

  const RedeemedUserItem({
    this.userImage,
    required this.ticketState,
    this.usedDtTm,
    required this.userInfo,
  });

  factory RedeemedUserItem.fromJson(Map<String, dynamic> json) {
    final rawInfo = (json['user_info'] is Map<String, dynamic>)
        ? json['user_info'] as Map<String, dynamic>
        : (json['user_data'] is Map<String, dynamic>)
            ? json['user_data'] as Map<String, dynamic>
            : json;

    final image = json['user_image']?.toString() ??
        json['register_user_photo']?.toString() ??
        rawInfo['user_image']?.toString() ??
        rawInfo['photo']?.toString();

    final state = (json['ticket_state'] ?? json['status'] ?? json['state'] ?? 'new').toString();
    final usedTime = (json['used_dt_tm'] ?? json['used_at'] ?? json['redeemed_at'] ?? json['punch_time'])?.toString();

    return RedeemedUserItem(
      userImage: (image != null && image.isNotEmpty) ? image : null,
      ticketState: state,
      usedDtTm: usedTime,
      userInfo: RedeemedUserInfo.fromJson(rawInfo),
    );
  }

  @override
  List<Object?> get props => [userImage, ticketState, usedDtTm, userInfo];
}

class RedeemedUserInfo extends Equatable {
  final String firstname;
  final String lastname;
  final String? companyName;
  final String? designation;
  final String? email;
  final String? mobile;
  final String? uniqueId;
  final String? exhibitorName;
  final String? createdBy;

  const RedeemedUserInfo({
    required this.firstname,
    required this.lastname,
    this.companyName,
    this.designation,
    this.email,
    this.mobile,
    this.uniqueId,
    this.exhibitorName,
    this.createdBy,
  });

  factory RedeemedUserInfo.fromJson(Map<String, dynamic> json) {
    return RedeemedUserInfo(
      firstname: (json['firstname'] ?? json['first_name'] ?? json['name'] ?? '').toString(),
      lastname: (json['lastname'] ?? json['last_name'] ?? '').toString(),
      companyName: (json['company_name'] ?? json['company'])?.toString(),
      designation: (json['designation'] ?? json['job_title'] ?? json['title'])?.toString(),
      email: json['email']?.toString(),
      mobile: (json['mobile'] ?? json['phone'])?.toString(),
      uniqueId: (json['unique_id'] ?? json['uid'] ?? json['ticket_id'] ?? json['urn'])?.toString(),
      exhibitorName: (json['exhibitor_name'] ?? json['exhibitor'])?.toString(),
      createdBy: (json['created_by'] ?? json['creator'])?.toString(),
    );
  }

  String get fullName {
    final first = firstname.trim();
    final last = lastname.trim();
    return [first, last].where((s) => s.isNotEmpty).join(' ');
  }

  String get initials {
    final name = fullName;
    if (name.isEmpty) return 'P';
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  List<Object?> get props => [
        firstname,
        lastname,
        companyName,
        designation,
        email,
        mobile,
        uniqueId,
        exhibitorName,
        createdBy,
      ];
}
