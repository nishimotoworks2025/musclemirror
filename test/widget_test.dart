// This is a basic Flutter widget test.

import 'package:flutter_test/flutter_test.dart';

import 'package:muscle_mirror/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MuscleMirrorApp(initialThemeMode: 0));

    // Verify that the app bar title is present.
    expect(find.text('Muscle Mirror'), findsOneWidget);
    
    // Verify that tabs are present.
    expect(find.text('概要'), findsOneWidget);
    expect(find.text('詳細'), findsOneWidget);
    expect(find.text('進捗'), findsOneWidget);
  });
}
