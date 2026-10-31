import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner/data/models/country_model.dart';
import 'package:qr_scanner/presentation/widgets/country_picker_modal.dart';

void main() {
  group('CountryPickerModal Widget Tests', () {
    const testCountries = [
      CountryModel(label: 'United Arab Emirates', code: 'AE', dialCode: '+971'),
      CountryModel(label: 'India', code: 'IN', dialCode: '+91'),
      CountryModel(label: 'United States', code: 'US', dialCode: '+1'),
    ];

    testWidgets('Renders country list and allows filtering by query', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CountryPickerModal(
              countries: testCountries,
              title: 'Select Test Country',
            ),
          ),
        ),
      );

      // Verify title & initial items
      expect(find.text('Select Test Country'), findsOneWidget);
      expect(find.text('United Arab Emirates'), findsOneWidget);
      expect(find.text('India'), findsOneWidget);
      expect(find.text('United States'), findsOneWidget);

      // Search for 'India'
      await tester.enterText(find.byType(TextField), 'India');
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is Text && w.data == 'India'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Text && w.data == 'United Arab Emirates'), findsNothing);
      expect(find.byWidgetPredicate((w) => w is Text && w.data == 'United States'), findsNothing);

      // Search by dial code '+1'
      await tester.enterText(find.byType(TextField), '+1');
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is Text && w.data == 'United States'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Text && w.data == 'India'), findsNothing);
    });
  });
}
