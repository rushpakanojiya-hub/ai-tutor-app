// This is a basic Flutter widget test for the AI Tutor app.
//
// The default counter-app template test was left in place with its
// original MyApp reference, which doesn't exist in this project
// (the root widget here is AiTutorApp). This smoke test just confirms
// the app builds without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_tutor_app/main.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const AiTutorApp());
    // Just confirms the widget tree builds successfully.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
