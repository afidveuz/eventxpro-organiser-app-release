import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/data/models/onsite_coupon_details_model.dart';
import 'package:qr_scanner/data/models/qr_blacklist_user_model.dart';

void main() {
  group('QrUserDetailsModel Tests', () {
    test('Correctly deserializes JSON with all fields', () {
      final json = {
        'status': true,
        'message': 'User details fetched successfully',
        'user_details': {
          'user_image': '/media/profiles/u1.jpg',
          'firstname': 'John',
          'lastname': 'Doe',
          'arabic_name': null,
          'company_name': 'Acme Global',
          'unique_id': 'URN-10029',
          'seat_no': 'A-12',
          'display_ticket_code': 'VIP-001',
          'country': 'UAE',
          'email': 'john@acme.com',
          'display_ticket_name': 'VIP Delegate',
          'ticket_type_cat': 'Delegate',
          'blacklist_status': false,
        },
        'last_checkin_session': 'Main Stage Opening',
        'last_checkin_time': '10:15:00',
        'session_access': [
          {
            'title': 'AI Keynote 2026',
            'start_tm': '11:00',
            'hall_name': 'Hall 1',
          }
        ],
      };

      final model = QrUserDetailsModel.fromJson(json, ticketId: 'TICKET-999');

      expect(model.status, isTrue);
      expect(model.ticketId, equals('TICKET-999'));
      expect(model.userDetails.fullName, equals('John Doe'));
      expect(model.userDetails.initials, equals('JD'));
      expect(model.userDetails.companyName, equals('Acme Global'));
      expect(model.userDetails.blacklistStatus, isFalse);
      expect(model.lastCheckinSession, equals('Main Stage Opening'));
      expect(model.sessionAccess.length, equals(1));
      expect(model.sessionAccess.first.title, equals('AI Keynote 2026'));
    });

    test('Initials generation edge cases', () {
      const u1 = QrAttendeeDetails(
        firstname: 'Adarsh',
        lastname: '',
        uniqueId: '1',
      );
      expect(u1.initials, equals('A'));

      const u2 = QrAttendeeDetails(
        firstname: 'Sarah',
        lastname: 'Connor',
        uniqueId: '2',
      );
      expect(u2.initials, equals('SC'));

      const u3 = QrAttendeeDetails(
        firstname: '',
        lastname: '',
        arabicName: 'Mohammed',
        uniqueId: '3',
      );
      expect(u3.initials, equals('M'));
    });

    test('copyWith properly updates blacklist status', () {
      const user = QrAttendeeDetails(
        firstname: 'John',
        lastname: 'Doe',
        uniqueId: '1',
        blacklistStatus: false,
      );

      final updated = user.copyWith(blacklistStatus: true);
      expect(updated.blacklistStatus, isTrue);
      expect(user.blacklistStatus, isFalse);
    });

    test('ticketCategory correctly falls back to ticket_type_cat when display_ticket_name is empty string', () {
      final json = {
        'status': true,
        'message': 'OK',
        'user_details': {
          'firstname': 'Arnold',
          'lastname': 'Schwarzenegger',
          'unique_id': '271333914225',
          'company_name': 'VEUZ',
          'ticket_type_cat': 'ism-test',
          'display_ticket_name': '',
          'display_ticket_code': '',
          'seat_no': '',
          'blacklist_status': false,
        },
      };

      final model = QrUserDetailsModel.fromJson(json, ticketId: '271333914225');
      expect(model.userDetails.ticketCategory, equals('ism-test'));
      expect(model.userDetails.seatNo, isNull);
      expect(model.userDetails.displayTicketCode, isNull);
    });

    test('ticketCategory returns display_ticket_name when present', () {
      final json = {
        'status': true,
        'message': 'OK',
        'user_details': {
          'firstname': 'Benjamin',
          'lastname': 'Martin',
          'unique_id': '271768614229',
          'ticket_type_cat': 'ism-test',
          'display_ticket_name': 'GULFHOST PAID',
          'blacklist_status': false,
        },
      };

      final model = QrUserDetailsModel.fromJson(json, ticketId: '271768614229');
      expect(model.userDetails.ticketCategory, equals('GULFHOST PAID'));
    });

    test('ticketCategory returns null when both display_ticket_name and ticket_type_cat are empty', () {
      final json = {
        'status': true,
        'message': 'OK',
        'user_details': {
          'firstname': 'Test',
          'lastname': 'User',
          'unique_id': '123',
          'ticket_type_cat': '',
          'display_ticket_name': '   ',
          'blacklist_status': false,
        },
      };

      final model = QrUserDetailsModel.fromJson(json, ticketId: '123');
      expect(model.userDetails.ticketCategory, isNull);
    });
  });

  group('OnsiteCouponModel Tests', () {
    test('Correctly deserializes coupon with redeemed users', () {
      final json = {
        'status': true,
        'message': 'Coupon verified',
        'coupon': {
          'promocode_type': 'Exhibitor Pass',
          'code': 'EXHIBIT2026',
        },
        'redeemed_users': [
          {
            'user_image': '/media/u1.jpg',
            'ticket_state': 'new',
            'used_dt_tm': '2026-10-30T14:30:00Z',
            'user_info': {
              'firstname': 'Alice',
              'lastname': 'Wonderland',
              'company_name': 'Tech Corp',
              'designation': 'CTO',
              'email': 'alice@tech.com',
              'mobile': '+971501234567',
              'unique_id': 'URN-8871',
              'exhibitor_name': 'Stand B1',
              'created_by': 'Admin',
            },
          }
        ],
      };

      final model = OnsiteCouponModel.fromJson(json);

      expect(model.status, isTrue);
      expect(model.coupon?.promocodeType, equals('Exhibitor Pass'));
      expect(model.redeemedUsers.length, equals(1));
      expect(model.redeemedUsers.first.ticketState, equals('new'));
      expect(model.redeemedUsers.first.userInfo.fullName, equals('Alice Wonderland'));
      expect(model.redeemedUsers.first.userInfo.initials, equals('AW'));
      expect(model.redeemedUsers.first.userInfo.companyName, equals('Tech Corp'));
    });

    test('Handles unused coupon with empty redeemed_users', () {
      final json = {
        'status': true,
        'message': 'Coupon valid',
        'coupon': {
          'promocode_type': 'VIP Pass',
          'code': 'UNUSEDCODE',
        },
        'redeemed_users': [],
      };

      final model = OnsiteCouponModel.fromJson(json);
      expect(model.status, isTrue);
      expect(model.redeemedUsers.isEmpty, isTrue);
    });
  });
}

