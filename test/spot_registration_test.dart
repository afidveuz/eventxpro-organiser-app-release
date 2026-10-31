import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/data/models/country_model.dart';
import 'package:qr_scanner/data/models/spot_registration_model.dart';
import 'package:qr_scanner/data/models/ticket_type_model.dart';

void main() {
  group('TicketTypeModel Tests', () {
    test('Correctly deserializes ticket list item from JSON', () {
      final json = {
        'pk': 105,
        'label': 'VIP Delegate Pass',
        'ticket_type_cat': 'Delegate',
        'price': 250.0,
        'currency': 'AED',
        'description': 'Access to VIP lounge and gala dinner',
      };

      final model = TicketTypeModel.fromJson(json);

      expect(model.pk, 105);
      expect(model.label, 'VIP Delegate Pass');
      expect(model.ticketTypeCat, 'Delegate');
      expect(model.price, 250.0);
      expect(model.currency, 'AED');
      expect(model.description, 'Access to VIP lounge and gala dinner');
    });

    test('Handles alternate key formats and string pk/price', () {
      final json = {
        'id': '42',
        'ticket_name': 'Standard Pass',
        'price': '100',
      };

      final model = TicketTypeModel.fromJson(json);

      expect(model.pk, 42);
      expect(model.label, 'Standard Pass');
      expect(model.price, 100);
    });
  });

  group('CountryModel Tests', () {
    test('Calculates Unicode Flag emoji correctly', () {
      const uae = CountryModel(label: 'United Arab Emirates', code: 'AE', dialCode: '+971');
      const india = CountryModel(label: 'India', code: 'IN', dialCode: '+91');
      const usa = CountryModel(label: 'United States', code: 'US', dialCode: '+1');

      expect(uae.flagEmoji, '🇦🇪');
      expect(india.flagEmoji, '🇮🇳');
      expect(usa.flagEmoji, '🇺🇸');
    });

    test('Correctly ensures dial code has + prefix', () {
      final json = {
        'label': 'United Arab Emirates',
        'code': 'ae',
        'dial_code': '971',
      };

      final model = CountryModel.fromJson(json);

      expect(model.code, 'AE');
      expect(model.dialCode, '+971');
      expect(model.label, 'United Arab Emirates');
    });
  });

  group('SpotRegistrationRequest & Result Tests', () {
    test('Serializes registration request matching backend schema', () {
      const request = SpotRegistrationRequest(
        eventId: 108,
        ticketId: 42,
        firstName: 'John',
        lastName: 'Doe',
        email: 'John.Doe@Example.com',
        countryCode: '971',
        mobile: '501234567',
        companyName: 'Acme Corp',
        jobTitle: 'VP Technology',
        country: 'United Arab Emirates',
        nationality: 'United Arab Emirates',
      );

      final json = request.toJson();

      expect(json['event_id'], 108);
      expect(json['ticket_id'], 42);
      expect(json['firstname'], 'John');
      expect(json['lastname'], 'Doe');
      expect(json['email'], 'john.doe@example.com');
      expect(json['country_code'], '+971');
      expect(json['mobile'], '501234567');
      expect(json['company_name'], 'Acme Corp');
      expect(json['job_title'], 'VP Technology');
      expect(json['country'], 'United Arab Emirates');
      expect(json['nationality'], 'United Arab Emirates');
    });

    test('Success result factory assigns fields properly', () {
      final result = SpotRegistrationResult.success(
        message: 'Registration completed',
        attendeeId: 999,
        uniqueId: 'URN-2026-999',
        fullName: 'Jane Smith',
        email: 'jane@example.com',
      );

      expect(result.isSuccess, isTrue);
      expect(result.attendeeId, 999);
      expect(result.uniqueId, 'URN-2026-999');
      expect(result.fullName, 'Jane Smith');
      expect(result.email, 'jane@example.com');
      expect(result.message, 'Registration completed');
    });

    test('Failure result factory sets isSuccess to false', () {
      final result = SpotRegistrationResult.failure(
        message: 'Attendee with this email already exists',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, 'Attendee with this email already exists');
    });
  });
}
