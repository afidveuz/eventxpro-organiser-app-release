import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/domain/entities/attendee.dart';
import 'package:qr_scanner/domain/entities/scan_decision_code.dart';
import 'package:qr_scanner/domain/entities/scan_response.dart';

void main() {
  group('Attendee Details & AttendeeSheet Entity Tests', () {
    test('Correctly extracts attendee initials matching React Native nameShoter', () {
      const attendeeDouble = Attendee(name: 'John Doe', badgeType: 'VIP');
      expect(attendeeDouble.initials, 'JD');

      const attendeeSingle = Attendee(name: 'Sarah', badgeType: 'Delegate');
      expect(attendeeSingle.initials, 'S');

      const attendeeThreeWords = Attendee(name: 'Marcus Vance Smith', badgeType: 'Exhibitor');
      expect(attendeeThreeWords.initials, 'MV');

      const attendeeEmpty = Attendee(name: '', badgeType: 'General');
      expect(attendeeEmpty.initials, 'P');
    });

    test('Correctly parses Django entrance response with user_data and session_access', () {
      final json = {
        'status': true,
        'alert_type': 'success',
        'message': 'Checked In Successfully!',
        'punch_time': '15:30',
        'last_checkin_session': 'Main Gate',
        'last_checkin_time': '14:15:00',
        'user_data': {
          'firstname': 'Victoria',
          'lastname': 'Sterling',
          'ticket_type_cat': 'VIP Speaker',
          'company_name': 'Quantum Analytics',
          'unique_id': 'TICK-99482',
          'register_user_photo': '/media/profiles/victoria.jpg',
          'reg_cat': 'VIP',
          'badge_issue': true,
        },
        'session_access': [
          {
            'title': 'AI Keynote',
            'start_tm': '10:00',
            'hall_name': 'Hall A',
          },
          {
            'title': 'Networking Lunch',
            'start_tm': '13:00',
            'hall_name': 'Lounge',
          },
        ],
      };

      final response = ScanResponse.fromJson(json);

      expect(response.code, ScanDecisionCode.entryAllowed);
      expect(response.status, 'ACCEPTED');
      expect(response.message, 'Checked In Successfully!');
      expect(response.alertType, 'success');
      expect(response.isAlertSuccess, isTrue);

      final attendee = response.attendee;
      expect(attendee, isNotNull);
      expect(attendee!.fullName, 'Victoria Sterling');
      expect(attendee.initials, 'VS');
      expect(attendee.company, 'Quantum Analytics');
      expect(attendee.ticketId, 'TICK-99482');
      expect(attendee.category, 'VIP');
      expect(attendee.badgeType, 'VIP Speaker');
      expect(attendee.photoUrl, '/media/profiles/victoria.jpg');
      expect(attendee.punchTime, '15:30');
      expect(attendee.lastCheckinSession, 'Main Gate');
      expect(attendee.lastCheckinTime, '14:15:00');
      expect(attendee.badgeIssue, isTrue);

      expect(attendee.sessionAccess, isNotNull);
      expect(attendee.sessionAccess!.length, 2);
      expect(attendee.sessionAccess![0].title, 'AI Keynote');
      expect(attendee.sessionAccess![0].startTm, '10:00');
      expect(attendee.sessionAccess![0].hallName, 'Hall A');
    });

    test('Correctly handles warning response (Already Checked In)', () {
      final json = {
        'status': false,
        'alert_type': 'warning',
        'message': 'Already Checked In',
        'punch_time': '14:20',
        'last_checkin_session': 'Entrance 1',
        'last_checkin_time': '14:20:00',
        'user_data': {
          'firstname': 'Alex',
          'lastname': 'Mercer',
          'ticket_type_cat': 'Delegate',
          'company_name': 'EventX Global',
          'unique_id': 'DEL-1029',
          'reg_cat': 'DELEGATE',
        },
      };

      final response = ScanResponse.fromJson(json);

      expect(response.code, ScanDecisionCode.alreadyCheckedIn);
      expect(response.status, 'WARNING');
      expect(response.alertType, 'warning');
      expect(response.isAlertWarning, isTrue);
      expect(response.attendee?.fullName, 'Alex Mercer');
      expect(response.attendee?.ticketId, 'DEL-1029');
      expect(response.attendee?.punchTime, '14:20');
    });

    test('Correctly parses nested data.user_data if backend wraps under data', () {
      final json = {
        'data': {
          'status': true,
          'alert_type': 'success',
          'message': 'Checked In Successfully!',
          'user_data': {
            'firstname': 'Elena',
            'lastname': 'Rostova',
            'unique_id': 'ELN-77',
            'ticket_type_cat': 'Speaker',
            'company_name': 'Tech Corp',
          },
        },
      };

      final response = ScanResponse.fromJson(json);
      expect(response.attendee?.fullName, 'Elena Rostova');
      expect(response.attendee?.ticketId, 'ELN-77');
      expect(response.attendee?.company, 'Tech Corp');
    });
  });
}
