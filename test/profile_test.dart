import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/data/models/user_profile_model.dart';

void main() {
  group('UserProfileModel Tests', () {
    test('Correctly parses organizer profile JSON from API', () {
      final json = {
        'status': true,
        'data': {
          'name': 'Amar Deep',
          'username': 'amar',
          'email': 'amar@eventxpro.com',
          'phone': '+91 9876543210',
          'photo': '/media/user_photos/amar.jpg',
          'is_admin': true,
        }
      };

      final profile = UserProfileModel.fromJson(json);

      expect(profile.name, 'Amar Deep');
      expect(profile.username, 'amar');
      expect(profile.email, 'amar@eventxpro.com');
      expect(profile.phone, '+91 9876543210');
      expect(profile.photo, '/media/user_photos/amar.jpg');
      expect(profile.isAdmin, true);
      expect(profile.initials, 'AD');
    });

    test('Computes initials correctly matching React Native nameShoter', () {
      expect(const UserProfileModel(name: 'John Doe', username: 'jdoe', email: '', phone: '').initials, 'JD');
      expect(const UserProfileModel(name: 'Single', username: 'single', email: '', phone: '').initials, 'S');
      expect(const UserProfileModel(name: '', username: 'admin', email: '', phone: '').initials, 'A');
      expect(const UserProfileModel(name: '', username: '', email: '', phone: '').initials, 'P');
    });

    test('Serializes to JSON and deserializes correctly', () {
      const original = UserProfileModel(
        name: 'Sarah Connor',
        username: 'sconnor',
        email: 'sarah@resistance.org',
        phone: '+1 555-0199',
        photo: null,
        isAdmin: false,
      );

      final map = original.toJson();
      final restored = UserProfileModel.fromJson(map);

      expect(restored.name, original.name);
      expect(restored.username, original.username);
      expect(restored.email, original.email);
      expect(restored.phone, original.phone);
      expect(restored.photo, original.photo);
      expect(restored.isAdmin, original.isAdmin);
      expect(restored.initials, 'SC');
    });
  });
}
