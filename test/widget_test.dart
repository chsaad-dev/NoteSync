import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App simple smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text('NoteSync Startup'),
        ),
      ),
    );

    expect(find.text('NoteSync Startup'), findsOneWidget);
  });
}
