import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okeyix/widgets/premium_auth_card.dart';

void main() {
  testWidgets('premium auth card renders child content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PremiumAuthCard(child: Text('Auth')),
        ),
      ),
    );

    expect(find.text('Auth'), findsOneWidget);
  });
}
