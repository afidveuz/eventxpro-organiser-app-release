import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toastification/toastification.dart';
import 'package:qr_scanner/core/utils/app_toast.dart';

Future<void> cleanUpToasts(WidgetTester tester) async {
  AppToast.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppToast Context-Free Tests', () {
    testWidgets('shows success toast without context', (tester) async {
      await tester.pumpWidget(
        ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  // No context passed!
                  AppToast.showSuccess(
                    title: 'Export Done',
                    message: 'Records saved to Downloads',
                  );
                },
                child: const Text('Show Success'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Success'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Export Done'), findsOneWidget);
      expect(find.text('Records saved to Downloads'), findsOneWidget);

      await cleanUpToasts(tester);
    });

    testWidgets('shows error toast using shorthand without context', (tester) async {
      await tester.pumpWidget(
        ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  // Shorthand call with string only
                  AppToast.error('Failed to download file.');
                },
                child: const Text('Show Error'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Failed to download file.'), findsOneWidget);

      await cleanUpToasts(tester);
    });

    testWidgets('shows warning toast using shorthand without context', (tester) async {
      await tester.pumpWidget(
        ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  AppToast.warning('No offline data available.');
                },
                child: const Text('Show Warning'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Warning'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('No offline data available.'), findsOneWidget);

      await cleanUpToasts(tester);
    });

    testWidgets('shows info toast using shorthand without context', (tester) async {
      await tester.pumpWidget(
        ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  AppToast.info('Scanner Profile Re-provisioned successfully');
                },
                child: const Text('Show Info'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Info'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Scanner Profile Re-provisioned successfully'), findsOneWidget);

      await cleanUpToasts(tester);
    });

    testWidgets('shows custom toast without context and dismisses cleanly', (tester) async {
      await tester.pumpWidget(
        ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  // No context passed!
                  AppToast.showCustom(
                    child: const Text('Custom Rush Mode Toast'),
                  );
                },
                child: const Text('Show Custom'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Custom'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Custom Rush Mode Toast'), findsOneWidget);

      AppToast.dismissAll(delayForAnimation: false);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Custom Rush Mode Toast'), findsNothing);

      await cleanUpToasts(tester);
    });
  });
}
