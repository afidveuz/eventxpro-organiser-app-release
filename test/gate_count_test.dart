import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/core/services/gate_count_service.dart';

void main() {
  group('GateCheckInOutCount Tests', () {
    test('Default values are 0', () {
      const count = GateCheckInOutCount();
      expect(count.checkIn, 0);
      expect(count.checkOut, 0);
    });

    test('copyWith updates checkIn and checkOut independently', () {
      const original = GateCheckInOutCount(checkIn: 5, checkOut: 2);
      final updatedIn = original.copyWith(checkIn: 6);
      expect(updatedIn.checkIn, 6);
      expect(updatedIn.checkOut, 2);

      final updatedOut = original.copyWith(checkOut: 3);
      expect(updatedOut.checkIn, 5);
      expect(updatedOut.checkOut, 3);
    });

    test('Equality and toString work correctly', () {
      const a = GateCheckInOutCount(checkIn: 10, checkOut: 4);
      const b = GateCheckInOutCount(checkIn: 10, checkOut: 4);
      const c = GateCheckInOutCount(checkIn: 10, checkOut: 5);

      expect(a, equals(b));
      expect(a == c, isFalse);
      expect(a.toString(), 'GateCheckInOutCount(in: 10, out: 4)');
    });
  });
}
